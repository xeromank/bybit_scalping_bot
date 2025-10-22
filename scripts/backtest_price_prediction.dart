import 'package:bybit_scalping_bot/backtesting/backtest_engine.dart';
import 'package:bybit_scalping_bot/services/price_prediction_service.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// 가격 예측 백테스트
/// 목표: 일주일 데이터로 예측 오차 검증 및 ATR 배수 최적화
void main() async {
  print('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('🔬 가격 예측 백테스트 (1주일)');
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

  // 백테스트 샘플 수집
  final samples = <PredictionBacktestSample>[];
  final predictionService = PricePredictionService();

  print('🔄 백테스트 실행 중...\n');

  for (int i = 50; i < klines5m.length - 1; i++) {
    // 현재 시점의 최근 50개 캔들
    final recent5m = klines5m.sublist(i - 49, i + 1).reversed.toList();
    final currentKline = klines5m[i];
    final nextKline = klines5m[i + 1]; // 실제 다음 캔들

    // 30분봉 매칭
    final matching30m = klines30m.where((k) {
      return k.timestamp.isBefore(currentKline.timestamp.add(Duration(minutes: 1))) &&
          k.timestamp.isAfter(currentKline.timestamp.subtract(Duration(minutes: 30)));
    }).toList();

    if (matching30m.isEmpty) continue;

    final idx30m = klines30m.indexOf(matching30m.first);
    if (idx30m < 49) continue;

    final recent30m = klines30m.sublist(idx30m - 49, idx30m + 1).reversed.toList();

    // 예측 신호 생성
    final signal = predictionService.generatePredictionSignal(
      klines5m: recent5m,
      klines30m: recent30m,
    );

    if (signal == null) continue;

    // 실제 결과
    final actualHigh = nextKline.high;
    final actualLow = nextKline.low;
    final actualRange = actualHigh - actualLow;

    // 오차 계산
    final highError = (signal.predictedHigh - actualHigh).abs();
    final lowError = (signal.predictedLow - actualLow).abs();
    final highErrorPercent = (highError / signal.currentPrice) * 100;
    final lowErrorPercent = (lowError / signal.currentPrice) * 100;

    // 범위 내 여부
    final actualHighInRange = actualHigh <= signal.predictedHigh;
    final actualLowInRange = actualLow >= signal.predictedLow;

    samples.add(PredictionBacktestSample(
      timestamp: currentKline.timestamp,
      marketState: signal.marketState,
      currentPrice: signal.currentPrice,
      predictedHigh: signal.predictedHigh,
      predictedLow: signal.predictedLow,
      actualHigh: actualHigh,
      actualLow: actualLow,
      actualRange: actualRange,
      highError: highError,
      lowError: lowError,
      highErrorPercent: highErrorPercent,
      lowErrorPercent: lowErrorPercent,
      actualHighInRange: actualHighInRange,
      actualLowInRange: actualLowInRange,
      atr: signal.atr,
    ));
  }

  print('✅ ${samples.length}개 샘플 백테스트 완료\n');

  // 전체 통계
  _printOverallStatistics(samples);

  // 시장 상태별 통계
  _printMarketStateStatistics(samples);

  // 최적 ATR 배수 계산
  _calculateOptimalMultipliers(samples);

  // CSV 저장
  await _saveCSV(samples);

  print('\n✅ 백테스트 완료!');
}

/// 전체 통계
void _printOverallStatistics(List<PredictionBacktestSample> samples) {
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('📊 전체 예측 성능');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  // 최고가 예측 오차
  final avgHighError = samples.map((s) => s.highError).reduce((a, b) => a + b) / samples.length;
  final highStdDev = _calculateStdDev(samples.map((s) => s.highError).toList());
  final maxHighError = samples.map((s) => s.highError).reduce(max);
  final minHighError = samples.map((s) => s.highError).reduce(min);

  // 최저가 예측 오차
  final avgLowError = samples.map((s) => s.lowError).reduce((a, b) => a + b) / samples.length;
  final lowStdDev = _calculateStdDev(samples.map((s) => s.lowError).toList());
  final maxLowError = samples.map((s) => s.lowError).reduce(max);
  final minLowError = samples.map((s) => s.lowError).reduce(min);

  // 범위 내 정확도
  final highInRangeCount = samples.where((s) => s.actualHighInRange).length;
  final lowInRangeCount = samples.where((s) => s.actualLowInRange).length;

  print('최고가 예측:');
  print('  평균 오차: \$${avgHighError.toStringAsFixed(2)}');
  print('  표준편차: \$${highStdDev.toStringAsFixed(2)}');
  print('  최대 오차: \$${maxHighError.toStringAsFixed(2)}');
  print('  최소 오차: \$${minHighError.toStringAsFixed(2)}');
  print('  범위 내 정확도: $highInRangeCount/${samples.length} (${(highInRangeCount / samples.length * 100).toStringAsFixed(1)}%)');
  print('');

  print('최저가 예측:');
  print('  평균 오차: \$${avgLowError.toStringAsFixed(2)}');
  print('  표준편차: \$${lowStdDev.toStringAsFixed(2)}');
  print('  최대 오차: \$${maxLowError.toStringAsFixed(2)}');
  print('  최소 오차: \$${minLowError.toStringAsFixed(2)}');
  print('  범위 내 정확도: $lowInRangeCount/${samples.length} (${(lowInRangeCount / samples.length * 100).toStringAsFixed(1)}%)');
  print('');

  // 목표 달성 여부
  if (avgHighError <= 1.0 && avgLowError <= 1.0) {
    print('✅ 목표 달성: 평균 오차 1달러 이내!');
  } else {
    print('⚠️  목표 미달: 평균 오차가 1달러를 초과합니다.');
    print('   → ATR 배수 재조정 필요');
  }
  print('');
}

/// 시장 상태별 통계
void _printMarketStateStatistics(List<PredictionBacktestSample> samples) {
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('📈 시장 상태별 예측 성능');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  final stateGroups = <String, List<PredictionBacktestSample>>{};
  for (final sample in samples) {
    stateGroups.putIfAbsent(sample.marketState.toString(), () => []).add(sample);
  }

  stateGroups.forEach((state, stateSamples) {
    final avgHighError = stateSamples.map((s) => s.highError).reduce((a, b) => a + b) / stateSamples.length;
    final avgLowError = stateSamples.map((s) => s.lowError).reduce((a, b) => a + b) / stateSamples.length;
    final highInRange = stateSamples.where((s) => s.actualHighInRange).length;
    final lowInRange = stateSamples.where((s) => s.actualLowInRange).length;

    print('[${state.split('.').last}] (${stateSamples.length}개)');
    print('  최고가 평균 오차: \$${avgHighError.toStringAsFixed(2)} (${(highInRange / stateSamples.length * 100).toStringAsFixed(1)}% 범위 내)');
    print('  최저가 평균 오차: \$${avgLowError.toStringAsFixed(2)} (${(lowInRange / stateSamples.length * 100).toStringAsFixed(1)}% 범위 내)');
    print('');
  });
}

/// 최적 ATR 배수 계산
void _calculateOptimalMultipliers(List<PredictionBacktestSample> samples) {
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('🎯 최적 ATR 배수 (오차 최소화)');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  final stateGroups = <String, List<PredictionBacktestSample>>{};
  for (final sample in samples) {
    stateGroups.putIfAbsent(sample.marketState.toString(), () => []).add(sample);
  }

  stateGroups.forEach((state, stateSamples) {
    // 실제 최고가/최저가까지의 거리를 ATR로 나눈 배수 계산
    final optimalHighMultipliers = stateSamples.map((s) {
      return (s.actualHigh - s.currentPrice) / s.atr;
    }).toList();

    final optimalLowMultipliers = stateSamples.map((s) {
      return (s.currentPrice - s.actualLow) / s.atr;
    }).toList();

    final avgOptimalHighMult = optimalHighMultipliers.reduce((a, b) => a + b) / optimalHighMultipliers.length;
    final avgOptimalLowMult = optimalLowMultipliers.reduce((a, b) => a + b) / optimalLowMultipliers.length;

    // 안전 마진 추가 (평균 + 0.5 표준편차)
    final highStdDev = _calculateStdDev(optimalHighMultipliers);
    final lowStdDev = _calculateStdDev(optimalLowMultipliers);

    final recommendedHighMult = avgOptimalHighMult + (highStdDev * 0.5);
    final recommendedLowMult = avgOptimalLowMult + (lowStdDev * 0.5);

    print('[${state.split('.').last}]');
    print('  현재 사용:');
    print('    highMultiplier: ${(stateSamples.first.predictedHigh - stateSamples.first.currentPrice) / stateSamples.first.atr}');
    print('    lowMultiplier: ${(stateSamples.first.currentPrice - stateSamples.first.predictedLow) / stateSamples.first.atr}');
    print('');
    print('  최적 배수 (실제 평균):');
    print('    highMultiplier: ${avgOptimalHighMult.toStringAsFixed(2)}');
    print('    lowMultiplier: ${avgOptimalLowMult.toStringAsFixed(2)}');
    print('');
    print('  권장 배수 (평균 + 0.5σ):');
    print('    highMultiplier: ${recommendedHighMult.toStringAsFixed(2)}');
    print('    lowMultiplier: ${recommendedLowMult.toStringAsFixed(2)}');
    print('');
  });
}

double _calculateStdDev(List<double> values) {
  if (values.isEmpty) return 0.0;
  final mean = values.reduce((a, b) => a + b) / values.length;
  final variance = values.map((v) => pow(v - mean, 2)).reduce((a, b) => a + b) / values.length;
  return sqrt(variance);
}

Future<void> _saveCSV(List<PredictionBacktestSample> samples) async {
  final csvLines = <String>[];

  csvLines.add('Timestamp,MarketState,CurrentPrice,PredictedHigh,PredictedLow,'
      'ActualHigh,ActualLow,HighError,LowError,HighErrorPercent,LowErrorPercent,'
      'HighInRange,LowInRange,ATR');

  for (final s in samples) {
    csvLines.add('${s.timestamp.toIso8601String()},${s.marketState.toString().split('.').last},'
        '${s.currentPrice},${s.predictedHigh},${s.predictedLow},'
        '${s.actualHigh},${s.actualLow},${s.highError},${s.lowError},'
        '${s.highErrorPercent},${s.lowErrorPercent},'
        '${s.actualHighInRange},${s.actualLowInRange},${s.atr}');
  }

  final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').substring(0, 19);
  final filename = 'prediction_backtest_$timestamp.csv';
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

class PredictionBacktestSample {
  final DateTime timestamp;
  final dynamic marketState;
  final double currentPrice;
  final double predictedHigh;
  final double predictedLow;
  final double actualHigh;
  final double actualLow;
  final double actualRange;
  final double highError;
  final double lowError;
  final double highErrorPercent;
  final double lowErrorPercent;
  final bool actualHighInRange;
  final bool actualLowInRange;
  final double atr;

  PredictionBacktestSample({
    required this.timestamp,
    required this.marketState,
    required this.currentPrice,
    required this.predictedHigh,
    required this.predictedLow,
    required this.actualHigh,
    required this.actualLow,
    required this.actualRange,
    required this.highError,
    required this.lowError,
    required this.highErrorPercent,
    required this.lowErrorPercent,
    required this.actualHighInRange,
    required this.actualLowInRange,
    required this.atr,
  });
}
