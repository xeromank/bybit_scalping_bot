/// Coinone ticker model
///
/// Represents real-time ticker data from Coinone WebSocket
/// Reference: https://docs.coinone.co.kr/reference/public-websocket-ticker
class CoinoneTicker {
  final String quoteCurrency; // e.g., "KRW"
  final String targetCurrency; // e.g., "XRP"
  final double last; // 최근 체결 가격
  final double high; // 24시간 최고가
  final double low; // 24시간 최저가
  final double first; // 24시간 시작가
  final double volume; // 24시간 거래량 (target currency)
  final double quoteVolume; // 24시간 거래대금 (quote currency)
  final double bid; // 매수 호가
  final double ask; // 매도 호가
  final DateTime timestamp;

  const CoinoneTicker({
    required this.quoteCurrency,
    required this.targetCurrency,
    required this.last,
    required this.high,
    required this.low,
    required this.first,
    required this.volume,
    required this.quoteVolume,
    required this.bid,
    required this.ask,
    required this.timestamp,
  });

  /// Create from WebSocket JSON message
  factory CoinoneTicker.fromJson(Map<String, dynamic> json) {
    return CoinoneTicker(
      quoteCurrency: json['quote_currency']?.toString().toUpperCase() ?? 'KRW',
      targetCurrency: json['target_currency']?.toString().toUpperCase() ?? '',
      last: double.parse(json['last']?.toString() ?? '0'),
      high: double.parse(json['high']?.toString() ?? '0'),
      low: double.parse(json['low']?.toString() ?? '0'),
      first: double.parse(json['first']?.toString() ?? '0'),
      volume: double.parse(json['target_volume']?.toString() ?? json['volume']?.toString() ?? '0'),
      quoteVolume: double.parse(json['quote_volume']?.toString() ?? '0'),
      bid: double.parse(json['bid_best_price']?.toString() ?? json['best_bid']?.toString() ?? '0'),
      ask: double.parse(json['ask_best_price']?.toString() ?? json['best_ask']?.toString() ?? '0'),
      timestamp: json['timestamp'] != null
          ? DateTime.fromMillisecondsSinceEpoch(
              int.parse(json['timestamp'].toString()))
          : DateTime.now(),
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'quote_currency': quoteCurrency,
      'target_currency': targetCurrency,
      'last': last.toString(),
      'high': high.toString(),
      'low': low.toString(),
      'first': first.toString(),
      'volume': volume.toString(),
      'quote_volume': quoteVolume.toString(),
      'best_bid': bid.toString(),
      'best_ask': ask.toString(),
      'timestamp': timestamp.millisecondsSinceEpoch,
    };
  }

  /// Get trading pair symbol (e.g., "XRP-KRW")
  String get symbol => '$targetCurrency-$quoteCurrency';

  /// Get 24h price change
  double get change => last - first;

  /// Get 24h price change percentage
  double get changePercent {
    if (first == 0) return 0;
    return ((last - first) / first) * 100;
  }

  /// Get spread (ask - bid)
  double get spread => ask - bid;

  /// Get spread percentage
  double get spreadPercent {
    if (last == 0) return 0;
    return (spread / last) * 100;
  }

  @override
  String toString() {
    return 'CoinoneTicker(symbol: $symbol, last: $last, change: ${changePercent.toStringAsFixed(2)}%)';
  }
}
