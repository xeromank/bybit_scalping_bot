import 'package:bybit_scalping_bot/backtesting/backtest_engine.dart';
import 'package:bybit_scalping_bot/utils/technical_indicators.dart';

/// 밴드워킹 분석 결과
class BandWalkingAnalysis {
  final DateTime timestamp;
  final double price;
  final double rsi;
  final double bbUpper;
  final double bbMiddle;
  final double bbLower;
  final double bbWidth;
  final double bbWidthChangePercent;
  final int consecutiveBandOutside;
  final double macdHistogram;
  final double macdHistogramChange;
  final double volumeRatio;
  final int bandWalkingScore;
  final String risk;
  final List<String> signals;

  BandWalkingAnalysis({
    required this.timestamp,
    required this.price,
    required this.rsi,
    required this.bbUpper,
    required this.bbMiddle,
    required this.bbLower,
    required this.bbWidth,
    required this.bbWidthChangePercent,
    required this.consecutiveBandOutside,
    required this.macdHistogram,
    required this.macdHistogramChange,
    required this.volumeRatio,
    required this.bandWalkingScore,
    required this.risk,
    required this.signals,
  });

  @override
  String toString() {
    return '''
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
⏰ ${timestamp.toString().substring(0, 16)} UTC
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
💰 Price: \$${price.toStringAsFixed(2)}
📊 RSI: ${rsi.toStringAsFixed(2)}
📈 BB: Upper \$${bbUpper.toStringAsFixed(2)} / Mid \$${bbMiddle.toStringAsFixed(2)} / Lower \$${bbLower.toStringAsFixed(2)}
📏 BB Width: ${bbWidth.toStringAsFixed(2)} (${bbWidthChangePercent >= 0 ? '+' : ''}${bbWidthChangePercent.toStringAsFixed(2)}%)
🔄 Consecutive Outside: $consecutiveBandOutside candles
📉 MACD Histogram: ${macdHistogram.toStringAsFixed(2)} (Change: ${macdHistogramChange >= 0 ? '+' : ''}${macdHistogramChange.toStringAsFixed(2)})
📊 Volume Ratio: ${volumeRatio.toStringAsFixed(2)}x

🎯 Band Walking Score: $bandWalkingScore/100
⚠️  Risk Level: $risk

🔍 Signals:
${signals.map((s) => '   - $s').join('\n')}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
''';
  }

  String toCsv() {
    return '${timestamp.toIso8601String()},$price,${rsi.toStringAsFixed(2)},${bbWidth.toStringAsFixed(2)},${bbWidthChangePercent.toStringAsFixed(2)},$consecutiveBandOutside,${macdHistogram.toStringAsFixed(2)},${macdHistogramChange.toStringAsFixed(2)},${volumeRatio.toStringAsFixed(2)},$bandWalkingScore,$risk';
  }

  static String csvHeader() {
    return 'Timestamp,Price,RSI,BB_Width,BB_Width_Change%,Consecutive_Outside,MACD_Histogram,MACD_Change,Volume_Ratio,Score,Risk';
  }
}

/// 밴드워킹 분석기
class BandWalkingAnalyzer {
  /// 특정 시간대의 밴드워킹 패턴 분석
  static List<BandWalkingAnalysis> analyzePeriod({
    required List<KlineData> klines,
    required DateTime startTime,
    required DateTime endTime,
  }) {
    List<BandWalkingAnalysis> results = [];

    // 최소 50개 캔들 필요
    if (klines.length < 50) {
      throw ArgumentError('Need at least 50 klines for analysis');
    }

    print('\n🔍 밴드워킹 분석 시작');
    print('Period: $startTime ~ $endTime UTC');
    print('Total Klines: ${klines.length}');

    // 분석할 시간대의 캔들 찾기
    for (int i = 49; i < klines.length; i++) {
      final currentKline = klines[i];

      // 시간대 필터링
      if (currentKline.timestamp.isBefore(startTime) ||
          currentKline.timestamp.isAfter(endTime)) {
        continue;
      }

      // 최근 50개 캔들로 지표 계산
      final recentKlines = klines.sublist(i - 49, i + 1);
      final closePrices = recentKlines.map((k) => k.close).toList();
      final volumes = recentKlines.map((k) => k.volume).toList();

      // 지표 계산
      final rsi = calculateRSI(closePrices, 14);
      final bb = calculateBollingerBands(closePrices, 20, 2.0);
      final macdSeries = calculateMACDFullSeries(closePrices);
      final currentMACD = macdSeries.last;

      // BB Width 계산
      final bbWidth = (bb.upper - bb.lower) / bb.middle;

      // 이전 BB Width (이전 캔들의 BB 계산)
      double prevBBWidth = 0;
      if (i >= 50) {
        final prevKlines = klines.sublist(i - 50, i);
        final prevClosePrices = prevKlines.map((k) => k.close).toList();
        final prevBB = calculateBollingerBands(prevClosePrices, 20, 2.0);
        prevBBWidth = (prevBB.upper - prevBB.lower) / prevBB.middle;
      }
      final bbWidthChangePercent = prevBBWidth > 0
          ? ((bbWidth - prevBBWidth) / prevBBWidth) * 100.0
          : 0.0;

      // 연속 밴드 밖 캔들 카운트
      int consecutiveOutside = 0;
      for (int j = 0; j < 5 && j < recentKlines.length; j++) {
        final candle = recentKlines[recentKlines.length - 1 - j];
        if (candle.close > bb.upper || candle.close < bb.lower) {
          consecutiveOutside++;
        } else {
          break;
        }
      }

      // MACD 히스토그램 변화
      double macdHistogramChange = 0;
      if (macdSeries.length >= 2) {
        macdHistogramChange = currentMACD.histogram - macdSeries[macdSeries.length - 2].histogram;
      }

      // Volume 비율
      final avgVolume = volumes.take(20).reduce((a, b) => a + b) / 20;
      final volumeRatio = currentKline.volume / avgVolume;

      // 밴드워킹 점수 계산
      int score = 0;
      List<String> signals = [];

      // 1. BBW 확장 (25점)
      if (bbWidthChangePercent > 5.0) {
        score += 25;
        signals.add('✅ BB Width 급증 ${bbWidthChangePercent.toStringAsFixed(1)}%');
      } else if (bbWidthChangePercent > 2.0) {
        score += 15;
        signals.add('⚠️  BB Width 확장 ${bbWidthChangePercent.toStringAsFixed(1)}%');
      }

      // 2. 연속 밴드 밖 캔들 (30점)
      if (consecutiveOutside >= 3) {
        score += 30;
        signals.add('✅ $consecutiveOutside개 연속 밴드 밖 캔들');
      } else if (consecutiveOutside >= 2) {
        score += 20;
        signals.add('⚠️  $consecutiveOutside개 연속 밴드 밖 캔들');
      }

      // 3. MACD 히스토그램 확장 (20점)
      final histogramAbs = currentMACD.histogram.abs();
      if (macdHistogramChange.abs() > 1.0 &&
          ((currentMACD.histogram > 0 && macdHistogramChange > 0) ||
           (currentMACD.histogram < 0 && macdHistogramChange < 0))) {
        score += 20;
        signals.add('✅ MACD 히스토그램 지속 확장 (${currentMACD.histogram.toStringAsFixed(2)})');
      } else if (histogramAbs > 5.0) {
        score += 10;
        signals.add('⚠️  MACD 히스토그램 강함 (${currentMACD.histogram.toStringAsFixed(2)})');
      }

      // 4. Volume 확인 (15점)
      if (volumeRatio > 2.0) {
        score += 15;
        signals.add('✅ 높은 거래량 ${volumeRatio.toStringAsFixed(1)}x');
      } else if (volumeRatio > 1.5) {
        score += 10;
        signals.add('⚠️  거래량 증가 ${volumeRatio.toStringAsFixed(1)}x');
      }

      // 5. RSI 지속 (10점)
      if (rsi > 70 || rsi < 30) {
        // 최근 3개 캔들의 RSI가 모두 극단 구간인지 확인
        bool sustained = true;
        for (int j = 1; j <= 3 && i - j >= 49; j++) {
          final prevRecentKlines = klines.sublist(i - j - 49, i - j + 1);
          final prevClosePrices = prevRecentKlines.map((k) => k.close).toList();
          final prevRsi = calculateRSI(prevClosePrices, 14);

          if (rsi > 70 && prevRsi < 65) sustained = false;
          if (rsi < 30 && prevRsi > 35) sustained = false;
        }

        if (sustained) {
          score += 10;
          signals.add('✅ RSI ${rsi > 70 ? "과매수" : "과매도"} 지속 (${rsi.toStringAsFixed(1)})');
        }
      }

      // Risk Level 결정
      String risk;
      if (score >= 70) {
        risk = 'HIGH';
      } else if (score >= 50) {
        risk = 'MEDIUM';
      } else if (score >= 30) {
        risk = 'LOW';
      } else {
        risk = 'NONE';
      }

      // 결과 저장
      results.add(BandWalkingAnalysis(
        timestamp: currentKline.timestamp,
        price: currentKline.close,
        rsi: rsi,
        bbUpper: bb.upper,
        bbMiddle: bb.middle,
        bbLower: bb.lower,
        bbWidth: bbWidth,
        bbWidthChangePercent: bbWidthChangePercent,
        consecutiveBandOutside: consecutiveOutside,
        macdHistogram: currentMACD.histogram,
        macdHistogramChange: macdHistogramChange,
        volumeRatio: volumeRatio,
        bandWalkingScore: score,
        risk: risk,
        signals: signals,
      ));
    }

    return results;
  }

  /// 밴드워킹 패턴 요약
  static void printSummary(List<BandWalkingAnalysis> analyses) {
    if (analyses.isEmpty) {
      print('\n⚠️  분석 결과 없음');
      return;
    }

    print('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    print('📊 밴드워킹 분석 요약');
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    print('Total Candles Analyzed: ${analyses.length}');

    final highRisk = analyses.where((a) => a.risk == 'HIGH').length;
    final mediumRisk = analyses.where((a) => a.risk == 'MEDIUM').length;
    final lowRisk = analyses.where((a) => a.risk == 'LOW').length;
    final noRisk = analyses.where((a) => a.risk == 'NONE').length;

    print('\nRisk Distribution:');
    print('  🔴 HIGH:   $highRisk (${(highRisk / analyses.length * 100).toStringAsFixed(1)}%)');
    print('  🟠 MEDIUM: $mediumRisk (${(mediumRisk / analyses.length * 100).toStringAsFixed(1)}%)');
    print('  🟡 LOW:    $lowRisk (${(lowRisk / analyses.length * 100).toStringAsFixed(1)}%)');
    print('  🟢 NONE:   $noRisk (${(noRisk / analyses.length * 100).toStringAsFixed(1)}%)');

    // 가장 높은 점수의 캔들들 찾기
    final sortedByScore = List<BandWalkingAnalysis>.from(analyses)
      ..sort((a, b) => b.bandWalkingScore.compareTo(a.bandWalkingScore));

    print('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    print('🔥 상위 5개 밴드워킹 신호:');
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

    for (int i = 0; i < 5 && i < sortedByScore.length; i++) {
      final analysis = sortedByScore[i];
      print('\n${i + 1}. ${analysis.timestamp.toString().substring(0, 16)} UTC');
      print('   Score: ${analysis.bandWalkingScore}/100 (${analysis.risk})');
      print('   Price: \$${analysis.price.toStringAsFixed(2)}');
      print('   Signals:');
      for (final signal in analysis.signals) {
        print('     $signal');
      }
    }

    print('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
  }
}
