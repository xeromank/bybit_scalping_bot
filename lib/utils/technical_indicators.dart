/// Technical Indicator Calculations
///
/// Responsibility: Calculate technical indicators from price data
///
/// This utility provides pure functions for calculating technical indicators
/// commonly used in trading strategies.

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

/// Technical analysis result
class TechnicalAnalysis {
  final double rsi6;
  final double rsi12;
  final double volumeMA5;
  final double volumeMA10;
  final double ema9;
  final double ema21;
  final double currentPrice;
  final double currentVolume;

  // RSI Thresholds (customizable)
  final double rsi6LongThreshold;
  final double rsi6ShortThreshold;
  final double rsi12LongThreshold;
  final double rsi12ShortThreshold;

  // EMA Settings (customizable)
  final bool useEmaFilter;
  final int emaPeriod;
  final double selectedEma; // The EMA value for the selected period

  TechnicalAnalysis({
    required this.rsi6,
    required this.rsi12,
    required this.volumeMA5,
    required this.volumeMA10,
    required this.ema9,
    required this.ema21,
    required this.currentPrice,
    required this.currentVolume,
    required this.rsi6LongThreshold,
    required this.rsi6ShortThreshold,
    required this.rsi12LongThreshold,
    required this.rsi12ShortThreshold,
    required this.useEmaFilter,
    required this.emaPeriod,
    required this.selectedEma,
  });

  /// Checks if long entry conditions are met
  /// Conservative approach: stricter RSI thresholds and optional EMA trend confirmation
  bool get isLongSignal {
    // RSI conditions (using custom thresholds):
    // RSI(6) < rsi6LongThreshold (default: 25 - very oversold)
    // AND RSI(12) < rsi12LongThreshold (default: 40 - mid-term confirmation)
    final rsiCondition = rsi6 < rsi6LongThreshold && rsi12 < rsi12LongThreshold;

    // Extreme RSI condition: Ignore EMA if RSI is extremely oversold (±5 from threshold)
    final extremeRsiCondition = rsi6 < (rsi6LongThreshold - 5) && rsi12 < (rsi12LongThreshold - 5);

    if (extremeRsiCondition) {
      // Extremely oversold: Signal regardless of EMA
      return true;
    }

    // EMA condition (optional):
    // price > selectedEMA (uptrend confirmation)
    if (useEmaFilter) {
      return rsiCondition && currentPrice > selectedEma;
    }

    return rsiCondition;
  }

  /// Checks if short entry conditions are met
  /// Conservative approach: stricter RSI thresholds and optional EMA trend confirmation
  bool get isShortSignal {
    // RSI conditions (using custom thresholds):
    // RSI(6) > rsi6ShortThreshold (default: 75 - very overbought)
    // AND RSI(12) > rsi12ShortThreshold (default: 60 - mid-term confirmation)
    final rsiCondition = rsi6 > rsi6ShortThreshold && rsi12 > rsi12ShortThreshold;

    // Extreme RSI condition: Ignore EMA if RSI is extremely overbought (±5 from threshold)
    final extremeRsiCondition = rsi6 > (rsi6ShortThreshold + 5) && rsi12 > (rsi12ShortThreshold + 5);

    if (extremeRsiCondition) {
      // Extremely overbought: Signal regardless of EMA
      return true;
    }

    // EMA condition (optional):
    // price < selectedEMA (downtrend confirmation)
    if (useEmaFilter) {
      return rsiCondition && currentPrice < selectedEma;
    }

    return rsiCondition;
  }

  /// Checks if conditions are partially met for long (one RSI condition satisfied)
  bool get isLongPreparing {
    if (isLongSignal) return false; // Already a full signal
    final rsi6Ok = rsi6 < rsi6LongThreshold;
    final rsi12Ok = rsi12 < rsi12LongThreshold;

    // At least one RSI condition
    if (!rsi6Ok && !rsi12Ok) return false;

    // If EMA filter is on, check trend condition
    if (useEmaFilter) {
      final trendOk = currentPrice > selectedEma;
      return trendOk && (rsi6Ok || rsi12Ok);
    }

    // Without EMA filter, just need one RSI condition
    return rsi6Ok || rsi12Ok;
  }

  /// Checks if conditions are partially met for short (one RSI condition satisfied)
  bool get isShortPreparing {
    if (isShortSignal) return false; // Already a full signal
    final rsi6Ok = rsi6 > rsi6ShortThreshold;
    final rsi12Ok = rsi12 > rsi12ShortThreshold;

    // At least one RSI condition
    if (!rsi6Ok && !rsi12Ok) return false;

    // If EMA filter is on, check trend condition
    if (useEmaFilter) {
      final trendOk = currentPrice < selectedEma;
      return trendOk && (rsi6Ok || rsi12Ok);
    }

    // Without EMA filter, just need one RSI condition
    return rsi6Ok || rsi12Ok;
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
    // Calculate volume ratio vs MA5 for monitoring
    final volumeRatio = (currentVolume / volumeMA5 * 100).toStringAsFixed(1);

    return 'Technical Analysis:\n'
        '  Price: \$$currentPrice\n'
        '  RSI(6): ${rsi6.toStringAsFixed(2)} | RSI(12): ${rsi12.toStringAsFixed(2)}\n'
        '  EMA(9): \$${ema9.toStringAsFixed(2)} | EMA(21): \$${ema21.toStringAsFixed(2)}\n'
        '  Volume: ${currentVolume.toStringAsFixed(0)} ($volumeRatio% of MA5)\n'
        '  Volume MA(5): ${volumeMA5.toStringAsFixed(0)} | MA(10): ${volumeMA10.toStringAsFixed(0)}\n'
        '  Status: $signalStatus';
  }
}

/// Analyzes price and volume data and returns technical indicators
TechnicalAnalysis analyzePriceData(
  List<double> closePrices,
  List<double> volumes, {
  required double rsi6LongThreshold,
  required double rsi6ShortThreshold,
  required double rsi12LongThreshold,
  required double rsi12ShortThreshold,
  required bool useEmaFilter,
  required int emaPeriod,
}) {
  if (closePrices.length < 30) {
    throw ArgumentError('Need at least 30 price points for analysis');
  }
  if (volumes.length < 30) {
    throw ArgumentError('Need at least 30 volume points for analysis');
  }

  final rsi6 = calculateRSI(closePrices, 6);
  final rsi12 = calculateRSI(closePrices, 12);
  final volumeMA5 = calculateSMA(volumes, 5);
  final volumeMA10 = calculateSMA(volumes, 10);
  final ema9 = calculateEMA(closePrices, 9);
  final ema21 = calculateEMA(closePrices, 21);
  final currentPrice = closePrices.last;
  final currentVolume = volumes.last;

  // Calculate selected EMA based on period
  double selectedEma;
  if (emaPeriod == 9) {
    selectedEma = ema9;
  } else if (emaPeriod == 21) {
    selectedEma = ema21;
  } else {
    // Calculate custom EMA for any period (1-500)
    selectedEma = calculateEMA(closePrices, emaPeriod);
  }

  return TechnicalAnalysis(
    rsi6: rsi6,
    rsi12: rsi12,
    volumeMA5: volumeMA5,
    volumeMA10: volumeMA10,
    ema9: ema9,
    ema21: ema21,
    currentPrice: currentPrice,
    currentVolume: currentVolume,
    rsi6LongThreshold: rsi6LongThreshold,
    rsi6ShortThreshold: rsi6ShortThreshold,
    rsi12LongThreshold: rsi12LongThreshold,
    rsi12ShortThreshold: rsi12ShortThreshold,
    useEmaFilter: useEmaFilter,
    emaPeriod: emaPeriod,
    selectedEma: selectedEma,
  );
}
