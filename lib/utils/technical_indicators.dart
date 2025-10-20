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
enum MarketTrend {
  uptrend,    // Bullish trend: price increased > threshold
  downtrend,  // Bearish trend: price decreased > threshold
  sideways,   // Ranging market: price change within ±threshold
  unknown,    // Not yet analyzed
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
