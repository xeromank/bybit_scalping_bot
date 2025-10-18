import 'package:intl/intl.dart';

/// Simple logger utility with timestamp
///
/// Responsibility: Provide formatted logging with timestamp
///
/// Usage:
///   Logger.log('Message');
///   Logger.info('Info message');
///   Logger.error('Error message');
///   Logger.warning('Warning message');
class Logger {
  static final DateFormat _dateFormat = DateFormat('yyyy-MM-dd HH:mm:ss.SSS');

  /// Gets formatted timestamp
  static String _timestamp() {
    return _dateFormat.format(DateTime.now());
  }

  /// General log message
  static void log(String message, {String? prefix}) {
    final time = _timestamp();
    if (prefix != null) {
      print('[$time] $prefix: $message');
    } else {
      print('[$time] $message');
    }
  }

  /// Info level log
  static void info(String message, {String? prefix}) {
    log('ℹ️ $message', prefix: prefix);
  }

  /// Error level log
  static void error(String message, {String? prefix}) {
    log('❌ $message', prefix: prefix);
  }

  /// Warning level log
  static void warning(String message, {String? prefix}) {
    log('⚠️ $message', prefix: prefix);
  }

  /// Success level log
  static void success(String message, {String? prefix}) {
    log('✅ $message', prefix: prefix);
  }

  /// Debug level log
  static void debug(String message, {String? prefix}) {
    log('🔍 $message', prefix: prefix);
  }
}
