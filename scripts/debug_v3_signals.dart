import 'package:bybit_scalping_bot/backtesting/backtest_engine.dart';
import 'package:bybit_scalping_bot/backtesting/position_tracker.dart';
import 'package:bybit_scalping_bot/models/market_condition.dart';
import 'package:bybit_scalping_bot/services/market_analyzer.dart';
import 'package:bybit_scalping_bot/services/v3/band_walking_detector.dart';
import 'package:bybit_scalping_bot/services/v3/breakout_classifier.dart';
import 'package:bybit_scalping_bot/utils/technical_indicators.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

/// V3 전략 디버그 스크립트 - 각 단계별 차단 이유 분석
void main() async {
  print('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('🔍 V3 전략 디버그 분석');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  // 밴드워킹 기간 포함 (10/20 14:00 ~ 10/21 04:00 = 14시간 = 168캔들)
  final startTime = DateTime.utc(2024, 10, 20, 14, 0);
  final endTime = DateTime.utc(2024, 10, 21, 4, 0);

  print('분석 기간: ${startTime.toString().substring(0, 16)} ~ ${endTime.toString().substring(0, 16)}');
  print('(하락 밴드워킹: 10/20 15:45~16:45)');
  print('(상승 밴드워킹: 10/20 23:10~10/21 00:05, 하락: 10/21 00:55~02:30)\n');

  print('📥 데이터 다운로드 중...');
  final klines = await _fetchKlines(
    symbol: 'ETHUSDT',
    interval: '5',
    startTime: startTime,
    endTime: endTime,
  );

  if (klines.isEmpty) {
    print('❌ 데이터를 가져올 수 없습니다.');
    return;
  }

  print('✅ ${klines.length}개 캔들 다운로드 완료');
  print('   첫 캔들: ${klines.first.timestamp}');
  print('   마지막 캔들: ${klines.last.timestamp}\n');

  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('📊 단계별 필터링 분석');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  final position = PositionTracker();
  int totalChecks = 0;
  int stage1Blocked = 0; // Confidence < 0.3
  int stage2Wait = 0; // BREAKOUT_INITIAL
  int stage3TrendFollowFail = 0; // 밴드워킹 HIGH이지만 조건 미달
  int stage3CounterTrendBlocked = 0; // 밴드워킹이 역추세 차단
  int stage4NoPattern = 0; // 진입 패턴 없음

  final Map<String, int> blockReasons = {};

  // 샘플링: 10개 캔들마다 상세 분석
  final sampleIndices = <int>[];
  for (int i = 50; i < klines.length; i += 10) {
    sampleIndices.add(i);
  }

  for (int i = 50; i < klines.length; i++) {
    totalChecks++;
    final currentKline = klines[i];
    final recentKlines = klines.sublist(i - 49, i + 1);

    final closePrices = recentKlines.map((k) => k.close).toList();
    final volumes = recentKlines.map((k) => k.volume).toList();

    // Stage 1: 복합 지표 분석
    final marketAnalysis = MarketAnalyzer.analyzeMarket(
      closePrices: closePrices,
      volumes: volumes,
    );

    final confidence = marketAnalysis.confidence;
    final marketCondition = marketAnalysis.condition;

    if (confidence < 0.3) {
      stage1Blocked++;
      continue;
    }

    // 지표 계산
    final rsi = calculateRSI(closePrices, 14);
    final bb = calculateBollingerBands(closePrices, 20, 2.0);
    final macdSeries = calculateMACDFullSeries(closePrices);
    final macd = macdSeries.last;
    final volumeAnalysis = analyzeVolume(volumes);

    // RSI 히스토리
    final rsiHistory = <double>[];
    if (recentKlines.length >= 53) {
      for (int j = 1; j <= 3; j++) {
        final prevClosePrices =
            recentKlines.sublist(j, j + 50).map((k) => k.close).toList();
        rsiHistory.add(calculateRSI(prevClosePrices, 14));
      }
    }

    // Stage 2: 밴드워킹 감지
    final bandWalkingSignal = BandWalkingDetector.detect(
      recentKlines: recentKlines,
      bb: bb,
      macd: macd,
      macdHistory: macdSeries,
      volume: volumeAnalysis,
      rsi: rsi,
      rsiHistory: rsiHistory,
    );

    // Stage 3: 브레이크아웃 분류
    final breakoutType = BreakoutClassifier.classify(
      bandWalking: bandWalkingSignal,
      volume: volumeAnalysis,
      rsi: rsi,
      macd: macd,
    );

    // 관망 체크
    if (breakoutType == BreakoutType.BREAKOUT_INITIAL) {
      stage2Wait++;
      blockReasons['BREAKOUT_INITIAL (관망)'] = (blockReasons['BREAKOUT_INITIAL (관망)'] ?? 0) + 1;
      continue;
    }

    if (breakoutType == BreakoutType.BREAKOUT_TO_BANDWALKING &&
        bandWalkingSignal.risk == BandWalkingRisk.MEDIUM) {
      stage2Wait++;
      blockReasons['BREAKOUT_TO_BANDWALKING + MEDIUM (관망)'] =
          (blockReasons['BREAKOUT_TO_BANDWALKING + MEDIUM (관망)'] ?? 0) + 1;
      continue;
    }

    // Stage 4: 진입 결정 체크
    bool trendFollowAttempted = false;
    bool counterTrendAttempted = false;

    // 추세 추종 체크
    if (bandWalkingSignal.shouldEnterTrendFollow) {
      trendFollowAttempted = true;

      if (bandWalkingSignal.direction == 'UP') {
        if (!(rsi > 65 && macd.histogram > 5.0 && volumeAnalysis.relativeVolumeRatio > 3.0)) {
          stage3TrendFollowFail++;
          final reason = '상승 밴드워킹 조건 미달: RSI=${rsi.toStringAsFixed(1)}(<65?), MACD=${macd.histogram.toStringAsFixed(1)}(<5?), Vol=${volumeAnalysis.relativeVolumeRatio.toStringAsFixed(1)}x(<3?)';
          blockReasons[reason] = (blockReasons[reason] ?? 0) + 1;

          // 샘플링 출력
          if (sampleIndices.contains(i)) {
            print('${currentKline.timestamp.toString().substring(0, 16)} - ❌ $reason');
          }
          continue;
        }
      } else if (bandWalkingSignal.direction == 'DOWN') {
        // 패닉 셀링 체크
        if (rsi < 25 && volumeAnalysis.relativeVolumeRatio > 20) {
          blockReasons['패닉 셀링 (진입 보류)'] = (blockReasons['패닉 셀링 (진입 보류)'] ?? 0) + 1;
          stage3TrendFollowFail++;
          continue;
        }

        final priceChangePercent = ((currentKline.close - bb.middle) / bb.middle) * 100;
        if (priceChangePercent < -1.5) {
          blockReasons['하락폭 과도 (>-1.5%)'] = (blockReasons['하락폭 과도 (>-1.5%)'] ?? 0) + 1;
          stage3TrendFollowFail++;
          continue;
        }

        if (!(rsi < 35 && macd.histogram < -5.0 && volumeAnalysis.relativeVolumeRatio > 3.0)) {
          stage3TrendFollowFail++;
          final reason = '하락 밴드워킹 조건 미달: RSI=${rsi.toStringAsFixed(1)}(>35?), MACD=${macd.histogram.toStringAsFixed(1)}(>-5?), Vol=${volumeAnalysis.relativeVolumeRatio.toStringAsFixed(1)}x(<3?)';
          blockReasons[reason] = (blockReasons[reason] ?? 0) + 1;

          if (sampleIndices.contains(i)) {
            print('${currentKline.timestamp.toString().substring(0, 16)} - ❌ $reason');
          }
          continue;
        }
      }
    }

    // 역추세 체크
    if (!bandWalkingSignal.shouldBlockCounterTrend && !trendFollowAttempted) {
      counterTrendAttempted = true;

      // 횡보장/약한 추세 체크
      if (marketCondition != MarketCondition.ranging &&
          marketCondition != MarketCondition.weakBullish &&
          marketCondition != MarketCondition.weakBearish) {
        blockReasons['시장 조건 부적합 (${marketCondition.name})'] =
            (blockReasons['시장 조건 부적합 (${marketCondition.name})'] ?? 0) + 1;
        stage4NoPattern++;
        continue;
      }

      // 브레이크아웃 패턴 체크
      if (breakoutType != BreakoutType.HEADFAKE &&
          breakoutType != BreakoutType.BREAKOUT_REVERSAL) {
        blockReasons['역추세 패턴 없음 (${breakoutType.name})'] =
            (blockReasons['역추세 패턴 없음 (${breakoutType.name})'] ?? 0) + 1;
        stage4NoPattern++;
        continue;
      }

      // MACD 개선/악화 체크
      final prevMacdHistogram = macdSeries.length >= 2
          ? macdSeries[macdSeries.length - 2].histogram
          : macd.histogram;

      // LONG 조건
      if (currentKline.close <= bb.lower &&
          rsi < 35 &&
          macd.histogram > prevMacdHistogram &&
          volumeAnalysis.relativeVolumeRatio < 10.0) {
        // 진입 가능!
        if (sampleIndices.contains(i)) {
          print('${currentKline.timestamp.toString().substring(0, 16)} - ✅ 역추세 LONG 진입 가능!');
        }
        continue;
      }

      // SHORT 조건
      if (currentKline.close >= bb.upper &&
          rsi > 65 &&
          macd.histogram < prevMacdHistogram &&
          volumeAnalysis.relativeVolumeRatio < 10.0) {
        // 진입 가능!
        if (sampleIndices.contains(i)) {
          print('${currentKline.timestamp.toString().substring(0, 16)} - ✅ 역추세 SHORT 진입 가능!');
        }
        continue;
      }

      // 역추세 조건 미달
      final longFail = currentKline.close <= bb.lower
          ? 'LONG 미달: RSI=${rsi.toStringAsFixed(1)}(<35?), MACD개선=${(macd.histogram > prevMacdHistogram)}, Vol=${volumeAnalysis.relativeVolumeRatio.toStringAsFixed(1)}x(<10?)'
          : null;
      final shortFail = currentKline.close >= bb.upper
          ? 'SHORT 미달: RSI=${rsi.toStringAsFixed(1)}(>65?), MACD악화=${(macd.histogram < prevMacdHistogram)}, Vol=${volumeAnalysis.relativeVolumeRatio.toStringAsFixed(1)}x(<10?)'
          : null;

      if (longFail != null || shortFail != null) {
        final reason = longFail ?? shortFail ?? '역추세 조건 미달';
        blockReasons[reason] = (blockReasons[reason] ?? 0) + 1;
        stage4NoPattern++;

        if (sampleIndices.contains(i)) {
          print('${currentKline.timestamp.toString().substring(0, 16)} - ❌ $reason');
        }
        continue;
      }

      blockReasons['가격이 BB 경계 밖 아님'] = (blockReasons['가격이 BB 경계 밖 아님'] ?? 0) + 1;
      stage4NoPattern++;
    }

    // 밴드워킹이 역추세 차단
    if (bandWalkingSignal.shouldBlockCounterTrend && !trendFollowAttempted) {
      stage3CounterTrendBlocked++;
      blockReasons['밴드워킹 ${bandWalkingSignal.risk.name}이 역추세 차단'] =
          (blockReasons['밴드워킹 ${bandWalkingSignal.risk.name}이 역추세 차단'] ?? 0) + 1;
    }

    // 아무 전략도 시도 안함
    if (!trendFollowAttempted && !counterTrendAttempted) {
      stage4NoPattern++;
      blockReasons['진입 조건 없음'] = (blockReasons['진입 조건 없음'] ?? 0) + 1;
    }
  }

  print('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('📊 단계별 차단 통계');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  print('총 체크 횟수: $totalChecks회\n');

  print('Stage 1 - Confidence < 0.3: $stage1Blocked회 (${(stage1Blocked / totalChecks * 100).toStringAsFixed(1)}%)');
  print('Stage 2 - 관망 (WAIT): $stage2Wait회 (${(stage2Wait / totalChecks * 100).toStringAsFixed(1)}%)');
  print('Stage 3 - 추세 추종 조건 미달: $stage3TrendFollowFail회 (${(stage3TrendFollowFail / totalChecks * 100).toStringAsFixed(1)}%)');
  print('Stage 3 - 밴드워킹이 역추세 차단: $stage3CounterTrendBlocked회 (${(stage3CounterTrendBlocked / totalChecks * 100).toStringAsFixed(1)}%)');
  print('Stage 4 - 진입 패턴 없음: $stage4NoPattern회 (${(stage4NoPattern / totalChecks * 100).toStringAsFixed(1)}%)\n');

  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('🔍 상세 차단 이유 (Top 10)');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  final sortedReasons = blockReasons.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  for (int i = 0; i < sortedReasons.length && i < 10; i++) {
    final entry = sortedReasons[i];
    final percent = (entry.value / totalChecks * 100).toStringAsFixed(1);
    print('${i + 1}. ${entry.key}');
    print('   → ${entry.value}회 ($percent%)\n');
  }

  print('✅ 디버그 분석 완료!');
}

Future<List<KlineData>> _fetchKlines({
  required String symbol,
  required String interval,
  required DateTime startTime,
  required DateTime endTime,
}) async {
  final List<KlineData> allKlines = [];
  DateTime currentStart = startTime;

  while (currentStart.isBefore(endTime)) {
    final startMs = currentStart.millisecondsSinceEpoch;
    final endMs = endTime.millisecondsSinceEpoch;

    final url = Uri.parse(
      'https://api.bybit.com/v5/market/kline?'
      'category=linear&'
      'symbol=$symbol&'
      'interval=$interval&'
      'start=$startMs&'
      'end=$endMs&'
      'limit=200',
    );

    try {
      final response = await http.get(url);
      if (response.statusCode != 200) break;

      final data = json.decode(response.body);
      if (data['retCode'] != 0) break;

      final klines = data['result']['list'] as List;
      if (klines.isEmpty) break;

      final parsedKlines = klines
          .map((k) => KlineData.fromBybitKline(k))
          .toList()
          .reversed
          .toList();

      allKlines.addAll(parsedKlines);

      currentStart = parsedKlines.last.timestamp.add(Duration(minutes: int.parse(interval)));
      await Future.delayed(Duration(milliseconds: 200));

      if (klines.length < 200) break;
    } catch (e) {
      print('Error: $e');
      break;
    }
  }

  final uniqueKlines = <DateTime, KlineData>{};
  for (final kline in allKlines) {
    uniqueKlines[kline.timestamp] = kline;
  }

  return uniqueKlines.values.toList()
    ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
}
