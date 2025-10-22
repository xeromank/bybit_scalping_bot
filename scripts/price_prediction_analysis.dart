import 'package:bybit_scalping_bot/backtesting/backtest_engine.dart';
import 'package:bybit_scalping_bot/utils/technical_indicators.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// 순수 가격 예측 분석
/// 목표: 다음 캔들의 방향 + 최고가/최저가 예측
void main() async {
  print('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('📈 순수 가격 예측 분석');
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
  final samples = <PricePredictionSample>[];

  for (int i = 50; i < klines5m.length - 1; i++) {
    final currentKline = klines5m[i];
    final nextKline = klines5m[i + 1];
    final recentKlines = klines5m.sublist(i - 49, i + 1);

    // 5분봉 지표
    final closePrices5m = recentKlines.map((k) => k.close).toList();
    final volumes5m = recentKlines.map((k) => k.volume).toList();

    final rsi5m = calculateRSI(closePrices5m, 14);
    final bb5m = calculateBollingerBands(closePrices5m, 20, 2.0);
    final macd5m = calculateMACDFullSeries(closePrices5m).last;
    final volumeRatio5m = analyzeVolume(volumes5m).relativeVolumeRatio;
    final atr5m = _calculateATR(recentKlines.sublist(recentKlines.length - 14));

    // 5분봉 스퀴즈 판단
    final bbWidth5m = (bb5m.upper - bb5m.lower) / bb5m.middle;
    final is5mSqueeze = bbWidth5m < 0.02; // 2% 미만

    // 30분봉 매칭
    final matching30m = klines30m.where((k) {
      return k.timestamp.isBefore(currentKline.timestamp.add(Duration(minutes: 1))) &&
          k.timestamp.isAfter(currentKline.timestamp.subtract(Duration(minutes: 30)));
    }).toList();

    if (matching30m.isEmpty) continue;

    final idx30m = klines30m.indexOf(matching30m.first);
    if (idx30m < 50) continue;

    final recent30m = klines30m.sublist(idx30m - 49, idx30m + 1);
    final closePrices30m = recent30m.map((k) => k.close).toList();

    final rsi30m = calculateRSI(closePrices30m, 14);
    final bb30m = calculateBollingerBands(closePrices30m, 20, 2.0);
    final macd30m = calculateMACDFullSeries(closePrices30m).last;

    // 30분봉 스퀴즈 판단
    final bbWidth30m = (bb30m.upper - bb30m.lower) / bb30m.middle;
    final is30mSqueeze = bbWidth30m < 0.02 &&
                         rsi30m > 40 && rsi30m < 60 &&
                         macd30m.histogram.abs() < 2.0;

    // 시장 상태 분류
    String marketState;
    if (is30mSqueeze) {
      marketState = '30m_SQUEEZE';
    } else if (is5mSqueeze) {
      marketState = '5m_SQUEEZE';
    } else {
      // 추세 판단
      if (rsi30m > 60 && macd30m.histogram > 2.0) {
        marketState = 'STRONG_UP';
      } else if (rsi30m < 40 && macd30m.histogram < -2.0) {
        marketState = 'STRONG_DOWN';
      } else if (rsi30m > 50 && macd30m.histogram > 0) {
        marketState = 'WEAK_UP';
      } else if (rsi30m < 50 && macd30m.histogram < 0) {
        marketState = 'WEAK_DOWN';
      } else {
        marketState = 'NEUTRAL';
      }
    }

    // 다음 캔들 실제 결과
    final actualDirection = nextKline.close > currentKline.close ? 'UP' : 'DOWN';
    final actualHigh = nextKline.high;
    final actualLow = nextKline.low;
    final actualRange = actualHigh - actualLow;
    final actualHighFromCurrent = actualHigh - currentKline.close;
    final actualLowFromCurrent = currentKline.close - actualLow;

    samples.add(PricePredictionSample(
      timestamp: currentKline.timestamp,
      currentPrice: currentKline.close,
      marketState: marketState,
      // 5분봉
      rsi5m: rsi5m,
      macd5m: macd5m.histogram,
      bbWidth5m: bbWidth5m,
      bbPosition5m: (currentKline.close - bb5m.lower) / (bb5m.upper - bb5m.lower),
      volumeRatio5m: volumeRatio5m,
      atr5m: atr5m,
      // 30분봉
      rsi30m: rsi30m,
      macd30m: macd30m.histogram,
      bbWidth30m: bbWidth30m,
      // 실제 결과
      actualDirection: actualDirection,
      actualHigh: actualHigh,
      actualLow: actualLow,
      actualRange: actualRange,
      actualHighFromCurrent: actualHighFromCurrent,
      actualLowFromCurrent: actualLowFromCurrent,
    ));
  }

  print('✅ ${samples.length}개 샘플 수집\n');

  // 시장 상태별 분석
  _analyzeByMarketState(samples);

  // 방향 예측 분석
  _analyzeDirectionPrediction(samples);

  // 가격 범위 예측 분석
  final rangeModels = _analyzePriceRangePrediction(samples);

  // 예측 편차 분석
  _analyzePredictionError(samples, rangeModels);

  // CSV 저장
  await _saveCSV(samples);

  print('\n✅ 분석 완료!');
}

/// 시장 상태별 분석
void _analyzeByMarketState(List<PricePredictionSample> samples) {
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('📊 시장 상태별 분석');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  final stateGroups = <String, List<PricePredictionSample>>{};
  for (final sample in samples) {
    stateGroups.putIfAbsent(sample.marketState, () => []).add(sample);
  }

  // 각 상태별 통계
  stateGroups.forEach((state, stateSamples) {
    final upCount = stateSamples.where((s) => s.actualDirection == 'UP').length;
    final avgRange = stateSamples.map((s) => s.actualRange).reduce((a, b) => a + b) / stateSamples.length;
    final avgHighMove = stateSamples.map((s) => s.actualHighFromCurrent).reduce((a, b) => a + b) / stateSamples.length;
    final avgLowMove = stateSamples.map((s) => s.actualLowFromCurrent).reduce((a, b) => a + b) / stateSamples.length;

    print('$state: ${stateSamples.length}개');
    print('  상승 확률: ${(upCount / stateSamples.length * 100).toStringAsFixed(1)}%');
    print('  평균 범위: \$${avgRange.toStringAsFixed(2)}');
    print('  평균 상승폭: +\$${avgHighMove.toStringAsFixed(2)}');
    print('  평균 하락폭: -\$${avgLowMove.toStringAsFixed(2)}');
    print('');
  });
}

/// 방향 예측 분석
void _analyzeDirectionPrediction(List<PricePredictionSample> samples) {
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('🎯 방향 예측 모델');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  // 시장 상태별로 방향 예측 모델 구축
  final models = <String, DirectionModel>{};

  // STRONG_UP 시장
  final strongUp = samples.where((s) => s.marketState == 'STRONG_UP').toList();
  if (strongUp.isNotEmpty) {
    models['STRONG_UP'] = _buildDirectionModel(strongUp, 'STRONG_UP');
  }

  // STRONG_DOWN 시장
  final strongDown = samples.where((s) => s.marketState == 'STRONG_DOWN').toList();
  if (strongDown.isNotEmpty) {
    models['STRONG_DOWN'] = _buildDirectionModel(strongDown, 'STRONG_DOWN');
  }

  // WEAK_UP 시장
  final weakUp = samples.where((s) => s.marketState == 'WEAK_UP').toList();
  if (weakUp.isNotEmpty) {
    models['WEAK_UP'] = _buildDirectionModel(weakUp, 'WEAK_UP');
  }

  // WEAK_DOWN 시장
  final weakDown = samples.where((s) => s.marketState == 'WEAK_DOWN').toList();
  if (weakDown.isNotEmpty) {
    models['WEAK_DOWN'] = _buildDirectionModel(weakDown, 'WEAK_DOWN');
  }

  // 5m SQUEEZE 시장 (역추세)
  final squeeze5m = samples.where((s) => s.marketState == '5m_SQUEEZE').toList();
  if (squeeze5m.isNotEmpty) {
    models['5m_SQUEEZE'] = _buildDirectionModel(squeeze5m, '5m_SQUEEZE');
  }

  // 30m SQUEEZE 시장
  final squeeze30m = samples.where((s) => s.marketState == '30m_SQUEEZE').toList();
  if (squeeze30m.isNotEmpty) {
    models['30m_SQUEEZE'] = _buildDirectionModel(squeeze30m, '30m_SQUEEZE');
  }

  // NEUTRAL 시장
  final neutral = samples.where((s) => s.marketState == 'NEUTRAL').toList();
  if (neutral.isNotEmpty) {
    models['NEUTRAL'] = _buildDirectionModel(neutral, 'NEUTRAL');
  }

  // 결과 출력
  models.forEach((state, model) {
    print('[$state]');
    print('  샘플: ${model.totalSamples}개');
    print('  상승 확률: ${(model.upProbability * 100).toStringAsFixed(1)}%');
    print('  예측 조건: ${model.bestCondition}');
    print('  예측 정확도: ${(model.accuracy * 100).toStringAsFixed(1)}%');
    print('');
  });
}

/// 방향 예측 모델 구축
DirectionModel _buildDirectionModel(List<PricePredictionSample> samples, String state) {
  final upCount = samples.where((s) => s.actualDirection == 'UP').length;
  final upProbability = upCount / samples.length;

  // 간단한 휴리스틱 조건 찾기
  String bestCondition = '';
  double accuracy = 0.0;

  // RSI 5m 기반
  final rsiUpSamples = samples.where((s) => s.rsi5m > 50).toList();
  if (rsiUpSamples.isNotEmpty) {
    final rsiUpCorrect = rsiUpSamples.where((s) => s.actualDirection == 'UP').length;
    final rsiAcc = rsiUpCorrect / rsiUpSamples.length;
    if (rsiAcc > accuracy) {
      accuracy = rsiAcc;
      bestCondition = 'RSI5m > 50';
    }
  }

  // MACD 5m 기반
  final macdUpSamples = samples.where((s) => s.macd5m > 0).toList();
  if (macdUpSamples.isNotEmpty) {
    final macdUpCorrect = macdUpSamples.where((s) => s.actualDirection == 'UP').length;
    final macdAcc = macdUpCorrect / macdUpSamples.length;
    if (macdAcc > accuracy) {
      accuracy = macdAcc;
      bestCondition = 'MACD5m > 0';
    }
  }

  // BB Position 기반
  final bbUpSamples = samples.where((s) => s.bbPosition5m > 0.5).toList();
  if (bbUpSamples.isNotEmpty) {
    final bbUpCorrect = bbUpSamples.where((s) => s.actualDirection == 'UP').length;
    final bbAcc = bbUpCorrect / bbUpSamples.length;
    if (bbAcc > accuracy) {
      accuracy = bbAcc;
      bestCondition = 'BBPos5m > 0.5';
    }
  }

  // 기본값
  if (bestCondition.isEmpty) {
    bestCondition = 'Default (${upProbability > 0.5 ? "UP" : "DOWN"} bias)';
    accuracy = max(upProbability, 1 - upProbability);
  }

  return DirectionModel(
    state: state,
    totalSamples: samples.length,
    upProbability: upProbability,
    bestCondition: bestCondition,
    accuracy: accuracy,
  );
}

/// 가격 범위 예측 분석
Map<String, PriceRangeModel> _analyzePriceRangePrediction(List<PricePredictionSample> samples) {
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('📏 가격 범위 예측');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  final stateGroups = <String, List<PricePredictionSample>>{};
  for (final sample in samples) {
    stateGroups.putIfAbsent(sample.marketState, () => []).add(sample);
  }

  final models = <String, PriceRangeModel>{};

  stateGroups.forEach((state, stateSamples) {
    // ATR 배수 계산
    final atrMultipliers = stateSamples.map((s) => s.actualRange / s.atr5m).toList();
    final avgATRMultiplier = atrMultipliers.reduce((a, b) => a + b) / atrMultipliers.length;

    // 상승폭/하락폭의 ATR 배수
    final highMultipliers = stateSamples.map((s) => s.actualHighFromCurrent / s.atr5m).toList();
    final lowMultipliers = stateSamples.map((s) => s.actualLowFromCurrent / s.atr5m).toList();
    final avgHighMult = highMultipliers.reduce((a, b) => a + b) / highMultipliers.length;
    final avgLowMult = lowMultipliers.reduce((a, b) => a + b) / lowMultipliers.length;

    models[state] = PriceRangeModel(
      state: state,
      highMultiplier: avgHighMult,
      lowMultiplier: avgLowMult,
      rangeMultiplier: avgATRMultiplier,
    );

    print('[$state]');
    print('  총 범위 = ATR * ${avgATRMultiplier.toStringAsFixed(2)}');
    print('  최고가 = 현재가 + (ATR * ${avgHighMult.toStringAsFixed(2)})');
    print('  최저가 = 현재가 - (ATR * ${avgLowMult.toStringAsFixed(2)})');
    print('');
  });

  return models;
}

/// 예측 편차 분석
void _analyzePredictionError(
  List<PricePredictionSample> samples,
  Map<String, PriceRangeModel> models,
) {
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('📊 예측 편차 분석');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  final stateGroups = <String, List<PricePredictionSample>>{};
  for (final sample in samples) {
    stateGroups.putIfAbsent(sample.marketState, () => []).add(sample);
  }

  stateGroups.forEach((state, stateSamples) {
    final model = models[state];
    if (model == null) return;

    // 각 샘플에 대해 예측값 계산
    final highErrors = <double>[];
    final lowErrors = <double>[];
    final highErrorPercents = <double>[];
    final lowErrorPercents = <double>[];

    for (final sample in stateSamples) {
      // 예측값
      final predictedHigh = sample.currentPrice + (sample.atr5m * model.highMultiplier);
      final predictedLow = sample.currentPrice - (sample.atr5m * model.lowMultiplier);

      // 실제값
      final actualHigh = sample.actualHigh;
      final actualLow = sample.actualLow;

      // 오차 (절대값)
      final highError = (predictedHigh - actualHigh).abs();
      final lowError = (predictedLow - actualLow).abs();

      // 오차 (퍼센트)
      final highErrorPercent = (highError / sample.currentPrice) * 100;
      final lowErrorPercent = (lowError / sample.currentPrice) * 100;

      highErrors.add(highError);
      lowErrors.add(lowError);
      highErrorPercents.add(highErrorPercent);
      lowErrorPercents.add(lowErrorPercent);
    }

    // 평균 오차
    final avgHighError = highErrors.reduce((a, b) => a + b) / highErrors.length;
    final avgLowError = lowErrors.reduce((a, b) => a + b) / lowErrors.length;
    final avgHighErrorPercent = highErrorPercents.reduce((a, b) => a + b) / highErrorPercents.length;
    final avgLowErrorPercent = lowErrorPercents.reduce((a, b) => a + b) / lowErrorPercents.length;

    // 최대/최소 오차
    final maxHighError = highErrors.reduce(max);
    final minHighError = highErrors.reduce(min);
    final maxLowError = lowErrors.reduce(max);
    final minLowError = lowErrors.reduce(min);

    // 오차 표준편차
    final highStdDev = _calculateStdDev(highErrors);
    final lowStdDev = _calculateStdDev(lowErrors);

    // 정확도 (±10% 이내)
    final highAccurate = highErrorPercents.where((e) => e <= 10.0).length;
    final lowAccurate = lowErrorPercents.where((e) => e <= 10.0).length;

    print('[$state] (${stateSamples.length}개 샘플)');
    print('');
    print('  최고가 예측:');
    print('    평균 오차: \$${avgHighError.toStringAsFixed(2)} (${avgHighErrorPercent.toStringAsFixed(2)}%)');
    print('    표준편차: \$${highStdDev.toStringAsFixed(2)}');
    print('    최대 오차: \$${maxHighError.toStringAsFixed(2)} / 최소: \$${minHighError.toStringAsFixed(2)}');
    print('    정확도 (±10% 이내): ${highAccurate}/${stateSamples.length} (${(highAccurate / stateSamples.length * 100).toStringAsFixed(1)}%)');
    print('');
    print('  최저가 예측:');
    print('    평균 오차: \$${avgLowError.toStringAsFixed(2)} (${avgLowErrorPercent.toStringAsFixed(2)}%)');
    print('    표준편차: \$${lowStdDev.toStringAsFixed(2)}');
    print('    최대 오차: \$${maxLowError.toStringAsFixed(2)} / 최소: \$${minLowError.toStringAsFixed(2)}');
    print('    정확도 (±10% 이내): ${lowAccurate}/${stateSamples.length} (${(lowAccurate / stateSamples.length * 100).toStringAsFixed(1)}%)');
    print('');
  });
}

double _calculateStdDev(List<double> values) {
  if (values.isEmpty) return 0.0;
  final mean = values.reduce((a, b) => a + b) / values.length;
  final variance = values.map((v) => pow(v - mean, 2)).reduce((a, b) => a + b) / values.length;
  return sqrt(variance);
}

double _calculateATR(List<KlineData> klines) {
  if (klines.length < 2) return 0.0;

  final trueRanges = <double>[];
  for (int i = 1; i < klines.length; i++) {
    final high = klines[i].high;
    final low = klines[i].low;
    final prevClose = klines[i - 1].close;

    final tr = max(
      high - low,
      max((high - prevClose).abs(), (low - prevClose).abs()),
    );
    trueRanges.add(tr);
  }

  return trueRanges.reduce((a, b) => a + b) / trueRanges.length;
}

Future<void> _saveCSV(List<PricePredictionSample> samples) async {
  final csvLines = <String>[];

  csvLines.add('Timestamp,CurrentPrice,MarketState,RSI5m,MACD5m,BBWidth5m,BBPos5m,Vol5m,ATR5m,'
      'RSI30m,MACD30m,BBWidth30m,ActualDir,ActualHigh,ActualLow,ActualRange,HighMove,LowMove');

  for (final s in samples) {
    csvLines.add('${s.timestamp.toIso8601String()},${s.currentPrice},${s.marketState},'
        '${s.rsi5m},${s.macd5m},${s.bbWidth5m},${s.bbPosition5m},${s.volumeRatio5m},${s.atr5m},'
        '${s.rsi30m},${s.macd30m},${s.bbWidth30m},'
        '${s.actualDirection},${s.actualHigh},${s.actualLow},${s.actualRange},'
        '${s.actualHighFromCurrent},${s.actualLowFromCurrent}');
  }

  final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').substring(0, 19);
  final filename = 'price_prediction_$timestamp.csv';
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

class PricePredictionSample {
  final DateTime timestamp;
  final double currentPrice;
  final String marketState;

  final double rsi5m;
  final double macd5m;
  final double bbWidth5m;
  final double bbPosition5m;
  final double volumeRatio5m;
  final double atr5m;

  final double rsi30m;
  final double macd30m;
  final double bbWidth30m;

  final String actualDirection;
  final double actualHigh;
  final double actualLow;
  final double actualRange;
  final double actualHighFromCurrent;
  final double actualLowFromCurrent;

  PricePredictionSample({
    required this.timestamp,
    required this.currentPrice,
    required this.marketState,
    required this.rsi5m,
    required this.macd5m,
    required this.bbWidth5m,
    required this.bbPosition5m,
    required this.volumeRatio5m,
    required this.atr5m,
    required this.rsi30m,
    required this.macd30m,
    required this.bbWidth30m,
    required this.actualDirection,
    required this.actualHigh,
    required this.actualLow,
    required this.actualRange,
    required this.actualHighFromCurrent,
    required this.actualLowFromCurrent,
  });
}

class DirectionModel {
  final String state;
  final int totalSamples;
  final double upProbability;
  final String bestCondition;
  final double accuracy;

  DirectionModel({
    required this.state,
    required this.totalSamples,
    required this.upProbability,
    required this.bestCondition,
    required this.accuracy,
  });
}

class PriceRangeModel {
  final String state;
  final double highMultiplier;
  final double lowMultiplier;
  final double rangeMultiplier;

  PriceRangeModel({
    required this.state,
    required this.highMultiplier,
    required this.lowMultiplier,
    required this.rangeMultiplier,
  });
}
