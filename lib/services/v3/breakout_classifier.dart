import 'package:bybit_scalping_bot/services/v3/band_walking_detector.dart';
import 'package:bybit_scalping_bot/utils/technical_indicators.dart';

/// 브레이크아웃 타입
enum BreakoutType {
  HEADFAKE, // 헤드페이크 (거짓 돌파)
  BREAKOUT_INITIAL, // 브레이크아웃 초기 (관망 필요)
  BREAKOUT_REVERSAL, // 브레이크아웃 실패 (복귀)
  BREAKOUT_TO_BANDWALKING, // 밴드워킹 전환 중
  BANDWALKING_CONFIRMED, // 밴드워킹 확정
}

/// 브레이크아웃 분류기
class BreakoutClassifier {
  /// 브레이크아웃 패턴 분류
  static BreakoutType classify({
    required BandWalkingSignal bandWalking,
    required VolumeAnalysis volume,
    required double rsi,
    required MACD macd,
  }) {
    final consecutiveOutside = bandWalking.consecutiveOutside;
    final volumeRatio = volume.relativeVolumeRatio;
    final rsiExtreme = rsi > 70 || rsi < 30;
    final macdStrong = macd.histogram.abs() > 5.0;

    // 1개 캔들만 밴드 밖
    if (consecutiveOutside == 1) {
      if (volumeRatio > 15.0) {
        return BreakoutType.BREAKOUT_INITIAL; // 브레이크아웃 초기 (관망)
      } else if (volumeRatio < 8.0) {
        return BreakoutType.HEADFAKE; // 헤드페이크 (역추세 진입 가능)
      } else {
        return BreakoutType.BREAKOUT_INITIAL; // 불확실 (관망)
      }
    }

    // 2개 캔들 밴드 밖
    if (consecutiveOutside == 2) {
      if (rsiExtreme && volumeRatio > 5.0) {
        return BreakoutType.BREAKOUT_TO_BANDWALKING; // 밴드워킹 전환 중
      } else {
        return BreakoutType.BREAKOUT_REVERSAL; // 브레이크아웃 실패
      }
    }

    // 3개+ 캔들 밴드 밖
    if (consecutiveOutside >= 3) {
      if (rsiExtreme && macdStrong && volumeRatio > 3.0) {
        return BreakoutType.BANDWALKING_CONFIRMED; // 밴드워킹 확정
      } else {
        return BreakoutType.BREAKOUT_REVERSAL; // 약한 추세 (복귀 가능)
      }
    }

    return BreakoutType.HEADFAKE;
  }

  /// 브레이크아웃 타입 설명
  static String getDescription(BreakoutType type) {
    switch (type) {
      case BreakoutType.HEADFAKE:
        return '헤드페이크 - 역추세 진입 가능';
      case BreakoutType.BREAKOUT_INITIAL:
        return '브레이크아웃 초기 - 관망 (3캔들 대기)';
      case BreakoutType.BREAKOUT_REVERSAL:
        return '브레이크아웃 실패 - 역추세 진입 고려';
      case BreakoutType.BREAKOUT_TO_BANDWALKING:
        return '밴드워킹 전환 중 - 역추세 차단';
      case BreakoutType.BANDWALKING_CONFIRMED:
        return '밴드워킹 확정 - 추세 추종 진입';
    }
  }
}
