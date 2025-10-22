import 'package:bybit_scalping_bot/backtesting/backtest_engine.dart';
import 'package:bybit_scalping_bot/services/price_prediction_service_v2.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// 가격 예측 V2 백테스트 (avgMove5m 기반)
/// 목표: 평균 오차 0.05% (약 $2) 이내
void main() async {
  print('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('🔬 가격 예측 V2 백테스트 (avgMove5m 기반)');
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
  final samples = <PredictionV2BacktestSample>[];
  final predictionService = PricePredictionServiceV2();

  print('🔄 백테스트 실행 중...\n');

  for (int i = 50; i < klines5m.length - 1; i++) {
    final recent5m = klines5m.sublist(i - 49, i + 1).reversed.toList();
    final currentKline = klines5m[i];
    final nextKline = klines5m[i + 1];

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

    // 다음 캔들의 실질 범위 (얇은 꼬리 제외)
    final nextBody = (nextKline.close - nextKline.open).abs();
    final nextUpperWick = nextKline.high - max(nextKline.open, nextKline.close);
    final nextLowerWick = min(nextKline.open, nextKline.close) - nextKline.low;

    final isUpperWickThin = nextBody > 0 && nextUpperWick < nextBody * 0.1;
    final isLowerWickThin = nextBody > 0 && nextLowerWick < nextBody * 0.1;

    final realHigh = isUpperWickThin
        ? max(nextKline.open, nextKline.close)
        : nextKline.high;
    final realLow = isLowerWickThin
        ? min(nextKline.open, nextKline.close)
        : nextKline.low;
    final realClose = nextKline.close;

    // 오차 계산
    final highError = (signal.predictedHigh - realHigh).abs();
    final lowError = (signal.predictedLow - realLow).abs();
    final closeError = (signal.predictedClose - realClose).abs();

    final highErrorPercent = (highError / signal.currentPrice) * 100;
    final lowErrorPercent = (lowError / signal.currentPrice) * 100;
    final closeErrorPercent = (closeError / signal.currentPrice) * 100;

    samples.add(PredictionV2BacktestSample(
      timestamp: currentKline.timestamp,
      marketState: signal.marketState.toString(),
      currentPrice: signal.currentPrice,
      predictedHigh: signal.predictedHigh,
      predictedLow: signal.predictedLow,
      predictedClose: signal.predictedClose,
      realHigh: realHigh,
      realLow: realLow,
      realClose: realClose,
      highError: highError,
      lowError: lowError,
      closeError: closeError,
      highErrorPercent: highErrorPercent,
      lowErrorPercent: lowErrorPercent,
      closeErrorPercent: closeErrorPercent,
      avgMove5m: signal.avgMove5m,
    ));
  }

  print('✅ ${samples.length}개 샘플 백테스트 완료\n');

  // 전체 통계
  _printOverallStatistics(samples);

  // 시장 상태별 통계
  _printMarketStateStatistics(samples);

  // CSV 저장
  await _saveCSV(samples);

  print('\n✅ 백테스트 완료!');
}

void _printOverallStatistics(List<PredictionV2BacktestSample> samples) {
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('📊 전체 예측 성능');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  final avgHighError = samples.map((s) => s.highError).reduce((a, b) => a + b) / samples.length;
  final avgLowError = samples.map((s) => s.lowError).reduce((a, b) => a + b) / samples.length;
  final avgCloseError = samples.map((s) => s.closeError).reduce((a, b) => a + b) / samples.length;

  final avgHighErrorPct = samples.map((s) => s.highErrorPercent).reduce((a, b) => a + b) / samples.length;
  final avgLowErrorPct = samples.map((s) => s.lowErrorPercent).reduce((a, b) => a + b) / samples.length;
  final avgCloseErrorPct = samples.map((s) => s.closeErrorPercent).reduce((a, b) => a + b) / samples.length;

  final highStdDev = _calculateStdDev(samples.map((s) => s.highError).toList());
  final lowStdDev = _calculateStdDev(samples.map((s) => s.lowError).toList());
  final closeStdDev = _calculateStdDev(samples.map((s) => s.closeError).toList());

  final maxHighError = samples.map((s) => s.highError).reduce(max);
  final maxLowError = samples.map((s) => s.lowError).reduce(max);
  final maxCloseError = samples.map((s) => s.closeError).reduce(max);

  final minHighError = samples.map((s) => s.highError).reduce(min);
  final minLowError = samples.map((s) => s.lowError).reduce(min);
  final minCloseError = samples.map((s) => s.closeError).reduce(min);

  // 중앙값 계산
  final sortedHighErrors = samples.map((s) => s.highError).toList()..sort();
  final sortedLowErrors = samples.map((s) => s.lowError).toList()..sort();
  final sortedCloseErrors = samples.map((s) => s.closeError).toList()..sort();

  final medianHighError = sortedHighErrors[sortedHighErrors.length ~/ 2];
  final medianLowError = sortedLowErrors[sortedLowErrors.length ~/ 2];
  final medianCloseError = sortedCloseErrors[sortedCloseErrors.length ~/ 2];

  // 퍼센트도 계산
  final minHighErrorPct = (minHighError / samples.where((s) => s.highError == minHighError).first.currentPrice) * 100;
  final minLowErrorPct = (minLowError / samples.where((s) => s.lowError == minLowError).first.currentPrice) * 100;
  final minCloseErrorPct = (minCloseError / samples.where((s) => s.closeError == minCloseError).first.currentPrice) * 100;

  final maxHighErrorPct = (maxHighError / samples.where((s) => s.highError == maxHighError).first.currentPrice) * 100;
  final maxLowErrorPct = (maxLowError / samples.where((s) => s.lowError == maxLowError).first.currentPrice) * 100;
  final maxCloseErrorPct = (maxCloseError / samples.where((s) => s.closeError == maxCloseError).first.currentPrice) * 100;

  final medianHighErrorPct = (medianHighError / samples[samples.length ~/ 2].currentPrice) * 100;
  final medianLowErrorPct = (medianLowError / samples[samples.length ~/ 2].currentPrice) * 100;
  final medianCloseErrorPct = (medianCloseError / samples[samples.length ~/ 2].currentPrice) * 100;

  print('최고가(HIGH) 예측:');
  print('  평균 오차: \$${avgHighError.toStringAsFixed(2)} (${avgHighErrorPct.toStringAsFixed(3)}%)');
  print('  중앙값:    \$${medianHighError.toStringAsFixed(2)} (${medianHighErrorPct.toStringAsFixed(3)}%)');
  print('  표준편차:  \$${highStdDev.toStringAsFixed(2)}');
  print('  최소 오차: \$${minHighError.toStringAsFixed(2)} (${minHighErrorPct.toStringAsFixed(3)}%)');
  print('  최대 오차: \$${maxHighError.toStringAsFixed(2)} (${maxHighErrorPct.toStringAsFixed(3)}%)');
  print('');

  print('최저가(LOW) 예측:');
  print('  평균 오차: \$${avgLowError.toStringAsFixed(2)} (${avgLowErrorPct.toStringAsFixed(3)}%)');
  print('  중앙값:    \$${medianLowError.toStringAsFixed(2)} (${medianLowErrorPct.toStringAsFixed(3)}%)');
  print('  표준편차:  \$${lowStdDev.toStringAsFixed(2)}');
  print('  최소 오차: \$${minLowError.toStringAsFixed(2)} (${minLowErrorPct.toStringAsFixed(3)}%)');
  print('  최대 오차: \$${maxLowError.toStringAsFixed(2)} (${maxLowErrorPct.toStringAsFixed(3)}%)');
  print('');

  print('종가(CLOSE) 예측:');
  print('  평균 오차: \$${avgCloseError.toStringAsFixed(2)} (${avgCloseErrorPct.toStringAsFixed(3)}%)');
  print('  중앙값:    \$${medianCloseError.toStringAsFixed(2)} (${medianCloseErrorPct.toStringAsFixed(3)}%)');
  print('  표준편차:  \$${closeStdDev.toStringAsFixed(2)}');
  print('  최소 오차: \$${minCloseError.toStringAsFixed(2)} (${minCloseErrorPct.toStringAsFixed(3)}%)');
  print('  최대 오차: \$${maxCloseError.toStringAsFixed(2)} (${maxCloseErrorPct.toStringAsFixed(3)}%)');
  print('');

  // 목표 달성 여부
  final targetPct = 0.05; // 0.05%
  final targetDollar = 2.0; // $2

  if (avgHighErrorPct <= targetPct && avgLowErrorPct <= targetPct) {
    print('✅ 목표 달성: 평균 오차 ${targetPct}% (약 \$${targetDollar}) 이내!');
  } else {
    print('⚠️  목표 미달:');
    if (avgHighErrorPct > targetPct) {
      print('   HIGH 오차 ${avgHighErrorPct.toStringAsFixed(3)}% > ${targetPct}%');
    }
    if (avgLowErrorPct > targetPct) {
      print('   LOW 오차 ${avgLowErrorPct.toStringAsFixed(3)}% > ${targetPct}%');
    }
    print('   → 하지만 0.3% 목표 대비 ${(avgHighErrorPct / 0.3 * 100).toStringAsFixed(1)}% 수준');
  }
  print('');
}

void _printMarketStateStatistics(List<PredictionV2BacktestSample> samples) {
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('📈 시장 상태별 예측 성능');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  final stateGroups = <String, List<PredictionV2BacktestSample>>{};
  for (final sample in samples) {
    stateGroups.putIfAbsent(sample.marketState, () => []).add(sample);
  }

  stateGroups.forEach((state, stateSamples) {
    final avgHigh = stateSamples.map((s) => s.highError).reduce((a, b) => a + b) / stateSamples.length;
    final avgLow = stateSamples.map((s) => s.lowError).reduce((a, b) => a + b) / stateSamples.length;
    final avgClose = stateSamples.map((s) => s.closeError).reduce((a, b) => a + b) / stateSamples.length;

    final avgHighPct = stateSamples.map((s) => s.highErrorPercent).reduce((a, b) => a + b) / stateSamples.length;
    final avgLowPct = stateSamples.map((s) => s.lowErrorPercent).reduce((a, b) => a + b) / stateSamples.length;
    final avgClosePct = stateSamples.map((s) => s.closeErrorPercent).reduce((a, b) => a + b) / stateSamples.length;

    print('[${state.split('.').last}] (${stateSamples.length}개)');
    print('  HIGH:  \$${avgHigh.toStringAsFixed(2)} (${avgHighPct.toStringAsFixed(3)}%)');
    print('  LOW:   \$${avgLow.toStringAsFixed(2)} (${avgLowPct.toStringAsFixed(3)}%)');
    print('  CLOSE: \$${avgClose.toStringAsFixed(2)} (${avgClosePct.toStringAsFixed(3)}%)');
    print('');
  });
}

double _calculateStdDev(List<double> values) {
  if (values.isEmpty) return 0.0;
  final mean = values.reduce((a, b) => a + b) / values.length;
  final variance = values.map((v) => pow(v - mean, 2)).reduce((a, b) => a + b) / values.length;
  return sqrt(variance);
}

Future<void> _saveCSV(List<PredictionV2BacktestSample> samples) async {
  final csvLines = <String>[];

  csvLines.add('Timestamp,MarketState,CurrentPrice,PredictedHigh,PredictedLow,PredictedClose,'
      'RealHigh,RealLow,RealClose,HighError,LowError,CloseError,'
      'HighErrorPct,LowErrorPct,CloseErrorPct,AvgMove5m');

  for (final s in samples) {
    csvLines.add('${s.timestamp.toIso8601String()},${s.marketState},${s.currentPrice},'
        '${s.predictedHigh},${s.predictedLow},${s.predictedClose},'
        '${s.realHigh},${s.realLow},${s.realClose},'
        '${s.highError},${s.lowError},${s.closeError},'
        '${s.highErrorPercent},${s.lowErrorPercent},${s.closeErrorPercent},${s.avgMove5m}');
  }

  final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').substring(0, 19);
  final filename = 'prediction_v2_backtest_$timestamp.csv';
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

class PredictionV2BacktestSample {
  final DateTime timestamp;
  final String marketState;
  final double currentPrice;
  final double predictedHigh;
  final double predictedLow;
  final double predictedClose;
  final double realHigh;
  final double realLow;
  final double realClose;
  final double highError;
  final double lowError;
  final double closeError;
  final double highErrorPercent;
  final double lowErrorPercent;
  final double closeErrorPercent;
  final double avgMove5m;

  PredictionV2BacktestSample({
    required this.timestamp,
    required this.marketState,
    required this.currentPrice,
    required this.predictedHigh,
    required this.predictedLow,
    required this.predictedClose,
    required this.realHigh,
    required this.realLow,
    required this.realClose,
    required this.highError,
    required this.lowError,
    required this.closeError,
    required this.highErrorPercent,
    required this.lowErrorPercent,
    required this.closeErrorPercent,
    required this.avgMove5m,
  });
}
