import 'technical_indicators.dart';

/// Trading signal type
enum SignalType {
  buy,
  sell,
  hold,
}

/// Trading signal with entry/exit parameters
class TradingSignal {
  final SignalType type;
  final double strength; // 0.0 to 1.0
  final String reason; // Signal reason (Korean)
  final double? entryPrice; // Suggested entry price
  final double? stopLoss; // Stop loss price
  final double? takeProfit; // Take profit price
  final double positionSizeMultiplier; // Position size multiplier (0.25, 0.5, 1.0)
  final DateTime timestamp;

  const TradingSignal({
    required this.type,
    required this.strength,
    required this.reason,
    this.entryPrice,
    this.stopLoss,
    this.takeProfit,
    this.positionSizeMultiplier = 1.0, // Default to full position
    required this.timestamp,
  });

  /// Create a HOLD signal (no action)
  factory TradingSignal.hold({
    required String reason,
    required DateTime timestamp,
  }) {
    return TradingSignal(
      type: SignalType.hold,
      strength: 0.0,
      reason: reason,
      timestamp: timestamp,
    );
  }

  /// Create a BUY signal
  factory TradingSignal.buy({
    required double strength,
    required String reason,
    required double entryPrice,
    required double stopLoss,
    required double takeProfit,
    double positionSizeMultiplier = 1.0,
    required DateTime timestamp,
  }) {
    return TradingSignal(
      type: SignalType.buy,
      strength: strength,
      reason: reason,
      entryPrice: entryPrice,
      stopLoss: stopLoss,
      takeProfit: takeProfit,
      positionSizeMultiplier: positionSizeMultiplier,
      timestamp: timestamp,
    );
  }

  /// Create a SELL signal
  factory TradingSignal.sell({
    required double strength,
    required String reason,
    required DateTime timestamp,
  }) {
    return TradingSignal(
      type: SignalType.sell,
      strength: strength,
      reason: reason,
      timestamp: timestamp,
    );
  }

  @override
  String toString() {
    return 'TradingSignal(type: $type, strength: ${strength.toStringAsFixed(2)}, reason: $reason)';
  }
}

/// Trading strategy interface
abstract class TradingStrategy {
  /// Strategy name
  String get name;

  /// Generate trading signal based on technical indicators
  TradingSignal generateSignal(TechnicalIndicators indicators);

  /// Check if should close position (for active positions)
  bool shouldClosePosition(
    TechnicalIndicators indicators,
    double entryPrice,
    double currentPrice,
  );
}
