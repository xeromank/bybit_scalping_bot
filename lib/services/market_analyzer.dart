import 'package:bybit_scalping_bot/models/market_condition.dart';
import 'package:bybit_scalping_bot/utils/technical_indicators.dart';

/// Market condition analysis result
class MarketAnalysisResult {
  final MarketCondition condition;
  final double priceChange;
  final double avgRsi;
  final double bollingerWidth;
  final bool isEmaAligned;
  final String emaDirection; // 'bullish', 'bearish', 'neutral'
  final double confidence; // 0.0 to 1.0
  final String reasoning;

  // New composite analysis fields
  final CompositeAnalysis? compositeAnalysis;
  final double? compositeScore;

  MarketAnalysisResult({
    required this.condition,
    required this.priceChange,
    required this.avgRsi,
    required this.bollingerWidth,
    required this.isEmaAligned,
    required this.emaDirection,
    required this.confidence,
    required this.reasoning,
    this.compositeAnalysis,
    this.compositeScore,
  });
}

/// Market analyzer service
///
/// Analyzes market conditions based on multiple indicators:
/// - Price change over recent candles
/// - RSI average and distribution
/// - Bollinger Band width (volatility)
/// - EMA alignment (trend strength)
class MarketAnalyzer {
  /// Analyze market condition from candle data
  ///
  /// Parameters:
  /// - closePrices: Recent close prices (at least 50 candles recommended)
  /// - volumes: Recent volumes (same length as closePrices)
  /// - useCompositeAnalysis: Use new multi-indicator composite analysis (default: true)
  ///
  /// Returns: MarketAnalysisResult with condition and analysis details
  static MarketAnalysisResult analyzeMarket({
    required List<double> closePrices,
    required List<double> volumes,
    bool useCompositeAnalysis = true,
  }) {
    if (closePrices.length < 30) {
      throw ArgumentError('Need at least 30 candles for market analysis');
    }

    // Use new composite analyzer if enabled and sufficient data
    if (useCompositeAnalysis && closePrices.length >= 50 && volumes.length >= 50) {
      return _analyzeMarketComposite(closePrices, volumes);
    }

    // Fallback to legacy analyzer
    return _analyzeMarketLegacy(closePrices, volumes);
  }

  /// New composite multi-indicator analysis
  static MarketAnalysisResult _analyzeMarketComposite(
    List<double> closePrices,
    List<double> volumes,
  ) {
    // Calculate composite analysis
    final composite = analyzeMarketComposite(closePrices, volumes);

    // Map EnhancedMarketCondition to MarketCondition
    final condition = _mapEnhancedToLegacyCondition(composite.marketCondition);

    // Extract EMA direction
    String emaDirection;
    bool isEmaAligned;
    if (composite.maTrend.isPerfectUptrend) {
      emaDirection = 'bullish';
      isEmaAligned = true;
    } else if (composite.maTrend.isPerfectDowntrend) {
      emaDirection = 'bearish';
      isEmaAligned = true;
    } else if (composite.maTrend.isPartialUptrend) {
      emaDirection = 'bullish';
      isEmaAligned = false;
    } else if (composite.maTrend.isPartialDowntrend) {
      emaDirection = 'bearish';
      isEmaAligned = false;
    } else {
      emaDirection = 'neutral';
      isEmaAligned = false;
    }

    // Calculate Bollinger width
    final bollingerWidth = (composite.bb.upper - composite.bb.lower) / composite.bb.middle;

    // Build reasoning
    final reasons = <String>[];
    reasons.add('Composite Score: ${composite.compositeScore.toStringAsFixed(2)}');
    reasons.add('RSI: ${composite.rsi.toStringAsFixed(1)}');
    reasons.add('Volume: ${composite.volume.relativeVolumeRatio.toStringAsFixed(2)}x');
    reasons.add('Price Action: ${(composite.priceAction.priceChangePercent * 100).toStringAsFixed(2)}%');
    reasons.add('MACD: ${composite.macd.isBullish ? "Bullish" : "Bearish"} ${composite.macdTrend.name}');

    // Map SignalConfidence to double
    double confidence;
    switch (composite.confidence) {
      case SignalConfidence.high:
        confidence = 0.85;
        break;
      case SignalConfidence.medium:
        confidence = 0.65;
        break;
      case SignalConfidence.low:
        confidence = 0.45;
        break;
    }

    return MarketAnalysisResult(
      condition: condition,
      priceChange: composite.priceAction.priceChangePercent,
      avgRsi: composite.rsi,
      bollingerWidth: bollingerWidth,
      isEmaAligned: isEmaAligned,
      emaDirection: emaDirection,
      confidence: confidence,
      reasoning: reasons.join(' • '),
      compositeAnalysis: composite,
      compositeScore: composite.compositeScore,
    );
  }

  /// Legacy market analysis (backward compatible)
  static MarketAnalysisResult _analyzeMarketLegacy(
    List<double> closePrices,
    List<double> volumes,
  ) {
    // 1. Calculate price change (recent 20 candles)
    final recentPrices = closePrices.length > 20
        ? closePrices.sublist(closePrices.length - 20)
        : closePrices;
    final priceChange = _calculatePriceChange(recentPrices);

    // 2. Calculate average RSI (recent 10 candles)
    final rsiValues = calculateRSISeries(closePrices, 14);
    final avgRsi = _calculateAverageRSI(rsiValues, lookback: 10);

    // 3. Calculate Bollinger Band width (volatility indicator)
    final bb = calculateBollingerBandsDefault(closePrices);
    final bollingerWidth = _calculateBollingerWidth(bb);

    // 4. Check EMA alignment
    final ema9 = calculateEMASeries(closePrices, 9);
    final ema21 = calculateEMASeries(closePrices, 21);
    final ema50 = calculateEMASeries(closePrices, 50);
    final emaAlignment = _analyzeEMAAlignment(ema9, ema21, ema50);

    // 5. Determine market condition based on all factors
    final result = _determineMarketCondition(
      priceChange: priceChange,
      avgRsi: avgRsi,
      bollingerWidth: bollingerWidth,
      emaDirection: emaAlignment['direction'] as String,
      isEmaAligned: emaAlignment['aligned'] as bool,
    );

    return result;
  }

  /// Map EnhancedMarketCondition to legacy MarketCondition
  static MarketCondition _mapEnhancedToLegacyCondition(EnhancedMarketCondition enhanced) {
    switch (enhanced) {
      case EnhancedMarketCondition.extremeBullish:
        return MarketCondition.extremeBullish;
      case EnhancedMarketCondition.strongBullish:
        return MarketCondition.strongBullish;
      case EnhancedMarketCondition.weakBullish:
        return MarketCondition.weakBullish;
      case EnhancedMarketCondition.ranging:
        return MarketCondition.ranging;
      case EnhancedMarketCondition.weakBearish:
        return MarketCondition.weakBearish;
      case EnhancedMarketCondition.strongBearish:
        return MarketCondition.strongBearish;
      case EnhancedMarketCondition.extremeBearish:
        return MarketCondition.extremeBearish;
    }
  }

  /// Calculate price change percentage
  static double _calculatePriceChange(List<double> prices) {
    if (prices.isEmpty) return 0.0;
    final firstPrice = prices.first;
    final lastPrice = prices.last;
    return (lastPrice - firstPrice) / firstPrice;
  }

  /// Calculate average RSI from recent values
  static double _calculateAverageRSI(List<double> rsiValues, {int lookback = 10}) {
    if (rsiValues.isEmpty) return 50.0;
    final recentRSI = rsiValues.length > lookback
        ? rsiValues.sublist(rsiValues.length - lookback)
        : rsiValues;
    final sum = recentRSI.reduce((a, b) => a + b);
    return sum / recentRSI.length;
  }

  /// Calculate Bollinger Band width as percentage
  static double _calculateBollingerWidth(BollingerBands bb) {
    final width = (bb.upper - bb.lower) / bb.middle;
    return width;
  }

  /// Analyze EMA alignment for trend detection
  static Map<String, dynamic> _analyzeEMAAlignment(
    List<double> ema9,
    List<double> ema21,
    List<double> ema50,
  ) {
    if (ema9.isEmpty || ema21.isEmpty || ema50.isEmpty) {
      return {'direction': 'neutral', 'aligned': false};
    }

    final current9 = ema9.last;
    final current21 = ema21.last;
    final current50 = ema50.last;

    // Check bullish alignment: EMA9 > EMA21 > EMA50
    if (current9 > current21 && current21 > current50) {
      return {'direction': 'bullish', 'aligned': true};
    }

    // Check bearish alignment: EMA9 < EMA21 < EMA50
    if (current9 < current21 && current21 < current50) {
      return {'direction': 'bearish', 'aligned': true};
    }

    // Mixed/neutral - EMAs are intertwined
    if (current9 > current21) {
      return {'direction': 'bullish', 'aligned': false};
    } else {
      return {'direction': 'bearish', 'aligned': false};
    }
  }

  /// Determine market condition based on multiple factors
  static MarketAnalysisResult _determineMarketCondition({
    required double priceChange,
    required double avgRsi,
    required double bollingerWidth,
    required String emaDirection,
    required bool isEmaAligned,
  }) {
    int bullishScore = 0;
    int bearishScore = 0;
    final List<String> reasons = [];

    // Score based on price change (20 candles = 100분) - 현실적으로 조정
    if (priceChange > 0.02) {
      // +2.0% or more (100분에 2% = 극강세)
      bullishScore += 4;
      reasons.add('극강세 (+${(priceChange * 100).toStringAsFixed(1)}%)');
    } else if (priceChange > 0.01) {
      // +1.0% to +2.0%
      bullishScore += 3;
      reasons.add('강세 (+${(priceChange * 100).toStringAsFixed(1)}%)');
    } else if (priceChange > 0.005) {
      // +0.5% to +1.0%
      bullishScore += 2;
      reasons.add('상승 (+${(priceChange * 100).toStringAsFixed(1)}%)');
    } else if (priceChange >= -0.005 && priceChange <= 0.005) {
      // -0.5% to +0.5% (횡보)
      reasons.add('횡보 (${(priceChange * 100).toStringAsFixed(1)}%)');
    } else if (priceChange >= -0.01) {
      // -0.5% to -1.0%
      bearishScore += 2;
      reasons.add('하락 (${(priceChange * 100).toStringAsFixed(1)}%)');
    } else if (priceChange >= -0.02) {
      // -1.0% to -2.0%
      bearishScore += 3;
      reasons.add('약세 (${(priceChange * 100).toStringAsFixed(1)}%)');
    } else {
      // -2.0% or less (100분에 -2% = 극약세)
      bearishScore += 4;
      reasons.add('극약세 (${(priceChange * 100).toStringAsFixed(1)}%)');
    }

    // Score based on RSI
    if (avgRsi > 70) {
      bullishScore += 2;
      reasons.add('RSI 과매수 (${avgRsi.toStringAsFixed(1)})');
    } else if (avgRsi > 55) {
      bullishScore += 1;
      reasons.add('RSI 강세 (${avgRsi.toStringAsFixed(1)})');
    } else if (avgRsi < 30) {
      bearishScore += 2;
      reasons.add('RSI 과매도 (${avgRsi.toStringAsFixed(1)})');
    } else if (avgRsi < 45) {
      bearishScore += 1;
      reasons.add('RSI 약세 (${avgRsi.toStringAsFixed(1)})');
    } else {
      reasons.add('RSI 중립 (${avgRsi.toStringAsFixed(1)})');
    }

    // Score based on EMA alignment
    if (isEmaAligned) {
      if (emaDirection == 'bullish') {
        bullishScore += 2;
        reasons.add('EMA 강세 정렬');
      } else if (emaDirection == 'bearish') {
        bearishScore += 2;
        reasons.add('EMA 약세 정렬');
      }
    } else {
      reasons.add('EMA 정렬 불명확');
    }

    // Score based on volatility (Bollinger width)
    if (bollingerWidth > 0.08) {
      // High volatility - trending market
      reasons.add('높은 변동성 (추세장)');
      // Amplify existing scores slightly in high volatility
      if (bullishScore > bearishScore) {
        bullishScore += 1;
      } else if (bearishScore > bullishScore) {
        bearishScore += 1;
      }
    } else if (bollingerWidth < 0.03) {
      // Very low volatility - likely ranging
      reasons.add('매우 낮은 변동성 (횡보 가능성)');
      // Only reduce scores if price change is also minimal
      if (priceChange.abs() < 0.002) {
        bullishScore = (bullishScore * 0.5).round();
        bearishScore = (bearishScore * 0.5).round();
      }
    } else if (bollingerWidth < 0.05) {
      // Low to moderate volatility
      reasons.add('낮은 변동성');
    }

    // Determine final condition (7 levels) - 덜 민감하게 조정
    final totalScore = bullishScore - bearishScore;
    final confidence = (bullishScore + bearishScore) / 12.0; // Max score is ~12 now

    MarketCondition condition;

    // 극강세: RSI 70+ && 강한 상승 (유지)
    if (totalScore >= 5 && avgRsi > 70) {
      condition = MarketCondition.extremeBullish;
    }
    // 강세: RSI 65-70 && 명확한 상승 (강화: 60 → 65, score 3 → 4)
    else if (totalScore >= 4 && avgRsi > 65) {
      condition = MarketCondition.strongBullish;
    }
    // 약한 강세: RSI 55-65 && 약한 상승 (강화: 50 → 55, score 1 → 2)
    else if (totalScore >= 2 && avgRsi > 55) {
      condition = MarketCondition.weakBullish;
    }
    // 극약세: RSI 30- && 강한 하락 (유지)
    else if (totalScore <= -5 && avgRsi < 30) {
      condition = MarketCondition.extremeBearish;
    }
    // 약세: RSI 30-35 && 명확한 하락 (강화: 40 → 35, score -3 → -4)
    else if (totalScore <= -4 && avgRsi < 35) {
      condition = MarketCondition.strongBearish;
    }
    // 약한 약세: RSI 45-55 && 약한 하락 (강화: 50 → 45, score -1 → -2)
    else if (totalScore <= -2 && avgRsi < 45) {
      condition = MarketCondition.weakBearish;
    }
    // 횡보: 나머지 모두 (RSI 45-65 구간으로 확대)
    else {
      condition = MarketCondition.ranging;
    }

    return MarketAnalysisResult(
      condition: condition,
      priceChange: priceChange,
      avgRsi: avgRsi,
      bollingerWidth: bollingerWidth,
      isEmaAligned: isEmaAligned,
      emaDirection: emaDirection,
      confidence: confidence.clamp(0.0, 1.0),
      reasoning: reasons.join(' • '),
    );
  }
}
