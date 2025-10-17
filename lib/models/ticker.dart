/// Represents real-time ticker information for a trading symbol
///
/// Responsibility: Encapsulate ticker/price data
///
/// This immutable value object represents the ticker information
/// returned by the Bybit API.
class Ticker {
  final String symbol;
  final String lastPrice;
  final String prevPrice24h;
  final String price24hPcnt;
  final String highPrice24h;
  final String lowPrice24h;
  final String turnover24h;
  final String volume24h;
  final String bid1Price;
  final String bid1Size;
  final String ask1Price;
  final String ask1Size;

  const Ticker({
    required this.symbol,
    required this.lastPrice,
    required this.prevPrice24h,
    required this.price24hPcnt,
    required this.highPrice24h,
    required this.lowPrice24h,
    required this.turnover24h,
    required this.volume24h,
    required this.bid1Price,
    required this.bid1Size,
    required this.ask1Price,
    required this.ask1Size,
  });

  /// Creates Ticker from API response
  factory Ticker.fromJson(Map<String, dynamic> json) {
    return Ticker(
      symbol: json['symbol'] as String,
      lastPrice: json['lastPrice'] as String? ?? '0',
      prevPrice24h: json['prevPrice24h'] as String? ?? '0',
      price24hPcnt: json['price24hPcnt'] as String? ?? '0',
      highPrice24h: json['highPrice24h'] as String? ?? '0',
      lowPrice24h: json['lowPrice24h'] as String? ?? '0',
      turnover24h: json['turnover24h'] as String? ?? '0',
      volume24h: json['volume24h'] as String? ?? '0',
      bid1Price: json['bid1Price'] as String? ?? '0',
      bid1Size: json['bid1Size'] as String? ?? '0',
      ask1Price: json['ask1Price'] as String? ?? '0',
      ask1Size: json['ask1Size'] as String? ?? '0',
    );
  }

  /// Converts Ticker to JSON
  Map<String, dynamic> toJson() {
    return {
      'symbol': symbol,
      'lastPrice': lastPrice,
      'prevPrice24h': prevPrice24h,
      'price24hPcnt': price24hPcnt,
      'highPrice24h': highPrice24h,
      'lowPrice24h': lowPrice24h,
      'turnover24h': turnover24h,
      'volume24h': volume24h,
      'bid1Price': bid1Price,
      'bid1Size': bid1Size,
      'ask1Price': ask1Price,
      'ask1Size': ask1Size,
    };
  }

  /// Gets last price as double
  double get lastPriceAsDouble => double.tryParse(lastPrice) ?? 0.0;

  /// Gets 24h price change percentage as double
  double get price24hPcntAsDouble => double.tryParse(price24hPcnt) ?? 0.0;

  /// Gets 24h price change percentage (as actual percentage, not decimal)
  double get price24hPcntAsPercent => price24hPcntAsDouble * 100;

  /// Returns true if price is going up (positive change)
  bool get isPriceIncreasing => price24hPcntAsDouble > 0;

  /// Returns true if price is going down (negative change)
  bool get isPriceDecreasing => price24hPcntAsDouble < 0;

  /// Gets the mid price (average of bid and ask)
  double get midPrice {
    final bid = double.tryParse(bid1Price) ?? 0.0;
    final ask = double.tryParse(ask1Price) ?? 0.0;
    return (bid + ask) / 2;
  }

  /// Gets the spread (difference between ask and bid)
  double get spread {
    final bid = double.tryParse(bid1Price) ?? 0.0;
    final ask = double.tryParse(ask1Price) ?? 0.0;
    return ask - bid;
  }

  /// Gets the spread as percentage
  double get spreadPercent {
    final mid = midPrice;
    if (mid == 0) return 0.0;
    return (spread / mid) * 100;
  }

  @override
  String toString() =>
      'Ticker(symbol: $symbol, lastPrice: $lastPrice, change24h: ${price24hPcntAsPercent.toStringAsFixed(2)}%)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Ticker &&
          runtimeType == other.runtimeType &&
          symbol == other.symbol &&
          lastPrice == other.lastPrice;

  @override
  int get hashCode => symbol.hashCode ^ lastPrice.hashCode;
}
