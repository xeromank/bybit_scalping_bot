/// Signal strength calculation for hybrid trading strategy
///
/// Calculates signal strength (0-10 points) based on:
/// - Bollinger Band deviation (0-3 points)
/// - RSI extreme values (0-3 points)
/// - Volume spike (0-2 points)
/// - Candle size (0-2 points)

import 'package:bybit_scalping_bot/utils/technical_indicators.dart';

/// Signal strength result
class SignalStrength {
  final double totalScore;
  final double bollingerScore;
  final double rsiScore;
  final double volumeScore;
  final double candleSizeScore;
  final String signalGrade;
  final String recommendation;

  SignalStrength({
    required this.totalScore,
    required this.bollingerScore,
    required this.rsiScore,
    required this.volumeScore,
    required this.candleSizeScore,
    required this.signalGrade,
    required this.recommendation,
  });

  /// Returns true if signal is strong enough for immediate entry
  bool get isExtremeSignal => totalScore >= 8.0;

  /// Returns true if signal is strong (can enter in late candle)
  bool get isStrongSignal => totalScore >= 6.0;

  /// Returns true if signal is moderate (wait for candle close)
  bool get isModerateSignal => totalScore >= 4.0;

  /// Returns true if signal is weak (skip entry)
  bool get isWeakSignal => totalScore < 4.0;

  @override
  String toString() {
    return 'SignalStrength(total: ${totalScore.toStringAsFixed(1)}/10, '
        'BB: ${bollingerScore.toStringAsFixed(1)}, '
        'RSI: ${rsiScore.toStringAsFixed(1)}, '
        'Vol: ${volumeScore.toStringAsFixed(1)}, '
        'Candle: ${candleSizeScore.toStringAsFixed(1)}, '
        'Grade: $signalGrade)';
  }
}

/// Calculates signal strength for Bollinger Band strategy
SignalStrength calculateBollingerSignalStrength({
  required TechnicalAnalysis analysis,
  required bool isLongSignal,
  required List<double> recentClosePrices,
}) {
  double bollingerScore = 0.0;
  double rsiScore = 0.0;
  double volumeScore = 0.0;
  double candleSizeScore = 0.0;

  final bb = analysis.bollingerBands!;
  final currentPrice = analysis.currentPrice;
  final rsi = analysis.bollingerRsi!;
  final currentVolume = analysis.currentVolume;
  final volumeMA5 = analysis.volumeMA5;

  // 1. Bollinger Band deviation score (0-3 points)
  if (isLongSignal) {
    // Long: price below lower band
    final deviation = (bb.lower - currentPrice) / bb.lower * 100;
    if (deviation >= 0.5) {
      bollingerScore = 3.0;
    } else if (deviation >= 0.3) {
      bollingerScore = 2.0;
    } else if (deviation >= 0.1) {
      bollingerScore = 1.0;
    }
  } else {
    // Short: price above upper band
    final deviation = (currentPrice - bb.upper) / bb.upper * 100;
    if (deviation >= 0.5) {
      bollingerScore = 3.0;
    } else if (deviation >= 0.3) {
      bollingerScore = 2.0;
    } else if (deviation >= 0.1) {
      bollingerScore = 1.0;
    }
  }

  // 2. RSI extreme value score (0-3 points)
  if (isLongSignal) {
    // Long: RSI oversold
    if (rsi < 20) {
      rsiScore = 3.0;
    } else if (rsi < 25) {
      rsiScore = 2.0;
    } else if (rsi < 30) {
      rsiScore = 1.0;
    }
  } else {
    // Short: RSI overbought
    if (rsi > 80) {
      rsiScore = 3.0;
    } else if (rsi > 75) {
      rsiScore = 2.0;
    } else if (rsi > 70) {
      rsiScore = 1.0;
    }
  }

  // 3. Volume spike score (0-2 points)
  final volumeRatio = currentVolume / volumeMA5;
  if (volumeRatio >= 3.0) {
    volumeScore = 2.0;
  } else if (volumeRatio >= 2.0) {
    volumeScore = 1.0;
  }

  // 4. Candle size score (0-2 points)
  if (recentClosePrices.length >= 10) {
    final last10Candles = recentClosePrices.sublist(recentClosePrices.length - 10);
    final avgCandleSize = _calculateAverageCandleSize(last10Candles);
    final currentCandleSize = (currentPrice - last10Candles.last).abs();
    final candleSizeRatio = currentCandleSize / avgCandleSize;

    if (candleSizeRatio >= 2.0) {
      candleSizeScore = 2.0;
    } else if (candleSizeRatio >= 1.5) {
      candleSizeScore = 1.0;
    }
  }

  // Calculate total score
  final totalScore = bollingerScore + rsiScore + volumeScore + candleSizeScore;

  // Determine grade and recommendation
  String signalGrade;
  String recommendation;

  if (totalScore >= 8.0) {
    signalGrade = '극단적 신호 🔥';
    recommendation = '즉시 진입 가능';
  } else if (totalScore >= 6.0) {
    signalGrade = '강한 신호 ⚡';
    recommendation = '캔들 후반이면 진입 가능';
  } else if (totalScore >= 4.0) {
    signalGrade = '보통 신호 ⭐';
    recommendation = '캔들 클로즈 대기';
  } else {
    signalGrade = '약한 신호 💤';
    recommendation = '진입 보류';
  }

  return SignalStrength(
    totalScore: totalScore,
    bollingerScore: bollingerScore,
    rsiScore: rsiScore,
    volumeScore: volumeScore,
    candleSizeScore: candleSizeScore,
    signalGrade: signalGrade,
    recommendation: recommendation,
  );
}

/// Calculates signal strength for EMA strategy
SignalStrength calculateEmaSignalStrength({
  required TechnicalAnalysis analysis,
  required bool isLongSignal,
  required List<double> recentClosePrices,
}) {
  double trendScore = 0.0;
  double rsiScore = 0.0;
  double volumeScore = 0.0;
  double candleSizeScore = 0.0;

  final currentPrice = analysis.currentPrice;
  final rsi6 = analysis.rsi6;
  final rsi14 = analysis.rsi12; // Actually RSI 14
  final currentVolume = analysis.currentVolume;
  final volumeMA5 = analysis.volumeMA5;
  final ema9 = analysis.ema9;
  final ema21 = analysis.ema21;

  // 1. Trend alignment score (0-3 points)
  if (isLongSignal) {
    // Long: price above EMAs
    if (currentPrice > ema9 && ema9 > ema21) {
      trendScore = 3.0;
    } else if (currentPrice > ema21) {
      trendScore = 2.0;
    } else if (currentPrice > ema9) {
      trendScore = 1.0;
    }
  } else {
    // Short: price below EMAs
    if (currentPrice < ema9 && ema9 < ema21) {
      trendScore = 3.0;
    } else if (currentPrice < ema21) {
      trendScore = 2.0;
    } else if (currentPrice < ema9) {
      trendScore = 1.0;
    }
  }

  // 2. Combined RSI score (0-3 points)
  if (isLongSignal) {
    // Long: both RSIs oversold
    if (rsi6 < 20 && rsi14 < 35) {
      rsiScore = 3.0;
    } else if (rsi6 < 25 && rsi14 < 40) {
      rsiScore = 2.0;
    } else if (rsi6 < analysis.rsi6LongThreshold && rsi14 < analysis.rsi12LongThreshold) {
      rsiScore = 1.0;
    }
  } else {
    // Short: both RSIs overbought
    if (rsi6 > 80 && rsi14 > 65) {
      rsiScore = 3.0;
    } else if (rsi6 > 75 && rsi14 > 60) {
      rsiScore = 2.0;
    } else if (rsi6 > analysis.rsi6ShortThreshold && rsi14 > analysis.rsi12ShortThreshold) {
      rsiScore = 1.0;
    }
  }

  // 3. Volume spike score (0-2 points)
  final volumeRatio = currentVolume / volumeMA5;
  if (volumeRatio >= 3.0) {
    volumeScore = 2.0;
  } else if (volumeRatio >= 2.0) {
    volumeScore = 1.0;
  }

  // 4. Candle size score (0-2 points)
  if (recentClosePrices.length >= 10) {
    final last10Candles = recentClosePrices.sublist(recentClosePrices.length - 10);
    final avgCandleSize = _calculateAverageCandleSize(last10Candles);
    final currentCandleSize = (currentPrice - last10Candles.last).abs();
    final candleSizeRatio = currentCandleSize / avgCandleSize;

    if (candleSizeRatio >= 2.0) {
      candleSizeScore = 2.0;
    } else if (candleSizeRatio >= 1.5) {
      candleSizeScore = 1.0;
    }
  }

  // Calculate total score
  final totalScore = trendScore + rsiScore + volumeScore + candleSizeScore;

  // Determine grade and recommendation
  String signalGrade;
  String recommendation;

  if (totalScore >= 8.0) {
    signalGrade = '극단적 신호 🔥';
    recommendation = '즉시 진입 가능';
  } else if (totalScore >= 6.0) {
    signalGrade = '강한 신호 ⚡';
    recommendation = '캔들 후반이면 진입 가능';
  } else if (totalScore >= 4.0) {
    signalGrade = '보통 신호 ⭐';
    recommendation = '캔들 클로즈 대기';
  } else {
    signalGrade = '약한 신호 💤';
    recommendation = '진입 보류';
  }

  return SignalStrength(
    totalScore: totalScore,
    bollingerScore: trendScore,
    rsiScore: rsiScore,
    volumeScore: volumeScore,
    candleSizeScore: candleSizeScore,
    signalGrade: signalGrade,
    recommendation: recommendation,
  );
}

/// Calculates average candle size from recent candles
double _calculateAverageCandleSize(List<double> closePrices) {
  if (closePrices.length < 2) return 0.0;

  double totalSize = 0.0;
  for (int i = 1; i < closePrices.length; i++) {
    totalSize += (closePrices[i] - closePrices[i - 1]).abs();
  }

  return totalSize / (closePrices.length - 1);
}
