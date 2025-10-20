import 'package:bybit_scalping_bot/models/market_condition.dart';
import 'package:bybit_scalping_bot/utils/technical_indicators.dart';
import 'package:bybit_scalping_bot/utils/logger.dart';

/// Trading signal type
enum SignalType {
  long,
  short,
  none,
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

      case MarketCondition.bullish:
        return StrategyConfig(
          takeProfitPercent: 0.008, // 0.8%
          stopLossPercent: 0.004, // 0.4%
          recommendedLeverage: 10,
          useTrailingStop: false,
          trailingStopTrigger: 0.006,
          description: '풀백 롱 진입',
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

      case MarketCondition.bearish:
        return StrategyConfig(
          takeProfitPercent: 0.008, // 0.8%
          stopLossPercent: 0.004, // 0.4%
          recommendedLeverage: 10,
          useTrailingStop: false,
          trailingStopTrigger: 0.006,
          description: '풀백 숏 진입',
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

    switch (condition) {
      case MarketCondition.extremeBullish:
        return _analyzeExtremeBullishSignal(
          closePrices: closePrices,
          volumes: volumes,
          currentPrice: currentPrice,
          strategyConfig: strategyConfig,
        );

      case MarketCondition.bullish:
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

      case MarketCondition.bearish:
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
}
