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
  /// [klines5m]: 5분봉 캔들 데이터 (참고용, 재귀 예측에도 사용)
  /// [klines30m]: 30분봉 캔들 데이터 (참고용)
  /// [interval]: 예측 인터벌 ('1', '5', '30', '60', '240')
  /// [useRecursivePrediction]: 30분/1시간/4시간봉 예측 시 5분봉 재귀 예측 사용 여부
  PricePredictionSignal? generatePredictionSignal({
    required List<KlineData> klinesMain,
    required List<KlineData> klines5m,
    required List<KlineData> klines30m,
    required String interval,
    bool useRecursivePrediction = true,
  }) {
    // 최소 데이터 체크
    if (klinesMain.length < 50 || klines5m.length < 50 || klines30m.length < 50) {
      return null;
    }

    // 재귀 예측 사용: 15분/30분/1시간/4시간봉은 5분봉을 재귀적으로 예측
    if (useRecursivePrediction && (interval == '15' || interval == '30' || interval == '60' || interval == '240')) {
      return _generateRecursivePrediction(
        klinesMain: klinesMain,
        klines5m: klines5m,
        klines30m: klines30m,
        interval: interval,
      );
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

  /// 재귀적 예측: 5분봉을 여러 번 예측하여 더 긴 인터벌 예측
  ///
  /// 예: 30분봉 예측을 위해 5분봉을 6번 예측 (현재 봉 완성 + 5개 추가)
  PricePredictionSignal? _generateRecursivePrediction({
    required List<KlineData> klinesMain,
    required List<KlineData> klines5m,
    required List<KlineData> klines30m,
    required String interval,
  }) {
    final currentKline5m = klines5m.first;
    final current5mTimestamp = currentKline5m.timestamp;

    // 목표 인터벌의 분 단위
    final int targetMinutes = int.parse(interval);

    // 현재 5분봉이 시작한지 몇 분 경과했는지 계산
    final now = DateTime.now();
    final minutesInto5m = now.difference(current5mTimestamp).inMinutes % 5;

    // 현재 봉을 완성하기 위한 예측 횟수 계산
    final predictionsToComplete5m = minutesInto5m > 0 ? 1 : 0;

    // 목표 인터벌 시작까지 필요한 5분봉 개수
    final minutesToNextTarget = (targetMinutes - (now.minute % targetMinutes)) % targetMinutes;
    final predictions5mToTarget = minutesToNextTarget == 0 ? 0 : (minutesToNextTarget / 5).ceil();

    // 목표 인터벌 완성까지 필요한 5분봉 개수
    final predictions5mForTarget = targetMinutes ~/ 5;

    // 총 예측 횟수
    final totalPredictions = predictionsToComplete5m + predictions5mToTarget + predictions5mForTarget;

    // ⭐ 추세 방향 확률 계산
    final trendProbability = _calculateTrendProbability(klines5m, klines30m, interval);

    print('🔮 재귀 예측 시작 (${interval}분봉): 총 ${totalPredictions}번의 5분봉 예측 필요');
    print('  - 현재 5분봉 완성: ${predictionsToComplete5m}번');
    print('  - 목표 인터벌 시작까지: ${predictions5mToTarget}번');
    print('  - 목표 인터벌 완성: ${predictions5mForTarget}번');
    print('  - 상승 추세 확률: ${(trendProbability * 100).toStringAsFixed(1)}%');

    // 시뮬레이션용 캔들 리스트 (예측 결과를 추가해나감)
    List<KlineData> simulated5mKlines = List.from(klines5m);

    // 재귀적으로 5분봉 예측
    for (int i = 0; i < totalPredictions; i++) {
      // 현재 상태로 다음 5분봉 예측
      final prediction = generatePredictionSignal(
        klinesMain: simulated5mKlines,
        klines5m: simulated5mKlines,
        klines30m: klines30m,
        interval: '5',
        useRecursivePrediction: false, // 재귀 방지
      );

      if (prediction == null) {
        print('⚠️ 재귀 예측 실패 at step ${i+1}/${totalPredictions}');
        return null;
      }

      // ⭐ 추세 방향 보정 적용
      final correctedPrediction = _applyTrendCorrection(
        prediction: prediction,
        currentPrice: simulated5mKlines.first.close,
        trendProbability: trendProbability,
        stepNumber: i + 1,
        totalSteps: totalPredictions,
      );

      // 예측된 5분봉을 시뮬레이션 리스트에 추가
      final nextTimestamp = simulated5mKlines.first.timestamp.add(const Duration(minutes: 5));
      final predictedKline = KlineData(
        timestamp: nextTimestamp,
        open: simulated5mKlines.first.close, // 이전 종가로 시작
        high: correctedPrediction.predictedHigh,
        low: correctedPrediction.predictedLow,
        close: correctedPrediction.predictedClose,
        volume: simulated5mKlines.first.volume, // 볼륨은 평균값 사용
      );

      // 맨 앞에 추가 (최신 데이터가 앞에 오도록)
      simulated5mKlines.insert(0, predictedKline);

      // 리스트 크기 유지 (최대 100개)
      if (simulated5mKlines.length > 100) {
        simulated5mKlines.removeLast();
      }
    }

    // 예측된 5분봉들로부터 목표 인터벌 캔들 집계
    final predictedKlines = simulated5mKlines.take(predictions5mForTarget).toList();

    if (predictedKlines.isEmpty) {
      print('⚠️ 예측된 캔들이 없습니다');
      return null;
    }

    // 집계: HIGH는 최대, LOW는 최소, CLOSE는 마지막
    final aggregatedHigh = predictedKlines.map((k) => k.high).reduce((a, b) => a > b ? a : b);
    final aggregatedLow = predictedKlines.map((k) => k.low).reduce((a, b) => a < b ? a : b);
    final aggregatedClose = predictedKlines.first.close; // 가장 최근 (마지막) 종가

    final currentPrice = klines5m.first.close;
    final predictionStartTime = klinesMain.first.timestamp;

    // 시장 상태 감지 (원래 로직 재사용)
    final closePrices5m = klines5m.take(50).map((k) => k.close).toList();
    final bb5m = calculateBollingerBands(closePrices5m, 20, 2.0);

    final closePrices30m = klines30m.take(50).map((k) => k.close).toList();
    final rsi30m = calculateRSI(closePrices30m, 14);
    final bb30m = calculateBollingerBands(closePrices30m, 20, 2.0);
    final macd30m = calculateMACDFullSeries(closePrices30m).last;

    final marketState = _detectMarketState(
      bb5m: bb5m,
      bb30m: bb30m,
      rsi30m: rsi30m,
      macd30m: macd30m,
    );

    print('✅ 재귀 예측 완료: HIGH=$aggregatedHigh, LOW=$aggregatedLow, CLOSE=$aggregatedClose');

    return PricePredictionSignal(
      marketState: marketState,
      currentPrice: currentPrice,
      predictedHigh: aggregatedHigh,
      predictedLow: aggregatedLow,
      predictedClose: aggregatedClose,
      predictedRange: aggregatedHigh - aggregatedLow,
      avgMove5m: (aggregatedHigh - aggregatedLow) / predictions5mForTarget,
      confidence: marketState.baseConfidence * 0.9, // 재귀 예측은 약간 낮은 신뢰도
      timestamp: DateTime.now(),
      predictionInterval: interval,
      predictionStartTime: predictionStartTime,
    );
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

/// 추세 방향 확률 계산
///
/// 기존 5분봉 여러 개와 각 타임 인터벌의 추세를 비교하여
/// 상승 추세일 확률을 반환 (0.0~1.0)
double _calculateTrendProbability(
  List<KlineData> klines5m,
  List<KlineData> klines30m,
  String targetInterval,
) {
  // 분석할 5분봉 개수 (목표 인터벌에 따라 다름)
  final int candlesToAnalyze;
  if (targetInterval == '15') {
    candlesToAnalyze = 15; // 15분 = 3개 * 5개 샘플
  } else if (targetInterval == '30') {
    candlesToAnalyze = 30; // 30분 = 6개 * 5개 샘플
  } else if (targetInterval == '60') {
    candlesToAnalyze = 60; // 1시간 = 12개 * 5개 샘플
  } else {
    candlesToAnalyze = 100; // 4시간 = 48개 * 2개 샘플
  }

  // 5분봉 추세 방향 분석
  int upCount5m = 0;
  int totalCount5m = 0;

  for (int i = 1; i < klines5m.length.clamp(0, candlesToAnalyze); i++) {
    final prev = klines5m[i];
    final curr = klines5m[i - 1];

    if (curr.close > prev.close) {
      upCount5m++;
    }
    totalCount5m++;
  }

  // 30분봉 추세 방향 분석 (가중치 2배)
  int upCount30m = 0;
  int totalCount30m = 0;

  for (int i = 1; i < klines30m.length.clamp(0, 10); i++) {
    final prev = klines30m[i];
    final curr = klines30m[i - 1];

    if (curr.close > prev.close) {
      upCount30m += 2; // 가중치
    }
    totalCount30m += 2;
  }

  // 전체 상승 확률
  final totalUp = upCount5m + upCount30m;
  final total = totalCount5m + totalCount30m;

  if (total == 0) return 0.5; // 중립

  return totalUp / total;
}

/// 추세 방향 보정 적용
///
/// 예측값에 추세 확률과 진행 단계에 따른 보정 계수를 적용하여
/// 오차 누적과 발산을 방지
PricePredictionSignal _applyTrendCorrection({
  required PricePredictionSignal prediction,
  required double currentPrice,
  required double trendProbability,
  required int stepNumber,
  required int totalSteps,
}) {
  // 진행률 (0.0 ~ 1.0)
  final progress = stepNumber / totalSteps;

  // 감쇠 계수: 진행률이 높을수록 예측 변동폭 감소
  // 초반에는 1.0, 중반에는 0.7, 후반에는 0.4
  final dampingFactor = 1.0 - (progress * 0.6);

  // 추세 방향 보정 계수
  // trendProbability가 0.5보다 크면 상승 편향, 작으면 하락 편향
  final trendBias = (trendProbability - 0.5) * 2.0; // -1.0 ~ 1.0

  // 예측 변화량
  final predictedChange = prediction.predictedClose - currentPrice;

  // 보정된 변화량: 추세 방향으로 편향 + 감쇠 적용
  final correctedChange = predictedChange * dampingFactor * (1.0 + trendBias * 0.3);

  // 보정된 종가
  final correctedClose = currentPrice + correctedChange;

  // HIGH/LOW도 비율에 맞춰 보정
  final highRatio = (prediction.predictedHigh - currentPrice) / (predictedChange != 0 ? predictedChange.abs() : 1);
  final lowRatio = (prediction.predictedLow - currentPrice) / (predictedChange != 0 ? predictedChange.abs() : 1);

  final correctedHigh = currentPrice + (correctedChange.abs() * highRatio.abs()) * (correctedChange > 0 ? 1 : -1);
  final correctedLow = currentPrice + (correctedChange.abs() * lowRatio.abs()) * (correctedChange > 0 ? 1 : -1);

  return PricePredictionSignal(
    predictedHigh: correctedHigh,
    predictedLow: correctedLow,
    predictedClose: correctedClose,
    currentPrice: currentPrice,
    predictionStartTime: prediction.predictionStartTime,
    marketState: prediction.marketState,
    predictedRange: (correctedHigh - correctedLow).abs(),
    avgMove5m: prediction.avgMove5m,
    confidence: prediction.confidence * dampingFactor, // 감쇠 계수만큼 신뢰도 감소
    timestamp: prediction.timestamp,
    predictionInterval: prediction.predictionInterval,
  );
}
