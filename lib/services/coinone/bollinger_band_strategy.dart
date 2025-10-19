import 'package:bybit_scalping_bot/models/coinone/coinone_chart.dart';

/// Bollinger Band trading strategy for Coinone spot trading
///
/// Responsibility: Calculate Bollinger Bands and generate trading signals
///
/// Strategy:
/// - 20-period Simple Moving Average (SMA)
/// - 2 standard deviations for upper/lower bands
/// - Buy signal: Price touches or goes below lower band
/// - Sell signal: Price touches or goes above upper band
///
/// Benefits:
/// - Identifies overbought/oversold conditions
/// - Mean reversion strategy
/// - Clear entry/exit signals
class BollingerBandStrategy {
  final int period;
  final double standardDeviations;

  BollingerBandStrategy({
    this.period = 20,
    this.standardDeviations = 2.0,
  });

  /// Calculate Bollinger Bands from chart data
  ///
  /// Returns null if insufficient data
  BollingerBands? calculate(List<CoinoneCandle> candles) {
    if (candles.length < period) {
      return null;
    }

    // Use most recent data
    final recentCandles = candles.sublist(candles.length - period);

    // Calculate SMA (middle band)
    final closes = recentCandles.map((c) => c.close).toList();
    final sma = _calculateSMA(closes);

    // Calculate standard deviation
    final stdDev = _calculateStandardDeviation(closes, sma);

    // Calculate upper and lower bands
    final upper = sma + (standardDeviations * stdDev);
    final lower = sma - (standardDeviations * stdDev);

    // Current price
    final currentPrice = candles.last.close;

    return BollingerBands(
      upper: upper,
      middle: sma,
      lower: lower,
      currentPrice: currentPrice,
    );
  }

  /// Generate trading signal based on Bollinger Bands
  ///
  /// Returns:
  /// - 'buy': Price at or below lower band (oversold)
  /// - 'sell': Price at or above upper band (overbought)
  /// - null: No signal (price within bands)
  String? generateSignal(BollingerBands bands) {
    final price = bands.currentPrice;

    // Buy signal: price touches or breaks below lower band
    if (price <= bands.lower) {
      return 'buy';
    }

    // Sell signal: price touches or breaks above upper band
    if (price >= bands.upper) {
      return 'sell';
    }

    // No signal
    return null;
  }

  /// Calculate signal strength (0.0 to 1.0)
  ///
  /// Higher value = stronger signal
  /// - 1.0: Price exactly at band
  /// - > 1.0: Price beyond band (very strong signal)
  double calculateSignalStrength(BollingerBands bands, String signal) {
    final price = bands.currentPrice;
    final range = bands.upper - bands.lower;

    if (range == 0) return 0.0;

    if (signal == 'buy') {
      // Distance below lower band
      final distance = bands.lower - price;
      return (distance / range).abs().clamp(0.0, 2.0);
    } else if (signal == 'sell') {
      // Distance above upper band
      final distance = price - bands.upper;
      return (distance / range).abs().clamp(0.0, 2.0);
    }

    return 0.0;
  }

  /// Check if price is within safe range of bands
  ///
  /// Used to determine if it's safe to exit a position
  /// Returns true if price is near middle band (within 30% of range)
  bool isNearMiddle(BollingerBands bands, {double threshold = 0.3}) {
    final range = bands.upper - bands.lower;
    final distanceFromMiddle = (bands.currentPrice - bands.middle).abs();

    if (range == 0) return true;

    return (distanceFromMiddle / range) <= threshold;
  }

  /// Simple Moving Average
  double _calculateSMA(List<double> values) {
    if (values.isEmpty) return 0.0;
    final sum = values.reduce((a, b) => a + b);
    return sum / values.length;
  }

  /// Standard Deviation
  double _calculateStandardDeviation(List<double> values, double mean) {
    if (values.isEmpty) return 0.0;

    final squaredDifferences = values.map((v) {
      final diff = v - mean;
      return diff * diff;
    }).toList();

    final variance = _calculateSMA(squaredDifferences);
    return variance.sqrt();
  }
}

/// Bollinger Bands data model
class BollingerBands {
  final double upper;
  final double middle;
  final double lower;
  final double currentPrice;

  BollingerBands({
    required this.upper,
    required this.middle,
    required this.lower,
    required this.currentPrice,
  });

  /// Band width (volatility indicator)
  double get width => upper - lower;

  /// Distance from current price to middle band (as percentage)
  double get distanceFromMiddlePercent {
    if (middle == 0) return 0.0;
    return ((currentPrice - middle) / middle) * 100;
  }

  /// Position within bands (0.0 = lower, 0.5 = middle, 1.0 = upper)
  double get positionInBands {
    if (width == 0) return 0.5;
    return ((currentPrice - lower) / width).clamp(0.0, 1.0);
  }

  @override
  String toString() {
    return 'BollingerBands(upper: ${upper.toStringAsFixed(2)}, '
        'middle: ${middle.toStringAsFixed(2)}, '
        'lower: ${lower.toStringAsFixed(2)}, '
        'current: ${currentPrice.toStringAsFixed(2)})';
  }
}

/// Extension for sqrt on double
extension DoubleExt on double {
  double sqrt() {
    if (this < 0) return 0.0;
    double x = this;
    double y = 1.0;
    final epsilon = 0.00001;

    while ((x - y).abs() > epsilon) {
      x = (x + y) / 2;
      y = this / x;
    }

    return x;
  }
}
