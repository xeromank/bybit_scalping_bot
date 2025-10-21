import 'package:bybit_scalping_bot/backtesting/backtest_engine.dart';
import 'package:bybit_scalping_bot/backtesting/position_tracker.dart';
import 'package:bybit_scalping_bot/backtesting/split_entry_strategy.dart';
import 'package:bybit_scalping_bot/models/market_condition.dart';
import 'package:bybit_scalping_bot/services/market_analyzer.dart';
import 'package:bybit_scalping_bot/services/v3/band_walking_detector.dart';
import 'package:bybit_scalping_bot/services/v3/breakout_classifier.dart';
import 'package:bybit_scalping_bot/utils/technical_indicators.dart';

/// V3 Entry Strategy
///
/// 4단계 필터링 시스템:
/// 1. 복합 지표 분석 (Composite Analysis)
/// 2. 밴드워킹 감지 (Band Walking Detection)
/// 3. 브레이크아웃 분류 (Breakout Classification)
/// 4. 최종 진입 결정 (Entry Decision)
class EntryStrategyV3 {
  /// Check for entry signal
  static SplitEntrySignal? checkEntrySignal({
    required List<KlineData> recentKlines,
    required double currentPrice,
    required DateTime currentTime,
    required PositionTracker position,
  }) {
    // 최소 50개 캔들 필요
    if (recentKlines.length < 50) {
      return null;
    }

    // 이미 포지션이 있으면 진입 안 함 (V3는 단순화: 1개 포지션만)
    if (position.hasPosition) {
      return null;
    }

    final closePrices = recentKlines.map((k) => k.close).toList();
    final volumes = recentKlines.map((k) => k.volume).toList();

    // Stage 1: 복합 지표 분석
    final marketAnalysis = MarketAnalyzer.analyzeMarket(
      closePrices: closePrices,
      volumes: volumes,
    );

    final marketCondition = marketAnalysis.condition;
    final confidence = marketAnalysis.confidence; // 0.0 ~ 1.0

    // 낮은 신뢰도면 진입 안 함 (0.3 미만으로 완화)
    if (confidence < 0.3) {
      return null;
    }

    // 지표 계산
    final rsi = calculateRSI(closePrices, 14);
    final bb = calculateBollingerBands(closePrices, 20, 2.0);
    final macdSeries = calculateMACDFullSeries(closePrices);
    final macd = macdSeries.last;
    final volumeAnalysis = analyzeVolume(volumes);

    // RSI 히스토리 (최근 3개)
    final rsiHistory = <double>[];
    if (recentKlines.length >= 53) {
      for (int i = 1; i <= 3; i++) {
        final prevClosePrices =
            recentKlines.sublist(i, i + 50).map((k) => k.close).toList();
        rsiHistory.add(calculateRSI(prevClosePrices, 14));
      }
    }

    // Stage 2: 밴드워킹 감지
    final bandWalkingSignal = BandWalkingDetector.detect(
      recentKlines: recentKlines,
      bb: bb,
      macd: macd,
      macdHistory: macdSeries,
      volume: volumeAnalysis,
      rsi: rsi,
      rsiHistory: rsiHistory,
    );

    // Stage 3: 브레이크아웃 분류
    final breakoutType = BreakoutClassifier.classify(
      bandWalking: bandWalkingSignal,
      volume: volumeAnalysis,
      rsi: rsi,
      macd: macd,
    );

    // Stage 4: 최종 진입 결정
    return _makeEntryDecision(
      marketCondition: marketCondition,
      confidence: confidence,
      bandWalkingSignal: bandWalkingSignal,
      breakoutType: breakoutType,
      currentPrice: currentPrice,
      rsi: rsi,
      bb: bb,
      macd: macd,
      macdSeries: macdSeries,
      volume: volumeAnalysis,
    );
  }

  /// 최종 진입 결정
  static SplitEntrySignal? _makeEntryDecision({
    required MarketCondition marketCondition,
    required double confidence, // 0.0 ~ 1.0
    required BandWalkingSignal bandWalkingSignal,
    required BreakoutType breakoutType,
    required double currentPrice,
    required double rsi,
    required BollingerBands bb,
    required MACD macd,
    required List<MACD> macdSeries,
    required VolumeAnalysis volume,
  }) {
    // 관망 조건 체크
    if (_shouldWait(breakoutType, confidence, bandWalkingSignal)) {
      return null;
    }

    // 전략 1: 추세 추종 (밴드워킹 확정 시)
    if (bandWalkingSignal.shouldEnterTrendFollow) {
      return _checkTrendFollowingEntry(
        bandWalkingSignal: bandWalkingSignal,
        currentPrice: currentPrice,
        rsi: rsi,
        bb: bb,
        macd: macd,
        volume: volume,
        confidence: confidence,
      );
    }

    // 전략 2: 역추세 (평균회귀)
    if (!bandWalkingSignal.shouldBlockCounterTrend) {
      return _checkCounterTrendEntry(
        marketCondition: marketCondition,
        currentPrice: currentPrice,
        rsi: rsi,
        bb: bb,
        macd: macd,
        macdSeries: macdSeries,
        volume: volume,
        confidence: confidence,
        breakoutType: breakoutType,
      );
    }

    return null;
  }

  /// 관망 여부 체크
  static bool _shouldWait(
    BreakoutType breakoutType,
    double confidence,
    BandWalkingSignal bandWalkingSignal,
  ) {
    // 브레이크아웃 초기 (1-2캔들) - 밴드워킹 전환 가능성
    if (breakoutType == BreakoutType.BREAKOUT_INITIAL) {
      return true;
    }

    // 밴드워킹 전환 중이고 MEDIUM이면 관망
    if (breakoutType == BreakoutType.BREAKOUT_TO_BANDWALKING &&
        bandWalkingSignal.risk == BandWalkingRisk.MEDIUM) {
      return true;
    }

    return false;
  }

  /// 추세 추종 진입 체크
  static SplitEntrySignal? _checkTrendFollowingEntry({
    required BandWalkingSignal bandWalkingSignal,
    required double currentPrice,
    required double rsi,
    required BollingerBands bb,
    required MACD macd,
    required VolumeAnalysis volume,
    required double confidence,
  }) {
    // 상승 밴드워킹
    if (bandWalkingSignal.direction == 'UP') {
      if (rsi > 65 &&
          macd.histogram > 0 &&
          volume.relativeVolumeRatio > 1.5) {
        return SplitEntrySignal(
          side: PositionSide.long,
          entryPrice: currentPrice,
          entryLevel: 1,
          strategyType: StrategyType.trendFollowing,
          reasoning:
              '상승 밴드워킹 확정 (Score: ${bandWalkingSignal.score}) - ${bandWalkingSignal.reasons.join(", ")}',
          confidence: 0.9,
        );
      }
    }

    // 하락 밴드워킹
    if (bandWalkingSignal.direction == 'DOWN') {
      // 패닉 셀링 체크 (RSI < 25, Volume > 20x)
      if (rsi < 25 && volume.relativeVolumeRatio > 20) {
        // 패닉 셀링 시 진입 보류
        return null;
      }

      // 너무 많이 떨어진 후면 진입 안 함
      final priceChangePercent =
          ((currentPrice - bb.middle) / bb.middle) * 100;
      if (priceChangePercent < -1.5) {
        return null;
      }

      if (rsi < 35 &&
          macd.histogram < 0 &&
          volume.relativeVolumeRatio > 1.5) {
        return SplitEntrySignal(
          side: PositionSide.short,
          entryPrice: currentPrice,
          entryLevel: 1,
          strategyType: StrategyType.trendFollowing,
          reasoning:
              '하락 밴드워킹 확정 (Score: ${bandWalkingSignal.score}) - ${bandWalkingSignal.reasons.join(", ")}',
          confidence: 0.85,
        );
      }
    }

    return null;
  }

  /// 역추세 진입 체크
  static SplitEntrySignal? _checkCounterTrendEntry({
    required MarketCondition marketCondition,
    required double currentPrice,
    required double rsi,
    required BollingerBands bb,
    required MACD macd,
    required List<MACD> macdSeries,
    required VolumeAnalysis volume,
    required double confidence,
    required BreakoutType breakoutType,
  }) {
    // 횡보장/약한 추세에서만 역추세 진입
    if (marketCondition != MarketCondition.ranging &&
        marketCondition != MarketCondition.weakBullish &&
        marketCondition != MarketCondition.weakBearish) {
      return null;
    }

    // 헤드페이크 또는 브레이크아웃 실패 패턴만
    if (breakoutType != BreakoutType.HEADFAKE &&
        breakoutType != BreakoutType.BREAKOUT_REVERSAL) {
      return null;
    }

    // MACD 히스토그램 개선/악화 체크
    final prevMacdHistogram = macdSeries.length >= 2
        ? macdSeries[macdSeries.length - 2].histogram
        : macd.histogram;

    // BB 하위 20% 영역 계산
    final bbLowerZone = bb.lower + (bb.middle - bb.lower) * 0.2;
    final bbUpperZone = bb.upper - (bb.upper - bb.middle) * 0.2;

    // LONG 진입 (BB 하위 20% 영역)
    if (currentPrice <= bbLowerZone &&
        rsi < 35 &&
        volume.relativeVolumeRatio < 10.0) {
      // Volume 폭발 아님
      return SplitEntrySignal(
        side: PositionSide.long,
        entryPrice: currentPrice,
        entryLevel: 1,
        strategyType: StrategyType.counterTrend,
        reasoning:
            '역추세 LONG (RSI: ${rsi.toStringAsFixed(1)}, BB하위권, Vol: ${volume.relativeVolumeRatio.toStringAsFixed(1)}x)',
        confidence: confidence >= 0.8 ? 0.8 : 0.6,
      );
    }

    // SHORT 진입 (BB 상위 20% 영역)
    if (currentPrice >= bbUpperZone &&
        rsi > 65 &&
        volume.relativeVolumeRatio < 10.0) {
      // Volume 폭발 아님
      return SplitEntrySignal(
        side: PositionSide.short,
        entryPrice: currentPrice,
        entryLevel: 1,
        strategyType: StrategyType.counterTrend,
        reasoning:
            '역추세 SHORT (RSI: ${rsi.toStringAsFixed(1)}, BB상위권, Vol: ${volume.relativeVolumeRatio.toStringAsFixed(1)}x)',
        confidence: confidence >= 0.8 ? 0.8 : 0.6,
      );
    }

    return null;
  }

  /// Check for exit signal (simplified)
  static SplitExitSignal? checkExitSignal({
    required List<KlineData> recentKlines,
    required double currentPrice,
    required PositionTracker position,
  }) {
    if (!position.hasPosition) {
      return null;
    }

    final closePrices = recentKlines.map((k) => k.close).toList();
    final volumes = recentKlines.map((k) => k.volume).toList();

    // 지표 계산
    final rsi = calculateRSI(closePrices, 14);
    final bb = calculateBollingerBands(closePrices, 20, 2.0);
    final macdSeries = calculateMACDFullSeries(closePrices);
    final macd = macdSeries.last;
    final volumeAnalysis = analyzeVolume(volumes);

    // RSI 히스토리
    final rsiHistory = <double>[];
    if (recentKlines.length >= 53) {
      for (int i = 1; i <= 3; i++) {
        final prevClosePrices =
            recentKlines.sublist(i, i + 50).map((k) => k.close).toList();
        rsiHistory.add(calculateRSI(prevClosePrices, 14));
      }
    }

    // 밴드워킹 감지 (긴급 손절용)
    final bandWalkingSignal = BandWalkingDetector.detect(
      recentKlines: recentKlines,
      bb: bb,
      macd: macd,
      macdHistory: macdSeries,
      volume: volumeAnalysis,
      rsi: rsi,
      rsiHistory: rsiHistory,
    );

    // 긴급 손절: 반대 방향 밴드워킹 HIGH
    if (position.currentSide == PositionSide.long &&
        bandWalkingSignal.direction == 'DOWN' &&
        bandWalkingSignal.risk == BandWalkingRisk.HIGH) {
      return SplitExitSignal(
        exitPrice: currentPrice,
        exitPercent: 1.0,
        reasoning: '긴급 손절: 하락 밴드워킹 감지',
        isEmergency: true,
      );
    }

    if (position.currentSide == PositionSide.short &&
        bandWalkingSignal.direction == 'UP' &&
        bandWalkingSignal.risk == BandWalkingRisk.HIGH) {
      return SplitExitSignal(
        exitPrice: currentPrice,
        exitPercent: 1.0,
        reasoning: '긴급 손절: 상승 밴드워킹 감지',
        isEmergency: true,
      );
    }

    // 일반 손절/익절
    final pnlPercent = position.calculateUnrealizedPnlPercent(currentPrice);

    // 손절: 전략 타입별로 다르게 적용
    double stopLossThreshold;
    if (position.strategyType == StrategyType.trendFollowing) {
      // 추세 추종: 매우 넓은 손절 (-5.0%) - 큰 추세를 따라가기 위함
      stopLossThreshold = -0.05;
    } else {
      // 역추세: 타이트한 손절 (-0.5%)
      stopLossThreshold = -0.005;
    }

    if (pnlPercent <= stopLossThreshold) {
      return SplitExitSignal(
        exitPrice: currentPrice,
        exitPercent: 1.0,
        reasoning: '손절 ${(pnlPercent * 100).toStringAsFixed(2)}%',
        isEmergency: false,
      );
    }

    // BB Middle 도달 시 익절
    // 단, 추세 추종 진입은 반대 밴드까지 홀딩 (밴드워킹 중)
    if (position.strategyType == StrategyType.counterTrend) {
      // 역추세는 BB Middle에서 익절
      if (position.currentSide == PositionSide.long && currentPrice >= bb.middle) {
        return SplitExitSignal(
          exitPrice: currentPrice,
          exitPercent: 1.0,
          reasoning: 'BB Middle 도달 익절 +${(pnlPercent * 100).toStringAsFixed(2)}%',
          isEmergency: false,
        );
      }

      if (position.currentSide == PositionSide.short && currentPrice <= bb.middle) {
        return SplitExitSignal(
          exitPrice: currentPrice,
          exitPercent: 1.0,
          reasoning: 'BB Middle 도달 익절 +${(pnlPercent * 100).toStringAsFixed(2)}%',
          isEmergency: false,
        );
      }
    } else if (position.strategyType == StrategyType.trendFollowing) {
      // 추세 추종은 반대 밴드 또는 밴드워킹 종료 시 청산
      if (position.currentSide == PositionSide.long && currentPrice >= bb.upper) {
        return SplitExitSignal(
          exitPrice: currentPrice,
          exitPercent: 1.0,
          reasoning: 'BB Upper 도달 익절 +${(pnlPercent * 100).toStringAsFixed(2)}%',
          isEmergency: false,
        );
      }

      if (position.currentSide == PositionSide.short && currentPrice <= bb.lower) {
        return SplitExitSignal(
          exitPrice: currentPrice,
          exitPercent: 1.0,
          reasoning: 'BB Lower 도달 익절 +${(pnlPercent * 100).toStringAsFixed(2)}%',
          isEmergency: false,
        );
      }

      // 밴드워킹 종료 시 BB Middle에서 청산
      if (bandWalkingSignal.risk != BandWalkingRisk.HIGH &&
          bandWalkingSignal.risk != BandWalkingRisk.MEDIUM) {
        if (position.currentSide == PositionSide.long && currentPrice >= bb.middle) {
          return SplitExitSignal(
            exitPrice: currentPrice,
            exitPercent: 1.0,
            reasoning: '밴드워킹 종료, BB Middle 익절 +${(pnlPercent * 100).toStringAsFixed(2)}%',
            isEmergency: false,
          );
        }

        if (position.currentSide == PositionSide.short && currentPrice <= bb.middle) {
          return SplitExitSignal(
            exitPrice: currentPrice,
            exitPercent: 1.0,
            reasoning: '밴드워킹 종료, BB Middle 익절 +${(pnlPercent * 100).toStringAsFixed(2)}%',
            isEmergency: false,
          );
        }
      }
    }

    return null;
  }
}
