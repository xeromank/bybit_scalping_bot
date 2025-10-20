import 'package:bybit_scalping_bot/models/market_condition.dart';
import 'package:bybit_scalping_bot/utils/technical_indicators.dart';
import 'package:bybit_scalping_bot/utils/logger.dart';

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

  MarketAnalysisResult({
    required this.condition,
    required this.priceChange,
    required this.avgRsi,
    required this.bollingerWidth,
    required this.isEmaAligned,
    required this.emaDirection,
    required this.confidence,
    required this.reasoning,
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
  ///
  /// Returns: MarketAnalysisResult with condition and analysis details
  static MarketAnalysisResult analyzeMarket({
    required List<double> closePrices,
    required List<double> volumes,
  }) {
    if (closePrices.length < 30) {
      throw ArgumentError('Need at least 30 candles for market analysis');
    }

    Logger.debug('MarketAnalyzer: Analyzing market with ${closePrices.length} candles');

    // 1. Calculate price change (recent 20 candles)
    final recentPrices = closePrices.length > 20
        ? closePrices.sublist(closePrices.length - 20)
        : closePrices;
    final priceChange = _calculatePriceChange(recentPrices);
    Logger.debug('MarketAnalyzer: Price change = ${(priceChange * 100).toStringAsFixed(2)}%');

    // 2. Calculate average RSI (recent 10 candles)
    Logger.debug('MarketAnalyzer: 📊 RSI 계산 시작');
    Logger.debug('MarketAnalyzer: - 총 캔들 개수: ${closePrices.length}개');
    Logger.debug('MarketAnalyzer: - 최근 5개 가격: ${closePrices.length >= 5 ? closePrices.sublist(closePrices.length - 5).map((p) => p.toStringAsFixed(2)).join(", ") : closePrices.map((p) => p.toStringAsFixed(2)).join(", ")}');

    final rsiValues = calculateRSISeries(closePrices, 14);
    Logger.debug('MarketAnalyzer: - RSI(14) 계산 완료: ${rsiValues.length}개 값');
    if (rsiValues.length >= 10) {
      final recentRSI = rsiValues.sublist(rsiValues.length - 10);
      Logger.debug('MarketAnalyzer: - 최근 10개 RSI: ${recentRSI.map((r) => r.toStringAsFixed(2)).join(", ")}');
    } else if (rsiValues.isNotEmpty) {
      Logger.debug('MarketAnalyzer: - 전체 RSI: ${rsiValues.map((r) => r.toStringAsFixed(2)).join(", ")}');
    }

    final avgRsi = _calculateAverageRSI(rsiValues, lookback: 10);
    Logger.debug('MarketAnalyzer: ✅ 평균 RSI(최근 10개) = ${avgRsi.toStringAsFixed(2)}');

    // 3. Calculate Bollinger Band width (volatility indicator)
    final bb = calculateBollingerBandsDefault(closePrices);
    final bollingerWidth = _calculateBollingerWidth(bb);
    Logger.debug('MarketAnalyzer: Bollinger width = ${(bollingerWidth * 100).toStringAsFixed(2)}%');

    // 4. Check EMA alignment
    final ema9 = calculateEMASeries(closePrices, 9);
    final ema21 = calculateEMASeries(closePrices, 21);
    final ema50 = calculateEMASeries(closePrices, 50);
    final emaAlignment = _analyzeEMAAlignment(ema9, ema21, ema50);
    Logger.debug('MarketAnalyzer: EMA alignment = ${emaAlignment['direction']} (aligned: ${emaAlignment['aligned']})');

    // 5. Determine market condition based on all factors
    final result = _determineMarketCondition(
      priceChange: priceChange,
      avgRsi: avgRsi,
      bollingerWidth: bollingerWidth,
      emaDirection: emaAlignment['direction'] as String,
      isEmaAligned: emaAlignment['aligned'] as bool,
    );

    Logger.success('MarketAnalyzer: Market condition = ${result.condition.displayName} (confidence: ${(result.confidence * 100).toStringAsFixed(0)}%)');

    return result;
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

    // Score based on price change (20 candles) - More granular scoring
    if (priceChange > 0.04) {
      // +4% or more
      bullishScore += 4;
      reasons.add('매우 강한 상승 (+${(priceChange * 100).toStringAsFixed(1)}%)');
    } else if (priceChange > 0.02) {
      // +2% to +4%
      bullishScore += 3;
      reasons.add('강한 가격 상승 (+${(priceChange * 100).toStringAsFixed(1)}%)');
    } else if (priceChange > 0.01) {
      // +1% to +2%
      bullishScore += 2;
      reasons.add('가격 상승 중 (+${(priceChange * 100).toStringAsFixed(1)}%)');
    } else if (priceChange > 0.003) {
      // +0.3% to +1%
      bullishScore += 1;
      reasons.add('약한 상승 (+${(priceChange * 100).toStringAsFixed(1)}%)');
    } else if (priceChange >= -0.003 && priceChange <= 0.003) {
      // -0.3% to +0.3%
      reasons.add('가격 횡보 (${(priceChange * 100).toStringAsFixed(1)}%)');
    } else if (priceChange >= -0.01) {
      // -1% to -0.3%
      bearishScore += 1;
      reasons.add('약한 하락 (${(priceChange * 100).toStringAsFixed(1)}%)');
    } else if (priceChange >= -0.02) {
      // -2% to -1%
      bearishScore += 2;
      reasons.add('가격 하락 중 (${(priceChange * 100).toStringAsFixed(1)}%)');
    } else if (priceChange >= -0.04) {
      // -4% to -2%
      bearishScore += 3;
      reasons.add('강한 가격 하락 (${(priceChange * 100).toStringAsFixed(1)}%)');
    } else {
      // -4% or less
      bearishScore += 4;
      reasons.add('매우 강한 하락 (${(priceChange * 100).toStringAsFixed(1)}%)');
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

    // Determine final condition
    final totalScore = bullishScore - bearishScore;
    final confidence = (bullishScore + bearishScore) / 12.0; // Max score is ~12 now

    MarketCondition condition;
    if (totalScore >= 5 && avgRsi > 65) {
      condition = MarketCondition.extremeBullish;
    } else if (totalScore >= 2) {
      // More sensitive threshold (was 3)
      condition = MarketCondition.bullish;
    } else if (totalScore <= -5 && avgRsi < 35) {
      condition = MarketCondition.extremeBearish;
    } else if (totalScore <= -2) {
      // More sensitive threshold (was -3)
      condition = MarketCondition.bearish;
    } else {
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
