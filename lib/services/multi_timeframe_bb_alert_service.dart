import 'package:bybit_scalping_bot/backtesting/backtest_engine.dart';
import 'package:bybit_scalping_bot/utils/technical_indicators.dart';

/// 멀티 타임프레임 볼린저 밴드 & RSI 알림 서비스
///
/// 기능:
/// - BB 알림: 5분, 15분, 30분, 1시간, 4시간 봉의 BB 계산, 4개 이상 타임프레임이 동시에 BB 상단/하단 근접 시 알림
/// - RSI 알림: 5분 RSI ≤ 30, 15분 RSI ≤ 35, 30분 RSI ≤ 40 동시 충족 시 알림
class MultiTimeframeBBAlertService {
  // BB 근접 판단 임계값 (10% = 0.1)
  static const double proximityThreshold = 0.10;

  // 최소 타임프레임 개수 (4개 이상)
  static const int minTimeframesRequired = 4;

  /// BB 알림 체크 결과
  BBAlertResult? checkBBAlert({
    required List<KlineData> klines5m,
    required List<KlineData> klines15m,
    required List<KlineData> klines30m,
    required List<KlineData> klines1h,
    required List<KlineData> klines4h,
    required double currentPrice,
  }) {
    // 각 타임프레임의 BB 상태 체크
    final bbStates = <String, BBState>{};

    bbStates['5m'] = _checkBBState(klines5m, currentPrice);
    bbStates['15m'] = _checkBBState(klines15m, currentPrice);
    bbStates['30m'] = _checkBBState(klines30m, currentPrice);
    bbStates['1h'] = _checkBBState(klines1h, currentPrice);
    bbStates['4h'] = _checkBBState(klines4h, currentPrice);

    // 상단 근접 카운트
    int upperCount = 0;
    double upperProximitySum = 0;
    final upperTimeframes = <String>[];

    // 하단 근접 카운트
    int lowerCount = 0;
    double lowerProximitySum = 0;
    final lowerTimeframes = <String>[];

    for (final entry in bbStates.entries) {
      final timeframe = entry.key;
      final state = entry.value;

      if (state.isNearUpper) {
        upperCount++;
        upperProximitySum += state.upperProximityPercent;
        upperTimeframes.add(timeframe);
      }

      if (state.isNearLower) {
        lowerCount++;
        lowerProximitySum += state.lowerProximityPercent;
        lowerTimeframes.add(timeframe);
      }
    }

    // 과매수 알림 (4개 이상이 상단 근접)
    if (upperCount >= minTimeframesRequired) {
      final avgProximity = upperProximitySum / upperCount;
      return BBAlertResult(
        type: BBAlertType.overbought,
        timeframeCount: upperCount,
        timeframes: upperTimeframes,
        avgProximityPercent: avgProximity,
        currentPrice: currentPrice,
        bbStates: bbStates,
      );
    }

    // 과매도 알림 (4개 이상이 하단 근접)
    if (lowerCount >= minTimeframesRequired) {
      final avgProximity = lowerProximitySum / lowerCount;
      return BBAlertResult(
        type: BBAlertType.oversold,
        timeframeCount: lowerCount,
        timeframes: lowerTimeframes,
        avgProximityPercent: avgProximity,
        currentPrice: currentPrice,
        bbStates: bbStates,
      );
    }

    // 알림 조건 미충족
    return null;
  }

  /// 특정 타임프레임의 BB 상태 체크
  BBState _checkBBState(List<KlineData> klines, double currentPrice) {
    if (klines.length < 20) {
      return BBState(
        bb: null,
        isNearUpper: false,
        isNearLower: false,
        upperProximityPercent: 0,
        lowerProximityPercent: 0,
      );
    }

    // BB 계산 (기간 20, 표준편차 2)
    final closes = klines.reversed.take(20).map((k) => k.close).toList();
    final bb = calculateBollingerBands(closes, 20, 2);

    // 상단 근접도 계산 (0~1, 1에 가까울수록 상단 근접)
    // upperProximity = (현재가 - middle) / (upper - middle)
    final upperDistance = bb.upper - currentPrice;
    final upperRange = bb.upper - bb.middle;
    final upperProximity = upperRange > 0 ? 1.0 - (upperDistance / upperRange) : 0;

    // 하단 근접도 계산 (0~1, 1에 가까울수록 하단 근접)
    // lowerProximity = (middle - 현재가) / (middle - lower)
    final lowerDistance = currentPrice - bb.lower;
    final lowerRange = bb.middle - bb.lower;
    final lowerProximity = lowerRange > 0 ? 1.0 - (lowerDistance / lowerRange) : 0;

    // 근접 판단 (상단/하단 10% 이내)
    final isNearUpper = upperProximity >= (1.0 - proximityThreshold);
    final isNearLower = lowerProximity >= (1.0 - proximityThreshold);

    return BBState(
      bb: bb,
      isNearUpper: isNearUpper,
      isNearLower: isNearLower,
      upperProximityPercent: upperProximity * 100,
      lowerProximityPercent: lowerProximity * 100,
    );
  }
}

/// BB 알림 타입
enum BBAlertType {
  overbought, // 과매수 (상단 근접) - 숏 기회
  oversold,   // 과매도 (하단 근접) - 롱 기회
}

/// BB 알림 결과
class BBAlertResult {
  final BBAlertType type;
  final int timeframeCount; // 조건 충족 타임프레임 개수
  final List<String> timeframes; // 조건 충족 타임프레임 목록
  final double avgProximityPercent; // 평균 근접도 (%)
  final double currentPrice;
  final Map<String, BBState> bbStates; // 각 타임프레임의 BB 상태

  BBAlertResult({
    required this.type,
    required this.timeframeCount,
    required this.timeframes,
    required this.avgProximityPercent,
    required this.currentPrice,
    required this.bbStates,
  });

  String get alertMessage {
    final typeEmoji = type == BBAlertType.overbought ? '📈' : '📉';
    final typeKr = type == BBAlertType.overbought ? '과매수' : '과매도';
    final opportunityKr = type == BBAlertType.overbought ? '숏 기회' : '롱 기회';

    return '$typeEmoji 멀티 타임프레임 $typeKr 알림\n'
        '🎯 $timeframeCount개 타임프레임 동시 감지\n'
        '⏰ ${timeframes.join(", ")}\n'
        '💰 현재가: \$${currentPrice.toStringAsFixed(2)}\n'
        '📊 평균 근접도: ${avgProximityPercent.toStringAsFixed(1)}%\n'
        '🔔 $opportunityKr';
  }

  String get logMessage {
    final typeKr = type == BBAlertType.overbought ? '과매수' : '과매도';
    final opportunityKr = type == BBAlertType.overbought ? '숏' : '롱';

    final details = StringBuffer();
    details.writeln('[$typeKr 알림] $timeframeCount개 타임프레임 동시 감지');
    details.writeln('현재가: \$${currentPrice.toStringAsFixed(2)}');
    details.writeln('평균 근접도: ${avgProximityPercent.toStringAsFixed(1)}%');
    details.writeln('감지 타임프레임: ${timeframes.join(", ")}');
    details.writeln('매매 기회: $opportunityKr');
    details.writeln('---');

    // 각 타임프레임 상세 정보
    for (final entry in bbStates.entries) {
      final tf = entry.key;
      final state = entry.value;

      if (state.bb != null) {
        final proximity = type == BBAlertType.overbought
            ? state.upperProximityPercent
            : state.lowerProximityPercent;

        final marker = (type == BBAlertType.overbought && state.isNearUpper) ||
                (type == BBAlertType.oversold && state.isNearLower)
            ? '✅'
            : '  ';

        details.writeln(
          '$marker $tf: BB(${state.bb!.lower.toStringAsFixed(2)}, '
          '${state.bb!.middle.toStringAsFixed(2)}, '
          '${state.bb!.upper.toStringAsFixed(2)}) '
          '근접도: ${proximity.toStringAsFixed(1)}%',
        );
      }
    }

    return details.toString();
  }
}

/// BB 상태
class BBState {
  final BollingerBands? bb;
  final bool isNearUpper; // 상단 근접 여부
  final bool isNearLower; // 하단 근접 여부
  final double upperProximityPercent; // 상단 근접도 (0~100%)
  final double lowerProximityPercent; // 하단 근접도 (0~100%)

  BBState({
    required this.bb,
    required this.isNearUpper,
    required this.isNearLower,
    required this.upperProximityPercent,
    required this.lowerProximityPercent,
  });
}

extension MultiTimeframeRSIAlert on MultiTimeframeBBAlertService {
  /// RSI 멀티 타임프레임 과매도 알림 체크
  ///
  /// 조건:
  /// - 5분봉 RSI ≤ 30
  /// - 15분봉 RSI ≤ 35
  /// - 30분봉 RSI ≤ 40
  RSIAlertResult? checkRSIOversold({
    required List<KlineData> klines5m,
    required List<KlineData> klines15m,
    required List<KlineData> klines30m,
    required double currentPrice,
  }) {
    // RSI 계산 (기간 14)
    if (klines5m.length < 15 || klines15m.length < 15 || klines30m.length < 15) {
      return null;
    }

    final closes5m = klines5m.reversed.take(15).map((k) => k.close).toList();
    final closes15m = klines15m.reversed.take(15).map((k) => k.close).toList();
    final closes30m = klines30m.reversed.take(15).map((k) => k.close).toList();

    final rsi5m = calculateRSI(closes5m, 14);
    final rsi15m = calculateRSI(closes15m, 14);
    final rsi30m = calculateRSI(closes30m, 14);

    // 조건 체크
    final is5mOversold = rsi5m <= 30;
    final is15mOversold = rsi15m <= 35;
    final is30mOversold = rsi30m <= 40;

    if (is5mOversold && is15mOversold && is30mOversold) {
      return RSIAlertResult(
        type: RSIAlertType.oversold,
        rsi5m: rsi5m,
        rsi15m: rsi15m,
        rsi30m: rsi30m,
        currentPrice: currentPrice,
      );
    }

    return null;
  }

  /// RSI 멀티 타임프레임 과매수 알림 체크
  ///
  /// 조건:
  /// - 5분봉 RSI ≥ 70
  /// - 15분봉 RSI ≥ 65
  /// - 30분봉 RSI ≥ 60
  RSIAlertResult? checkRSIOverbought({
    required List<KlineData> klines5m,
    required List<KlineData> klines15m,
    required List<KlineData> klines30m,
    required double currentPrice,
  }) {
    // RSI 계산 (기간 14)
    if (klines5m.length < 15 || klines15m.length < 15 || klines30m.length < 15) {
      return null;
    }

    final closes5m = klines5m.reversed.take(15).map((k) => k.close).toList();
    final closes15m = klines15m.reversed.take(15).map((k) => k.close).toList();
    final closes30m = klines30m.reversed.take(15).map((k) => k.close).toList();

    final rsi5m = calculateRSI(closes5m, 14);
    final rsi15m = calculateRSI(closes15m, 14);
    final rsi30m = calculateRSI(closes30m, 14);

    // 조건 체크
    final is5mOverbought = rsi5m >= 70;
    final is15mOverbought = rsi15m >= 65;
    final is30mOverbought = rsi30m >= 60;

    if (is5mOverbought && is15mOverbought && is30mOverbought) {
      return RSIAlertResult(
        type: RSIAlertType.overbought,
        rsi5m: rsi5m,
        rsi15m: rsi15m,
        rsi30m: rsi30m,
        currentPrice: currentPrice,
      );
    }

    return null;
  }
}

/// RSI 알림 타입
enum RSIAlertType {
  overbought, // 과매수 (상단) - 숏 기회
  oversold,   // 과매도 (하단) - 롱 기회
}

/// RSI 알림 결과
class RSIAlertResult {
  final RSIAlertType type;
  final double rsi5m;
  final double rsi15m;
  final double rsi30m;
  final double currentPrice;

  RSIAlertResult({
    required this.type,
    required this.rsi5m,
    required this.rsi15m,
    required this.rsi30m,
    required this.currentPrice,
  });

  String get alertMessage {
    if (type == RSIAlertType.oversold) {
      return '📉 멀티 타임프레임 RSI 과매도 알림\n'
          '🎯 3개 타임프레임 동시 과매도\n'
          '⏰ 5분, 15분, 30분\n'
          '💰 현재가: \$${currentPrice.toStringAsFixed(2)}\n'
          '📊 RSI: 5분=${rsi5m.toStringAsFixed(1)}, 15분=${rsi15m.toStringAsFixed(1)}, 30분=${rsi30m.toStringAsFixed(1)}\n'
          '🔔 롱 기회 (강한 과매도)';
    } else {
      return '📈 멀티 타임프레임 RSI 과매수 알림\n'
          '🎯 3개 타임프레임 동시 과매수\n'
          '⏰ 5분, 15분, 30분\n'
          '💰 현재가: \$${currentPrice.toStringAsFixed(2)}\n'
          '📊 RSI: 5분=${rsi5m.toStringAsFixed(1)}, 15분=${rsi15m.toStringAsFixed(1)}, 30분=${rsi30m.toStringAsFixed(1)}\n'
          '🔔 숏 기회 (강한 과매수)';
    }
  }

  String get logMessage {
    if (type == RSIAlertType.oversold) {
      return '[RSI 과매도 알림] 3개 타임프레임 동시 감지\n'
          '현재가: \$${currentPrice.toStringAsFixed(2)}\n'
          '---\n'
          '✅ 5분봉: RSI ${rsi5m.toStringAsFixed(1)} (≤ 30)\n'
          '✅ 15분봉: RSI ${rsi15m.toStringAsFixed(1)} (≤ 35)\n'
          '✅ 30분봉: RSI ${rsi30m.toStringAsFixed(1)} (≤ 40)\n'
          '매매 기회: 롱 (강한 과매도)';
    } else {
      return '[RSI 과매수 알림] 3개 타임프레임 동시 감지\n'
          '현재가: \$${currentPrice.toStringAsFixed(2)}\n'
          '---\n'
          '✅ 5분봉: RSI ${rsi5m.toStringAsFixed(1)} (≥ 70)\n'
          '✅ 15분봉: RSI ${rsi15m.toStringAsFixed(1)} (≥ 65)\n'
          '✅ 30분봉: RSI ${rsi30m.toStringAsFixed(1)} (≥ 60)\n'
          '매매 기회: 숏 (강한 과매수)';
    }
  }
}
