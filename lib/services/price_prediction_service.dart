import 'package:bybit_scalping_bot/backtesting/backtest_engine.dart';
import 'package:bybit_scalping_bot/models/price_prediction_signal.dart';
import 'package:bybit_scalping_bot/utils/technical_indicators.dart';
import 'dart:math';

/// 가격 범위 예측 서비스
///
/// 역할: 다음 5분봉의 가격 범위(최고가/최저가)를 예측하는 신호만 제공
/// - 진입/청산 로직 없음
/// - 순수하게 예측 신호만 생성
class PricePredictionService {
  /// 최적 ATR 배수 (백테스트 결과 기반 - 실제 평균값)
  /// 백테스트: 949개 샘플, 평균 오차 최소화 목표
  static const Map<MarketState, _PriceRangeMultipliers> _multipliers = {
    MarketState.SQUEEZE_5M: _PriceRangeMultipliers(
      highMultiplier: 0.42, // 실제 평균 배수 (오차 최소화)
      lowMultiplier: 0.46,  // 실제 평균 배수 (오차 최소화)
    ),
    MarketState.SQUEEZE_30M: _PriceRangeMultipliers(
      highMultiplier: 0.47, // 실제 평균 배수 (오차 최소화)
      lowMultiplier: 0.43,  // 실제 평균 배수 (오차 최소화)
    ),
    MarketState.STRONG_UP: _PriceRangeMultipliers(
      highMultiplier: 0.28, // 실제 평균 배수 (오차 최소화)
      lowMultiplier: 0.58,  // 실제 평균 배수 (오차 최소화)
    ),
    MarketState.STRONG_DOWN: _PriceRangeMultipliers(
      highMultiplier: 0.23, // 실제 평균 배수 (오차 최소화)
      lowMultiplier: 0.50,  // 실제 평균 배수 (오차 최소화)
    ),
    MarketState.WEAK_UP: _PriceRangeMultipliers(
      highMultiplier: 0.34, // 실제 평균 배수 (오차 최소화)
      lowMultiplier: 0.44,  // 실제 평균 배수 (오차 최소화)
    ),
    MarketState.WEAK_DOWN: _PriceRangeMultipliers(
      highMultiplier: 0.34, // 실제 평균 배수 (오차 최소화)
      lowMultiplier: 0.39,  // 실제 평균 배수 (오차 최소화)
    ),
    MarketState.NEUTRAL: _PriceRangeMultipliers(
      highMultiplier: 0.61, // 실제 평균 배수 (오차 최소화)
      lowMultiplier: 0.44,  // 실제 평균 배수 (오차 최소화)
    ),
  };

  /// 가격 예측 신호 생성
  ///
  /// [klines5m]: 최소 50개 이상의 5분봉 데이터 (최신이 첫 번째)
  /// [klines30m]: 최소 50개 이상의 30분봉 데이터 (최신이 첫 번째)
  ///
  /// 반환: 다음 5분봉의 예상 가격 범위 신호
  PricePredictionSignal? generatePredictionSignal({
    required List<KlineData> klines5m,
    required List<KlineData> klines30m,
  }) {
    // 최소 데이터 체크
    if (klines5m.length < 50 || klines30m.length < 50) {
      return null;
    }

    // 현재 캔들 (가장 최신)
    final currentKline = klines5m.first;
    final currentPrice = currentKline.close;

    // 5분봉 지표 계산
    final closePrices5m = klines5m.take(50).map((k) => k.close).toList();
    final bb5m = calculateBollingerBands(closePrices5m, 20, 2.0);

    // 30분봉 지표 계산
    final closePrices30m = klines30m.take(50).map((k) => k.close).toList();
    final rsi30m = calculateRSI(closePrices30m, 14);
    final bb30m = calculateBollingerBands(closePrices30m, 20, 2.0);
    final macd30m = calculateMACDFullSeries(closePrices30m).last;

    // ATR 계산 (5분봉 기준, 14개 캔들)
    final atr = _calculateATR(klines5m.take(14).toList());

    // 시장 상태 감지
    final marketState = _detectMarketState(
      bb5m: bb5m,
      bb30m: bb30m,
      rsi30m: rsi30m,
      macd30m: macd30m,
    );

    // 시장 상태별 ATR 배수 가져오기
    final multipliers = _multipliers[marketState]!;

    // 가격 범위 예측
    final predictedHigh = currentPrice + (atr * multipliers.highMultiplier);
    final predictedLow = currentPrice - (atr * multipliers.lowMultiplier);
    final predictedRange = predictedHigh - predictedLow;

    // 종가 예측: 시장 상태에 따라 종가 위치 결정
    final predictedClose = marketState == MarketState.STRONG_UP || marketState == MarketState.WEAK_UP
        ? currentPrice + (atr * 0.5) // 상승장: 현재가보다 위
        : marketState == MarketState.STRONG_DOWN || marketState == MarketState.WEAK_DOWN
            ? currentPrice - (atr * 0.5) // 하락장: 현재가보다 아래
            : currentPrice; // 횡보: 현재가 근처

    return PricePredictionSignal(
      marketState: marketState,
      currentPrice: currentPrice,
      predictedHigh: predictedHigh,
      predictedLow: predictedLow,
      predictedClose: predictedClose,
      predictedRange: predictedRange,
      avgMove5m: atr, // V1에서는 ATR을 avgMove5m으로 사용
      confidence: marketState.baseConfidence,
      timestamp: DateTime.now(),
    );
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

  /// ATR 계산
  double _calculateATR(List<KlineData> klines) {
    if (klines.length < 2) return 0.0;

    final trueRanges = <double>[];
    for (int i = 1; i < klines.length; i++) {
      final high = klines[i].high;
      final low = klines[i].low;
      final prevClose = klines[i - 1].close;

      final tr = max(
        high - low,
        max((high - prevClose).abs(), (low - prevClose).abs()),
      );
      trueRanges.add(tr);
    }

    return trueRanges.reduce((a, b) => a + b) / trueRanges.length;
  }
}

/// 가격 범위 ATR 배수
class _PriceRangeMultipliers {
  final double highMultiplier;
  final double lowMultiplier;

  const _PriceRangeMultipliers({
    required this.highMultiplier,
    required this.lowMultiplier,
  });
}
