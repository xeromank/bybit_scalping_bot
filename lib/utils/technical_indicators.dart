/// Technical Indicator Calculations
///
/// Responsibility: Calculate technical indicators from price data
///
/// This utility provides pure functions for calculating technical indicators
/// commonly used in trading strategies.

import 'dart:math' as math;
import 'package:bybit_scalping_bot/utils/logger.dart';

/// Trading strategy mode
enum TradingMode {
  auto,           // Auto mode - selects best strategy based on market conditions
  bollinger,      // Bollinger Band + RSI strategy (mean reversion)
  ema,            // EMA crossover + RSI strategy (trend following)
  multiTimeframe, // Multi-timeframe RSI strategy (1min + 5min analysis)
}

/// Market trend classification (based on analysis of recent candles)
/// DEPRECATED: Use EnhancedMarketCondition instead for more granular classification
enum MarketTrend {
  uptrend,    // Bullish trend: price increased > threshold
  downtrend,  // Bearish trend: price decreased > threshold
  sideways,   // Ranging market: price change within ±threshold
  unknown,    // Not yet analyzed
}

/// Enhanced 7-level market condition classification
/// Based on composite multi-indicator analysis
enum EnhancedMarketCondition {
  extremeBullish,  // Extreme bullish: Very strong buy signals (score > 0.6)
  strongBullish,   // Strong bullish: Strong buy signals (score 0.4 to 0.6)
  weakBullish,     // Weak bullish: Moderate buy signals (score 0.15 to 0.4)
  ranging,         // Ranging/Neutral: Mixed signals (score -0.15 to 0.15)
  weakBearish,     // Weak bearish: Moderate sell signals (score -0.4 to -0.15)
  strongBearish,   // Strong bearish: Strong sell signals (score -0.6 to -0.4)
  extremeBearish,  // Extreme bearish: Very strong sell signals (score < -0.6)
}

/// Bollinger Bands values
class BollingerBands {
  final double upper;
  final double middle;
  final double lower;

  BollingerBands({
    required this.upper,
    required this.middle,
    required this.lower,
  });

  @override
  String toString() {
    return 'BB(upper: ${upper.toStringAsFixed(2)}, middle: ${middle.toStringAsFixed(2)}, lower: ${lower.toStringAsFixed(2)})';
  }
}

/// Calculates Bollinger Bands
///
/// [prices] - List of prices (oldest first)
/// [period] - Bollinger Band period (typically 20)
/// [stdDev] - Number of standard deviations (typically 2.0)
///
/// Returns BollingerBands object with upper, middle, and lower bands
BollingerBands calculateBollingerBands(List<double> prices, int period, double stdDev) {
  if (prices.length < period) {
    throw ArgumentError('Need at least $period price points for Bollinger Bands($period)');
  }

  // Calculate middle band (SMA)
  final middle = calculateSMA(prices, period);

  // Calculate standard deviation
  final relevantPrices = prices.skip(prices.length - period).take(period).toList();
  final variance = relevantPrices
      .map((price) => (price - middle) * (price - middle))
      .reduce((a, b) => a + b) / period;
  final standardDeviation = math.sqrt(variance);

  // Calculate upper and lower bands
  final upper = middle + (stdDev * standardDeviation);
  final lower = middle - (stdDev * standardDeviation);

  return BollingerBands(
    upper: upper,
    middle: middle,
    lower: lower,
  );
}

/// Calculates RSI (Relative Strength Index)
///
/// [closePrices] - List of closing prices (oldest first)
/// [period] - RSI period (typically 6, 12, or 14)
///
/// Returns RSI value between 0-100
double calculateRSI(List<double> closePrices, int period) {
  if (closePrices.length < period + 1) {
    throw ArgumentError('Need at least ${period + 1} price points for RSI($period)');
  }

  // Calculate price changes
  final gains = <double>[];
  final losses = <double>[];

  for (int i = 1; i < closePrices.length; i++) {
    final change = closePrices[i] - closePrices[i - 1];
    gains.add(change > 0 ? change : 0);
    losses.add(change < 0 ? -change : 0);
  }

  // Calculate average gain and loss
  double avgGain = gains.take(period).reduce((a, b) => a + b) / period;
  double avgLoss = losses.take(period).reduce((a, b) => a + b) / period;

  // Smooth the averages (Wilder's smoothing method)
  for (int i = period; i < gains.length; i++) {
    avgGain = (avgGain * (period - 1) + gains[i]) / period;
    avgLoss = (avgLoss * (period - 1) + losses[i]) / period;
  }

  // Calculate RS and RSI
  if (avgLoss == 0) return 100;
  final rs = avgGain / avgLoss;
  final rsi = 100 - (100 / (1 + rs));

  return rsi;
}

/// Calculates EMA (Exponential Moving Average)
///
/// [prices] - List of prices (oldest first)
/// [period] - EMA period (typically 9, 21, 50, 200)
///
/// Returns current EMA value
double calculateEMA(List<double> prices, int period) {
  if (prices.length < period) {
    throw ArgumentError('Need at least $period price points for EMA($period)');
  }

  // Calculate initial SMA as starting point
  double ema = prices.take(period).reduce((a, b) => a + b) / period;

  // Calculate multiplier
  final multiplier = 2.0 / (period + 1);

  // Calculate EMA for remaining prices
  for (int i = period; i < prices.length; i++) {
    ema = (prices[i] - ema) * multiplier + ema;
  }

  return ema;
}

/// EMA Crossover detection types
enum EmaCrossover {
  bullish,  // Fast EMA crossed above slow EMA (golden cross)
  bearish,  // Fast EMA crossed below slow EMA (death cross)
  none,     // No crossover
}

/// Detects EMA crossover
///
/// [prices] - List of prices (oldest first), needs at least 2 candles for crossover detection
/// [fastPeriod] - Fast EMA period (typically 9)
/// [slowPeriod] - Slow EMA period (typically 21)
///
/// Returns EmaCrossover indicating bullish, bearish, or no crossover
EmaCrossover detectEmaCrossover(List<double> prices, int fastPeriod, int slowPeriod) {
  if (prices.length < slowPeriod + 1) {
    throw ArgumentError('Need at least ${slowPeriod + 1} price points for EMA crossover detection');
  }

  // Calculate current EMAs
  final fastEmaCurrent = calculateEMA(prices, fastPeriod);
  final slowEmaCurrent = calculateEMA(prices, slowPeriod);

  // Calculate previous EMAs (using prices excluding the last candle)
  final pricesPrevious = prices.sublist(0, prices.length - 1);
  final fastEmaPrevious = calculateEMA(pricesPrevious, fastPeriod);
  final slowEmaPrevious = calculateEMA(pricesPrevious, slowPeriod);

  // Detect crossover
  // Bullish: fast was below or equal, now above
  if (fastEmaPrevious <= slowEmaPrevious && fastEmaCurrent > slowEmaCurrent) {
    return EmaCrossover.bullish;
  }

  // Bearish: fast was above or equal, now below
  if (fastEmaPrevious >= slowEmaPrevious && fastEmaCurrent < slowEmaCurrent) {
    return EmaCrossover.bearish;
  }

  return EmaCrossover.none;
}

/// Calculates SMA (Simple Moving Average)
///
/// [prices] - List of prices (oldest first)
/// [period] - SMA period
///
/// Returns current SMA value
double calculateSMA(List<double> prices, int period) {
  if (prices.length < period) {
    throw ArgumentError('Need at least $period price points for SMA($period)');
  }

  final relevantPrices = prices.skip(prices.length - period).take(period);
  return relevantPrices.reduce((a, b) => a + b) / period;
}

/// Parses K-line data from Bybit API response
///
/// Returns list of closing prices (oldest first)
List<double> parseClosePrices(Map<String, dynamic> klineResponse) {
  if (klineResponse['retCode'] != 0) {
    throw Exception('Failed to fetch K-line data: ${klineResponse['retMsg']}');
  }

  final list = klineResponse['result']['list'] as List;

  // Bybit returns newest first, so we need to reverse
  final closePrices = list.reversed.map((kline) {
    // Kline format: [startTime, openPrice, highPrice, lowPrice, closePrice, volume, turnover]
    return double.parse(kline[4].toString());
  }).toList();

  return closePrices;
}

/// Parses volume data from Bybit API response
///
/// Returns list of volumes (oldest first)
List<double> parseVolumes(Map<String, dynamic> klineResponse) {
  if (klineResponse['retCode'] != 0) {
    throw Exception('Failed to fetch K-line data: ${klineResponse['retMsg']}');
  }

  final list = klineResponse['result']['list'] as List;

  // Bybit returns newest first, so we need to reverse
  final volumes = list.reversed.map((kline) {
    // Kline format: [startTime, openPrice, highPrice, lowPrice, closePrice, volume, turnover]
    return double.parse(kline[5].toString());
  }).toList();

  return volumes;
}

/// Technical analysis result (supports both trading modes)
class TechnicalAnalysis {
  // Trading Mode
  final TradingMode mode;

  // Common indicators (both modes)
  final double currentPrice;
  final double currentVolume;
  final double volumeMA5;
  final double volumeMA10;
  final double ema9;
  final double ema21;

  // EMA Mode specific
  final double rsi6;
  final double rsi14;  // Actually RSI 14 in new design
  final double rsi6LongThreshold;
  final double rsi6ShortThreshold;
  final double rsi14LongThreshold;  // Actually RSI 14 threshold
  final double rsi14ShortThreshold;  // Actually RSI 14 threshold
  final bool useEmaFilter;
  final int emaPeriod;
  final double selectedEma;
  final EmaCrossover? emaCrossover;

  // Bollinger Mode specific
  final BollingerBands? bollingerBands;
  final double? bollingerRsi;  // RSI 14 for Bollinger mode
  final double? bollingerRsiOverbought;
  final double? bollingerRsiOversold;
  final bool? useVolumeFilter;
  final double? volumeMultiplier;

  TechnicalAnalysis({
    required this.mode,
    required this.currentPrice,
    required this.currentVolume,
    required this.volumeMA5,
    required this.volumeMA10,
    required this.ema9,
    required this.ema21,
    // EMA mode parameters
    required this.rsi6,
    required this.rsi14,
    required this.rsi6LongThreshold,
    required this.rsi6ShortThreshold,
    required this.rsi14LongThreshold,
    required this.rsi14ShortThreshold,
    required this.useEmaFilter,
    required this.emaPeriod,
    required this.selectedEma,
    this.emaCrossover,
    // Bollinger mode parameters
    this.bollingerBands,
    this.bollingerRsi,
    this.bollingerRsiOverbought,
    this.bollingerRsiOversold,
    this.useVolumeFilter,
    this.volumeMultiplier,
  });

  /// Checks if long entry conditions are met
  bool get isLongSignal {
    if (mode == TradingMode.bollinger) {
      return _isBollingerLongSignal;
    } else {
      return _isEmaLongSignal;
    }
  }

  /// Checks if short entry conditions are met
  bool get isShortSignal {
    if (mode == TradingMode.bollinger) {
      return _isBollingerShortSignal;
    } else {
      return _isEmaShortSignal;
    }
  }

  /// Checks if conditions are partially met for long
  bool get isLongPreparing {
    if (mode == TradingMode.bollinger) {
      return _isBollingerLongPreparing;
    } else {
      return _isEmaLongPreparing;
    }
  }

  /// Checks if conditions are partially met for short
  bool get isShortPreparing {
    if (mode == TradingMode.bollinger) {
      return _isBollingerShortPreparing;
    } else {
      return _isEmaShortPreparing;
    }
  }

  // ===== BOLLINGER MODE LOGIC =====

  /// Bollinger Band Long Entry:
  /// 1. Price touches or breaks below lower band
  /// 2. RSI(14) < oversold threshold (default: 30)
  /// 3. Volume > avgVolume × multiplier (optional)
  bool get _isBollingerLongSignal {
    if (bollingerBands == null || bollingerRsi == null) return false;

    // Price condition: at or below lower band
    final priceBelowLowerBand = currentPrice <= bollingerBands!.lower;

    // RSI condition
    final rsiOversold = bollingerRsi! < (bollingerRsiOversold ?? 30.0);

    // Volume condition (optional)
    bool volumeOk = true;
    if (useVolumeFilter ?? false) {
      final volumeThreshold = volumeMA5 * (volumeMultiplier ?? 1.5);
      volumeOk = currentVolume > volumeThreshold;
    }

    return priceBelowLowerBand && rsiOversold && volumeOk;
  }

  /// Bollinger Band Short Entry:
  /// 1. Price touches or breaks above upper band
  /// 2. RSI(14) > overbought threshold (default: 70)
  /// 3. Volume > avgVolume × multiplier (optional)
  bool get _isBollingerShortSignal {
    if (bollingerBands == null || bollingerRsi == null) return false;

    // Price condition: at or above upper band
    final priceAboveUpperBand = currentPrice >= bollingerBands!.upper;

    // RSI condition
    final rsiOverbought = bollingerRsi! > (bollingerRsiOverbought ?? 70.0);

    // Volume condition (optional)
    bool volumeOk = true;
    if (useVolumeFilter ?? false) {
      final volumeThreshold = volumeMA5 * (volumeMultiplier ?? 1.5);
      volumeOk = currentVolume > volumeThreshold;
    }

    return priceAboveUpperBand && rsiOverbought && volumeOk;
  }

  /// Bollinger Long Preparing: Price near lower band but not all conditions met
  bool get _isBollingerLongPreparing {
    if (isLongSignal || bollingerBands == null || bollingerRsi == null) return false;

    // Price is approaching lower band (within 0.5% distance)
    final distanceToLowerBand = (currentPrice - bollingerBands!.lower) / bollingerBands!.lower;
    final nearLowerBand = distanceToLowerBand < 0.005; // Within 0.5%

    // RSI is getting oversold (within 10 points of threshold)
    final rsiApproachingOversold = bollingerRsi! < (bollingerRsiOversold ?? 30.0) + 10;

    return nearLowerBand || rsiApproachingOversold;
  }

  /// Bollinger Short Preparing: Price near upper band but not all conditions met
  bool get _isBollingerShortPreparing {
    if (isShortSignal || bollingerBands == null || bollingerRsi == null) return false;

    // Price is approaching upper band (within 0.5% distance)
    final distanceToUpperBand = (bollingerBands!.upper - currentPrice) / bollingerBands!.upper;
    final nearUpperBand = distanceToUpperBand < 0.005; // Within 0.5%

    // RSI is getting overbought (within 10 points of threshold)
    final rsiApproachingOverbought = bollingerRsi! > (bollingerRsiOverbought ?? 70.0) - 10;

    return nearUpperBand || rsiApproachingOverbought;
  }

  // ===== EMA MODE LOGIC =====

  /// EMA Trend Long Entry:
  /// 1. EMA(9) crosses above EMA(21) OR already in uptrend
  /// 2. RSI(6) < long threshold (default: 25)
  /// 3. RSI(14) < long threshold (default: 40)
  /// 4. Volume > avgVolume × 1.5 (optional)
  bool get _isEmaLongSignal {
    // RSI conditions
    final rsiCondition = rsi6 < rsi6LongThreshold && rsi14 < rsi14LongThreshold;

    // Extreme RSI: Ignore other conditions if RSI is extremely oversold
    final extremeRsiCondition = rsi6 < (rsi6LongThreshold - 15) && rsi14 < (rsi14LongThreshold - 15);
    if (extremeRsiCondition) return true;

    // EMA trend condition: Bullish crossover or price above EMA
    bool trendOk = true;
    if (useEmaFilter) {
      // Check for bullish crossover
      final hasBullishCrossover = emaCrossover == EmaCrossover.bullish;
      // OR price is above selected EMA (uptrend confirmation)
      final priceAboveEma = currentPrice > selectedEma;
      trendOk = hasBullishCrossover || priceAboveEma;
    }

    // Volume condition (optional - always enabled in EMA mode)
    final volumeThreshold = volumeMA5 * 1.5;
    final volumeOk = currentVolume > volumeThreshold;

    return rsiCondition && trendOk && volumeOk;
  }

  /// EMA Trend Short Entry:
  /// 1. EMA(9) crosses below EMA(21) OR already in downtrend
  /// 2. RSI(6) > short threshold (default: 75)
  /// 3. RSI(14) > short threshold (default: 60)
  /// 4. Volume > avgVolume × 1.5 (optional)
  bool get _isEmaShortSignal {
    // RSI conditions
    final rsiCondition = rsi6 > rsi6ShortThreshold && rsi14 > rsi14ShortThreshold;

    // Extreme RSI: Ignore other conditions if RSI is extremely overbought
    final extremeRsiCondition = rsi6 > (rsi6ShortThreshold + 15) && rsi14 > (rsi14ShortThreshold + 15);
    if (extremeRsiCondition) return true;

    // EMA trend condition: Bearish crossover or price below EMA
    bool trendOk = true;
    if (useEmaFilter) {
      // Check for bearish crossover
      final hasBearishCrossover = emaCrossover == EmaCrossover.bearish;
      // OR price is below selected EMA (downtrend confirmation)
      final priceBelowEma = currentPrice < selectedEma;
      trendOk = hasBearishCrossover || priceBelowEma;
    }

    // Volume condition (optional - always enabled in EMA mode)
    final volumeThreshold = volumeMA5 * 1.5;
    final volumeOk = currentVolume > volumeThreshold;

    return rsiCondition && trendOk && volumeOk;
  }

  /// EMA Long Preparing: One or more conditions partially met
  bool get _isEmaLongPreparing {
    if (isLongSignal) return false;

    final rsi6Ok = rsi6 < rsi6LongThreshold;
    final rsi14Ok = rsi14 < rsi14LongThreshold;

    if (!rsi6Ok && !rsi14Ok) return false;

    if (useEmaFilter) {
      final trendOk = currentPrice > selectedEma;
      return trendOk && (rsi6Ok || rsi14Ok);
    }

    return rsi6Ok || rsi14Ok;
  }

  /// EMA Short Preparing: One or more conditions partially met
  bool get _isEmaShortPreparing {
    if (isShortSignal) return false;

    final rsi6Ok = rsi6 > rsi6ShortThreshold;
    final rsi14Ok = rsi14 > rsi14ShortThreshold;

    if (!rsi6Ok && !rsi14Ok) return false;

    if (useEmaFilter) {
      final trendOk = currentPrice < selectedEma;
      return trendOk && (rsi6Ok || rsi14Ok);
    }

    return rsi6Ok || rsi14Ok;
  }

  /// Get signal status text
  String get signalStatus {
    if (isLongSignal) return '🟢 LONG SIGNAL';
    if (isShortSignal) return '🔴 SHORT SIGNAL';
    if (isLongPreparing) return '🟡 Long Preparing...';
    if (isShortPreparing) return '🟠 Short Preparing...';
    return '⚪ No Signal';
  }

  @override
  String toString() {
    final volumeRatio = (currentVolume / volumeMA5 * 100).toStringAsFixed(1);

    if (mode == TradingMode.bollinger) {
      return 'Technical Analysis (Bollinger Mode):\n'
          '  Price: \$$currentPrice\n'
          '  BB: Upper=\$${bollingerBands?.upper.toStringAsFixed(2)}, '
          'Middle=\$${bollingerBands?.middle.toStringAsFixed(2)}, '
          'Lower=\$${bollingerBands?.lower.toStringAsFixed(2)}\n'
          '  RSI(14): ${bollingerRsi?.toStringAsFixed(2)}\n'
          '  Volume: ${currentVolume.toStringAsFixed(0)} ($volumeRatio% of MA5)\n'
          '  Status: $signalStatus';
    } else {
      return 'Technical Analysis (EMA Mode):\n'
          '  Price: \$$currentPrice\n'
          '  RSI(6): ${rsi6.toStringAsFixed(2)} | RSI(14): ${rsi14.toStringAsFixed(2)}\n'
          '  EMA(9): \$${ema9.toStringAsFixed(2)} | EMA(21): \$${ema21.toStringAsFixed(2)}\n'
          '  Volume: ${currentVolume.toStringAsFixed(0)} ($volumeRatio% of MA5)\n'
          '  Status: $signalStatus';
    }
  }
}

/// Auto-selects optimal trading mode based on market conditions
///
/// Returns 'bollinger' for ranging markets, 'ema' for trending markets
TradingMode selectOptimalMode(List<double> closePrices) {
  if (closePrices.length < 50) {
    // Not enough data, default to bollinger (safer for ranging markets)
    return TradingMode.bollinger;
  }

  int trendScore = 0;

  // 1. EMA Alignment Check (max 3 points)
  final ema9 = calculateEMA(closePrices, 9);
  final ema21 = calculateEMA(closePrices, 21);
  final ema50 = calculateEMA(closePrices, 50);

  // Perfect uptrend or downtrend alignment
  if ((ema9 > ema21 && ema21 > ema50) || (ema9 < ema21 && ema21 < ema50)) {
    trendScore += 3;
  }
  // Partial alignment
  else if (ema9 > ema21 || ema9 < ema21) {
    trendScore += 1;
  }

  // 2. Bollinger Band Width (max 3 points)
  final bollingerBands = calculateBollingerBands(closePrices, 20, 2.0);
  final bbWidth = (bollingerBands.upper - bollingerBands.lower) / bollingerBands.middle;

  // Calculate average BB width over last 20 candles
  double totalBBWidth = 0;
  int widthSamples = 0;
  for (int i = math.max(0, closePrices.length - 20); i < closePrices.length; i++) {
    final historicalPrices = closePrices.sublist(0, i + 1);
    if (historicalPrices.length >= 20) {
      final bb = calculateBollingerBands(historicalPrices, 20, 2.0);
      totalBBWidth += (bb.upper - bb.lower) / bb.middle;
      widthSamples++;
    }
  }
  final avgBBWidth = widthSamples > 0 ? totalBBWidth / widthSamples : bbWidth;

  // Wide band = high volatility = trending
  if (bbWidth > avgBBWidth * 1.5) {
    trendScore += 3;
  } else if (bbWidth > avgBBWidth * 1.2) {
    trendScore += 2;
  } else if (bbWidth < avgBBWidth * 0.8) {
    trendScore += 0;  // Narrow band = low volatility = ranging
  } else {
    trendScore += 1;
  }

  // 3. Price Distance from EMA 50 (max 2 points)
  final currentPrice = closePrices.last;
  final distanceFromEma50 = (currentPrice - ema50).abs() / ema50;

  if (distanceFromEma50 > 0.02) {  // 2% or more distance
    trendScore += 2;  // Strong trend
  } else if (distanceFromEma50 > 0.01) {  // 1-2% distance
    trendScore += 1;
  }

  // 4. Recent Price Movement (max 2 points)
  if (closePrices.length >= 10) {
    final recentPrices = closePrices.sublist(closePrices.length - 10);
    final priceChange = (recentPrices.last - recentPrices.first).abs() / recentPrices.first;

    if (priceChange > 0.015) {  // 1.5% move in 10 candles
      trendScore += 2;
    } else if (priceChange > 0.01) {  // 1% move
      trendScore += 1;
    }
  }

  // Decision: 7+ = strong trend (EMA), 5-6 = medium trend (EMA), 0-4 = ranging (Bollinger)
  if (trendScore >= 7) {
    return TradingMode.ema;  // Strong trend
  } else if (trendScore >= 5) {
    return TradingMode.ema;  // Medium trend
  } else {
    return TradingMode.bollinger;  // Ranging or weak trend
  }
}

/// Analyzes price and volume data and returns technical indicators
/// Supports Auto, Bollinger Band, and EMA trading modes
TechnicalAnalysis analyzePriceData(
  List<double> closePrices,
  List<double> volumes, {
  required TradingMode mode,
  // Bollinger mode parameters
  int? bollingerPeriod,
  double? bollingerStdDev,
  int? bollingerRsiPeriod,
  double? bollingerRsiOverbought,
  double? bollingerRsiOversold,
  bool? useVolumeFilter,
  double? volumeMultiplier,
  // EMA mode parameters
  double? rsi6LongThreshold,
  double? rsi6ShortThreshold,
  double? rsi14LongThreshold,
  double? rsi14ShortThreshold,
  bool? useEmaFilter,
  int? emaPeriod,
}) {
  if (closePrices.length < 30) {
    throw ArgumentError('Need at least 30 price points for analysis');
  }
  if (volumes.length < 30) {
    throw ArgumentError('Need at least 30 volume points for analysis');
  }

  // Auto mode: Select optimal strategy based on market conditions
  TradingMode effectiveMode = mode;
  if (mode == TradingMode.auto) {
    effectiveMode = selectOptimalMode(closePrices);
    Logger.info('Auto mode selected: ${effectiveMode == TradingMode.bollinger ? "Bollinger (Ranging Market)" : "EMA (Trending Market)"}');
  }

  // Common indicators for both modes
  final volumeMA5 = calculateSMA(volumes, 5);
  final volumeMA10 = calculateSMA(volumes, 10);
  final ema9 = calculateEMA(closePrices, 9);
  final ema21 = calculateEMA(closePrices, 21);
  final currentPrice = closePrices.last;
  final currentVolume = volumes.last;

  if (effectiveMode == TradingMode.bollinger) {
    // Bollinger Band Mode
    final bbPeriod = bollingerPeriod ?? 20;
    final bbStdDev = bollingerStdDev ?? 2.0;
    final bollingerBands = calculateBollingerBands(closePrices, bbPeriod, bbStdDev);

    final rsiPeriod = bollingerRsiPeriod ?? 14;
    final bollingerRsi = calculateRSI(closePrices, rsiPeriod);

    // Also calculate RSI(6) and RSI(14) for display purposes
    final rsi6 = calculateRSI(closePrices, 6);
    final rsi14 = calculateRSI(closePrices, 14);  // Actually RSI 14

    return TechnicalAnalysis(
      mode: effectiveMode,  // Use effective mode (auto-selected or original)
      currentPrice: currentPrice,
      currentVolume: currentVolume,
      volumeMA5: volumeMA5,
      volumeMA10: volumeMA10,
      ema9: ema9,
      ema21: ema21,
      // EMA mode parameters (calculate for display even in Bollinger mode)
      rsi6: rsi6,
      rsi14: rsi14,
      rsi6LongThreshold: rsi6LongThreshold ?? 25.0,
      rsi6ShortThreshold: rsi6ShortThreshold ?? 75.0,
      rsi14LongThreshold: rsi14LongThreshold ?? 30.0,
      rsi14ShortThreshold: rsi14ShortThreshold ?? 70.0,
      useEmaFilter: false,
      emaPeriod: 21,
      selectedEma: ema21,
      // Bollinger mode parameters
      bollingerBands: bollingerBands,
      bollingerRsi: bollingerRsi,
      bollingerRsiOverbought: bollingerRsiOverbought ?? 70.0,
      bollingerRsiOversold: bollingerRsiOversold ?? 30.0,
      useVolumeFilter: useVolumeFilter ?? true,
      volumeMultiplier: volumeMultiplier ?? 1.5,
    );
  } else {
    // EMA Mode
    final rsi6 = calculateRSI(closePrices, 6);
    final rsi14 = calculateRSI(closePrices, 14);  // Actually RSI 14

    final emaPer = emaPeriod ?? 21;
    double selectedEma;
    if (emaPer == 9) {
      selectedEma = ema9;
    } else if (emaPer == 21) {
      selectedEma = ema21;
    } else {
      selectedEma = calculateEMA(closePrices, emaPer);
    }

    // Detect EMA crossover
    final emaCrossover = detectEmaCrossover(closePrices, 9, 21);

    return TechnicalAnalysis(
      mode: effectiveMode,  // Use effective mode (auto-selected or original)
      currentPrice: currentPrice,
      currentVolume: currentVolume,
      volumeMA5: volumeMA5,
      volumeMA10: volumeMA10,
      ema9: ema9,
      ema21: ema21,
      // EMA mode parameters
      rsi6: rsi6,
      rsi14: rsi14,
      rsi6LongThreshold: rsi6LongThreshold ?? 25.0,
      rsi6ShortThreshold: rsi6ShortThreshold ?? 75.0,
      rsi14LongThreshold: rsi14LongThreshold ?? 30.0,
      rsi14ShortThreshold: rsi14ShortThreshold ?? 70.0,
      useEmaFilter: useEmaFilter ?? false,
      emaPeriod: emaPer,
      selectedEma: selectedEma,
      emaCrossover: emaCrossover,
    );
  }
}

// ============================================================================
// SERIES CALCULATION FUNCTIONS (for market analysis)
// ============================================================================
// These functions return a series of values instead of just the latest value

/// Calculates RSI series (returns RSI value for each candle)
///
/// [closePrices] - List of prices (oldest first)
/// [period] - RSI period (typically 14)
///
/// Returns list of RSI values (same length as input prices, first few values will be NaN)
List<double> calculateRSISeries(List<double> closePrices, int period) {
  if (closePrices.length < period + 1) {
    return [];
  }

  final rsiValues = <double>[];

  // Calculate price changes
  final gains = <double>[];
  final losses = <double>[];

  for (int i = 1; i < closePrices.length; i++) {
    final change = closePrices[i] - closePrices[i - 1];
    gains.add(change > 0 ? change : 0);
    losses.add(change < 0 ? -change : 0);
  }

  // Calculate initial average gain and loss
  double avgGain = gains.take(period).reduce((a, b) => a + b) / period;
  double avgLoss = losses.take(period).reduce((a, b) => a + b) / period;

  // First RSI value
  double rsi;
  if (avgLoss == 0) {
    rsi = 100;
  } else {
    final rs = avgGain / avgLoss;
    rsi = 100 - (100 / (1 + rs));
  }
  rsiValues.add(rsi);

  // Calculate RSI for each subsequent period using Wilder's smoothing
  for (int i = period; i < gains.length; i++) {
    avgGain = (avgGain * (period - 1) + gains[i]) / period;
    avgLoss = (avgLoss * (period - 1) + losses[i]) / period;

    if (avgLoss == 0) {
      rsi = 100;
    } else {
      final rs = avgGain / avgLoss;
      rsi = 100 - (100 / (1 + rs));
    }
    rsiValues.add(rsi);
  }

  return rsiValues;
}

/// Calculates EMA series (returns EMA value for each candle)
///
/// [prices] - List of prices (oldest first)
/// [period] - EMA period (typically 9, 21, 50)
///
/// Returns list of EMA values (length = prices.length - period + 1)
List<double> calculateEMASeries(List<double> prices, int period) {
  if (prices.length < period) {
    return [];
  }

  final emaValues = <double>[];

  // Calculate initial SMA as starting point
  double ema = prices.take(period).reduce((a, b) => a + b) / period;
  emaValues.add(ema);

  // Calculate multiplier
  final multiplier = 2.0 / (period + 1);

  // Calculate EMA for remaining prices
  for (int i = period; i < prices.length; i++) {
    ema = (prices[i] - ema) * multiplier + ema;
    emaValues.add(ema);
  }

  return emaValues;
}

/// Calculates Bollinger Bands with default parameters
///
/// Wrapper function for calculateBollingerBands with standard settings
/// [prices] - List of prices (oldest first)
///
/// Returns BollingerBands object
BollingerBands calculateBollingerBandsDefault(List<double> prices) {
  return calculateBollingerBands(prices, 20, 2.0);
}

// ============================================================================
// MACD INDICATOR
// ============================================================================

/// MACD histogram trend state
enum MACDHistogramTrend {
  improving,   // Histogram moving toward signal direction (bullish getting more bullish or bearish getting more bearish)
  worsening,   // Histogram moving against signal direction (bullish weakening or bearish weakening)
  crossing,    // Histogram crossed zero line recently
  sideways,    // Histogram flat/choppy
}

/// MACD (Moving Average Convergence Divergence) values
class MACD {
  final double macdLine;      // Fast EMA - Slow EMA
  final double signalLine;    // Signal line (EMA of MACD line)
  final double histogram;     // MACD line - Signal line

  MACD({
    required this.macdLine,
    required this.signalLine,
    required this.histogram,
  });

  /// Is MACD bullish? (MACD > Signal)
  bool get isBullish => macdLine > signalLine;

  /// Is MACD bearish? (MACD < Signal)
  bool get isBearish => macdLine < signalLine;

  /// Histogram strength (absolute value)
  double get histogramStrength => histogram.abs();

  @override
  String toString() {
    return 'MACD(line: ${macdLine.toStringAsFixed(4)}, signal: ${signalLine.toStringAsFixed(4)}, histogram: ${histogram.toStringAsFixed(4)})';
  }
}

/// Calculates MACD (Moving Average Convergence Divergence)
///
/// [prices] - List of prices (oldest first)
/// [fastPeriod] - Fast EMA period (typically 12)
/// [slowPeriod] - Slow EMA period (typically 26)
/// [signalPeriod] - Signal line EMA period (typically 9)
///
/// Returns MACD object with current values
MACD calculateMACD(
  List<double> prices, {
  int fastPeriod = 12,
  int slowPeriod = 26,
  int signalPeriod = 9,
}) {
  if (prices.length < slowPeriod + signalPeriod) {
    throw ArgumentError('Need at least ${slowPeriod + signalPeriod} price points for MACD');
  }

  // Calculate fast and slow EMAs
  final fastEMA = calculateEMA(prices, fastPeriod);
  final slowEMA = calculateEMA(prices, slowPeriod);

  // MACD line = Fast EMA - Slow EMA
  final macdLine = fastEMA - slowEMA;

  // Calculate signal line (EMA of MACD line)
  // We need to calculate MACD series first
  final macdSeries = calculateMACDSeries(
    prices,
    fastPeriod: fastPeriod,
    slowPeriod: slowPeriod,
  );

  // Signal line is EMA of MACD series
  final signalLine = calculateEMA(macdSeries, signalPeriod);

  // Histogram = MACD line - Signal line
  final histogram = macdLine - signalLine;

  return MACD(
    macdLine: macdLine,
    signalLine: signalLine,
    histogram: histogram,
  );
}

/// Calculates MACD series (returns MACD line value for each candle)
///
/// [prices] - List of prices (oldest first)
/// [fastPeriod] - Fast EMA period (typically 12)
/// [slowPeriod] - Slow EMA period (typically 26)
///
/// Returns list of MACD line values
List<double> calculateMACDSeries(
  List<double> prices, {
  int fastPeriod = 12,
  int slowPeriod = 26,
}) {
  if (prices.length < slowPeriod) {
    return [];
  }

  final macdValues = <double>[];

  // Calculate EMA series for fast and slow
  final fastEMASeries = calculateEMASeries(prices, fastPeriod);
  final slowEMASeries = calculateEMASeries(prices, slowPeriod);

  // MACD line = Fast EMA - Slow EMA
  // Note: slowEMASeries starts later (at index slowPeriod-1)
  // fastEMASeries starts at index fastPeriod-1
  // So we need to align them
  final startIndex = slowPeriod - fastPeriod;
  for (int i = 0; i < slowEMASeries.length; i++) {
    final macdLine = fastEMASeries[startIndex + i] - slowEMASeries[i];
    macdValues.add(macdLine);
  }

  return macdValues;
}

/// Calculates full MACD series with histogram
///
/// [prices] - List of prices (oldest first)
/// [fastPeriod] - Fast EMA period (typically 12)
/// [slowPeriod] - Slow EMA period (typically 26)
/// [signalPeriod] - Signal line period (typically 9)
///
/// Returns list of MACD objects
List<MACD> calculateMACDFullSeries(
  List<double> prices, {
  int fastPeriod = 12,
  int slowPeriod = 26,
  int signalPeriod = 9,
}) {
  if (prices.length < slowPeriod + signalPeriod) {
    return [];
  }

  final macdObjects = <MACD>[];

  // Calculate MACD line series
  final macdLineSeries = calculateMACDSeries(
    prices,
    fastPeriod: fastPeriod,
    slowPeriod: slowPeriod,
  );

  // Calculate signal line series (EMA of MACD line)
  final signalLineSeries = calculateEMASeries(macdLineSeries, signalPeriod);

  // Create MACD objects with histogram
  // signalLineSeries starts at index signalPeriod-1 relative to macdLineSeries
  final startIndex = signalPeriod - 1;
  for (int i = 0; i < signalLineSeries.length; i++) {
    final macdLine = macdLineSeries[startIndex + i];
    final signalLine = signalLineSeries[i];
    final histogram = macdLine - signalLine;

    macdObjects.add(MACD(
      macdLine: macdLine,
      signalLine: signalLine,
      histogram: histogram,
    ));
  }

  return macdObjects;
}

/// Determines MACD histogram trend state
///
/// [macdSeries] - List of MACD objects (oldest first, minimum 3)
/// [lookbackPeriod] - How many recent candles to analyze (default: 3)
///
/// Returns MACDHistogramTrend state
MACDHistogramTrend getMACDHistogramTrend(
  List<MACD> macdSeries, {
  int lookbackPeriod = 3,
}) {
  if (macdSeries.length < lookbackPeriod) {
    return MACDHistogramTrend.sideways;
  }

  // Get recent histograms
  final recentHistograms = macdSeries
      .skip(macdSeries.length - lookbackPeriod)
      .map((m) => m.histogram)
      .toList();

  final currentHistogram = recentHistograms.last;
  final previousHistogram = recentHistograms[recentHistograms.length - 2];

  // Check for zero crossing
  if ((previousHistogram >= 0 && currentHistogram < 0) ||
      (previousHistogram <= 0 && currentHistogram > 0)) {
    return MACDHistogramTrend.crossing;
  }

  // Calculate histogram slope (change over lookback period)
  final histogramChange = currentHistogram - recentHistograms.first;
  final changeThreshold = currentHistogram.abs() * 0.05; // 5% change threshold

  // IMPROVING: Histogram moving away from zero (strengthening)
  // - If positive and increasing → improving bullish
  // - If negative and decreasing (more negative) → improving bearish
  if (currentHistogram > 0 && histogramChange > changeThreshold) {
    return MACDHistogramTrend.improving;
  }
  if (currentHistogram < 0 && histogramChange < -changeThreshold) {
    return MACDHistogramTrend.improving;
  }

  // WORSENING: Histogram moving toward zero (weakening)
  // - If positive and decreasing → worsening bullish
  // - If negative and increasing (less negative) → worsening bearish
  if (currentHistogram > 0 && histogramChange < -changeThreshold) {
    return MACDHistogramTrend.worsening;
  }
  if (currentHistogram < 0 && histogramChange > changeThreshold) {
    return MACDHistogramTrend.worsening;
  }

  // SIDEWAYS: No significant change
  return MACDHistogramTrend.sideways;
}

// ============================================================================
// VOLUME ANALYZER
// ============================================================================

/// Volume analysis result
class VolumeAnalysis {
  final double currentVolume;
  final double volumeMA20;
  final double relativeVolumeRatio; // current / MA20
  final bool isHighVolume;          // Ratio > 1.5x
  final bool isLowVolume;           // Ratio < 0.5x
  final double score;               // Volume score: -1.0 (very low) to +1.0 (very high)

  VolumeAnalysis({
    required this.currentVolume,
    required this.volumeMA20,
    required this.relativeVolumeRatio,
    required this.isHighVolume,
    required this.isLowVolume,
    required this.score,
  });

  @override
  String toString() {
    return 'Volume(current: ${currentVolume.toStringAsFixed(0)}, MA20: ${volumeMA20.toStringAsFixed(0)}, ratio: ${relativeVolumeRatio.toStringAsFixed(2)}x, score: ${score.toStringAsFixed(2)})';
  }
}

/// Analyzes volume
///
/// [volumes] - List of volumes (oldest first)
/// [highVolumeThreshold] - Threshold for high volume (default: 1.5x MA20)
/// [lowVolumeThreshold] - Threshold for low volume (default: 0.5x MA20)
///
/// Returns VolumeAnalysis object
VolumeAnalysis analyzeVolume(
  List<double> volumes, {
  double highVolumeThreshold = 1.5,
  double lowVolumeThreshold = 0.5,
}) {
  if (volumes.length < 20) {
    throw ArgumentError('Need at least 20 volume points for volume analysis');
  }

  final currentVolume = volumes.last;
  final volumeMA20 = calculateSMA(volumes, 20);

  // Calculate relative volume ratio
  final relativeVolumeRatio = currentVolume / volumeMA20;

  // Determine high/low volume flags
  final isHighVolume = relativeVolumeRatio >= highVolumeThreshold;
  final isLowVolume = relativeVolumeRatio <= lowVolumeThreshold;

  // Calculate volume score (-1.0 to +1.0)
  // Very high volume (3x+) = +1.0
  // Normal volume (1x) = 0.0
  // Very low volume (0.33x or less) = -1.0
  double score;
  if (relativeVolumeRatio >= 3.0) {
    score = 1.0;
  } else if (relativeVolumeRatio >= 1.0) {
    // Linear scale from 0.0 to 1.0 (1x to 3x)
    score = (relativeVolumeRatio - 1.0) / 2.0;
  } else if (relativeVolumeRatio >= 0.33) {
    // Linear scale from -1.0 to 0.0 (0.33x to 1x)
    score = (relativeVolumeRatio - 1.0) / 0.67;
  } else {
    score = -1.0;
  }

  return VolumeAnalysis(
    currentVolume: currentVolume,
    volumeMA20: volumeMA20,
    relativeVolumeRatio: relativeVolumeRatio,
    isHighVolume: isHighVolume,
    isLowVolume: isLowVolume,
    score: score,
  );
}

// ============================================================================
// PRICE ACTION ANALYZER
// ============================================================================

/// Price action analysis result
class PriceActionAnalysis {
  final double priceChangePercent;  // Recent price change (last 5 candles)
  final bool isStrongUpMove;        // Price up > 1.5%
  final bool isStrongDownMove;      // Price down > 1.5%
  final double momentum;            // Momentum score
  final double score;               // Price action score: -1.0 (strong down) to +1.0 (strong up)

  PriceActionAnalysis({
    required this.priceChangePercent,
    required this.isStrongUpMove,
    required this.isStrongDownMove,
    required this.momentum,
    required this.score,
  });

  @override
  String toString() {
    return 'PriceAction(change: ${(priceChangePercent * 100).toStringAsFixed(2)}%, momentum: ${momentum.toStringAsFixed(2)}, score: ${score.toStringAsFixed(2)})';
  }
}

/// Analyzes price action (momentum and recent price changes)
///
/// [closePrices] - List of prices (oldest first)
/// [lookbackPeriod] - Number of candles to analyze (default: 5)
///
/// Returns PriceActionAnalysis object
PriceActionAnalysis analyzePriceAction(
  List<double> closePrices, {
  int lookbackPeriod = 5,
}) {
  if (closePrices.length < lookbackPeriod + 1) {
    throw ArgumentError('Need at least ${lookbackPeriod + 1} price points for price action analysis');
  }

  // Calculate recent price change
  final recentPrices = closePrices.skip(closePrices.length - lookbackPeriod).toList();
  final priceChangePercent = (recentPrices.last - recentPrices.first) / recentPrices.first;

  // Determine strong moves
  final isStrongUpMove = priceChangePercent >= 0.015;   // +1.5% or more
  final isStrongDownMove = priceChangePercent <= -0.015; // -1.5% or more

  // Calculate momentum (average of recent candle changes)
  double totalChange = 0.0;
  for (int i = 1; i < recentPrices.length; i++) {
    totalChange += (recentPrices[i] - recentPrices[i - 1]) / recentPrices[i - 1];
  }
  final momentum = totalChange / (recentPrices.length - 1);

  // Calculate price action score (-1.0 to +1.0)
  // Strong up move (3%+) = +1.0
  // Neutral (0%) = 0.0
  // Strong down move (3%-) = -1.0
  double score;
  if (priceChangePercent >= 0.03) {
    score = 1.0;
  } else if (priceChangePercent >= 0.0) {
    // Linear scale from 0.0 to 1.0 (0% to 3%)
    score = priceChangePercent / 0.03;
  } else if (priceChangePercent >= -0.03) {
    // Linear scale from -1.0 to 0.0 (-3% to 0%)
    score = priceChangePercent / 0.03;
  } else {
    score = -1.0;
  }

  return PriceActionAnalysis(
    priceChangePercent: priceChangePercent,
    isStrongUpMove: isStrongUpMove,
    isStrongDownMove: isStrongDownMove,
    momentum: momentum,
    score: score,
  );
}

// ============================================================================
// MOVING AVERAGE TREND ANALYZER
// ============================================================================

/// MA trend analysis result
class MATrendAnalysis {
  final double ema9;
  final double ema21;
  final double ema50;
  final bool isPerfectUptrend;   // EMA9 > EMA21 > EMA50
  final bool isPerfectDowntrend; // EMA9 < EMA21 < EMA50
  final bool isPartialUptrend;   // EMA9 > EMA21
  final bool isPartialDowntrend; // EMA9 < EMA21
  final double score;            // MA trend score: -1.0 (strong downtrend) to +1.0 (strong uptrend)

  MATrendAnalysis({
    required this.ema9,
    required this.ema21,
    required this.ema50,
    required this.isPerfectUptrend,
    required this.isPerfectDowntrend,
    required this.isPartialUptrend,
    required this.isPartialDowntrend,
    required this.score,
  });

  @override
  String toString() {
    return 'MATrend(EMA9: ${ema9.toStringAsFixed(2)}, EMA21: ${ema21.toStringAsFixed(2)}, EMA50: ${ema50.toStringAsFixed(2)}, score: ${score.toStringAsFixed(2)})';
  }
}

/// Analyzes MA trend alignment
///
/// [closePrices] - List of prices (oldest first)
///
/// Returns MATrendAnalysis object
MATrendAnalysis analyzeMATrend(List<double> closePrices) {
  if (closePrices.length < 50) {
    throw ArgumentError('Need at least 50 price points for MA trend analysis');
  }

  // Calculate EMAs
  final ema9 = calculateEMA(closePrices, 9);
  final ema21 = calculateEMA(closePrices, 21);
  final ema50 = calculateEMA(closePrices, 50);

  // Check trend alignment
  final isPerfectUptrend = ema9 > ema21 && ema21 > ema50;
  final isPerfectDowntrend = ema9 < ema21 && ema21 < ema50;
  final isPartialUptrend = ema9 > ema21;
  final isPartialDowntrend = ema9 < ema21;

  // Calculate MA trend score (-1.0 to +1.0)
  double score;
  if (isPerfectUptrend) {
    // Perfect uptrend: check strength by distance between EMAs
    final gap9_21 = (ema9 - ema21) / ema21;
    final gap21_50 = (ema21 - ema50) / ema50;
    final avgGap = (gap9_21 + gap21_50) / 2;

    // If gaps are > 2%, score = 1.0; scale linearly from 0.5 to 1.0
    if (avgGap >= 0.02) {
      score = 1.0;
    } else {
      score = 0.5 + (avgGap / 0.02) * 0.5;
    }
  } else if (isPerfectDowntrend) {
    // Perfect downtrend: check strength by distance between EMAs
    final gap9_21 = (ema21 - ema9) / ema21;
    final gap21_50 = (ema50 - ema21) / ema50;
    final avgGap = (gap9_21 + gap21_50) / 2;

    // If gaps are > 2%, score = -1.0; scale linearly from -0.5 to -1.0
    if (avgGap >= 0.02) {
      score = -1.0;
    } else {
      score = -0.5 - (avgGap / 0.02) * 0.5;
    }
  } else if (isPartialUptrend) {
    // Partial uptrend: weaker signal
    final gap = (ema9 - ema21) / ema21;
    score = 0.25 + (gap / 0.02) * 0.25;
    if (score > 0.5) score = 0.5;
  } else if (isPartialDowntrend) {
    // Partial downtrend: weaker signal
    final gap = (ema21 - ema9) / ema21;
    score = -0.25 - (gap / 0.02) * 0.25;
    if (score < -0.5) score = -0.5;
  } else {
    // Choppy/ranging
    score = 0.0;
  }

  return MATrendAnalysis(
    ema9: ema9,
    ema21: ema21,
    ema50: ema50,
    isPerfectUptrend: isPerfectUptrend,
    isPerfectDowntrend: isPerfectDowntrend,
    isPartialUptrend: isPartialUptrend,
    isPartialDowntrend: isPartialDowntrend,
    score: score,
  );
}

// ============================================================================
// COMPOSITE MULTI-INDICATOR ANALYZER
// ============================================================================

/// Signal confidence level
enum SignalConfidence {
  high,    // Multiple confirmations (75%+ indicators agree)
  medium,  // Some confirmations (50-75% indicators agree)
  low,     // Weak signal (<50% indicators agree)
}

/// Composite market analysis result
class CompositeAnalysis {
  // Individual indicator results
  final double rsi;
  final VolumeAnalysis volume;
  final PriceActionAnalysis priceAction;
  final MATrendAnalysis maTrend;
  final BollingerBands bb;
  final MACD macd;
  final MACDHistogramTrend macdTrend;

  // Composite score and classification
  final double compositeScore;                    // -1.0 (extreme bearish) to +1.0 (extreme bullish)
  final EnhancedMarketCondition marketCondition;  // 7-level market classification
  final SignalConfidence confidence;

  // Individual component scores (weighted)
  final double rsiScore;           // RSI contribution (25%)
  final double volumeScore;        // Volume contribution (20%)
  final double priceActionScore;   // Price action contribution (20%)
  final double maTrendScore;       // MA trend contribution (15%)
  final double bbScore;            // BB contribution (10%)
  final double macdScore;          // MACD contribution (10%)

  CompositeAnalysis({
    required this.rsi,
    required this.volume,
    required this.priceAction,
    required this.maTrend,
    required this.bb,
    required this.macd,
    required this.macdTrend,
    required this.compositeScore,
    required this.marketCondition,
    required this.confidence,
    required this.rsiScore,
    required this.volumeScore,
    required this.priceActionScore,
    required this.maTrendScore,
    required this.bbScore,
    required this.macdScore,
  });

  /// Is the composite signal bullish?
  bool get isBullish => compositeScore > 0.15;

  /// Is the composite signal bearish?
  bool get isBearish => compositeScore < -0.15;

  /// Is the signal neutral/ranging?
  bool get isRanging => !isBullish && !isBearish;

  @override
  String toString() {
    // Format market condition name
    String marketConditionName;
    switch (marketCondition) {
      case EnhancedMarketCondition.extremeBullish:
        marketConditionName = 'EXTREME BULLISH 🚀';
        break;
      case EnhancedMarketCondition.strongBullish:
        marketConditionName = 'STRONG BULLISH 📈';
        break;
      case EnhancedMarketCondition.weakBullish:
        marketConditionName = 'WEAK BULLISH 📊';
        break;
      case EnhancedMarketCondition.ranging:
        marketConditionName = 'RANGING ↔️';
        break;
      case EnhancedMarketCondition.weakBearish:
        marketConditionName = 'WEAK BEARISH 📉';
        break;
      case EnhancedMarketCondition.strongBearish:
        marketConditionName = 'STRONG BEARISH 📉📉';
        break;
      case EnhancedMarketCondition.extremeBearish:
        marketConditionName = 'EXTREME BEARISH 💥';
        break;
    }

    final currentPrice = bb.middle; // Approximation
    final pricePositionInBB = ((currentPrice - bb.lower) / (bb.upper - bb.lower) * 100);

    return 'CompositeAnalysis(\n'
        '  Market: $marketConditionName\n'
        '  Composite Score: ${compositeScore.toStringAsFixed(2)} (Confidence: ${confidence.name.toUpperCase()})\n'
        '  ───────────────────────────────────────\n'
        '  RSI: ${rsi.toStringAsFixed(2)} (score: ${rsiScore.toStringAsFixed(2)})\n'
        '  Volume: ${volume.relativeVolumeRatio.toStringAsFixed(2)}x (score: ${volumeScore.toStringAsFixed(2)})\n'
        '  Price Action: ${(priceAction.priceChangePercent * 100).toStringAsFixed(2)}% (score: ${priceActionScore.toStringAsFixed(2)})\n'
        '  MA Trend: ${maTrend.isPerfectUptrend ? "Perfect Up" : maTrend.isPerfectDowntrend ? "Perfect Down" : "Mixed"} (score: ${maTrendScore.toStringAsFixed(2)})\n'
        '  BB Position: ${pricePositionInBB.toStringAsFixed(0)}% (score: ${bbScore.toStringAsFixed(2)})\n'
        '  MACD: ${macd.isBullish ? "Bullish" : "Bearish"} ${macdTrend.name} (score: ${macdScore.toStringAsFixed(2)})\n'
        ')';
  }
}

/// Determines enhanced market condition from composite score
///
/// [compositeScore] - Composite score from -1.0 to +1.0
///
/// Returns EnhancedMarketCondition
EnhancedMarketCondition getMarketConditionFromScore(double compositeScore) {
  if (compositeScore > 0.6) {
    return EnhancedMarketCondition.extremeBullish;
  } else if (compositeScore > 0.4) {
    return EnhancedMarketCondition.strongBullish;
  } else if (compositeScore > 0.15) {
    return EnhancedMarketCondition.weakBullish;
  } else if (compositeScore >= -0.15) {
    return EnhancedMarketCondition.ranging;
  } else if (compositeScore >= -0.4) {
    return EnhancedMarketCondition.weakBearish;
  } else if (compositeScore >= -0.6) {
    return EnhancedMarketCondition.strongBearish;
  } else {
    return EnhancedMarketCondition.extremeBearish;
  }
}

/// Calculates composite multi-indicator analysis
///
/// Weights:
/// - RSI: 25%
/// - Volume: 20%
/// - Price Action: 20%
/// - MA Trend: 15%
/// - Bollinger Bands: 10%
/// - MACD: 10%
///
/// [closePrices] - List of prices (oldest first, minimum 50)
/// [volumes] - List of volumes (oldest first, minimum 50)
///
/// Returns CompositeAnalysis object
CompositeAnalysis analyzeMarketComposite(
  List<double> closePrices,
  List<double> volumes,
) {
  if (closePrices.length < 50) {
    throw ArgumentError('Need at least 50 price points for composite analysis');
  }
  if (volumes.length < 50) {
    throw ArgumentError('Need at least 50 volume points for composite analysis');
  }

  // Calculate individual indicators
  final rsi = calculateRSI(closePrices, 14);
  final volumeAnalysis = analyzeVolume(volumes);
  final priceActionAnalysis = analyzePriceAction(closePrices);
  final maTrendAnalysis = analyzeMATrend(closePrices);
  final bb = calculateBollingerBandsDefault(closePrices);
  final macdFullSeries = calculateMACDFullSeries(closePrices);
  final macd = macdFullSeries.last;
  final macdTrend = getMACDHistogramTrend(macdFullSeries);

  // Calculate RSI score (25% weight)
  // Oversold (RSI < 30) = +1.0, Overbought (RSI > 70) = -1.0, Neutral (50) = 0.0
  double rsiComponentScore;
  if (rsi <= 30) {
    rsiComponentScore = 1.0;
  } else if (rsi >= 70) {
    rsiComponentScore = -1.0;
  } else if (rsi < 50) {
    // Linear scale from +1.0 to 0.0 (RSI 30 to 50)
    rsiComponentScore = (50 - rsi) / 20;
  } else {
    // Linear scale from 0.0 to -1.0 (RSI 50 to 70)
    rsiComponentScore = -(rsi - 50) / 20;
  }
  final rsiScore = rsiComponentScore * 0.25;

  // Volume score (20% weight)
  final volumeScore = volumeAnalysis.score * 0.20;

  // Price action score (20% weight)
  final priceActionScore = priceActionAnalysis.score * 0.20;

  // MA trend score (15% weight)
  final maTrendScore = maTrendAnalysis.score * 0.15;

  // BB score (10% weight)
  // Price near lower band = +1.0 (oversold), near upper band = -1.0 (overbought)
  final currentPrice = closePrices.last;
  final bbRange = bb.upper - bb.lower;
  final pricePositionInBB = (currentPrice - bb.lower) / bbRange;
  double bbComponentScore;
  if (pricePositionInBB <= 0.2) {
    bbComponentScore = 1.0;  // Near lower band
  } else if (pricePositionInBB >= 0.8) {
    bbComponentScore = -1.0; // Near upper band
  } else {
    // Linear scale from +1.0 to -1.0 (position 0.2 to 0.8)
    bbComponentScore = 1.0 - ((pricePositionInBB - 0.2) / 0.6) * 2.0;
  }
  final bbScore = bbComponentScore * 0.10;

  // MACD score (10% weight)
  // Combines histogram direction and trend state
  double macdComponentScore;
  if (macd.histogram > 0) {
    // Bullish histogram
    if (macdTrend == MACDHistogramTrend.improving) {
      macdComponentScore = 1.0;  // Strong bullish
    } else if (macdTrend == MACDHistogramTrend.worsening) {
      macdComponentScore = 0.3;  // Weakening bullish
    } else if (macdTrend == MACDHistogramTrend.crossing) {
      macdComponentScore = 0.5;  // Just crossed bullish
    } else {
      macdComponentScore = 0.5;  // Sideways bullish
    }
  } else {
    // Bearish histogram
    if (macdTrend == MACDHistogramTrend.improving) {
      macdComponentScore = -1.0; // Strong bearish
    } else if (macdTrend == MACDHistogramTrend.worsening) {
      macdComponentScore = -0.3; // Weakening bearish
    } else if (macdTrend == MACDHistogramTrend.crossing) {
      macdComponentScore = -0.5; // Just crossed bearish
    } else {
      macdComponentScore = -0.5; // Sideways bearish
    }
  }
  final macdScore = macdComponentScore * 0.10;

  // Calculate composite score
  final compositeScore = rsiScore + volumeScore + priceActionScore +
                         maTrendScore + bbScore + macdScore;

  // Determine confidence level
  // Count how many indicators agree with the composite direction
  int agreeCount = 0;
  final isBullishComposite = compositeScore > 0;

  if (isBullishComposite) {
    if (rsiComponentScore > 0) agreeCount++;
    if (volumeAnalysis.score > 0) agreeCount++;
    if (priceActionAnalysis.score > 0) agreeCount++;
    if (maTrendAnalysis.score > 0) agreeCount++;
    if (bbComponentScore > 0) agreeCount++;
    if (macdComponentScore > 0) agreeCount++;
  } else {
    if (rsiComponentScore < 0) agreeCount++;
    if (volumeAnalysis.score < 0) agreeCount++;
    if (priceActionAnalysis.score < 0) agreeCount++;
    if (maTrendAnalysis.score < 0) agreeCount++;
    if (bbComponentScore < 0) agreeCount++;
    if (macdComponentScore < 0) agreeCount++;
  }

  final agreementPercent = agreeCount / 6.0;
  SignalConfidence confidence;
  if (agreementPercent >= 0.75) {
    confidence = SignalConfidence.high;
  } else if (agreementPercent >= 0.50) {
    confidence = SignalConfidence.medium;
  } else {
    confidence = SignalConfidence.low;
  }

  // Determine market condition
  final marketCondition = getMarketConditionFromScore(compositeScore);

  return CompositeAnalysis(
    rsi: rsi,
    volume: volumeAnalysis,
    priceAction: priceActionAnalysis,
    maTrend: maTrendAnalysis,
    bb: bb,
    macd: macd,
    macdTrend: macdTrend,
    compositeScore: compositeScore,
    marketCondition: marketCondition,
    confidence: confidence,
    rsiScore: rsiScore,
    volumeScore: volumeScore,
    priceActionScore: priceActionScore,
    maTrendScore: maTrendScore,
    bbScore: bbScore,
    macdScore: macdScore,
  );
}
