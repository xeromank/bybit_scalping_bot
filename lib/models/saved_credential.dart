import 'package:bybit_scalping_bot/core/enums/exchange_type.dart';

/// Saved credential model for recent logins
class SavedCredential {
  final String id; // Unique identifier (timestamp-based)
  final String nickname; // User-friendly name
  final ExchangeType exchange;
  final String apiKey; // Only first 8 chars for display
  final DateTime lastUsed;

  const SavedCredential({
    required this.id,
    required this.nickname,
    required this.exchange,
    required this.apiKey,
    required this.lastUsed,
  });

  /// Create from JSON
  factory SavedCredential.fromJson(Map<String, dynamic> json) {
    return SavedCredential(
      id: json['id'] as String,
      nickname: json['nickname'] as String,
      exchange: ExchangeType.values.firstWhere(
        (e) => e.toString() == json['exchange'],
      ),
      apiKey: json['apiKey'] as String,
      lastUsed: DateTime.parse(json['lastUsed'] as String),
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'nickname': nickname,
      'exchange': exchange.toString(),
      'apiKey': apiKey,
      'lastUsed': lastUsed.toIso8601String(),
    };
  }

  /// Get display name for UI
  String get displayName {
    final exchangeName = exchange == ExchangeType.bybit ? 'Bybit' : 'Coinone';
    return '$nickname ($exchangeName)';
  }

  /// Get masked API key for display (e.g., "12345678...")
  String get maskedApiKey {
    if (apiKey.length <= 8) return apiKey;
    return '${apiKey.substring(0, 8)}...';
  }

  /// Copy with updated fields
  SavedCredential copyWith({
    String? id,
    String? nickname,
    ExchangeType? exchange,
    String? apiKey,
    DateTime? lastUsed,
  }) {
    return SavedCredential(
      id: id ?? this.id,
      nickname: nickname ?? this.nickname,
      exchange: exchange ?? this.exchange,
      apiKey: apiKey ?? this.apiKey,
      lastUsed: lastUsed ?? this.lastUsed,
    );
  }
}
