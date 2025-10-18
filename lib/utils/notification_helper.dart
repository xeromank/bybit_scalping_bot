import 'package:flutter/services.dart';
import 'package:vibration/vibration.dart';

/// Helper class for haptic feedback and notifications
class NotificationHelper {
  /// Triggers vibration and haptic feedback for order events
  static Future<void> notifyOrderEvent() async {
    try {
      // Check if device supports vibration
      final hasVibrator = await Vibration.hasVibrator() ?? false;

      if (hasVibrator) {
        // Vibrate for 500ms
        await Vibration.vibrate(duration: 500);
      }

      // Haptic feedback (works on iOS and some Android devices)
      await HapticFeedback.heavyImpact();
    } catch (e) {
      print('NotificationHelper: Error triggering notification: $e');
    }
  }

  /// Triggers vibration and haptic feedback for position change events
  static Future<void> notifyPositionChange() async {
    try {
      // Check if device supports vibration
      final hasVibrator = await Vibration.hasVibrator() ?? false;

      if (hasVibrator) {
        // Double vibration pattern: 200ms, pause 100ms, 200ms
        await Vibration.vibrate(pattern: [0, 200, 100, 200]);
      }

      // Haptic feedback
      await HapticFeedback.mediumImpact();
    } catch (e) {
      print('NotificationHelper: Error triggering notification: $e');
    }
  }

  /// Triggers light haptic feedback for ready state
  static Future<void> notifyReadyState() async {
    try {
      // Light haptic feedback only (no vibration for ready state)
      await HapticFeedback.lightImpact();
    } catch (e) {
      print('NotificationHelper: Error triggering notification: $e');
    }
  }
}
