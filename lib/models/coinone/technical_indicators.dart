/// Technical Indicators for trading analysis
///
/// Contains RSI, EMA, Bollinger Bands, Volume, and other indicators
class TechnicalIndicators {
  final double rsi;
  final double ema9;
  final double ema21;
  final double ema50;
  final double ema200;
  final double bollingerUpper;
  final double bollingerMiddle;
  final double bollingerLower;
  final double currentPrice;
  final double currentVolume; // Current candle volume
  final double volumeMA5; // 5-period volume moving average
  final DateTime timestamp;

  TechnicalIndicators({
    required this.rsi,
    required this.ema9,
    required this.ema21,
    required this.ema50,
    required this.ema200,
    required this.bollingerUpper,
    required this.bollingerMiddle,
    required this.bollingerLower,
    required this.currentPrice,
    required this.currentVolume,
    required this.volumeMA5,
    required this.timestamp,
  });

  /// Check if in uptrend (EMA50 > EMA200)
  bool get isUptrend => ema50 > ema200;

  /// Check if in downtrend (EMA50 < EMA200)
  bool get isDowntrend => ema50 < ema200;

  /// Get trend description
  String get trendDescription {
    if (isUptrend) return '상승 추세';
    if (isDowntrend) return '하락 추세';
    return '횡보';
  }

  /// RSI status (oversold, neutral, overbought)
  String get rsiStatus {
    if (rsi < 30) return '과매도';
    if (rsi > 70) return '과매수';
    return '중립';
  }

  /// Bollinger Band position
  String get bollingerPosition {
    if (currentPrice <= bollingerLower) return '하단';
    if (currentPrice >= bollingerUpper) return '상단';
    if (currentPrice > bollingerMiddle) return '중간 위';
    return '중간 아래';
  }

  /// Distance from Bollinger Lower Band (percentage)
  double get distanceFromLowerBand {
    return ((currentPrice - bollingerLower) / bollingerLower) * 100;
  }

  /// Distance from Bollinger Upper Band (percentage)
  double get distanceFromUpperBand {
    return ((bollingerUpper - currentPrice) / currentPrice) * 100;
  }

  /// Bollinger Band width (volatility indicator)
  double get bollingerWidth {
    return ((bollingerUpper - bollingerLower) / bollingerMiddle) * 100;
  }

  /// Check if volume is above average (bullish confirmation)
  bool get isVolumeAboveAverage => currentVolume > volumeMA5;

  /// Volume ratio (current volume / average volume)
  double get volumeRatio => volumeMA5 > 0 ? currentVolume / volumeMA5 : 1.0;

  /// Volume strength description
  String get volumeStatus {
    if (volumeRatio >= 1.5) return '매우 높음';
    if (volumeRatio >= 1.2) return '높음';
    if (volumeRatio >= 0.8) return '보통';
    return '낮음';
  }

  @override
  String toString() {
    return 'TechnicalIndicators('
        'RSI: ${rsi.toStringAsFixed(2)}, '
        'EMA9: ${ema9.toStringAsFixed(2)}, '
        'EMA50: ${ema50.toStringAsFixed(2)}, '
        'EMA200: ${ema200.toStringAsFixed(2)}, '
        'BB: [${bollingerLower.toStringAsFixed(2)}, ${bollingerMiddle.toStringAsFixed(2)}, ${bollingerUpper.toStringAsFixed(2)}], '
        'Price: ${currentPrice.toStringAsFixed(2)}, '
        'Volume: ${currentVolume.toStringAsFixed(0)} (ratio: ${volumeRatio.toStringAsFixed(2)})'
        ')';
  }
}
