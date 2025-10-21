/// Market condition classification
///
/// 7-level market condition based on price movement, RSI, and volatility
enum MarketCondition {
  /// Extreme bullish market (Band Walking uptrend)
  /// - RSI: 70+ sustained
  /// - Strategy: Long trend following only
  extremeBullish,

  /// Strong bullish market (Clear uptrend)
  /// - RSI: 60-70
  /// - Strategy: Long trend following (but watch for overheating)
  strongBullish,

  /// Weak bullish market (Mild uptrend)
  /// - RSI: 50-60
  /// - Strategy: Mean reversion (short on BB upper, long on BB lower)
  weakBullish,

  /// Ranging market (Sideways/Consolidation)
  /// - RSI: 40-60
  /// - Strategy: Mean reversion (Bollinger Band)
  ranging,

  /// Weak bearish market (Mild downtrend)
  /// - RSI: 40-50
  /// - Strategy: Mean reversion (long on BB lower, short on BB upper)
  weakBearish,

  /// Strong bearish market (Clear downtrend)
  /// - RSI: 30-40
  /// - Strategy: Short trend following (but watch for overselling)
  strongBearish,

  /// Extreme bearish market (Band Walking downtrend)
  /// - RSI: Below 30 sustained
  /// - Strategy: Short trend following only
  extremeBearish,
}

extension MarketConditionExtension on MarketCondition {
  /// Get display name in Korean
  String get displayName {
    switch (this) {
      case MarketCondition.extremeBullish:
        return '극강세';
      case MarketCondition.strongBullish:
        return '강세';
      case MarketCondition.weakBullish:
        return '약한 강세';
      case MarketCondition.ranging:
        return '횡보장';
      case MarketCondition.weakBearish:
        return '약한 약세';
      case MarketCondition.strongBearish:
        return '약세';
      case MarketCondition.extremeBearish:
        return '극약세';
    }
  }

  /// Get emoji representation
  String get emoji {
    switch (this) {
      case MarketCondition.extremeBullish:
        return '🔥';
      case MarketCondition.strongBullish:
        return '📈';
      case MarketCondition.weakBullish:
        return '↗️';
      case MarketCondition.ranging:
        return '↔️';
      case MarketCondition.weakBearish:
        return '↘️';
      case MarketCondition.strongBearish:
        return '📉';
      case MarketCondition.extremeBearish:
        return '💥';
    }
  }

  /// Get recommended strategy description
  String get strategyDescription {
    switch (this) {
      case MarketCondition.extremeBullish:
        return '추세 추종 (롱 전용)';
      case MarketCondition.strongBullish:
        return '추세 추종 (롱 위주)';
      case MarketCondition.weakBullish:
        return '평균회귀 (양방향)';
      case MarketCondition.ranging:
        return '평균회귀 (양방향)';
      case MarketCondition.weakBearish:
        return '평균회귀 (양방향)';
      case MarketCondition.strongBearish:
        return '추세 추종 (숏 위주)';
      case MarketCondition.extremeBearish:
        return '추세 추종 (숏 전용)';
    }
  }

  /// Get risk level (1-5 stars)
  int get riskLevel {
    switch (this) {
      case MarketCondition.extremeBullish:
      case MarketCondition.extremeBearish:
        return 4; // High risk due to extreme volatility
      case MarketCondition.strongBullish:
      case MarketCondition.strongBearish:
        return 3; // Medium-high risk
      case MarketCondition.weakBullish:
      case MarketCondition.weakBearish:
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
      case MarketCondition.strongBullish:
        return 'green';
      case MarketCondition.weakBullish:
        return 'lightGreen';
      case MarketCondition.ranging:
        return 'orange';
      case MarketCondition.weakBearish:
        return 'lightRed';
      case MarketCondition.strongBearish:
        return 'red';
      case MarketCondition.extremeBearish:
        return 'purple'; // Very bearish
    }
  }
}
