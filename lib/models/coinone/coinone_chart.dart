/// Coinone chart candle data
///
/// Represents a single candlestick from Coinone chart API
/// Reference: https://docs.coinone.co.kr/reference/chart
class CoinoneCandle {
  final DateTime timestamp;
  final double open;
  final double high;
  final double low;
  final double close;
  final double volume; // Target currency volume
  final double quoteVolume; // Quote currency volume

  const CoinoneCandle({
    required this.timestamp,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.volume,
    required this.quoteVolume,
  });

  /// Create from API JSON response
  factory CoinoneCandle.fromJson(Map<String, dynamic> json) {
    return CoinoneCandle(
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        int.parse(json['timestamp'].toString()) * 1000, // API returns seconds
      ),
      open: double.parse(json['open'].toString()),
      high: double.parse(json['high'].toString()),
      low: double.parse(json['low'].toString()),
      close: double.parse(json['close'].toString()),
      volume: double.parse(json['target_volume']?.toString() ?? '0'),
      quoteVolume: double.parse(json['quote_volume']?.toString() ?? '0'),
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'timestamp': timestamp.millisecondsSinceEpoch ~/ 1000,
      'open': open.toString(),
      'high': high.toString(),
      'low': low.toString(),
      'close': close.toString(),
      'target_volume': volume.toString(),
      'quote_volume': quoteVolume.toString(),
    };
  }

  /// Get price change
  double get change => close - open;

  /// Get price change percentage
  double get changePercent {
    if (open == 0) return 0;
    return ((close - open) / open) * 100;
  }

  /// Check if candle is bullish
  bool get isBullish => close > open;

  /// Check if candle is bearish
  bool get isBearish => close < open;

  /// Get candle body size
  double get bodySize => (close - open).abs();

  /// Get candle range (high - low)
  double get range => high - low;

  @override
  String toString() {
    return 'CoinoneCandle(time: $timestamp, O: $open, H: $high, L: $low, C: $close)';
  }
}

/// Chart interval types
enum ChartInterval {
  oneMinute('1m'),
  threeMinutes('3m'),
  fiveMinutes('5m'),
  tenMinutes('10m'),
  fifteenMinutes('15m'),
  thirtyMinutes('30m'),
  oneHour('1h'),
  twoHours('2h'),
  fourHours('4h'),
  sixHours('6h'),
  twelveHours('12h'),
  oneDay('1d'),
  oneWeek('1w');

  final String value;
  const ChartInterval(this.value);

  /// Get interval in seconds
  int get seconds {
    switch (this) {
      case ChartInterval.oneMinute:
        return 60;
      case ChartInterval.threeMinutes:
        return 180;
      case ChartInterval.fiveMinutes:
        return 300;
      case ChartInterval.tenMinutes:
        return 600;
      case ChartInterval.fifteenMinutes:
        return 900;
      case ChartInterval.thirtyMinutes:
        return 1800;
      case ChartInterval.oneHour:
        return 3600;
      case ChartInterval.twoHours:
        return 7200;
      case ChartInterval.fourHours:
        return 14400;
      case ChartInterval.sixHours:
        return 21600;
      case ChartInterval.twelveHours:
        return 43200;
      case ChartInterval.oneDay:
        return 86400;
      case ChartInterval.oneWeek:
        return 604800;
    }
  }

  @override
  String toString() => value;
}

/// Chart data response
class CoinoneChartData {
  final String quoteCurrency;
  final String targetCurrency;
  final ChartInterval interval;
  final List<CoinoneCandle> candles;
  final DateTime fetchedAt;

  const CoinoneChartData({
    required this.quoteCurrency,
    required this.targetCurrency,
    required this.interval,
    required this.candles,
    required this.fetchedAt,
  });

  /// Create from API response
  factory CoinoneChartData.fromJson(
    String quoteCurrency,
    String targetCurrency,
    ChartInterval interval,
    List<dynamic> json,
  ) {
    final candles = json
        .map((e) => CoinoneCandle.fromJson(e as Map<String, dynamic>))
        .toList();

    // Sort by timestamp ascending
    candles.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    return CoinoneChartData(
      quoteCurrency: quoteCurrency,
      targetCurrency: targetCurrency,
      interval: interval,
      candles: candles,
      fetchedAt: DateTime.now(),
    );
  }

  /// Get symbol
  String get symbol => '$targetCurrency-$quoteCurrency';

  /// Get latest candle
  CoinoneCandle? get latestCandle => candles.isNotEmpty ? candles.last : null;

  /// Get latest close price
  double? get latestClose => latestCandle?.close;

  /// Get candles for specific count from latest
  List<CoinoneCandle> getLatestCandles(int count) {
    if (candles.length <= count) return candles;
    return candles.sublist(candles.length - count);
  }

  @override
  String toString() {
    return 'CoinoneChartData(symbol: $symbol, interval: $interval, candles: ${candles.length})';
  }
}
