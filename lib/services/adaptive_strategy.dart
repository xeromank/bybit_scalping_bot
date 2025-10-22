import 'package:bybit_scalping_bot/models/market_condition.dart';
import 'package:bybit_scalping_bot/utils/technical_indicators.dart';
import 'package:bybit_scalping_bot/utils/logger.dart';

/// Trading signal type
enum SignalType {
  long,
  short,
  none,
}

/// Helper function to convert SignalType to string (avoids .name compatibility issues)
String signalTypeToString(SignalType type) {
  switch (type) {
    case SignalType.long:
      return 'long';
    case SignalType.short:
      return 'short';
    case SignalType.none:
      return 'none';
  }
}

/// Strategy configuration for a specific market condition
class StrategyConfig {
  final double takeProfitPercent; // TP as percentage (e.g., 0.008 = 0.8%)
  final double stopLossPercent; // SL as percentage (e.g., 0.004 = 0.4%)
  final int recommendedLeverage;
  final bool useTrailingStop;
  final double trailingStopTrigger; // Profit percentage to activate trailing
  final String description;

  StrategyConfig({
    required this.takeProfitPercent,
    required this.stopLossPercent,
    required this.recommendedLeverage,
    required this.useTrailingStop,
    required this.trailingStopTrigger,
    required this.description,
  });

  /// Get TP/SL in ROE percentage (considering leverage)
  double get takeProfitROE => takeProfitPercent * recommendedLeverage * 100;
  double get stopLossROE => stopLossPercent * recommendedLeverage * 100;
}

/// Trading signal with entry details
class TradingSignal {
  final SignalType type;
  final double confidence; // 0.0 to 1.0
  final String reasoning;
  final double? entryPrice; // Suggested entry price
  final double? takeProfitPrice;
  final double? stopLossPrice;
  final StrategyConfig strategyConfig;

  TradingSignal({
    required this.type,
    required this.confidence,
    required this.reasoning,
    this.entryPrice,
    this.takeProfitPrice,
    this.stopLossPrice,
    required this.strategyConfig,
  });

  bool get hasSignal => type != SignalType.none;
}

/// Adaptive trading strategy
///
/// Provides market-condition-specific trading strategies:
/// - Entry signal detection
/// - TP/SL calculation
/// - Position sizing recommendation
class AdaptiveStrategy {
  /// Get strategy configuration for a market condition
  static StrategyConfig getStrategyConfig(MarketCondition condition) {
    switch (condition) {
      case MarketCondition.extremeBullish:
        return StrategyConfig(
          takeProfitPercent: 0.012, // 1.2%
          stopLossPercent: 0.004, // 0.4%
          recommendedLeverage: 5,
          useTrailingStop: true,
          trailingStopTrigger: 0.005, // Activate at +0.5%
          description: 'Band Walking 추세 추종 (롱 전용)',
        );

      case MarketCondition.strongBullish:
        return StrategyConfig(
          takeProfitPercent: 0.010, // 1.0%
          stopLossPercent: 0.004, // 0.4%
          recommendedLeverage: 8,
          useTrailingStop: false,
          trailingStopTrigger: 0.006,
          description: '강세장 추세 추종 (롱 위주)',
        );

      case MarketCondition.weakBullish:
        return StrategyConfig(
          takeProfitPercent: 0.008, // 0.8%
          stopLossPercent: 0.004, // 0.4%
          recommendedLeverage: 10,
          useTrailingStop: false,
          trailingStopTrigger: 0.006,
          description: '약한 강세장 평균회귀',
        );

      case MarketCondition.ranging:
        return StrategyConfig(
          takeProfitPercent: 0.005, // 0.5%
          stopLossPercent: 0.003, // 0.3%
          recommendedLeverage: 15,
          useTrailingStop: false,
          trailingStopTrigger: 0.004,
          description: '볼린저 밴드 역추세',
        );

      case MarketCondition.weakBearish:
        return StrategyConfig(
          takeProfitPercent: 0.008, // 0.8%
          stopLossPercent: 0.004, // 0.4%
          recommendedLeverage: 10,
          useTrailingStop: false,
          trailingStopTrigger: 0.006,
          description: '약한 약세장 평균회귀',
        );

      case MarketCondition.strongBearish:
        return StrategyConfig(
          takeProfitPercent: 0.010, // 1.0%
          stopLossPercent: 0.004, // 0.4%
          recommendedLeverage: 8,
          useTrailingStop: false,
          trailingStopTrigger: 0.006,
          description: '약세장 추세 추종 (숏 위주)',
        );

      case MarketCondition.extremeBearish:
        return StrategyConfig(
          takeProfitPercent: 0.012, // 1.2%
          stopLossPercent: 0.004, // 0.4%
          recommendedLeverage: 5,
          useTrailingStop: true,
          trailingStopTrigger: 0.005,
          description: 'Band Walking 추세 추종 (숏 전용)',
        );
    }
  }

  /// Analyze and generate trading signal based on market condition
  static TradingSignal analyzeSignal({
    required MarketCondition condition,
    required List<double> closePrices,
    required List<double> volumes,
    required double currentPrice,
  }) {
    Logger.debug('AdaptiveStrategy: Analyzing signal for ${condition.displayName}');

    final strategyConfig = getStrategyConfig(condition);

    // PRIORITY 1: Check for breakout signals first (strongest signals)
    // Breakouts only in extreme market conditions
    final breakoutSignal = _analyzeBreakoutSignal(
      condition: condition,
      closePrices: closePrices,
      currentPrice: currentPrice,
      strategyConfig: strategyConfig,
    );

    if (breakoutSignal.hasSignal) {
      Logger.debug('🚀 BREAKOUT DETECTED: ${breakoutSignal.reasoning}');
      return breakoutSignal;
    }

    // PRIORITY 2: Condition-based strategies
    switch (condition) {
      case MarketCondition.extremeBullish:
        return _analyzeExtremeBullishSignal(
          closePrices: closePrices,
          volumes: volumes,
          currentPrice: currentPrice,
          strategyConfig: strategyConfig,
        );

      case MarketCondition.strongBullish:
      case MarketCondition.weakBullish:
        return _analyzeBullishSignal(
          closePrices: closePrices,
          volumes: volumes,
          currentPrice: currentPrice,
          strategyConfig: strategyConfig,
        );

      case MarketCondition.ranging:
        return _analyzeRangingSignal(
          closePrices: closePrices,
          volumes: volumes,
          currentPrice: currentPrice,
          strategyConfig: strategyConfig,
        );

      case MarketCondition.weakBearish:
      case MarketCondition.strongBearish:
        return _analyzeBearishSignal(
          closePrices: closePrices,
          volumes: volumes,
          currentPrice: currentPrice,
          strategyConfig: strategyConfig,
        );

      case MarketCondition.extremeBearish:
        return _analyzeExtremeBearishSignal(
          closePrices: closePrices,
          volumes: volumes,
          currentPrice: currentPrice,
          strategyConfig: strategyConfig,
        );
    }
  }

  /// Extreme Bullish Strategy: Long on RSI pullback
  static TradingSignal _analyzeExtremeBullishSignal({
    required List<double> closePrices,
    required List<double> volumes,
    required double currentPrice,
    required StrategyConfig strategyConfig,
  }) {
    final rsi = calculateRSISeries(closePrices, 14);
    if (rsi.isEmpty) {
      return TradingSignal(
        type: SignalType.none,
        confidence: 0.0,
        reasoning: 'RSI 데이터 부족',
        strategyConfig: strategyConfig,
      );
    }

    final currentRSI = rsi.last;
    Logger.debug('📈 [극강세] RSI(14) = ${currentRSI.toStringAsFixed(2)} (최근5개: ${rsi.length >= 5 ? rsi.sublist(rsi.length - 5).map((r) => r.toStringAsFixed(1)).join(", ") : rsi.map((r) => r.toStringAsFixed(1)).join(", ")})');
    final bb = calculateBollingerBandsDefault(closePrices);

    // Entry: RSI pullback from 70+ to 50-65 range
    if (currentRSI >= 50 && currentRSI <= 65) {
      // Check if RSI was recently above 70 (within last 5 candles)
      final recentRSI = rsi.length >= 5 ? rsi.sublist(rsi.length - 5) : rsi;
      final wasOverbought = recentRSI.any((r) => r > 70);

      if (wasOverbought) {
        final confidence = 0.7 + (65 - currentRSI) / 100; // Higher confidence closer to 50

        return TradingSignal(
          type: SignalType.long,
          confidence: confidence.clamp(0.0, 1.0),
          reasoning: 'RSI 조정 후 재상승 신호 (RSI: ${currentRSI.toStringAsFixed(1)})',
          entryPrice: currentPrice,
          takeProfitPrice: currentPrice * (1 + strategyConfig.takeProfitPercent),
          stopLossPrice: currentPrice * (1 - strategyConfig.stopLossPercent),
          strategyConfig: strategyConfig,
        );
      }
    }

    return TradingSignal(
      type: SignalType.none,
      confidence: 0.0,
      reasoning: 'RSI 조정 대기 중 (현재 RSI: ${currentRSI.toStringAsFixed(1)})',
      strategyConfig: strategyConfig,
    );
  }

  /// Bullish Strategy: Long on dips with RSI 45-55
  static TradingSignal _analyzeBullishSignal({
    required List<double> closePrices,
    required List<double> volumes,
    required double currentPrice,
    required StrategyConfig strategyConfig,
  }) {
    final rsi = calculateRSISeries(closePrices, 14);
    if (rsi.isEmpty) {
      return TradingSignal(
        type: SignalType.none,
        confidence: 0.0,
        reasoning: 'RSI 데이터 부족',
        strategyConfig: strategyConfig,
      );
    }

    final currentRSI = rsi.last;
    Logger.debug('📊 [강세] RSI(14) = ${currentRSI.toStringAsFixed(2)} (최근5개: ${rsi.length >= 5 ? rsi.sublist(rsi.length - 5).map((r) => r.toStringAsFixed(1)).join(", ") : rsi.map((r) => r.toStringAsFixed(1)).join(", ")})');
    final ema9 = calculateEMASeries(closePrices, 9);

    // Entry: RSI pullback to 45-55, or bounce off EMA9
    if (currentRSI >= 45 && currentRSI <= 55) {
      final confidence = 0.6 + (55 - currentRSI) / 50; // Higher confidence closer to 45

      return TradingSignal(
        type: SignalType.long,
        confidence: confidence.clamp(0.0, 1.0),
        reasoning: '풀백 진입 신호 (RSI: ${currentRSI.toStringAsFixed(1)})',
        entryPrice: currentPrice,
        takeProfitPrice: currentPrice * (1 + strategyConfig.takeProfitPercent),
        stopLossPrice: currentPrice * (1 - strategyConfig.stopLossPercent),
        strategyConfig: strategyConfig,
      );
    }

    return TradingSignal(
      type: SignalType.none,
      confidence: 0.0,
      reasoning: 'RSI 풀백 대기 (현재: ${currentRSI.toStringAsFixed(1)})',
      strategyConfig: strategyConfig,
    );
  }

  /// Ranging Strategy: Bollinger Band mean reversion
  static TradingSignal _analyzeRangingSignal({
    required List<double> closePrices,
    required List<double> volumes,
    required double currentPrice,
    required StrategyConfig strategyConfig,
  }) {
    final rsi = calculateRSISeries(closePrices, 14);
    final bb = calculateBollingerBandsDefault(closePrices);

    if (rsi.isEmpty) {
      return TradingSignal(
        type: SignalType.none,
        confidence: 0.0,
        reasoning: 'RSI 데이터 부족',
        strategyConfig: strategyConfig,
      );
    }

    final currentRSI = rsi.last;
    Logger.debug('↔️  [횡보] RSI(14) = ${currentRSI.toStringAsFixed(2)} (최근5개: ${rsi.length >= 5 ? rsi.sublist(rsi.length - 5).map((r) => r.toStringAsFixed(1)).join(", ") : rsi.map((r) => r.toStringAsFixed(1)).join(", ")})');

    // Long signal: Price near lower band + RSI < 35
    if (currentPrice <= bb.lower * 1.005 && currentRSI < 35) {
      return TradingSignal(
        type: SignalType.long,
        confidence: 0.75,
        reasoning: '볼린저 하단 + 과매도 (RSI: ${currentRSI.toStringAsFixed(1)})',
        entryPrice: currentPrice,
        takeProfitPrice: currentPrice * (1 + strategyConfig.takeProfitPercent),
        stopLossPrice: currentPrice * (1 - strategyConfig.stopLossPercent),
        strategyConfig: strategyConfig,
      );
    }

    // Short signal: Price near upper band + RSI > 65
    if (currentPrice >= bb.upper * 0.995 && currentRSI > 65) {
      return TradingSignal(
        type: SignalType.short,
        confidence: 0.75,
        reasoning: '볼린저 상단 + 과매수 (RSI: ${currentRSI.toStringAsFixed(1)})',
        entryPrice: currentPrice,
        takeProfitPrice: currentPrice * (1 - strategyConfig.takeProfitPercent),
        stopLossPrice: currentPrice * (1 + strategyConfig.stopLossPercent),
        strategyConfig: strategyConfig,
      );
    }

    return TradingSignal(
      type: SignalType.none,
      confidence: 0.0,
      reasoning: '진입 신호 없음 (RSI: ${currentRSI.toStringAsFixed(1)})',
      strategyConfig: strategyConfig,
    );
  }

  /// Bearish Strategy: Short on bounces with RSI 45-55
  static TradingSignal _analyzeBearishSignal({
    required List<double> closePrices,
    required List<double> volumes,
    required double currentPrice,
    required StrategyConfig strategyConfig,
  }) {
    final rsi = calculateRSISeries(closePrices, 14);
    if (rsi.isEmpty) {
      return TradingSignal(
        type: SignalType.none,
        confidence: 0.0,
        reasoning: 'RSI 데이터 부족',
        strategyConfig: strategyConfig,
      );
    }

    final currentRSI = rsi.last;
    Logger.debug('📉 [약세] RSI(14) = ${currentRSI.toStringAsFixed(2)} (최근5개: ${rsi.length >= 5 ? rsi.sublist(rsi.length - 5).map((r) => r.toStringAsFixed(1)).join(", ") : rsi.map((r) => r.toStringAsFixed(1)).join(", ")})');

    // Entry: RSI bounce to 45-55 range
    if (currentRSI >= 45 && currentRSI <= 55) {
      final confidence = 0.6 + (currentRSI - 45) / 50; // Higher confidence closer to 55

      return TradingSignal(
        type: SignalType.short,
        confidence: confidence.clamp(0.0, 1.0),
        reasoning: '반등 숏 진입 신호 (RSI: ${currentRSI.toStringAsFixed(1)})',
        entryPrice: currentPrice,
        takeProfitPrice: currentPrice * (1 - strategyConfig.takeProfitPercent),
        stopLossPrice: currentPrice * (1 + strategyConfig.stopLossPercent),
        strategyConfig: strategyConfig,
      );
    }

    return TradingSignal(
      type: SignalType.none,
      confidence: 0.0,
      reasoning: 'RSI 반등 대기 (현재: ${currentRSI.toStringAsFixed(1)})',
      strategyConfig: strategyConfig,
    );
  }

  /// Extreme Bearish Strategy: Short on RSI bounce
  static TradingSignal _analyzeExtremeBearishSignal({
    required List<double> closePrices,
    required List<double> volumes,
    required double currentPrice,
    required StrategyConfig strategyConfig,
  }) {
    final rsi = calculateRSISeries(closePrices, 14);
    if (rsi.isEmpty) {
      return TradingSignal(
        type: SignalType.none,
        confidence: 0.0,
        reasoning: 'RSI 데이터 부족',
        strategyConfig: strategyConfig,
      );
    }

    final currentRSI = rsi.last;
    Logger.debug('📉📉 [극약세] RSI(14) = ${currentRSI.toStringAsFixed(2)} (최근5개: ${rsi.length >= 5 ? rsi.sublist(rsi.length - 5).map((r) => r.toStringAsFixed(1)).join(", ") : rsi.map((r) => r.toStringAsFixed(1)).join(", ")})');

    // Entry: RSI bounce from 30- to 35-50 range
    if (currentRSI >= 35 && currentRSI <= 50) {
      // Check if RSI was recently below 30 (within last 5 candles)
      final recentRSI = rsi.length >= 5 ? rsi.sublist(rsi.length - 5) : rsi;
      final wasOversold = recentRSI.any((r) => r < 30);

      if (wasOversold) {
        final confidence = 0.7 + (currentRSI - 35) / 100;

        return TradingSignal(
          type: SignalType.short,
          confidence: confidence.clamp(0.0, 1.0),
          reasoning: 'RSI 반등 후 재하락 신호 (RSI: ${currentRSI.toStringAsFixed(1)})',
          entryPrice: currentPrice,
          takeProfitPrice: currentPrice * (1 - strategyConfig.takeProfitPercent),
          stopLossPrice: currentPrice * (1 + strategyConfig.stopLossPercent),
          strategyConfig: strategyConfig,
        );
      }
    }

    return TradingSignal(
      type: SignalType.none,
      confidence: 0.0,
      reasoning: 'RSI 반등 대기 중 (현재 RSI: ${currentRSI.toStringAsFixed(1)})',
      strategyConfig: strategyConfig,
    );
  }

  // ============================================================================
  // BREAKOUT STRATEGY (Priority Signal - Extreme Markets Only)
  // ============================================================================

  /// Analyze breakout/breakdown signals for EXTREME market conditions only
  ///
  /// This strategy only activates in extreme bullish/bearish markets.
  ///
  /// Extreme Bullish Market (강한 상승 모멘텀):
  /// - RSI <= 75: LONG breakout (추세 방향, 쉽게 진입)
  ///   - Condition: currentPrice > resistance * 1.001 (0.1% 돌파)
  /// - RSI > 75: SHORT breakdown (역추세, 엄격하게 진입)
  ///   - Condition: currentPrice < support * 0.995 (0.5% 이탈)
  ///
  /// Extreme Bearish Market (강한 하락 모멘텀):
  /// - RSI >= 50: SHORT breakdown (추세 방향, 쉽게 진입)
  ///   - Condition: currentPrice < support * 0.999 (0.1% 이탈)
  ///   - ⭐ RSI < 50은 이미 과매도 구간 → 급락 후반 → SHORT 금지
  /// - RSI < 30: LONG breakout (역추세, 엄격하게 진입)
  ///   - Condition: currentPrice > resistance * 1.005 (0.5% 돌파)
  ///
  /// Other market conditions: Breakout strategy disabled
  static TradingSignal _analyzeBreakoutSignal({
    required MarketCondition condition,
    required List<double> closePrices,
    required double currentPrice,
    required StrategyConfig strategyConfig,
  }) {
    // Only activate in extreme markets
    if (condition != MarketCondition.extremeBullish &&
        condition != MarketCondition.extremeBearish) {
      return TradingSignal(
        type: SignalType.none,
        confidence: 0.0,
        reasoning: '브레이크아웃 전략 비활성화 (극단적 시장만 활성화)',
        strategyConfig: strategyConfig,
      );
    }

    if (closePrices.length < 30) {
      return TradingSignal(
        type: SignalType.none,
        confidence: 0.0,
        reasoning: '데이터 부족',
        strategyConfig: strategyConfig,
      );
    }

    // Calculate RSI
    final rsi = calculateRSISeries(closePrices, 14);
    if (rsi.isEmpty) {
      return TradingSignal(
        type: SignalType.none,
        confidence: 0.0,
        reasoning: 'RSI 데이터 부족',
        strategyConfig: strategyConfig,
      );
    }
    final currentRSI = rsi.last;

    // Calculate support and resistance from recent 20 candles (EXCLUDING current candle)
    final lookback = closePrices.length >= 21 ? 20 : closePrices.length - 1;
    if (lookback < 10) {
      return TradingSignal(
        type: SignalType.none,
        confidence: 0.0,
        reasoning: '브레이크아웃 분석용 데이터 부족',
        strategyConfig: strategyConfig,
      );
    }
    final recentPrices = closePrices.sublist(closePrices.length - lookback - 1, closePrices.length - 1);

    final resistance = recentPrices.reduce((a, b) => a > b ? a : b); // 최고점
    final support = recentPrices.reduce((a, b) => a < b ? a : b);    // 최저점

    Logger.debug('💎 Support/Resistance: \$${support.toStringAsFixed(2)} / \$${resistance.toStringAsFixed(2)}');
    Logger.debug('   Current: \$${currentPrice.toStringAsFixed(2)} | RSI: ${currentRSI.toStringAsFixed(1)}');

    // ========================================================================
    // EXTREME BULLISH MARKET (극단적 상승장)
    // ========================================================================
    if (condition == MarketCondition.extremeBullish) {

      // RSI <= 75: LONG 브레이크아웃 (추세 방향, 쉽게)
      if (currentRSI <= 75) {
        if (currentPrice > resistance * 1.001 && currentRSI > 50 && currentRSI <= 85) {
          final breakoutPercent = ((currentPrice - resistance) / resistance * 100);
          final confidence = 0.80 + (currentRSI - 50) / 100;

          Logger.debug('🚀 LONG BREAKOUT: \$${currentPrice.toStringAsFixed(2)} > \$${resistance.toStringAsFixed(2)} (+${breakoutPercent.toStringAsFixed(2)}%)');

          return TradingSignal(
            type: SignalType.long,
            confidence: confidence.clamp(0.0, 1.0),
            reasoning: '저항선 돌파 (극단적 상승 모멘텀, RSI: ${currentRSI.toStringAsFixed(1)})',
            entryPrice: currentPrice,
            takeProfitPrice: currentPrice * (1 + strategyConfig.takeProfitPercent),
            stopLossPrice: currentPrice * (1 - strategyConfig.stopLossPercent),
            strategyConfig: strategyConfig,
          );
        }
      }

      // RSI > 75: SHORT 브레이크다운 (역추세, 엄격)
      else {
        if (currentPrice < support * 0.995 && currentRSI > 75 && currentRSI < 90) {
          final breakdownPercent = ((support - currentPrice) / support * 100);
          final confidence = 0.65 + (currentRSI - 75) / 100;

          Logger.debug('📉 SHORT BREAKDOWN (역추세): \$${currentPrice.toStringAsFixed(2)} < \$${support.toStringAsFixed(2)} (-${breakdownPercent.toStringAsFixed(2)}%)');

          return TradingSignal(
            type: SignalType.short,
            confidence: confidence.clamp(0.0, 1.0),
            reasoning: '과매수 구간 지지선 이탈 (반전 신호, RSI: ${currentRSI.toStringAsFixed(1)})',
            entryPrice: currentPrice,
            takeProfitPrice: currentPrice * (1 - strategyConfig.takeProfitPercent),
            stopLossPrice: currentPrice * (1 + strategyConfig.stopLossPercent),
            strategyConfig: strategyConfig,
          );
        }
      }
    }

    // ========================================================================
    // EXTREME BEARISH MARKET (극단적 하락장)
    // ========================================================================
    else if (condition == MarketCondition.extremeBearish) {

      // RSI >= 50: SHORT 브레이크다운 (추세 방향, 쉽게)
      // ⭐ 핵심: RSI < 50은 이미 과매도 → 급락 후반 → SHORT 금지
      if (currentRSI >= 50) {
        if (currentPrice < support * 0.999 && currentRSI >= 50 && currentRSI < 75) {
          final breakdownPercent = ((support - currentPrice) / support * 100);
          final confidence = 0.80 + (75 - currentRSI) / 100;

          Logger.debug('📉 SHORT BREAKDOWN: \$${currentPrice.toStringAsFixed(2)} < \$${support.toStringAsFixed(2)} (-${breakdownPercent.toStringAsFixed(2)}%)');

          return TradingSignal(
            type: SignalType.short,
            confidence: confidence.clamp(0.0, 1.0),
            reasoning: '지지선 이탈 (극단적 하락 모멘텀, RSI: ${currentRSI.toStringAsFixed(1)})',
            entryPrice: currentPrice,
            takeProfitPrice: currentPrice * (1 - strategyConfig.takeProfitPercent),
            stopLossPrice: currentPrice * (1 + strategyConfig.stopLossPercent),
            strategyConfig: strategyConfig,
          );
        }
      }

      // RSI < 30: LONG 브레이크아웃 (역추세, 엄격)
      else if (currentRSI < 30) {
        if (currentPrice > resistance * 1.005 && currentRSI >= 15 && currentRSI < 30) {
          final breakoutPercent = ((currentPrice - resistance) / resistance * 100);
          final confidence = 0.65 + (30 - currentRSI) / 100;

          Logger.debug('🚀 LONG BREAKOUT (역추세): \$${currentPrice.toStringAsFixed(2)} > \$${resistance.toStringAsFixed(2)} (+${breakoutPercent.toStringAsFixed(2)}%)');

          return TradingSignal(
            type: SignalType.long,
            confidence: confidence.clamp(0.0, 1.0),
            reasoning: '과매도 구간 저항선 돌파 (반등 신호, RSI: ${currentRSI.toStringAsFixed(1)})',
            entryPrice: currentPrice,
            takeProfitPrice: currentPrice * (1 + strategyConfig.takeProfitPercent),
            stopLossPrice: currentPrice * (1 - strategyConfig.stopLossPercent),
            strategyConfig: strategyConfig,
          );
        }
      }
    }

    // No breakout signal
    return TradingSignal(
      type: SignalType.none,
      confidence: 0.0,
      reasoning: '브레이크아웃 대기 중',
      strategyConfig: strategyConfig,
    );
  }
}
