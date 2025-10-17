/// Represents API credentials for authentication
///
/// Responsibility: Encapsulate API key and secret data
///
/// This immutable value object ensures that credentials are handled safely
/// and provides a type-safe way to pass credentials throughout the application.
class Credentials {
  final String apiKey;
  final String apiSecret;

  const Credentials({
    required this.apiKey,
    required this.apiSecret,
  });

  /// Validates if credentials are not empty
  bool get isValid => apiKey.isNotEmpty && apiSecret.isNotEmpty;

  /// Creates Credentials from JSON
  factory Credentials.fromJson(Map<String, dynamic> json) {
    return Credentials(
      apiKey: json['apiKey'] as String,
      apiSecret: json['apiSecret'] as String,
    );
  }

  /// Converts Credentials to JSON
  Map<String, dynamic> toJson() {
    return {
      'apiKey': apiKey,
      'apiSecret': apiSecret,
    };
  }

  /// Creates a copy with updated fields
  Credentials copyWith({
    String? apiKey,
    String? apiSecret,
  }) {
    return Credentials(
      apiKey: apiKey ?? this.apiKey,
      apiSecret: apiSecret ?? this.apiSecret,
    );
  }

  @override
  String toString() => 'Credentials(apiKey: ${apiKey.substring(0, 8)}...)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Credentials &&
          runtimeType == other.runtimeType &&
          apiKey == other.apiKey &&
          apiSecret == other.apiSecret;

  @override
  int get hashCode => apiKey.hashCode ^ apiSecret.hashCode;
}
