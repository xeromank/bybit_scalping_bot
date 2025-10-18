/// Candle progress tracking for hybrid entry strategy
///
/// Tracks the progress of the current candle to determine
/// if immediate entry is allowed or should wait for candle close

class CandleProgress {
  final int startTime; // Candle start timestamp (milliseconds)
  final int endTime; // Candle end timestamp (milliseconds)
  final int currentTime; // Current timestamp (milliseconds)
  final bool isConfirmed; // Whether the candle is confirmed/closed

  CandleProgress({
    required this.startTime,
    required this.endTime,
    required this.currentTime,
    required this.isConfirmed,
  });

  /// Returns candle progress as percentage (0-100)
  double get progressPercent {
    if (isConfirmed) return 100.0;

    final totalDuration = endTime - startTime;
    if (totalDuration <= 0) return 0.0;

    final elapsed = currentTime - startTime;
    final progress = (elapsed / totalDuration * 100).clamp(0.0, 100.0);

    return progress;
  }

  /// Returns remaining time in seconds
  int get remainingSeconds {
    if (isConfirmed) return 0;

    final remaining = (endTime - currentTime) ~/ 1000;
    return remaining.clamp(0, 999999);
  }

  /// Returns elapsed time in seconds
  int get elapsedSeconds {
    final elapsed = (currentTime - startTime) ~/ 1000;
    return elapsed.clamp(0, 999999);
  }

  /// Returns true if candle is in early stage (0-60%)
  bool get isEarlyStage => progressPercent < 60.0;

  /// Returns true if candle is in mid stage (60-90%)
  bool get isMidStage => progressPercent >= 60.0 && progressPercent < 90.0;

  /// Returns true if candle is in late stage (90-100%)
  bool get isLateStage => progressPercent >= 90.0;

  /// Returns stage name for display
  String get stageName {
    if (isConfirmed) return '확정';
    if (isLateStage) return '후반';
    if (isMidStage) return '중반';
    return '초반';
  }

  /// Returns formatted time string (e.g., "3분 45초")
  String get elapsedTimeString {
    final minutes = elapsedSeconds ~/ 60;
    final seconds = elapsedSeconds % 60;
    return '$minutes분 $seconds초';
  }

  /// Returns formatted remaining time string (e.g., "1분 15초")
  String get remainingTimeString {
    final minutes = remainingSeconds ~/ 60;
    final seconds = remainingSeconds % 60;
    return '$minutes분 $seconds초';
  }

  @override
  String toString() {
    return 'CandleProgress(progress: ${progressPercent.toStringAsFixed(1)}%, '
        'stage: $stageName, '
        'elapsed: $elapsedTimeString, '
        'remaining: $remainingTimeString, '
        'confirmed: $isConfirmed)';
  }

  /// Creates CandleProgress from WebSocket kline data
  factory CandleProgress.fromKline(Map<String, dynamic> kline) {
    final start = int.tryParse(kline['start']?.toString() ?? '0') ?? 0;
    final end = int.tryParse(kline['end']?.toString() ?? '0') ?? 0;
    final timestamp = int.tryParse(kline['timestamp']?.toString() ?? '0') ?? 0;
    final confirm = kline['confirm'] as bool? ?? false;

    return CandleProgress(
      startTime: start,
      endTime: end,
      currentTime: timestamp,
      isConfirmed: confirm,
    );
  }
}

/// Determines if immediate entry is allowed based on candle progress and signal strength
class HybridEntryDecision {
  final bool canEnterImmediately;
  final String reason;
  final String recommendation;

  HybridEntryDecision({
    required this.canEnterImmediately,
    required this.reason,
    required this.recommendation,
  });

  /// Evaluates whether immediate entry is allowed
  ///
  /// Rules:
  /// 1. Confirmed candle: Always allow entry
  /// 2. Extreme signal (8+ points): Allow immediate entry
  /// 3. Late stage (90%+): Allow immediate entry
  /// 4. Strong signal (6+ points) + Mid stage (60%+): Allow entry
  /// 5. Otherwise: Wait for candle close
  factory HybridEntryDecision.evaluate({
    required CandleProgress candleProgress,
    required double signalStrength,
  }) {
    // Rule 1: Confirmed candle - always allow
    if (candleProgress.isConfirmed) {
      return HybridEntryDecision(
        canEnterImmediately: true,
        reason: '캔들 확정',
        recommendation: '진입 가능',
      );
    }

    // Rule 2: Extreme signal (8+ points) - immediate entry
    if (signalStrength >= 8.0) {
      return HybridEntryDecision(
        canEnterImmediately: true,
        reason: '극단적 신호 (${signalStrength.toStringAsFixed(1)}점)',
        recommendation: '즉시 진입 권장',
      );
    }

    // Rule 3: Late stage (90%+) - immediate entry
    if (candleProgress.isLateStage) {
      return HybridEntryDecision(
        canEnterImmediately: true,
        reason: '캔들 마감 임박 (${candleProgress.progressPercent.toStringAsFixed(0)}%)',
        recommendation: '진입 가능',
      );
    }

    // Rule 4: Strong signal (6+ points) + Mid stage (60%+)
    if (signalStrength >= 6.0 && candleProgress.isMidStage) {
      return HybridEntryDecision(
        canEnterImmediately: true,
        reason: '강한 신호 (${signalStrength.toStringAsFixed(1)}점) + 캔들 중반 (${candleProgress.progressPercent.toStringAsFixed(0)}%)',
        recommendation: '진입 가능',
      );
    }

    // Rule 5: Otherwise - wait for candle close
    String waitReason;
    if (signalStrength < 6.0) {
      waitReason = '신호 약함 (${signalStrength.toStringAsFixed(1)}점)';
    } else if (candleProgress.isEarlyStage) {
      waitReason = '캔들 초반 (${candleProgress.progressPercent.toStringAsFixed(0)}%)';
    } else {
      waitReason = '조건 미충족';
    }

    return HybridEntryDecision(
      canEnterImmediately: false,
      reason: waitReason,
      recommendation: '캔들 클로즈 대기 (${candleProgress.remainingTimeString} 남음)',
    );
  }

  @override
  String toString() {
    return 'HybridEntryDecision(canEnter: $canEnterImmediately, reason: $reason, recommendation: $recommendation)';
  }
}
