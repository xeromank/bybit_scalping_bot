import '../core/enums/exchange_type.dart';

/// Represents exchange API credentials with metadata
///
/// Used for storing and managing multiple API key sets per exchange.
/// The most recently used credentials are tracked for easy selection.
class ExchangeCredentials {
  final ExchangeType exchangeType;
  final String apiKey;
  final String apiSecret;
  final DateTime lastUsed;
  final String? label; // Optional user-friendly label

  const ExchangeCredentials({
    required this.exchangeType,
    required this.apiKey,
    required this.apiSecret,
    required this.lastUsed,
    this.label,
  });

  /// Create from JSON
  factory ExchangeCredentials.fromJson(Map<String, dynamic> json) {
    return ExchangeCredentials(
      exchangeType: ExchangeTypeExtension.fromIdentifier(json['exchangeType'] as String),
      apiKey: json['apiKey'] as String,
      apiSecret: json['apiSecret'] as String,
      lastUsed: DateTime.fromMillisecondsSinceEpoch(json['lastUsed'] as int),
      label: json['label'] as String?,
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'exchangeType': exchangeType.identifier,
      'apiKey': apiKey,
      'apiSecret': apiSecret,
      'lastUsed': lastUsed.millisecondsSinceEpoch,
      'label': label,
    };
  }

  /// Get a masked version of the API key for display (shows first 8 chars)
  String get maskedApiKey {
    if (apiKey.length <= 12) {
      return '${apiKey.substring(0, 4)}...';
    }
    return '${apiKey.substring(0, 8)}...${apiKey.substring(apiKey.length - 4)}';
  }

  /// Get display label (uses label if available, otherwise masked API key)
  String get displayLabel {
    if (label != null && label!.isNotEmpty) {
      return label!;
    }
    return maskedApiKey;
  }

  /// Create a copy with updated fields
  ExchangeCredentials copyWith({
    ExchangeType? exchangeType,
    String? apiKey,
    String? apiSecret,
    DateTime? lastUsed,
    String? label,
  }) {
    return ExchangeCredentials(
      exchangeType: exchangeType ?? this.exchangeType,
      apiKey: apiKey ?? this.apiKey,
      apiSecret: apiSecret ?? this.apiSecret,
      lastUsed: lastUsed ?? this.lastUsed,
      label: label ?? this.label,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is ExchangeCredentials &&
        other.exchangeType == exchangeType &&
        other.apiKey == apiKey &&
        other.apiSecret == apiSecret;
  }

  @override
  int get hashCode {
    return exchangeType.hashCode ^ apiKey.hashCode ^ apiSecret.hashCode;
  }

  @override
  String toString() {
    return 'ExchangeCredentials(exchange: ${exchangeType.displayName}, apiKey: $maskedApiKey)';
  }
}
