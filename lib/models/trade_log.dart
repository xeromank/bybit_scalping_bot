/// Represents a trade log entry
///
/// Responsibility: Encapsulate log entry data
///
/// This immutable value object represents a log entry in the trading system.
class TradeLog {
  final DateTime timestamp;
  final String message;
  final LogLevel level;
  final Map<String, dynamic>? metadata;

  const TradeLog({
    required this.timestamp,
    required this.message,
    required this.level,
    this.metadata,
  });

  /// Creates a TradeLog with current timestamp
  factory TradeLog.now({
    required String message,
    required LogLevel level,
    Map<String, dynamic>? metadata,
  }) {
    return TradeLog(
      timestamp: DateTime.now(),
      message: message,
      level: level,
      metadata: metadata,
    );
  }

  /// Creates an info log
  factory TradeLog.info(String message, [Map<String, dynamic>? metadata]) {
    return TradeLog.now(
      message: message,
      level: LogLevel.info,
      metadata: metadata,
    );
  }

  /// Creates a success log
  factory TradeLog.success(String message, [Map<String, dynamic>? metadata]) {
    return TradeLog.now(
      message: message,
      level: LogLevel.success,
      metadata: metadata,
    );
  }

  /// Creates a warning log
  factory TradeLog.warning(String message, [Map<String, dynamic>? metadata]) {
    return TradeLog.now(
      message: message,
      level: LogLevel.warning,
      metadata: metadata,
    );
  }

  /// Creates an error log
  factory TradeLog.error(String message, [Map<String, dynamic>? metadata]) {
    return TradeLog.now(
      message: message,
      level: LogLevel.error,
      metadata: metadata,
    );
  }

  /// Creates TradeLog from JSON
  factory TradeLog.fromJson(Map<String, dynamic> json) {
    return TradeLog(
      timestamp: DateTime.parse(json['timestamp'] as String),
      message: json['message'] as String,
      level: LogLevel.values.firstWhere(
        (e) => e.name == json['level'],
        orElse: () => LogLevel.info,
      ),
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }

  /// Converts TradeLog to JSON
  Map<String, dynamic> toJson() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'message': message,
      'level': level.name,
      if (metadata != null) 'metadata': metadata,
    };
  }

  /// Formats timestamp as HH:MM:SS
  String get formattedTime =>
      '${timestamp.hour.toString().padLeft(2, '0')}:'
      '${timestamp.minute.toString().padLeft(2, '0')}:'
      '${timestamp.second.toString().padLeft(2, '0')}';

  /// Returns true if this is an error log
  bool get isError => level == LogLevel.error;

  /// Returns true if this is a warning log
  bool get isWarning => level == LogLevel.warning;

  /// Returns true if this is a success log
  bool get isSuccess => level == LogLevel.success;

  /// Returns true if this is an info log
  bool get isInfo => level == LogLevel.info;

  @override
  String toString() =>
      'TradeLog($formattedTime - ${level.name.toUpperCase()}: $message)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TradeLog &&
          runtimeType == other.runtimeType &&
          timestamp == other.timestamp &&
          message == other.message &&
          level == other.level;

  @override
  int get hashCode => timestamp.hashCode ^ message.hashCode ^ level.hashCode;
}

/// Log level enumeration
enum LogLevel {
  info,
  success,
  warning,
  error,
}
