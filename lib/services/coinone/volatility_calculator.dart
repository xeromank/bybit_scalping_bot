import 'dart:math';
import '../../models/coinone/coinone_chart.dart';

/// Volatility level classification
enum VolatilityLevel {
  low, // Low volatility (< 1%)
  medium, // Medium volatility (1-3%)
  high, // High volatility (> 3%)
}

/// Calculates market volatility for dynamic parameter adjustment
class VolatilityCalculator {
  /// Calculate volatility from recent candles
  ///
  /// Uses Average True Range (ATR) as percentage of price
  double calculateVolatility(List<CoinoneCandle> candles, {int period = 14}) {
    if (candles.length < period + 1) {
      return 0.0;
    }

    // Calculate True Range for each candle
    final trueRanges = <double>[];
    for (int i = 1; i < candles.length; i++) {
      final high = candles[i].high;
      final low = candles[i].low;
      final prevClose = candles[i - 1].close;

      // True Range = max(high - low, |high - prevClose|, |low - prevClose|)
      final tr = max(
        high - low,
        max((high - prevClose).abs(), (low - prevClose).abs()),
      );

      trueRanges.add(tr);
    }

    // Calculate ATR (Average True Range) for last N periods
    final recentTR = trueRanges.skip(trueRanges.length - period).toList();
    final atr = recentTR.reduce((a, b) => a + b) / period;

    // Calculate ATR as percentage of current price
    final currentPrice = candles.last.close;
    final volatilityPercent = (atr / currentPrice) * 100;

    return volatilityPercent;
  }

  /// Classify volatility level
  VolatilityLevel classifyVolatility(double volatilityPercent) {
    if (volatilityPercent < 1.0) {
      return VolatilityLevel.low;
    } else if (volatilityPercent < 3.0) {
      return VolatilityLevel.medium;
    } else {
      return VolatilityLevel.high;
    }
  }

  /// Get suggested parameter adjustments based on volatility
  ///
  /// Returns multiplier for stop loss / take profit
  /// - Low volatility: Use tighter stops (0.8x)
  /// - Medium volatility: Use normal stops (1.0x)
  /// - High volatility: Use wider stops (1.5x)
  double getParameterMultiplier(VolatilityLevel level) {
    switch (level) {
      case VolatilityLevel.low:
        return 0.8; // Tighter stops
      case VolatilityLevel.medium:
        return 1.0; // Normal stops
      case VolatilityLevel.high:
        return 1.5; // Wider stops
    }
  }

  /// Get volatility description in Korean
  String getVolatilityDescription(VolatilityLevel level) {
    switch (level) {
      case VolatilityLevel.low:
        return '낮음';
      case VolatilityLevel.medium:
        return '보통';
      case VolatilityLevel.high:
        return '높음';
    }
  }
}
