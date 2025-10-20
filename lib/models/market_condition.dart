/// Market condition classification
///
/// 5-level market condition based on price movement, RSI, and volatility
enum MarketCondition {
  /// Extreme bullish market (Band Walking uptrend)
  /// - Price change: +3% or more
  /// - RSI: 70+ sustained
  /// - Strategy: Long trend following only
  extremeBullish,

  /// Bullish market (Uptrend)
  /// - Price change: +1% to +3%
  /// - RSI: 55-70
  /// - Strategy: Long bias (70% long, 30% short)
  bullish,

  /// Ranging market (Sideways/Consolidation)
  /// - Price change: -0.5% to +0.5%
  /// - RSI: 40-60
  /// - Strategy: Mean reversion (Bollinger Band)
  ranging,

  /// Bearish market (Downtrend)
  /// - Price change: -1% to -3%
  /// - RSI: 30-45
  /// - Strategy: Short bias (70% short, 30% long)
  bearish,

  /// Extreme bearish market (Band Walking downtrend)
  /// - Price change: -3% or less
  /// - RSI: Below 30 sustained
  /// - Strategy: Short trend following only
  extremeBearish,
}

extension MarketConditionExtension on MarketCondition {
  /// Get display name in Korean
  String get displayName {
    switch (this) {
      case MarketCondition.extremeBullish:
        return '극단적 상승장';
      case MarketCondition.bullish:
        return '상승장';
      case MarketCondition.ranging:
        return '횡보장';
      case MarketCondition.bearish:
        return '하락장';
      case MarketCondition.extremeBearish:
        return '극단적 하락장';
    }
  }

  /// Get emoji representation
  String get emoji {
    switch (this) {
      case MarketCondition.extremeBullish:
        return '🔥';
      case MarketCondition.bullish:
        return '📈';
      case MarketCondition.ranging:
        return '↔️';
      case MarketCondition.bearish:
        return '📉';
      case MarketCondition.extremeBearish:
        return '💥';
    }
  }

  /// Get recommended strategy description
  String get strategyDescription {
    switch (this) {
      case MarketCondition.extremeBullish:
        return 'Band Walking 추세 추종 (롱 전용)';
      case MarketCondition.bullish:
        return '풀백 롱 진입 (롱 편향)';
      case MarketCondition.ranging:
        return '볼린저 밴드 역추세';
      case MarketCondition.bearish:
        return '풀백 숏 진입 (숏 편향)';
      case MarketCondition.extremeBearish:
        return 'Band Walking 추세 추종 (숏 전용)';
    }
  }

  /// Get risk level (1-5 stars)
  int get riskLevel {
    switch (this) {
      case MarketCondition.extremeBullish:
      case MarketCondition.extremeBearish:
        return 4; // High risk due to extreme volatility
      case MarketCondition.bullish:
      case MarketCondition.bearish:
        return 3; // Medium-high risk
      case MarketCondition.ranging:
        return 2; // Low-medium risk
    }
  }

  /// Get risk stars display
  String get riskStars {
    return '⭐' * riskLevel + '☆' * (5 - riskLevel);
  }

  /// Get color for UI
  String get colorName {
    switch (this) {
      case MarketCondition.extremeBullish:
        return 'red'; // Hot
      case MarketCondition.bullish:
        return 'green';
      case MarketCondition.ranging:
        return 'orange';
      case MarketCondition.bearish:
        return 'red';
      case MarketCondition.extremeBearish:
        return 'purple'; // Very bearish
    }
  }
}
