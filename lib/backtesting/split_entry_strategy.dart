import 'package:bybit_scalping_bot/models/market_condition.dart';
import 'package:bybit_scalping_bot/utils/technical_indicators.dart';
import 'package:bybit_scalping_bot/backtesting/position_tracker.dart';

/// Strategy type
enum StrategyType {
  trendFollowing,  // Strategy A: Extreme markets
  counterTrend,    // Strategy B: Ranging/normal markets
}

extension StrategyTypeExtension on StrategyType {
  String get name {
    switch (this) {
      case StrategyType.trendFollowing:
        return '추세추종';
      case StrategyType.counterTrend:
        return '역추세';
    }
  }
}

/// Entry signal for split entry strategy
class SplitEntrySignal {
  final PositionSide side;
  final double entryPrice;
  final int entryLevel; // 1, 2, 3
  final StrategyType strategyType;
  final String reasoning;
  final double confidence;

  SplitEntrySignal({
    required this.side,
    required this.entryPrice,
    required this.entryLevel,
    required this.strategyType,
    required this.reasoning,
    required this.confidence,
  });

  bool get hasSignal => side != PositionSide.none;

  @override
  String toString() {
    return 'Signal[Lv$entryLevel ${side.name.toUpperCase()} @\$${entryPrice.toStringAsFixed(2)} ${strategyType.name} (${(confidence * 100).toStringAsFixed(0)}%)]';
  }
}

/// Exit signal for split exit strategy
class SplitExitSignal {
  final double exitPrice;
  final double exitPercent; // 0.0 to 1.0 (how much to close)
  final String reasoning;
  final bool isEmergency; // Emergency stop loss

  SplitExitSignal({
    required this.exitPrice,
    required this.exitPercent,
    required this.reasoning,
    this.isEmergency = false,
  });

  bool get hasSignal => exitPercent > 0;

  @override
  String toString() {
    final percentStr = (exitPercent * 100).toStringAsFixed(0);
    return 'Exit[${percentStr}% @\$${exitPrice.toStringAsFixed(2)} ${isEmergency ? '⚠️긴급' : ''}]';
  }
}

/// Split Entry/Exit Strategy (Adaptive by Market Condition)
///
/// Strategy A (Trend Following) - Extreme Markets:
/// - BB breakout direction entry
/// - Add on trend confirmation
/// - Target large profits
///
/// Strategy B (Counter Trend + Averaging) - Ranging/Normal Markets:
/// - BB breakout opposite entry (mean reversion bet)
/// - Add on pullback (averaging down/up)
/// - Quick profit target
class SplitEntryStrategy {
  /// Minimum time between entries (seconds)
  static const int _minSecondsBetween2nd = 120; // 2 minutes
  static const int _minSecondsBetween3rd = 180; // 3 minutes

  /// Check for entry signal
  static SplitEntrySignal? checkEntrySignal({
    required MarketCondition marketCondition,
    required List<double> closePrices,
    required List<double> volumes,
    required double currentPrice,
    required DateTime currentTime,
    required PositionTracker position,
  }) {
    // Determine strategy type based on market condition
    final strategyType = _getStrategyType(marketCondition);

    // Check entry based on strategy type
    if (strategyType == StrategyType.trendFollowing) {
      return _checkTrendFollowingEntry(
        marketCondition: marketCondition,
        closePrices: closePrices,
        volumes: volumes,
        currentPrice: currentPrice,
        currentTime: currentTime,
        position: position,
      );
    } else {
      return _checkCounterTrendEntry(
        marketCondition: marketCondition,
        closePrices: closePrices,
        volumes: volumes,
        currentPrice: currentPrice,
        currentTime: currentTime,
        position: position,
      );
    }
  }

  /// Check for exit signal
  static SplitExitSignal? checkExitSignal({
    required MarketCondition marketCondition,
    required List<double> closePrices,
    required double currentPrice,
    required DateTime currentTime,
    required PositionTracker position,
    required int leverage,
  }) {
    if (!position.hasPosition) return null;

    // Safety check: strategyType should not be null if we have a position
    if (position.strategyType == null) {
      return null;
    }

    final strategyType = position.strategyType!;
    final unrealizedPnl = position.calculateUnrealizedPnlPercent(currentPrice);

    // PRIORITY 1: Emergency stop loss check (both strategies)
    final emergencyExit = _checkEmergencyStopLoss(
      marketCondition: marketCondition,
      closePrices: closePrices,
      currentPrice: currentPrice,
      position: position,
      unrealizedPnl: unrealizedPnl,
      leverage: leverage,
    );

    if (emergencyExit != null) return emergencyExit;

    // PRIORITY 2: Normal exit based on strategy type
    if (strategyType == StrategyType.trendFollowing) {
      return _checkTrendFollowingExit(
        closePrices: closePrices,
        currentPrice: currentPrice,
        position: position,
        unrealizedPnl: unrealizedPnl,
        leverage: leverage,
      );
    } else {
      return _checkCounterTrendExit(
        closePrices: closePrices,
        currentPrice: currentPrice,
        position: position,
        unrealizedPnl: unrealizedPnl,
        leverage: leverage,
      );
    }
  }

  // ==========================================================================
  // Strategy Type Selection
  // ==========================================================================

  static StrategyType _getStrategyType(MarketCondition condition) {
    switch (condition) {
      // 극단적 추세: 추세 추종만 (한 방향만)
      case MarketCondition.extremeBullish:
      case MarketCondition.extremeBearish:
        return StrategyType.trendFollowing;

      // 강한 추세: 추세 추종 위주 (하지만 극단적 과열시 역추세도 고려)
      case MarketCondition.strongBullish:
      case MarketCondition.strongBearish:
        return StrategyType.trendFollowing;

      // 약한 추세 + 횡보: 평균회귀 전략 (양방향)
      case MarketCondition.weakBullish:
      case MarketCondition.weakBearish:
      case MarketCondition.ranging:
        return StrategyType.counterTrend;
    }
  }

  // ==========================================================================
  // STRATEGY A: Trend Following (Extreme Markets)
  // ==========================================================================

  static SplitEntrySignal? _checkTrendFollowingEntry({
    required MarketCondition marketCondition,
    required List<double> closePrices,
    required List<double> volumes,
    required double currentPrice,
    required DateTime currentTime,
    required PositionTracker position,
  }) {
    if (closePrices.length < 50) return null;

    final bb = calculateBollingerBandsDefault(closePrices);
    final rsi = calculateRSISeries(closePrices, 14);
    if (rsi.isEmpty) return null;

    final currentRSI = rsi.last;
    final avgVolume = volumes.length >= 20
        ? volumes.sublist(volumes.length - 20).reduce((a, b) => a + b) / 20
        : volumes.reduce((a, b) => a + b) / volumes.length;
    final currentVolume = volumes.last;

    final ema9 = calculateEMASeries(closePrices, 9);

    // Determine side based on market condition
    final targetSide = (marketCondition == MarketCondition.extremeBullish ||
                        marketCondition == MarketCondition.strongBullish)
        ? PositionSide.long
        : PositionSide.short;

    // No position yet - check for 1st entry
    if (!position.hasPosition) {
      return _checkTrendFollowing1stEntry(
        targetSide: targetSide,
        currentPrice: currentPrice,
        bb: bb,
        currentRSI: currentRSI,
        avgVolume: avgVolume,
        currentVolume: currentVolume,
        ema9: ema9,
      );
    }

    // Already have position - check for 2nd or 3rd entry
    if (position.currentSide != targetSide) return null;

    final timeSinceLastEntry = currentTime.difference(position.entries.last.entryTime).inSeconds;

    if (position.latestEntryLevel == 1) {
      return _checkTrendFollowing2ndEntry(
        targetSide: targetSide,
        currentPrice: currentPrice,
        position: position,
        timeSinceLastEntry: timeSinceLastEntry,
        bb: bb,
      );
    } else if (position.latestEntryLevel == 2) {
      return _checkTrendFollowing3rdEntry(
        targetSide: targetSide,
        currentPrice: currentPrice,
        position: position,
        timeSinceLastEntry: timeSinceLastEntry,
        currentRSI: currentRSI,
        closePrices: closePrices,
      );
    }

    return null;
  }

  static SplitEntrySignal? _checkTrendFollowing1stEntry({
    required PositionSide targetSide,
    required double currentPrice,
    required BollingerBands bb,
    required double currentRSI,
    required double avgVolume,
    required double currentVolume,
    required List<double> ema9,
  }) {
    final volumeRatio = currentVolume / avgVolume;

    if (targetSide == PositionSide.long) {
      // Long: BB upper breakout + RSI > 55 (완화)
      if (currentPrice > bb.upper &&
          currentRSI > 55 &&
          currentRSI < 85 &&
          volumeRatio >= 1.1 &&
          ema9.isNotEmpty &&
          ema9.last > ema9[ema9.length - 2]) {
        return SplitEntrySignal(
          side: PositionSide.long,
          entryPrice: currentPrice,
          entryLevel: 1,
          strategyType: StrategyType.trendFollowing,
          reasoning: 'BB 상단 돌파 (RSI: ${currentRSI.toStringAsFixed(1)}, Vol: ${volumeRatio.toStringAsFixed(1)}x)',
          confidence: 0.7,
        );
      }
    } else {
      // Short: BB lower breakout + RSI < 45 (완화)
      if (currentPrice < bb.lower &&
          currentRSI < 45 &&
          currentRSI > 15 &&
          volumeRatio >= 1.1 &&
          ema9.isNotEmpty &&
          ema9.last < ema9[ema9.length - 2]) {
        return SplitEntrySignal(
          side: PositionSide.short,
          entryPrice: currentPrice,
          entryLevel: 1,
          strategyType: StrategyType.trendFollowing,
          reasoning: 'BB 하단 돌파 (RSI: ${currentRSI.toStringAsFixed(1)}, Vol: ${volumeRatio.toStringAsFixed(1)}x)',
          confidence: 0.7,
        );
      }
    }

    return null;
  }

  static SplitEntrySignal? _checkTrendFollowing2ndEntry({
    required PositionSide targetSide,
    required double currentPrice,
    required PositionTracker position,
    required int timeSinceLastEntry,
    required BollingerBands bb,
  }) {
    if (timeSinceLastEntry < _minSecondsBetween2nd) return null;

    final unrealizedPnl = position.calculateUnrealizedPnlPercent(currentPrice);

    // Check: Still outside BB + profit > 0.15%
    final outsideBB = targetSide == PositionSide.long
        ? currentPrice > bb.upper
        : currentPrice < bb.lower;

    if (outsideBB && unrealizedPnl > 0.0015) {
      return SplitEntrySignal(
        side: targetSide,
        entryPrice: currentPrice,
        entryLevel: 2,
        strategyType: StrategyType.trendFollowing,
        reasoning: '추세 지속 확인 (수익: ${(unrealizedPnl * 100).toStringAsFixed(2)}%)',
        confidence: 0.75,
      );
    }

    return null;
  }

  static SplitEntrySignal? _checkTrendFollowing3rdEntry({
    required PositionSide targetSide,
    required double currentPrice,
    required PositionTracker position,
    required int timeSinceLastEntry,
    required double currentRSI,
    required List<double> closePrices,
  }) {
    if (timeSinceLastEntry < _minSecondsBetween3rd) return null;

    final unrealizedPnl = position.calculateUnrealizedPnlPercent(currentPrice);

    // Check: Profit > 0.3% + RSI still extreme + candle confirmation
    if (unrealizedPnl < 0.003) return null;

    final rsiCheck = targetSide == PositionSide.long
        ? currentRSI >= 55
        : currentRSI <= 45;

    if (!rsiCheck) return null;

    // Candle confirmation: last 2 candles in target direction
    if (closePrices.length >= 3) {
      final recent3 = closePrices.sublist(closePrices.length - 3);
      final bullishCandles = recent3[1] > recent3[0] && recent3[2] > recent3[1];
      final bearishCandles = recent3[1] < recent3[0] && recent3[2] < recent3[1];

      final candleCheck = targetSide == PositionSide.long ? bullishCandles : bearishCandles;

      if (candleCheck) {
        return SplitEntrySignal(
          side: targetSide,
          entryPrice: currentPrice,
          entryLevel: 3,
          strategyType: StrategyType.trendFollowing,
          reasoning: '강한 추세 확정 (수익: ${(unrealizedPnl * 100).toStringAsFixed(2)}%, RSI: ${currentRSI.toStringAsFixed(1)})',
          confidence: 0.80,
        );
      }
    }

    return null;
  }

  static SplitExitSignal? _checkTrendFollowingExit({
    required List<double> closePrices,
    required double currentPrice,
    required PositionTracker position,
    required double unrealizedPnl,
    required int leverage,
  }) {
    // Tiered exit based on leverage
    final exitTiers = _getTrendFollowingExitTiers(leverage);

    for (final tier in exitTiers) {
      if (unrealizedPnl >= tier.profitTarget) {
        return SplitExitSignal(
          exitPrice: currentPrice,
          exitPercent: tier.exitPercent,
          reasoning: '목표 달성 ${(unrealizedPnl * 100).toStringAsFixed(2)}%',
        );
      }
    }

    // Individual entry stop loss
    final stopLoss = -0.004; // -0.4% for 1st entry
    if (unrealizedPnl <= stopLoss) {
      return SplitExitSignal(
        exitPrice: currentPrice,
        exitPercent: 1.0,
        reasoning: '손절 ${(unrealizedPnl * 100).toStringAsFixed(2)}%',
      );
    }

    return null;
  }

  static List<({double profitTarget, double exitPercent})> _getTrendFollowingExitTiers(int leverage) {
    if (leverage >= 15) {
      return [
        (profitTarget: 0.006, exitPercent: 0.30),
        (profitTarget: 0.012, exitPercent: 0.40),
        (profitTarget: 0.020, exitPercent: 0.20),
        (profitTarget: 0.030, exitPercent: 0.10),
      ];
    } else if (leverage >= 10) {
      return [
        (profitTarget: 0.005, exitPercent: 0.25),
        (profitTarget: 0.010, exitPercent: 0.35),
        (profitTarget: 0.015, exitPercent: 0.25),
        (profitTarget: 0.022, exitPercent: 0.15),
      ];
    } else {
      // leverage 5
      return [
        (profitTarget: 0.004, exitPercent: 0.20),
        (profitTarget: 0.008, exitPercent: 0.30),
        (profitTarget: 0.012, exitPercent: 0.30),
        (profitTarget: 0.018, exitPercent: 0.20),
      ];
    }
  }

  // ==========================================================================
  // STRATEGY B: Counter Trend + Averaging (Ranging/Normal Markets)
  // ==========================================================================

  static SplitEntrySignal? _checkCounterTrendEntry({
    required MarketCondition marketCondition,
    required List<double> closePrices,
    required List<double> volumes,
    required double currentPrice,
    required DateTime currentTime,
    required PositionTracker position,
  }) {
    if (closePrices.length < 50) return null;

    final bb = calculateBollingerBandsDefault(closePrices);
    final rsi = calculateRSISeries(closePrices, 14);
    if (rsi.isEmpty) return null;

    final currentRSI = rsi.last;

    // No position - check for 1st entry (mean reversion)
    if (!position.hasPosition) {
      return _checkCounterTrend1stEntry(
        currentPrice: currentPrice,
        bb: bb,
        currentRSI: currentRSI,
        closePrices: closePrices,
      );
    }

    // Check if market condition changed to extreme (abort averaging!)
    if (marketCondition == MarketCondition.extremeBullish ||
        marketCondition == MarketCondition.extremeBearish) {
      // Do NOT add more entries - wait for exit
      return null;
    }

    // Already have position - check for averaging
    final timeSinceLastEntry = currentTime.difference(position.entries.last.entryTime).inSeconds;
    final unrealizedPnl = position.calculateUnrealizedPnlPercent(currentPrice);

    if (position.latestEntryLevel == 1) {
      return _checkCounterTrend2ndEntry(
        currentPrice: currentPrice,
        position: position,
        timeSinceLastEntry: timeSinceLastEntry,
        unrealizedPnl: unrealizedPnl,
        currentRSI: currentRSI,
        bb: bb,
      );
    } else if (position.latestEntryLevel == 2) {
      return _checkCounterTrend3rdEntry(
        currentPrice: currentPrice,
        position: position,
        timeSinceLastEntry: timeSinceLastEntry,
        unrealizedPnl: unrealizedPnl,
        currentRSI: currentRSI,
        bb: bb,
      );
    }

    return null;
  }

  static SplitEntrySignal? _checkCounterTrend1stEntry({
    required double currentPrice,
    required BollingerBands bb,
    required double currentRSI,
    required List<double> closePrices,
  }) {
    // ETH 기준: BB lower/upper 영역에서 RSI 확인 (매우 완화)

    // Long signal: BB lower 아래 OR (BB 하단 5% 이내 + RSI < 50)
    if (currentPrice <= bb.lower ||
        (currentPrice <= bb.lower * 1.05 && currentRSI < 50)) {
      return SplitEntrySignal(
        side: PositionSide.long,
        entryPrice: currentPrice,
        entryLevel: 1,
        strategyType: StrategyType.counterTrend,
        reasoning: 'BB 하단 과매도 (RSI: ${currentRSI.toStringAsFixed(1)})',
        confidence: 0.65,
      );
    }

    // Short signal: BB upper 위 OR (BB 상단 5% 이내 + RSI > 50)
    if (currentPrice >= bb.upper ||
        (currentPrice >= bb.upper * 0.95 && currentRSI > 50)) {
      return SplitEntrySignal(
        side: PositionSide.short,
        entryPrice: currentPrice,
        entryLevel: 1,
        strategyType: StrategyType.counterTrend,
        reasoning: 'BB 상단 과매수 (RSI: ${currentRSI.toStringAsFixed(1)})',
        confidence: 0.65,
      );
    }

    return null;
  }

  static SplitEntrySignal? _checkCounterTrend2ndEntry({
    required double currentPrice,
    required PositionTracker position,
    required int timeSinceLastEntry,
    required double unrealizedPnl,
    required double currentRSI,
    required BollingerBands bb,
  }) {
    if (timeSinceLastEntry < _minSecondsBetween2nd) return null;

    // 2차 진입: 손실 -0.2% ~ -0.8% (완화)
    if (unrealizedPnl > -0.002 || unrealizedPnl < -0.008) return null;

    // Check: Price moved against us + RSI still extreme (ETH 기준)
    final targetSide = position.currentSide;

    if (targetSide == PositionSide.long) {
      // Long position: price dropped + RSI still < 50 (ETH 기준 완화)
      if (currentRSI < 50 && currentPrice < position.averagePrice * 0.997) {
        return SplitEntrySignal(
          side: PositionSide.long,
          entryPrice: currentPrice,
          entryLevel: 2,
          strategyType: StrategyType.counterTrend,
          reasoning: '평단가 개선 (손실: ${(unrealizedPnl * 100).toStringAsFixed(2)}%)',
          confidence: 0.60,
        );
      }
    } else {
      // Short position: price rose + RSI still > 50 (ETH 기준 완화)
      if (currentRSI > 50 && currentPrice > position.averagePrice * 1.003) {
        return SplitEntrySignal(
          side: PositionSide.short,
          entryPrice: currentPrice,
          entryLevel: 2,
          strategyType: StrategyType.counterTrend,
          reasoning: '평단가 개선 (손실: ${(unrealizedPnl * 100).toStringAsFixed(2)}%)',
          confidence: 0.60,
        );
      }
    }

    return null;
  }

  static SplitEntrySignal? _checkCounterTrend3rdEntry({
    required double currentPrice,
    required PositionTracker position,
    required int timeSinceLastEntry,
    required double unrealizedPnl,
    required double currentRSI,
    required BollingerBands bb,
  }) {
    if (timeSinceLastEntry < _minSecondsBetween3rd) return null;

    // 3차 진입: 손실 -0.6% ~ -1.5% (완화)
    if (unrealizedPnl > -0.006 || unrealizedPnl < -0.015) return null;

    // Check: Extreme RSI + price outside BB (ETH 기준)
    final targetSide = position.currentSide;

    if (targetSide == PositionSide.long) {
      // 롱: RSI < 45 (ETH 기준 완화)
      if (currentRSI < 45 && currentPrice < bb.lower * 0.99) {
        return SplitEntrySignal(
          side: PositionSide.long,
          entryPrice: currentPrice,
          entryLevel: 3,
          strategyType: StrategyType.counterTrend,
          reasoning: '최종 평단가 개선 (손실: ${(unrealizedPnl * 100).toStringAsFixed(2)}%, RSI: ${currentRSI.toStringAsFixed(1)})',
          confidence: 0.70,
        );
      }
    } else {
      // 숏: RSI > 55 (ETH 기준 완화)
      if (currentRSI > 55 && currentPrice > bb.upper * 1.01) {
        return SplitEntrySignal(
          side: PositionSide.short,
          entryPrice: currentPrice,
          entryLevel: 3,
          strategyType: StrategyType.counterTrend,
          reasoning: '최종 평단가 개선 (손실: ${(unrealizedPnl * 100).toStringAsFixed(2)}%, RSI: ${currentRSI.toStringAsFixed(1)})',
          confidence: 0.70,
        );
      }
    }

    return null;
  }

  static SplitExitSignal? _checkCounterTrendExit({
    required List<double> closePrices,
    required double currentPrice,
    required PositionTracker position,
    required double unrealizedPnl,
    required int leverage,
  }) {
    if (closePrices.length < 20) return null;

    // BB Middle 도달 시 빠른 청산 (평균회귀 완료)
    final bb = calculateBollingerBandsDefault(closePrices);
    final targetSide = position.currentSide;

    if (targetSide == PositionSide.long) {
      // 롱: 가격이 BB Middle 이상 도달 → 즉시 청산
      if (currentPrice >= bb.middle && unrealizedPnl > 0) {
        return SplitExitSignal(
          exitPrice: currentPrice,
          exitPercent: 1.0,
          reasoning: 'BB Middle 도달 (평균회귀 완료)',
        );
      }
    } else {
      // 숏: 가격이 BB Middle 이하 도달 → 즉시 청산
      if (currentPrice <= bb.middle && unrealizedPnl > 0) {
        return SplitExitSignal(
          exitPrice: currentPrice,
          exitPercent: 1.0,
          reasoning: 'BB Middle 도달 (평균회귀 완료)',
        );
      }
    }

    // Quick profit targets (lower than trend following)
    final exitTiers = _getCounterTrendExitTiers(leverage);

    for (final tier in exitTiers) {
      if (unrealizedPnl >= tier.profitTarget) {
        return SplitExitSignal(
          exitPrice: currentPrice,
          exitPercent: tier.exitPercent,
          reasoning: '빠른 익절 ${(unrealizedPnl * 100).toStringAsFixed(2)}%',
        );
      }
    }

    // 역추세 최종 손절: -2.0% (분할 진입 충분히 허용)
    final stopLoss = -0.020; // -2.0%

    if (unrealizedPnl <= stopLoss) {
      return SplitExitSignal(
        exitPrice: currentPrice,
        exitPercent: 1.0,
        reasoning: '최종 손절 ${(unrealizedPnl * 100).toStringAsFixed(2)}%',
      );
    }

    return null;
  }

  static List<({double profitTarget, double exitPercent})> _getCounterTrendExitTiers(int leverage) {
    if (leverage >= 15) {
      return [
        (profitTarget: 0.005, exitPercent: 0.40),
        (profitTarget: 0.010, exitPercent: 0.40),
        (profitTarget: 0.015, exitPercent: 0.15),
        (profitTarget: 0.025, exitPercent: 0.05),
      ];
    } else if (leverage >= 10) {
      return [
        (profitTarget: 0.004, exitPercent: 0.35),
        (profitTarget: 0.008, exitPercent: 0.40),
        (profitTarget: 0.012, exitPercent: 0.15),
        (profitTarget: 0.020, exitPercent: 0.10),
      ];
    } else {
      // leverage 5
      return [
        (profitTarget: 0.003, exitPercent: 0.30),
        (profitTarget: 0.006, exitPercent: 0.40),
        (profitTarget: 0.010, exitPercent: 0.20),
        (profitTarget: 0.015, exitPercent: 0.10),
      ];
    }
  }

  // ==========================================================================
  // Emergency Stop Loss (Both Strategies)
  // ==========================================================================

  static SplitExitSignal? _checkEmergencyStopLoss({
    required MarketCondition marketCondition,
    required List<double> closePrices,
    required double currentPrice,
    required PositionTracker position,
    required double unrealizedPnl,
    required int leverage,
  }) {
    final strategyType = position.strategyType!;

    // Emergency SL based on strategy type
    if (strategyType == StrategyType.trendFollowing) {
      // Trend following: -0.8% total loss
      if (unrealizedPnl <= -0.008) {
        return SplitExitSignal(
          exitPrice: currentPrice,
          exitPercent: 1.0,
          reasoning: '긴급 손절 -0.8%',
          isEmergency: true,
        );
      }

      // BB reversal check - AND 조건으로 변경 (덜 민감하게)
      final bb = calculateBollingerBandsDefault(closePrices);
      final rsi = calculateRSISeries(closePrices, 14);
      if (rsi.isNotEmpty) {
        final currentRSI = rsi.last;

        if (position.currentSide == PositionSide.long) {
          // Long: dropped below BB lower AND RSI < 40 (완화)
          if (currentPrice < bb.lower && currentRSI < 40) {
            return SplitExitSignal(
              exitPrice: currentPrice,
              exitPercent: 1.0,
              reasoning: '추세 반전 감지',
              isEmergency: true,
            );
          }
        } else {
          // Short: rose above BB upper AND RSI > 60 (완화)
          if (currentPrice > bb.upper && currentRSI > 60) {
            return SplitExitSignal(
              exitPrice: currentPrice,
              exitPercent: 1.0,
              reasoning: '추세 반전 감지',
              isEmergency: true,
            );
          }
        }
      }
    } else {
      // Counter trend: stricter emergency SL

      // 1. Total loss > -1.0% (or -0.8% for high leverage)
      final maxLoss = leverage >= 10 ? -0.008 : -0.010;
      if (unrealizedPnl <= maxLoss) {
        return SplitExitSignal(
          exitPrice: currentPrice,
          exitPercent: 1.0,
          reasoning: '긴급 손절 ${(maxLoss * 100).toStringAsFixed(1)}%',
          isEmergency: true,
        );
      }

      // 2. Market condition changed to strong trend (역추세 전략 위험)
      // EMA 정렬 + 가격 모멘텀으로 강화
      if (closePrices.length >= 21) {
        final ema9 = calculateEMASeries(closePrices, 9);
        final ema21 = calculateEMASeries(closePrices, 21);

        if (ema9.isNotEmpty && ema21.isNotEmpty) {
          final isStrongUptrend = ema9.last > ema21.last * 1.002; // EMA9가 EMA21보다 0.2% 이상 높음
          final isStrongDowntrend = ema9.last < ema21.last * 0.998; // EMA9가 EMA21보다 0.2% 이상 낮음

          // 최근 5봉의 가격 모멘텀 체크
          final recentPrices = closePrices.length >= 5
              ? closePrices.sublist(closePrices.length - 5)
              : closePrices;
          final priceChange = (recentPrices.last - recentPrices.first) / recentPrices.first;

          // Short position + Strong uptrend detected
          if (position.currentSide == PositionSide.short) {
            if ((marketCondition == MarketCondition.extremeBullish ||
                 marketCondition == MarketCondition.strongBullish) &&
                isStrongUptrend &&
                priceChange > 0.003) { // 최근 5봉에서 0.3% 이상 상승
              return SplitExitSignal(
                exitPrice: currentPrice,
                exitPercent: 1.0,
                reasoning: '시장 조건 전환 (${marketCondition.displayName})',
                isEmergency: true,
              );
            }
          }

          // Long position + Strong downtrend detected
          if (position.currentSide == PositionSide.long) {
            if ((marketCondition == MarketCondition.extremeBearish ||
                 marketCondition == MarketCondition.strongBearish) &&
                isStrongDowntrend &&
                priceChange < -0.003) { // 최근 5봉에서 0.3% 이상 하락
              return SplitExitSignal(
                exitPrice: currentPrice,
                exitPercent: 1.0,
                reasoning: '시장 조건 전환 (${marketCondition.displayName})',
                isEmergency: true,
              );
            }
          }
        }
      }

      // 3. BB opposite side breakout
      final bb = calculateBollingerBandsDefault(closePrices);
      if (position.currentSide == PositionSide.long) {
        // Long position: price broke above BB upper (opposite)
        if (currentPrice > bb.upper * 1.01) {
          return SplitExitSignal(
            exitPrice: currentPrice,
            exitPercent: 1.0,
            reasoning: 'BB 반대편 돌파',
            isEmergency: true,
          );
        }
      } else {
        // Short position: price broke below BB lower (opposite)
        if (currentPrice < bb.lower * 0.99) {
          return SplitExitSignal(
            exitPrice: currentPrice,
            exitPercent: 1.0,
            reasoning: 'BB 반대편 돌파',
            isEmergency: true,
          );
        }
      }
    }

    return null;
  }
}
