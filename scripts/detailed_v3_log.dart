import 'package:bybit_scalping_bot/backtesting/backtest_engine.dart';
import 'package:bybit_scalping_bot/backtesting/position_tracker.dart';
import 'package:bybit_scalping_bot/models/market_condition.dart';
import 'package:bybit_scalping_bot/services/market_analyzer.dart';
import 'package:bybit_scalping_bot/services/v3/band_walking_detector.dart';
import 'package:bybit_scalping_bot/services/v3/breakout_classifier.dart';
import 'package:bybit_scalping_bot/utils/technical_indicators.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';

/// 프레임별 상세 로그 - CSV 파일로 출력
void main() async {
  print('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('📝 V3 전략 프레임별 상세 로그');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  // 2025-10-21 전체 기간 (10:50 밴드워킹 vs 14:45 일반)
  final startTime = DateTime.utc(2025, 10, 21, 0, 0);
  final endTime = DateTime.utc(2025, 10, 22, 0, 0);

  print('분석 기간: ${startTime.toString().substring(0, 16)} ~ ${endTime.toString().substring(0, 16)}\n');

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

  print('📊 프레임별 분석 시작...\n');

  final position = PositionTracker();
  final csvLines = <String>[];

  // CSV 헤더
  csvLines.add('Timestamp,Price,RSI,MACD_Hist,Volume_Ratio,BB_Lower,BB_Middle,BB_Upper,'
      'Confidence,Market_Condition,BandWalking_Risk,BandWalking_Score,BandWalking_Dir,'
      'Breakout_Type,Stage1_Pass,Stage2_Pass,Stage3_TrendFollow,Stage3_CounterTrend,'
      'Stage4_Result,Block_Reason');

  int entrySignals = 0;

  for (int i = 50; i < klines.length; i++) {
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

    // 각 단계별 통과 여부
    bool stage1Pass = confidence >= 0.3;
    bool stage2Pass = true;
    String stage3TrendFollow = '-';
    String stage3CounterTrend = '-';
    String stage4Result = 'NO_ENTRY';
    String blockReason = '';

    // Stage 1 체크
    if (!stage1Pass) {
      blockReason = 'Confidence_Low_${confidence.toStringAsFixed(2)}';
    } else {
      // Stage 2: 관망 체크
      if (breakoutType == BreakoutType.BREAKOUT_INITIAL) {
        stage2Pass = false;
        blockReason = 'WAIT_BREAKOUT_INITIAL';
      } else if (breakoutType == BreakoutType.BREAKOUT_TO_BANDWALKING &&
          bandWalkingSignal.risk == BandWalkingRisk.MEDIUM) {
        stage2Pass = false;
        blockReason = 'WAIT_BANDWALKING_TRANSITION';
      }

      if (stage2Pass) {
        // Stage 3: 추세 추종 체크
        if (bandWalkingSignal.shouldEnterTrendFollow) {
          if (bandWalkingSignal.direction == 'UP') {
            final rsiOk = rsi > 55;
            final macdOk = macd.histogram > 0;
            final volOk = volumeAnalysis.relativeVolumeRatio > 1.5;

            if (rsiOk && macdOk && volOk) {
              stage3TrendFollow = 'LONG_OK';
              stage4Result = 'ENTRY_LONG_TREND';
              entrySignals++;
            } else {
              stage3TrendFollow = 'LONG_FAIL[RSI:${rsiOk},MACD:${macdOk},Vol:${volOk}]';
              blockReason = 'TrendFollow_UP_RSI${rsi.toStringAsFixed(0)}_MACD${macd.histogram.toStringAsFixed(1)}_Vol${volumeAnalysis.relativeVolumeRatio.toStringAsFixed(1)}';
            }
          } else if (bandWalkingSignal.direction == 'DOWN') {
            // 패닉 셀링 체크
            if (rsi < 25 && volumeAnalysis.relativeVolumeRatio > 20) {
              stage3TrendFollow = 'SHORT_PANIC';
              blockReason = 'Panic_Selling';
            } else {
              final priceChangePercent = ((currentKline.close - bb.middle) / bb.middle) * 100;
              if (priceChangePercent < -1.5) {
                stage3TrendFollow = 'SHORT_OVERDROP';
                blockReason = 'Overdrop_${priceChangePercent.toStringAsFixed(1)}%';
              } else {
                final rsiOk = rsi < 45;
                final macdOk = macd.histogram < 0;
                final volOk = volumeAnalysis.relativeVolumeRatio > 1.5;

                if (rsiOk && macdOk && volOk) {
                  stage3TrendFollow = 'SHORT_OK';
                  stage4Result = 'ENTRY_SHORT_TREND';
                  entrySignals++;
                } else {
                  stage3TrendFollow = 'SHORT_FAIL[RSI:${rsiOk},MACD:${macdOk},Vol:${volOk}]';
                  blockReason = 'TrendFollow_DOWN_RSI${rsi.toStringAsFixed(0)}_MACD${macd.histogram.toStringAsFixed(1)}_Vol${volumeAnalysis.relativeVolumeRatio.toStringAsFixed(1)}';
                }
              }
            }
          }
        }

        // Stage 4: 역추세 체크
        if (!bandWalkingSignal.shouldBlockCounterTrend && stage3TrendFollow == '-') {
          // 시장 조건 체크
          if (marketCondition != MarketCondition.ranging &&
              marketCondition != MarketCondition.weakBullish &&
              marketCondition != MarketCondition.weakBearish) {
            stage3CounterTrend = 'MARKET_NG';
            blockReason = 'Market_${marketCondition.name}';
          } else if (breakoutType != BreakoutType.HEADFAKE &&
              breakoutType != BreakoutType.BREAKOUT_REVERSAL) {
            stage3CounterTrend = 'PATTERN_NG';
            blockReason = 'Pattern_${breakoutType.name}';
          } else {
            // BB 영역 계산
            final bbLowerZone = bb.lower + (bb.middle - bb.lower) * 0.2;
            final bbUpperZone = bb.upper - (bb.upper - bb.middle) * 0.2;

            // LONG 체크
            if (currentKline.close <= bbLowerZone) {
              final rsiOk = rsi < 35;
              final volOk = volumeAnalysis.relativeVolumeRatio < 10.0;

              if (rsiOk && volOk) {
                stage3CounterTrend = 'LONG_OK';
                stage4Result = 'ENTRY_LONG_COUNTER';
                entrySignals++;
              } else {
                stage3CounterTrend = 'LONG_FAIL[RSI:${rsiOk},Vol:${volOk}]';
                blockReason = 'Counter_LONG_RSI${rsi.toStringAsFixed(0)}_Vol${volumeAnalysis.relativeVolumeRatio.toStringAsFixed(1)}';
              }
            } else if (currentKline.close >= bbUpperZone) {
              final rsiOk = rsi > 65;
              final volOk = volumeAnalysis.relativeVolumeRatio < 10.0;

              if (rsiOk && volOk) {
                stage3CounterTrend = 'SHORT_OK';
                stage4Result = 'ENTRY_SHORT_COUNTER';
                entrySignals++;
              } else {
                stage3CounterTrend = 'SHORT_FAIL[RSI:${rsiOk},Vol:${volOk}]';
                blockReason = 'Counter_SHORT_RSI${rsi.toStringAsFixed(0)}_Vol${volumeAnalysis.relativeVolumeRatio.toStringAsFixed(1)}';
              }
            } else {
              stage3CounterTrend = 'PRICE_NOT_IN_ZONE';
              blockReason = 'Price_${currentKline.close.toStringAsFixed(0)}_BBL${bbLowerZone.toStringAsFixed(0)}_BBU${bbUpperZone.toStringAsFixed(0)}';
            }
          }
        } else if (bandWalkingSignal.shouldBlockCounterTrend && stage3TrendFollow == '-') {
          blockReason = 'BandWalking_Block_Counter';
        }

        if (stage4Result == 'NO_ENTRY' && blockReason.isEmpty) {
          blockReason = 'No_Pattern_Match';
        }
      }
    }

    // CSV 라인 추가
    csvLines.add('${currentKline.timestamp.toIso8601String()},'
        '${currentKline.close.toStringAsFixed(2)},'
        '${rsi.toStringAsFixed(1)},'
        '${macd.histogram.toStringAsFixed(2)},'
        '${volumeAnalysis.relativeVolumeRatio.toStringAsFixed(1)},'
        '${bb.lower.toStringAsFixed(2)},'
        '${bb.middle.toStringAsFixed(2)},'
        '${bb.upper.toStringAsFixed(2)},'
        '${confidence.toStringAsFixed(2)},'
        '${marketCondition.name},'
        '${bandWalkingSignal.risk.name},'
        '${bandWalkingSignal.score},'
        '${bandWalkingSignal.direction},'
        '${breakoutType.name},'
        '$stage1Pass,'
        '$stage2Pass,'
        '$stage3TrendFollow,'
        '$stage3CounterTrend,'
        '$stage4Result,'
        '$blockReason');
  }

  // CSV 파일 저장
  final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').substring(0, 19);
  final filename = 'v3_detailed_log_$timestamp.csv';
  await File(filename).writeAsString(csvLines.join('\n'));

  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('📊 분석 결과');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
  print('총 프레임: ${klines.length - 50}개');
  print('진입 신호: $entrySignals개');
  print('CSV 파일: $filename\n');
  print('✅ 완료!');
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
      'limit=1000',
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
