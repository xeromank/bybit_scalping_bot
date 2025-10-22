import 'package:bybit_scalping_bot/backtesting/backtest_engine.dart';
import 'package:bybit_scalping_bot/utils/technical_indicators.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// 역산 분석: 일주일 데이터로 최적 예측 모델 찾기
void main() async {
  print('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('🔬 예측 모델 역산 분석');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  // 일주일 데이터 (2025-10-15 ~ 2025-10-22)
  final startTime = DateTime.utc(2025, 10, 15, 0, 0);
  final endTime = DateTime.utc(2025, 10, 22, 0, 0);

  print('분석 기간: ${startTime.toString().substring(0, 10)} ~ ${endTime.toString().substring(0, 10)}');
  print('목표: 80% 시점 지표로 다음 캔들 가격 예측\n');

  print('📥 5분봉 데이터 다운로드 중...');
  final klines5m = await _fetchKlines(
    symbol: 'ETHUSDT',
    interval: '5',
    startTime: startTime,
    endTime: endTime,
  );

  print('📥 30분봉 데이터 다운로드 중...');
  final klines30m = await _fetchKlines(
    symbol: 'ETHUSDT',
    interval: '30',
    startTime: startTime,
    endTime: endTime,
  );

  if (klines5m.isEmpty || klines30m.isEmpty) {
    print('❌ 데이터를 가져올 수 없습니다.');
    return;
  }

  print('✅ 5분봉: ${klines5m.length}개');
  print('✅ 30분봉: ${klines30m.length}개\n');

  print('🔍 역산 분석 시작...\n');

  final samples = <PredictionSample>[];

  // 각 5분봉마다 분석
  for (int i = 50; i < klines5m.length - 1; i++) {
    final currentKline = klines5m[i];
    final nextKline = klines5m[i + 1];
    final recentKlines = klines5m.sublist(i - 49, i + 1);

    // 5분봉 지표 계산
    final closePrices5m = recentKlines.map((k) => k.close).toList();
    final volumes5m = recentKlines.map((k) => k.volume).toList();

    final rsi5m = calculateRSI(closePrices5m, 14);
    final bb5m = calculateBollingerBands(closePrices5m, 20, 2.0);
    final macd5m = calculateMACDFullSeries(closePrices5m).last;
    final volumeRatio5m = analyzeVolume(volumes5m).relativeVolumeRatio;
    final atr5m = _calculateATR(recentKlines.sublist(recentKlines.length - 14));

    // 30분봉 매칭 (현재 5분봉이 속한 30분봉 찾기)
    final matching30m = klines30m.where((k) {
      return k.timestamp.isBefore(currentKline.timestamp.add(Duration(minutes: 1))) &&
          k.timestamp.isAfter(currentKline.timestamp.subtract(Duration(minutes: 30)));
    }).toList();

    if (matching30m.isEmpty) continue;

    // 30분봉 지표 계산 (최근 50개)
    final idx30m = klines30m.indexOf(matching30m.first);
    if (idx30m < 50) continue;

    final recent30m = klines30m.sublist(idx30m - 49, idx30m + 1);
    final closePrices30m = recent30m.map((k) => k.close).toList();

    final rsi30m = calculateRSI(closePrices30m, 14);
    final bb30m = calculateBollingerBands(closePrices30m, 20, 2.0);
    final macd30m = calculateMACDFullSeries(closePrices30m).last;

    // EMA 정렬 확인
    final ema9_5m = _calculateEMA(closePrices5m, 9);
    final ema21_5m = _calculateEMA(closePrices5m, 21);
    final ema50_5m = _calculateEMA(closePrices5m, 50);

    final ema9_30m = _calculateEMA(closePrices30m, 9);
    final ema21_30m = _calculateEMA(closePrices30m, 21);
    final ema50_30m = _calculateEMA(closePrices30m, 50);

    // 다음 캔들의 실제 결과
    final actualHigh = nextKline.high;
    final actualLow = nextKline.low;
    final actualClose = nextKline.close;
    final actualRange = actualHigh - actualLow;
    final actualDirection = actualClose > currentKline.close ? 'UP' : 'DOWN';
    final actualChangePercent = ((actualClose - currentKline.close) / currentKline.close) * 100;

    samples.add(PredictionSample(
      timestamp: currentKline.timestamp,
      currentPrice: currentKline.close,
      // 5분봉 지표
      rsi5m: rsi5m,
      macd5m: macd5m.histogram,
      bbPosition5m: (currentKline.close - bb5m.lower) / (bb5m.upper - bb5m.lower),
      bbWidth5m: (bb5m.upper - bb5m.lower) / bb5m.middle,
      volumeRatio5m: volumeRatio5m,
      atr5m: atr5m,
      ema9_5m: ema9_5m,
      ema21_5m: ema21_5m,
      ema50_5m: ema50_5m,
      // 30분봉 지표
      rsi30m: rsi30m,
      macd30m: macd30m.histogram,
      bbPosition30m: (currentKline.close - bb30m.lower) / (bb30m.upper - bb30m.lower),
      ema9_30m: ema9_30m,
      ema21_30m: ema21_30m,
      ema50_30m: ema50_30m,
      // 실제 결과
      actualDirection: actualDirection,
      actualHigh: actualHigh,
      actualLow: actualLow,
      actualClose: actualClose,
      actualRange: actualRange,
      actualChangePercent: actualChangePercent,
    ));
  }

  print('✅ ${samples.length}개 샘플 수집 완료\n');

  // 분석 시작
  _analyzeDirectionPrediction(samples);
  _analyzeRangePrediction(samples);
  _generateOptimalStrategy(samples);

  // CSV 저장
  await _saveSamplesCSV(samples);

  print('\n✅ 분석 완료!');
}

/// 방향 예측 분석
void _analyzeDirectionPrediction(List<PredictionSample> samples) {
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('📊 방향 예측 분석');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  // 상승/하락 샘플 분리
  final upSamples = samples.where((s) => s.actualDirection == 'UP').toList();
  final downSamples = samples.where((s) => s.actualDirection == 'DOWN').toList();

  print('상승: ${upSamples.length}개 (${(upSamples.length / samples.length * 100).toStringAsFixed(1)}%)');
  print('하락: ${downSamples.length}개 (${(downSamples.length / samples.length * 100).toStringAsFixed(1)}%)\n');

  // 지표별 평균 비교
  print('지표별 평균 비교:');
  print('─────────────────────────────────────────────');
  _compareIndicator('RSI 5m', upSamples, downSamples, (s) => s.rsi5m);
  _compareIndicator('MACD 5m', upSamples, downSamples, (s) => s.macd5m);
  _compareIndicator('BB Position 5m', upSamples, downSamples, (s) => s.bbPosition5m);
  _compareIndicator('Volume Ratio 5m', upSamples, downSamples, (s) => s.volumeRatio5m);
  _compareIndicator('RSI 30m', upSamples, downSamples, (s) => s.rsi30m);
  _compareIndicator('MACD 30m', upSamples, downSamples, (s) => s.macd30m);

  // EMA 정렬 상태
  final upEmaAligned = upSamples.where((s) => s.ema9_5m > s.ema21_5m && s.ema21_5m > s.ema50_5m).length;
  final downEmaAligned = downSamples.where((s) => s.ema9_5m < s.ema21_5m && s.ema21_5m < s.ema50_5m).length;

  print('\nEMA 정렬 (5m):');
  print('  상승 시 정배열: ${upEmaAligned}/${upSamples.length} (${(upEmaAligned / upSamples.length * 100).toStringAsFixed(1)}%)');
  print('  하락 시 역배열: ${downEmaAligned}/${downSamples.length} (${(downEmaAligned / downSamples.length * 100).toStringAsFixed(1)}%)');
  print('');
}

/// 가격 범위 예측 분석
void _analyzeRangePrediction(List<PredictionSample> samples) {
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('📏 가격 범위 예측 분석');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  // ATR vs 실제 범위 비교
  final atrAccuracy = <double>[];
  final bbWidthAccuracy = <double>[];

  for (final sample in samples) {
    final atrRatio = sample.actualRange / sample.atr5m;
    atrAccuracy.add(atrRatio);

    final bbWidthAmount = sample.bbWidth5m * sample.currentPrice;
    final bbWidthRatio = sample.actualRange / bbWidthAmount;
    bbWidthAccuracy.add(bbWidthRatio);
  }

  final avgATRRatio = atrAccuracy.reduce((a, b) => a + b) / atrAccuracy.length;
  final avgBBWidthRatio = bbWidthAccuracy.reduce((a, b) => a + b) / bbWidthAccuracy.length;

  print('ATR 기반 예측:');
  print('  평균 실제범위/ATR 비율: ${avgATRRatio.toStringAsFixed(2)}x');
  print('  → 다음 캔들 예상 범위 = ATR * ${avgATRRatio.toStringAsFixed(2)}\n');

  print('BB Width 기반 예측:');
  print('  평균 실제범위/BBWidth 비율: ${avgBBWidthRatio.toStringAsFixed(2)}x');
  print('  → 다음 캔들 예상 범위 = BB Width * ${avgBBWidthRatio.toStringAsFixed(2)}\n');

  // 변동성 구간별 분석
  print('변동성별 범위:');
  final sortedByVolume = List<PredictionSample>.from(samples)
    ..sort((a, b) => a.volumeRatio5m.compareTo(b.volumeRatio5m));

  final lowVol = sortedByVolume.sublist(0, sortedByVolume.length ~/ 3);
  final midVol = sortedByVolume.sublist(sortedByVolume.length ~/ 3, sortedByVolume.length * 2 ~/ 3);
  final highVol = sortedByVolume.sublist(sortedByVolume.length * 2 ~/ 3);

  final avgRangeLow = lowVol.map((s) => s.actualRange).reduce((a, b) => a + b) / lowVol.length;
  final avgRangeMid = midVol.map((s) => s.actualRange).reduce((a, b) => a + b) / midVol.length;
  final avgRangeHigh = highVol.map((s) => s.actualRange).reduce((a, b) => a + b) / highVol.length;

  print('  낮은 거래량: 평균 범위 \$${avgRangeLow.toStringAsFixed(2)}');
  print('  중간 거래량: 평균 범위 \$${avgRangeMid.toStringAsFixed(2)}');
  print('  높은 거래량: 평균 범위 \$${avgRangeHigh.toStringAsFixed(2)}');
  print('');
}

/// 최적 전략 생성
void _generateOptimalStrategy(List<PredictionSample> samples) {
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('🎯 최적 예측 전략');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  // 여러 조건 조합 테스트
  final strategies = <String, StrategyResult>{};

  // 전략 1: RSI + MACD (5m + 30m)
  strategies['RSI_MACD'] = _testStrategy(samples, (s) {
    return s.rsi5m > 55 && s.macd5m > 0 && s.rsi30m > 50 && s.macd30m > 0;
  }, (s) {
    return s.rsi5m < 45 && s.macd5m < 0 && s.rsi30m < 50 && s.macd30m < 0;
  });

  // 전략 2: EMA 정렬 + RSI
  strategies['EMA_RSI'] = _testStrategy(samples, (s) {
    return s.ema9_5m > s.ema21_5m && s.ema21_5m > s.ema50_5m &&
           s.ema9_30m > s.ema21_30m && s.rsi5m > 50;
  }, (s) {
    return s.ema9_5m < s.ema21_5m && s.ema21_5m < s.ema50_5m &&
           s.ema9_30m < s.ema21_30m && s.rsi5m < 50;
  });

  // 전략 3: BB Position + MACD
  strategies['BB_MACD'] = _testStrategy(samples, (s) {
    return s.bbPosition5m > 0.6 && s.macd5m > 0 && s.macd30m > 0;
  }, (s) {
    return s.bbPosition5m < 0.4 && s.macd5m < 0 && s.macd30m < 0;
  });

  // 전략 4: 복합 (RSI 5m&30m + MACD 5m&30m + EMA)
  strategies['COMPLEX'] = _testStrategy(samples, (s) {
    return s.rsi5m > 55 && s.rsi30m > 50 &&
           s.macd5m > 0 && s.macd30m > 0 &&
           s.ema9_5m > s.ema21_5m;
  }, (s) {
    return s.rsi5m < 45 && s.rsi30m < 50 &&
           s.macd5m < 0 && s.macd30m < 0 &&
           s.ema9_5m < s.ema21_5m;
  });

  // 전략 5: 스퀴즈 필터 추가
  strategies['WITH_SQUEEZE_FILTER'] = _testStrategyWithFilter(samples,
    // 스퀴즈 필터: 30분봉이 스퀴즈면 제외
    (s) {
      // BB Width가 평균 대비 작고, RSI 중립이면 스퀴즈
      return s.bbWidth5m < 0.03 || // BB Width 3% 미만
             (s.rsi30m > 45 && s.rsi30m < 55 && s.macd30m.abs() < 1.0);
    },
    // 상승 조건
    (s) {
      return s.rsi5m > 55 && s.rsi30m > 50 &&
             s.macd5m > 0 && s.macd30m > 0 &&
             s.ema9_5m > s.ema21_5m;
    },
    // 하락 조건
    (s) {
      return s.rsi5m < 45 && s.rsi30m < 50 &&
             s.macd5m < 0 && s.macd30m < 0 &&
             s.ema9_5m < s.ema21_5m;
    });

  // 전략 6: 강한 추세만 (30분봉 극단 RSI)
  strategies['STRONG_TREND_ONLY'] = _testStrategy(samples, (s) {
    return s.rsi5m > 55 && s.rsi30m > 60 && // 30분봉 RSI 더 극단적
           s.macd5m > 0 && s.macd30m > 2.0 && // MACD도 강하게
           s.ema9_5m > s.ema21_5m;
  }, (s) {
    return s.rsi5m < 45 && s.rsi30m < 40 &&
           s.macd5m < 0 && s.macd30m < -2.0 &&
           s.ema9_5m < s.ema21_5m;
  });

  // 결과 출력
  strategies.forEach((name, result) {
    print('전략: $name');
    print('  정확도: ${(result.accuracy * 100).toStringAsFixed(1)}%');
    print('  상승 예측: ${result.upPredicted}개 (정확: ${result.upCorrect}개, ${(result.upCorrect / result.upPredicted * 100).toStringAsFixed(1)}%)');
    print('  하락 예측: ${result.downPredicted}개 (정확: ${result.downCorrect}개, ${(result.downCorrect / result.downPredicted * 100).toStringAsFixed(1)}%)');
    print('  평균 수익 (예측 맞을 때): ${result.avgProfitWhenCorrect.toStringAsFixed(2)}%');
    print('');
  });

  // 최고 전략 선택
  final bestStrategy = strategies.entries.reduce((a, b) =>
    a.value.accuracy > b.value.accuracy ? a : b);

  print('🏆 최고 전략: ${bestStrategy.key}');
  print('   정확도: ${(bestStrategy.value.accuracy * 100).toStringAsFixed(1)}%\n');
}

/// 전략 테스트
StrategyResult _testStrategy(
  List<PredictionSample> samples,
  bool Function(PredictionSample) upCondition,
  bool Function(PredictionSample) downCondition,
) {
  int upPredicted = 0, upCorrect = 0;
  int downPredicted = 0, downCorrect = 0;
  final profits = <double>[];

  for (final sample in samples) {
    if (upCondition(sample)) {
      upPredicted++;
      if (sample.actualDirection == 'UP') {
        upCorrect++;
        profits.add(sample.actualChangePercent);
      }
    } else if (downCondition(sample)) {
      downPredicted++;
      if (sample.actualDirection == 'DOWN') {
        downCorrect++;
        profits.add(sample.actualChangePercent.abs());
      }
    }
  }

  final totalPredicted = upPredicted + downPredicted;
  final totalCorrect = upCorrect + downCorrect;
  final accuracy = totalPredicted > 0 ? totalCorrect / totalPredicted : 0.0;
  final avgProfit = profits.isNotEmpty
    ? profits.reduce((a, b) => a + b) / profits.length
    : 0.0;

  return StrategyResult(
    upPredicted: upPredicted,
    upCorrect: upCorrect,
    downPredicted: downPredicted,
    downCorrect: downCorrect,
    accuracy: accuracy,
    avgProfitWhenCorrect: avgProfit,
  );
}

/// 필터 포함 전략 테스트
StrategyResult _testStrategyWithFilter(
  List<PredictionSample> samples,
  bool Function(PredictionSample) filterCondition, // 스퀴즈 필터
  bool Function(PredictionSample) upCondition,
  bool Function(PredictionSample) downCondition,
) {
  int upPredicted = 0, upCorrect = 0;
  int downPredicted = 0, downCorrect = 0;
  final profits = <double>[];
  int filtered = 0;

  for (final sample in samples) {
    // 스퀴즈면 거래 안 함
    if (filterCondition(sample)) {
      filtered++;
      continue;
    }

    if (upCondition(sample)) {
      upPredicted++;
      if (sample.actualDirection == 'UP') {
        upCorrect++;
        profits.add(sample.actualChangePercent);
      }
    } else if (downCondition(sample)) {
      downPredicted++;
      if (sample.actualDirection == 'DOWN') {
        downCorrect++;
        profits.add(sample.actualChangePercent.abs());
      }
    }
  }

  final totalPredicted = upPredicted + downPredicted;
  final totalCorrect = upCorrect + downCorrect;
  final accuracy = totalPredicted > 0 ? totalCorrect / totalPredicted : 0.0;
  final avgProfit = profits.isNotEmpty
    ? profits.reduce((a, b) => a + b) / profits.length
    : 0.0;

  print('  (필터링: ${filtered}개 제외)');

  return StrategyResult(
    upPredicted: upPredicted,
    upCorrect: upCorrect,
    downPredicted: downPredicted,
    downCorrect: downCorrect,
    accuracy: accuracy,
    avgProfitWhenCorrect: avgProfit,
  );
}

/// 지표 비교
void _compareIndicator(
  String name,
  List<PredictionSample> upSamples,
  List<PredictionSample> downSamples,
  double Function(PredictionSample) getValue,
) {
  final upAvg = upSamples.map(getValue).reduce((a, b) => a + b) / upSamples.length;
  final downAvg = downSamples.map(getValue).reduce((a, b) => a + b) / downSamples.length;
  final diff = upAvg - downAvg;

  print('$name: 상승 ${upAvg.toStringAsFixed(2)} vs 하락 ${downAvg.toStringAsFixed(2)} (차이: ${diff.toStringAsFixed(2)})');
}

/// ATR 계산
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

/// EMA 계산
double _calculateEMA(List<double> prices, int period) {
  if (prices.length < period) return prices.last;

  final multiplier = 2.0 / (period + 1);
  double ema = prices.sublist(0, period).reduce((a, b) => a + b) / period;

  for (int i = period; i < prices.length; i++) {
    ema = (prices[i] - ema) * multiplier + ema;
  }

  return ema;
}

/// CSV 저장
Future<void> _saveSamplesCSV(List<PredictionSample> samples) async {
  final csvLines = <String>[];

  csvLines.add('Timestamp,CurrentPrice,RSI5m,MACD5m,BBPos5m,BBWidth5m,Vol5m,ATR5m,'
      'RSI30m,MACD30m,BBPos30m,EMA9_5m,EMA21_5m,EMA50_5m,EMA9_30m,EMA21_30m,EMA50_30m,'
      'ActualDir,ActualHigh,ActualLow,ActualClose,ActualRange,ActualChange%');

  for (final s in samples) {
    csvLines.add('${s.timestamp.toIso8601String()},${s.currentPrice},'
        '${s.rsi5m},${s.macd5m},${s.bbPosition5m},${s.bbWidth5m},${s.volumeRatio5m},${s.atr5m},'
        '${s.rsi30m},${s.macd30m},${s.bbPosition30m},'
        '${s.ema9_5m},${s.ema21_5m},${s.ema50_5m},${s.ema9_30m},${s.ema21_30m},${s.ema50_30m},'
        '${s.actualDirection},${s.actualHigh},${s.actualLow},${s.actualClose},${s.actualRange},${s.actualChangePercent}');
  }

  final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').substring(0, 19);
  final filename = 'prediction_analysis_$timestamp.csv';
  await File(filename).writeAsString(csvLines.join('\n'));

  print('📄 CSV 저장: $filename');
}

/// Kline 데이터 가져오기
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

/// 예측 샘플
class PredictionSample {
  final DateTime timestamp;
  final double currentPrice;

  // 5분봉 지표
  final double rsi5m;
  final double macd5m;
  final double bbPosition5m;
  final double bbWidth5m;
  final double volumeRatio5m;
  final double atr5m;
  final double ema9_5m;
  final double ema21_5m;
  final double ema50_5m;

  // 30분봉 지표
  final double rsi30m;
  final double macd30m;
  final double bbPosition30m;
  final double ema9_30m;
  final double ema21_30m;
  final double ema50_30m;

  // 실제 결과
  final String actualDirection;
  final double actualHigh;
  final double actualLow;
  final double actualClose;
  final double actualRange;
  final double actualChangePercent;

  PredictionSample({
    required this.timestamp,
    required this.currentPrice,
    required this.rsi5m,
    required this.macd5m,
    required this.bbPosition5m,
    required this.bbWidth5m,
    required this.volumeRatio5m,
    required this.atr5m,
    required this.ema9_5m,
    required this.ema21_5m,
    required this.ema50_5m,
    required this.rsi30m,
    required this.macd30m,
    required this.bbPosition30m,
    required this.ema9_30m,
    required this.ema21_30m,
    required this.ema50_30m,
    required this.actualDirection,
    required this.actualHigh,
    required this.actualLow,
    required this.actualClose,
    required this.actualRange,
    required this.actualChangePercent,
  });
}

/// 전략 결과
class StrategyResult {
  final int upPredicted;
  final int upCorrect;
  final int downPredicted;
  final int downCorrect;
  final double accuracy;
  final double avgProfitWhenCorrect;

  StrategyResult({
    required this.upPredicted,
    required this.upCorrect,
    required this.downPredicted,
    required this.downCorrect,
    required this.accuracy,
    required this.avgProfitWhenCorrect,
  });
}
