import '../../models/coinone/technical_indicators.dart';

/// Market trend classification
enum MarketTrend {
  uptrend,
  sideways,
  downtrend,
}

/// Detects market trend based on technical indicators
///
/// Uses EMA analysis and price action to classify market as:
/// - Uptrend: EMA50 > EMA200 AND price > EMA50
/// - Downtrend: EMA50 < EMA200 AND price < EMA50
/// - Sideways: Otherwise (consolidation, weak trend)
class MarketTrendDetector {
  /// Detect current market trend
  MarketTrend detectTrend(TechnicalIndicators indicators) {
    final price = indicators.currentPrice;
    final ema50 = indicators.ema50;
    final ema200 = indicators.ema200;

    // Strong uptrend: EMA50 > EMA200 AND price > EMA50
    if (ema50 > ema200 && price > ema50) {
      // Additional confirmation: price significantly above EMA50 (> 0.5%)
      final priceAboveEma50 = ((price - ema50) / ema50) * 100;
      if (priceAboveEma50 > 0.5) {
        return MarketTrend.uptrend;
      }
    }

    // Strong downtrend: EMA50 < EMA200 AND price < EMA50
    if (ema50 < ema200 && price < ema50) {
      // Additional confirmation: price significantly below EMA50 (> 0.5%)
      final priceBelowEma50 = ((ema50 - price) / ema50) * 100;
      if (priceBelowEma50 > 0.5) {
        return MarketTrend.downtrend;
      }
    }

    // Sideways: weak trend or consolidation
    return MarketTrend.sideways;
  }

  /// Get trend description in Korean
  String getTrendDescription(MarketTrend trend) {
    switch (trend) {
      case MarketTrend.uptrend:
        return '상승 추세';
      case MarketTrend.sideways:
        return '횡보';
      case MarketTrend.downtrend:
        return '하락 추세';
    }
  }

  /// Calculate trend strength (0.0 to 1.0)
  double getTrendStrength(TechnicalIndicators indicators) {
    final price = indicators.currentPrice;
    final ema50 = indicators.ema50;
    final ema200 = indicators.ema200;

    // Calculate EMA separation
    final emaSeparation = ((ema50 - ema200).abs() / ema200) * 100;

    // Calculate price distance from EMA50
    final priceDistance = ((price - ema50).abs() / ema50) * 100;

    // Combine both factors (normalized to 0-1 range)
    // Strong trend: EMA separation > 2% AND price distance > 1%
    final strength = ((emaSeparation / 2.0) + (priceDistance / 1.0)) / 2.0;

    return strength.clamp(0.0, 1.0);
  }
}
