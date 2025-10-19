/// Supported exchange types
enum ExchangeType {
  /// Bybit exchange (futures trading)
  bybit,

  /// Coinone exchange (spot trading)
  coinone,
}

extension ExchangeTypeExtension on ExchangeType {
  /// Get display name for UI
  String get displayName {
    switch (this) {
      case ExchangeType.bybit:
        return 'Bybit';
      case ExchangeType.coinone:
        return 'Coinone';
    }
  }

  /// Get short identifier for storage
  String get identifier {
    switch (this) {
      case ExchangeType.bybit:
        return 'bybit';
      case ExchangeType.coinone:
        return 'coinone';
    }
  }

  /// Parse from string identifier
  static ExchangeType fromIdentifier(String identifier) {
    switch (identifier.toLowerCase()) {
      case 'bybit':
        return ExchangeType.bybit;
      case 'coinone':
        return ExchangeType.coinone;
      default:
        throw ArgumentError('Unknown exchange type: $identifier');
    }
  }
}
