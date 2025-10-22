import 'package:bybit_scalping_bot/backtesting/backtest_engine.dart';
import 'package:bybit_scalping_bot/utils/technical_indicators.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// 실질 가격 범위 분석 (얇은 꼬리 제외)
///
/// 목표:
/// 1. 얇은 wick 제외하고 실질적인 body 범위 분석
/// 2. low/high/close 각각 예측
/// 3. 평균 오차 0.05% (약 $2) 이내 달성
void main() async {
  print('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('🔬 실질 가격 범위 분석 (얇은 꼬리 제외)');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  // 일주일 데이터
  final startTime = DateTime.utc(2025, 10, 15, 0, 0);
  final endTime = DateTime.utc(2025, 10, 22, 0, 0);

  print('📥 데이터 다운로드 중...\n');

  final klines5m = await _fetchKlines(
    symbol: 'ETHUSDT',
    interval: '5',
    startTime: startTime,
    endTime: endTime,
  );

  final klines30m = await _fetchKlines(
    symbol: 'ETHUSDT',
    interval: '30',
    startTime: startTime,
    endTime: endTime,
  );

  print('✅ 5분봉: ${klines5m.length}개');
  print('✅ 30분봉: ${klines30m.length}개\n');

  // 샘플 수집
  final samples = <RealPriceRangeSample>[];

  print('🔄 실질 범위 분석 중...\n');

  for (int i = 50; i < klines5m.length - 1; i++) {
    final currentKline = klines5m[i];
    final nextKline = klines5m[i + 1];
    final recent5m = klines5m.sublist(i - 49, i + 1);

    // 30분봉 매칭
    final matching30m = klines30m.where((k) {
      return k.timestamp.isBefore(currentKline.timestamp.add(Duration(minutes: 1))) &&
          k.timestamp.isAfter(currentKline.timestamp.subtract(Duration(minutes: 30)));
    }).toList();

    if (matching30m.isEmpty) continue;

    final idx30m = klines30m.indexOf(matching30m.first);
    if (idx30m < 49) continue;

    final recent30m = klines30m.sublist(idx30m - 49, idx30m + 1);

    // 지표 계산
    final closePrices5m = recent5m.map((k) => k.close).toList();
    final closePrices30m = recent30m.map((k) => k.close).toList();

    final rsi5m = calculateRSI(closePrices5m, 14);
    final bb5m = calculateBollingerBands(closePrices5m, 20, 2.0);
    final macd5m = calculateMACDFullSeries(closePrices5m).last;

    final rsi30m = calculateRSI(closePrices30m, 14);
    final bb30m = calculateBollingerBands(closePrices30m, 20, 2.0);
    final macd30m = calculateMACDFullSeries(closePrices30m).last;

    // 시장 상태
    final marketState = _detectMarketState(bb5m, bb30m, rsi30m, macd30m);

    // 현재 캔들
    final currentPrice = currentKline.close;

    // 다음 캔들의 실질 범위 (얇은 꼬리 제외)
    // 얇은 꼬리: body의 10% 미만인 wick은 제외
    final nextBody = (nextKline.close - nextKline.open).abs();
    final nextUpperWick = nextKline.high - max(nextKline.open, nextKline.close);
    final nextLowerWick = min(nextKline.open, nextKline.close) - nextKline.low;

    // 얇은 꼬리 판정: body의 10% 미만
    final isUpperWickThin = nextBody > 0 && nextUpperWick < nextBody * 0.1;
    final isLowerWickThin = nextBody > 0 && nextLowerWick < nextBody * 0.1;

    // 실질 high/low (얇은 꼬리 제외)
    final realHigh = isUpperWickThin
        ? max(nextKline.open, nextKline.close)
        : nextKline.high;
    final realLow = isLowerWickThin
        ? min(nextKline.open, nextKline.close)
        : nextKline.low;

    final realClose = nextKline.close;

    // 현재가 대비 변화
    final highMove = realHigh - currentPrice;
    final lowMove = currentPrice - realLow;
    final closeMove = realClose - currentPrice;

    // 퍼센트
    final highMovePercent = (highMove / currentPrice) * 100.0;
    final lowMovePercent = (lowMove / currentPrice) * 100.0;
    final closeMovePercent = (closeMove / currentPrice) * 100.0;

    // 최근 N개 캔들의 평균 이동폭
    final recentMoves5m = recent5m.take(5).map((k) {
      final body = (k.close - k.open).abs();
      final range = k.high - k.low;
      return range;
    }).toList();
    final avgMove5m = recentMoves5m.reduce((a, b) => a + b) / recentMoves5m.length;

    samples.add(RealPriceRangeSample(
      timestamp: currentKline.timestamp,
      marketState: marketState,
      currentPrice: currentPrice,
      rsi5m: rsi5m,
      macd5m: macd5m.histogram,
      bbWidth5m: (bb5m.upper - bb5m.lower) / bb5m.middle,
      rsi30m: rsi30m,
      macd30m: macd30m.histogram,
      bbWidth30m: (bb30m.upper - bb30m.lower) / bb30m.middle,
      avgMove5m: avgMove5m,
      realHigh: realHigh,
      realLow: realLow,
      realClose: realClose,
      highMove: highMove,
      lowMove: lowMove,
      closeMove: closeMove,
      highMovePercent: highMovePercent,
      lowMovePercent: lowMovePercent,
      closeMovePercent: closeMovePercent,
      isUpperWickThin: isUpperWickThin,
      isLowerWickThin: isLowerWickThin,
    ));
  }

  print('✅ ${samples.length}개 샘플 분석 완료\n');

  // 통계 분석
  _analyzeStatistics(samples);

  // 시장 상태별 분석
  _analyzeByMarketState(samples);

  // 예측 모델 역산
  _buildPredictionModels(samples);

  // CSV 저장
  await _saveCSV(samples);

  print('\n✅ 분석 완료!');
}

void _analyzeStatistics(List<RealPriceRangeSample> samples) {
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('📊 실질 가격 이동 통계');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  final avgHighMove = samples.map((s) => s.highMove).reduce((a, b) => a + b) / samples.length;
  final avgLowMove = samples.map((s) => s.lowMove).reduce((a, b) => a + b) / samples.length;
  final avgCloseMove = samples.map((s) => s.closeMove.abs()).reduce((a, b) => a + b) / samples.length;

  final avgHighPercent = samples.map((s) => s.highMovePercent).reduce((a, b) => a + b) / samples.length;
  final avgLowPercent = samples.map((s) => s.lowMovePercent).reduce((a, b) => a + b) / samples.length;
  final avgClosePercent = samples.map((s) => s.closeMovePercent.abs()).reduce((a, b) => a + b) / samples.length;

  final thinUpperCount = samples.where((s) => s.isUpperWickThin).length;
  final thinLowerCount = samples.where((s) => s.isLowerWickThin).length;

  print('평균 HIGH 이동: \$${avgHighMove.toStringAsFixed(2)} (${avgHighPercent.toStringAsFixed(3)}%)');
  print('평균 LOW 이동: \$${avgLowMove.toStringAsFixed(2)} (${avgLowPercent.toStringAsFixed(3)}%)');
  print('평균 CLOSE 이동: \$${avgCloseMove.toStringAsFixed(2)} (${avgClosePercent.toStringAsFixed(3)}%)');
  print('');
  print('얇은 꼬리 비율:');
  print('  상단 wick: $thinUpperCount/${samples.length} (${(thinUpperCount / samples.length * 100).toStringAsFixed(1)}%)');
  print('  하단 wick: $thinLowerCount/${samples.length} (${(thinLowerCount / samples.length * 100).toStringAsFixed(1)}%)');
  print('');

  // 목표 체크
  if (avgHighPercent <= 0.05 && avgLowPercent <= 0.05) {
    print('✅ 목표 달성 가능: 평균 이동폭이 0.05% 이내!');
  } else {
    print('⚠️  평균 이동폭이 0.05% 초과 → 예측 모델로 개선 필요');
  }
  print('');
}

void _analyzeByMarketState(List<RealPriceRangeSample> samples) {
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('📈 시장 상태별 이동폭');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  final stateGroups = <String, List<RealPriceRangeSample>>{};
  for (final sample in samples) {
    stateGroups.putIfAbsent(sample.marketState, () => []).add(sample);
  }

  stateGroups.forEach((state, stateSamples) {
    final avgHigh = stateSamples.map((s) => s.highMove).reduce((a, b) => a + b) / stateSamples.length;
    final avgLow = stateSamples.map((s) => s.lowMove).reduce((a, b) => a + b) / stateSamples.length;
    final avgClose = stateSamples.map((s) => s.closeMove.abs()).reduce((a, b) => a + b) / stateSamples.length;

    final avgHighPct = stateSamples.map((s) => s.highMovePercent).reduce((a, b) => a + b) / stateSamples.length;
    final avgLowPct = stateSamples.map((s) => s.lowMovePercent).reduce((a, b) => a + b) / stateSamples.length;
    final avgClosePct = stateSamples.map((s) => s.closeMovePercent.abs()).reduce((a, b) => a + b) / stateSamples.length;

    print('[$state] (${stateSamples.length}개)');
    print('  HIGH: \$${avgHigh.toStringAsFixed(2)} (${avgHighPct.toStringAsFixed(3)}%)');
    print('  LOW:  \$${avgLow.toStringAsFixed(2)} (${avgLowPct.toStringAsFixed(3)}%)');
    print('  CLOSE: \$${avgClose.toStringAsFixed(2)} (${avgClosePct.toStringAsFixed(3)}%)');
    print('');
  });
}

void _buildPredictionModels(List<RealPriceRangeSample> samples) {
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('🎯 예측 모델 (최근 5개 캔들 평균 이동폭 기반)');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  final stateGroups = <String, List<RealPriceRangeSample>>{};
  for (final sample in samples) {
    stateGroups.putIfAbsent(sample.marketState, () => []).add(sample);
  }

  stateGroups.forEach((state, stateSamples) {
    // avgMove5m 대비 실제 이동의 배수 계산
    final highMultipliers = stateSamples.map((s) => s.highMove / s.avgMove5m).toList();
    final lowMultipliers = stateSamples.map((s) => s.lowMove / s.avgMove5m).toList();
    final closeMultipliers = stateSamples.map((s) => s.closeMove.abs() / s.avgMove5m).toList();

    final avgHighMult = highMultipliers.reduce((a, b) => a + b) / highMultipliers.length;
    final avgLowMult = lowMultipliers.reduce((a, b) => a + b) / lowMultipliers.length;
    final avgCloseMult = closeMultipliers.reduce((a, b) => a + b) / closeMultipliers.length;

    // 표준편차
    final highStdDev = _calculateStdDev(highMultipliers);
    final lowStdDev = _calculateStdDev(lowMultipliers);

    print('[$state]');
    print('  예측 공식:');
    print('    HIGH = current + (avgMove5m × ${avgHighMult.toStringAsFixed(2)})');
    print('    LOW  = current - (avgMove5m × ${avgLowMult.toStringAsFixed(2)})');
    print('    CLOSE = current + (avgMove5m × ${avgCloseMult.toStringAsFixed(2)} × direction)');
    print('  표준편차: high ${highStdDev.toStringAsFixed(2)}, low ${lowStdDev.toStringAsFixed(2)}');
    print('');
  });

  print('💡 avgMove5m: 최근 5개 캔들의 평균 (high - low)');
  print('');
}

double _calculateStdDev(List<double> values) {
  if (values.isEmpty) return 0.0;
  final mean = values.reduce((a, b) => a + b) / values.length;
  final variance = values.map((v) => pow(v - mean, 2)).reduce((a, b) => a + b) / values.length;
  return sqrt(variance);
}

String _detectMarketState(BollingerBands bb5m, BollingerBands bb30m, double rsi30m, MACD macd30m) {
  final bbWidth5m = (bb5m.upper - bb5m.lower) / bb5m.middle;
  final bbWidth30m = (bb30m.upper - bb30m.lower) / bb30m.middle;

  final is5mSqueeze = bbWidth5m < 0.02;
  final is30mSqueeze = bbWidth30m < 0.02 &&
                       rsi30m > 40 && rsi30m < 60 &&
                       macd30m.histogram.abs() < 2.0;

  if (is30mSqueeze) {
    return '30m_SQUEEZE';
  } else if (is5mSqueeze) {
    return '5m_SQUEEZE';
  } else {
    if (rsi30m > 60 && macd30m.histogram > 2.0) {
      return 'STRONG_UP';
    } else if (rsi30m < 40 && macd30m.histogram < -2.0) {
      return 'STRONG_DOWN';
    } else if (rsi30m > 50 && macd30m.histogram > 0) {
      return 'WEAK_UP';
    } else if (rsi30m < 50 && macd30m.histogram < 0) {
      return 'WEAK_DOWN';
    } else {
      return 'NEUTRAL';
    }
  }
}

Future<void> _saveCSV(List<RealPriceRangeSample> samples) async {
  final csvLines = <String>[];

  csvLines.add('Timestamp,MarketState,CurrentPrice,RSI5m,MACD5m,BBWidth5m,RSI30m,MACD30m,BBWidth30m,'
      'AvgMove5m,RealHigh,RealLow,RealClose,HighMove,LowMove,CloseMove,'
      'HighMovePct,LowMovePct,CloseMovePct,ThinUpperWick,ThinLowerWick');

  for (final s in samples) {
    csvLines.add('${s.timestamp.toIso8601String()},${s.marketState},${s.currentPrice},'
        '${s.rsi5m},${s.macd5m},${s.bbWidth5m},${s.rsi30m},${s.macd30m},${s.bbWidth30m},'
        '${s.avgMove5m},${s.realHigh},${s.realLow},${s.realClose},'
        '${s.highMove},${s.lowMove},${s.closeMove},'
        '${s.highMovePercent},${s.lowMovePercent},${s.closeMovePercent},'
        '${s.isUpperWickThin},${s.isLowerWickThin}');
  }

  final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').substring(0, 19);
  final filename = 'real_price_range_$timestamp.csv';
  await File(filename).writeAsString(csvLines.join('\n'));

  print('📄 CSV 저장: $filename');
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

class RealPriceRangeSample {
  final DateTime timestamp;
  final String marketState;
  final double currentPrice;
  final double rsi5m;
  final double macd5m;
  final double bbWidth5m;
  final double rsi30m;
  final double macd30m;
  final double bbWidth30m;
  final double avgMove5m; // 최근 5개 캔들 평균 이동폭
  final double realHigh;
  final double realLow;
  final double realClose;
  final double highMove;
  final double lowMove;
  final double closeMove;
  final double highMovePercent;
  final double lowMovePercent;
  final double closeMovePercent;
  final bool isUpperWickThin;
  final bool isLowerWickThin;

  RealPriceRangeSample({
    required this.timestamp,
    required this.marketState,
    required this.currentPrice,
    required this.rsi5m,
    required this.macd5m,
    required this.bbWidth5m,
    required this.rsi30m,
    required this.macd30m,
    required this.bbWidth30m,
    required this.avgMove5m,
    required this.realHigh,
    required this.realLow,
    required this.realClose,
    required this.highMove,
    required this.lowMove,
    required this.closeMove,
    required this.highMovePercent,
    required this.lowMovePercent,
    required this.closeMovePercent,
    required this.isUpperWickThin,
    required this.isLowerWickThin,
  });
}
