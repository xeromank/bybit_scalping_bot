import 'package:bybit_scalping_bot/backtesting/backtest_engine.dart';
import 'package:bybit_scalping_bot/models/price_prediction_signal.dart';
import 'package:bybit_scalping_bot/utils/technical_indicators.dart';

/// 가격 범위 예측 서비스 V2
///
/// 개선사항:
/// - ATR 대신 최근 5개 캔들의 평균 이동폭(avgMove5m) 사용
/// - 얇은 꼬리 제외한 실질 가격 범위 예측
/// - HIGH/LOW/CLOSE 3가지 모두 예측
/// - 목표: 평균 오차 0.05% (약 $2) 이내
class PricePredictionServiceV2 {
  /// 최적 avgMove5m 배수 (백테스트 결과 기반)
  static const Map<MarketState, _PredictionMultipliers> _multipliers = {
    MarketState.SQUEEZE_5M: _PredictionMultipliers(
      highMultiplier: 0.52,
      lowMultiplier: 0.57,
      closeMultiplier: 0.55,
    ),
    MarketState.SQUEEZE_30M: _PredictionMultipliers(
      highMultiplier: 0.60,
      lowMultiplier: 0.74,
      closeMultiplier: 0.65,
    ),
    MarketState.STRONG_UP: _PredictionMultipliers(
      highMultiplier: 1.17,
      lowMultiplier: 0.70,
      closeMultiplier: 0.99,
    ),
    MarketState.STRONG_DOWN: _PredictionMultipliers(
      highMultiplier: 0.68,
      lowMultiplier: 1.30,
      closeMultiplier: 0.93,
    ),
    MarketState.WEAK_UP: _PredictionMultipliers(
      highMultiplier: 0.62,
      lowMultiplier: 0.66,
      closeMultiplier: 0.69,
    ),
    MarketState.WEAK_DOWN: _PredictionMultipliers(
      highMultiplier: 0.66,
      lowMultiplier: 0.41,
      closeMultiplier: 0.47,
    ),
    MarketState.NEUTRAL: _PredictionMultipliers(
      highMultiplier: 0.70,
      lowMultiplier: 0.70,
      closeMultiplier: 0.70,
    ),
  };

  /// 가격 예측 신호 생성
  ///
  /// [klinesMain]: 예측 대상 인터벌의 캔들 데이터
  /// [klines5m]: 5분봉 캔들 데이터 (참고용)
  /// [klines30m]: 30분봉 캔들 데이터 (참고용)
  /// [interval]: 예측 인터벌 ('1', '5', '30', '60', '240')
  PricePredictionSignal? generatePredictionSignal({
    required List<KlineData> klinesMain,
    required List<KlineData> klines5m,
    required List<KlineData> klines30m,
    required String interval,
  }) {
    // 최소 데이터 체크
    if (klinesMain.length < 50 || klines5m.length < 50 || klines30m.length < 50) {
      return null;
    }

    // 현재 캔들 (예측 대상 인터벌)
    final currentKline = klinesMain.first;
    final currentPrice = currentKline.close;
    final predictionStartTime = currentKline.timestamp;

    // 주 인터벌 지표 계산
    final closePricesMain = klinesMain.take(50).map((k) => k.close).toList();
    final macdMain = calculateMACDFullSeries(closePricesMain).last;

    // 5분봉 지표 계산 (참고용)
    final closePrices5m = klines5m.take(50).map((k) => k.close).toList();
    final bb5m = calculateBollingerBands(closePrices5m, 20, 2.0);

    // 30분봉 지표 계산 (참고용)
    final closePrices30m = klines30m.take(50).map((k) => k.close).toList();
    final rsi30m = calculateRSI(closePrices30m, 14);
    final bb30m = calculateBollingerBands(closePrices30m, 20, 2.0);
    final macd30m = calculateMACDFullSeries(closePrices30m).last;

    // 최근 5개 캔들의 평균 이동폭 계산 (주 인터벌 기준)
    final avgMove = _calculateAvgMove(klinesMain.take(5).toList());

    // 시장 상태 감지
    final marketState = _detectMarketState(
      bb5m: bb5m,
      bb30m: bb30m,
      rsi30m: rsi30m,
      macd30m: macd30m,
    );

    // 배수 가져오기
    final multipliers = _multipliers[marketState]!;

    // 인터벌별 배수 조정
    final adjustedMultipliers = _adjustMultipliersForInterval(multipliers, interval);

    // 방향 예측 (종가용) - 주 인터벌 MACD 사용
    final direction = _predictDirection(macd5m: macdMain, marketState: marketState);

    // 가격 예측
    final predictedHigh = currentPrice + (avgMove * adjustedMultipliers.highMultiplier);
    final predictedLow = currentPrice - (avgMove * adjustedMultipliers.lowMultiplier);
    final predictedClose = currentPrice + (avgMove * adjustedMultipliers.closeMultiplier * direction);
    final predictedRange = predictedHigh - predictedLow;

    return PricePredictionSignal(
      marketState: marketState,
      currentPrice: currentPrice,
      predictedHigh: predictedHigh,
      predictedLow: predictedLow,
      predictedClose: predictedClose,
      predictedRange: predictedRange,
      avgMove5m: avgMove, // 이름은 유지하되, 실제로는 주 인터벌 기준
      confidence: marketState.baseConfidence,
      timestamp: DateTime.now(),
      predictionInterval: interval,
      predictionStartTime: predictionStartTime,
    );
  }

  /// 최근 5개 캔들의 평균 이동폭 계산
  double _calculateAvgMove(List<KlineData> recentKlines) {
    if (recentKlines.length < 5) return 0.0;

    final moves = recentKlines.map((k) => k.high - k.low).toList();
    return moves.reduce((a, b) => a + b) / moves.length;
  }

  /// 인터벌별 배수 조정
  ///
  /// 기본 배수는 5분봉 기준이므로, 다른 인터벌에 맞게 조정
  _PredictionMultipliers _adjustMultipliersForInterval(
    _PredictionMultipliers baseMultipliers,
    String interval,
  ) {
    // 5분봉 기준이므로 조정 계수 적용
    double adjustmentFactor;

    switch (interval) {
      case '1': // 1분봉: 변동폭이 5분봉의 ~20% 수준
        adjustmentFactor = 0.20;
        break;
      case '5': // 5분봉: 기본 (1.0)
        adjustmentFactor = 1.0;
        break;
      case '30': // 30분봉: 변동폭이 5분봉의 ~6배
        adjustmentFactor = 6.0;
        break;
      case '60': // 1시간봉: 변동폭이 5분봉의 ~12배
        adjustmentFactor = 12.0;
        break;
      case '240': // 4시간봉: 변동폭이 5분봉의 ~48배
        adjustmentFactor = 48.0;
        break;
      default:
        // 비표준 인터벌: 비율 계산
        final minutes = int.tryParse(interval) ?? 5;
        adjustmentFactor = minutes / 5.0;
    }

    return _PredictionMultipliers(
      highMultiplier: baseMultipliers.highMultiplier * adjustmentFactor,
      lowMultiplier: baseMultipliers.lowMultiplier * adjustmentFactor,
      closeMultiplier: baseMultipliers.closeMultiplier * adjustmentFactor,
    );
  }

  /// 방향 예측 (-1: 하락, +1: 상승)
  double _predictDirection({
    required MACD macd5m,
    required MarketState marketState,
  }) {
    // 추세 시장: MACD로 방향 판단
    if (marketState == MarketState.STRONG_UP || marketState == MarketState.WEAK_UP) {
      return 1.0; // 상승
    } else if (marketState == MarketState.STRONG_DOWN || marketState == MarketState.WEAK_DOWN) {
      return -1.0; // 하락
    }

    // 스퀴즈/중립: MACD 히스토그램으로 판단
    if (macd5m.histogram > 0) {
      return 1.0;
    } else if (macd5m.histogram < 0) {
      return -1.0;
    }

    return 0.0; // 중립
  }

  /// 시장 상태 감지
  MarketState _detectMarketState({
    required BollingerBands bb5m,
    required BollingerBands bb30m,
    required double rsi30m,
    required MACD macd30m,
  }) {
    // BB Width 계산
    final bbWidth5m = (bb5m.upper - bb5m.lower) / bb5m.middle;
    final bbWidth30m = (bb30m.upper - bb30m.lower) / bb30m.middle;

    // 5분봉 스퀴즈 판단
    final is5mSqueeze = bbWidth5m < 0.02; // 2% 미만

    // 30분봉 스퀴즈 판단
    final is30mSqueeze = bbWidth30m < 0.02 &&
                         rsi30m > 40 &&
                         rsi30m < 60 &&
                         macd30m.histogram.abs() < 2.0;

    // 시장 상태 분류
    if (is30mSqueeze) {
      return MarketState.SQUEEZE_30M;
    } else if (is5mSqueeze) {
      return MarketState.SQUEEZE_5M;
    } else {
      // 추세 판단
      if (rsi30m > 60 && macd30m.histogram > 2.0) {
        return MarketState.STRONG_UP;
      } else if (rsi30m < 40 && macd30m.histogram < -2.0) {
        return MarketState.STRONG_DOWN;
      } else if (rsi30m > 50 && macd30m.histogram > 0) {
        return MarketState.WEAK_UP;
      } else if (rsi30m < 50 && macd30m.histogram < 0) {
        return MarketState.WEAK_DOWN;
      } else {
        return MarketState.NEUTRAL;
      }
    }
  }
}

/// 예측 배수
class _PredictionMultipliers {
  final double highMultiplier;
  final double lowMultiplier;
  final double closeMultiplier;

  const _PredictionMultipliers({
    required this.highMultiplier,
    required this.lowMultiplier,
    required this.closeMultiplier,
  });
}
