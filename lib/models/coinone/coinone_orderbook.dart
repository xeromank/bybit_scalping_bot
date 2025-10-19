/// Coinone orderbook entry (bid or ask)
class OrderbookEntry {
  final double price;
  final double quantity;

  const OrderbookEntry({
    required this.price,
    required this.quantity,
  });

  /// Create from JSON array [price, quantity]
  factory OrderbookEntry.fromJson(List<dynamic> json) {
    return OrderbookEntry(
      price: double.parse(json[0].toString()),
      quantity: double.parse(json[1].toString()),
    );
  }

  /// Convert to JSON
  List<dynamic> toJson() {
    return [price.toString(), quantity.toString()];
  }

  /// Get total value (price * quantity)
  double get value => price * quantity;

  @override
  String toString() {
    return 'OrderbookEntry(price: $price, qty: $quantity)';
  }
}

/// Coinone orderbook model
///
/// Represents real-time orderbook data from Coinone WebSocket
/// Reference: https://docs.coinone.co.kr/reference/public-websocket-orderbook
class CoinoneOrderbook {
  final String quoteCurrency; // e.g., "KRW"
  final String targetCurrency; // e.g., "XRP"
  final List<OrderbookEntry> bids; // 매수 호가 (가격 높은 순)
  final List<OrderbookEntry> asks; // 매도 호가 (가격 낮은 순)
  final DateTime timestamp;

  const CoinoneOrderbook({
    required this.quoteCurrency,
    required this.targetCurrency,
    required this.bids,
    required this.asks,
    required this.timestamp,
  });

  /// Create from WebSocket JSON message
  factory CoinoneOrderbook.fromJson(Map<String, dynamic> json) {
    final bidsJson = json['bid'] as List<dynamic>? ?? [];
    final asksJson = json['ask'] as List<dynamic>? ?? [];

    return CoinoneOrderbook(
      quoteCurrency: json['quote_currency']?.toString() ?? 'KRW',
      targetCurrency: json['target_currency']?.toString() ?? '',
      bids: bidsJson
          .map((e) => OrderbookEntry.fromJson(e as List<dynamic>))
          .toList(),
      asks: asksJson
          .map((e) => OrderbookEntry.fromJson(e as List<dynamic>))
          .toList(),
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
      'bid': bids.map((e) => e.toJson()).toList(),
      'ask': asks.map((e) => e.toJson()).toList(),
      'timestamp': timestamp.millisecondsSinceEpoch,
    };
  }

  /// Get trading pair symbol (e.g., "XRP-KRW")
  String get symbol => '$targetCurrency-$quoteCurrency';

  /// Get best bid price (highest buy price)
  double? get bestBid => bids.isNotEmpty ? bids.first.price : null;

  /// Get best ask price (lowest sell price)
  double? get bestAsk => asks.isNotEmpty ? asks.first.price : null;

  /// Get spread (best ask - best bid)
  double? get spread {
    if (bestBid == null || bestAsk == null) return null;
    return bestAsk! - bestBid!;
  }

  /// Get mid price
  double? get midPrice {
    if (bestBid == null || bestAsk == null) return null;
    return (bestBid! + bestAsk!) / 2;
  }

  /// Calculate slippage for market buy order
  ///
  /// Returns the average price you would get for buying [quantity] amount
  /// Returns null if orderbook depth is insufficient
  double? calculateBuySlippage(double quantity) {
    if (asks.isEmpty) return null;

    double remainingQty = quantity;
    double totalCost = 0;

    for (final ask in asks) {
      if (remainingQty <= 0) break;

      final qtyToFill = remainingQty > ask.quantity ? ask.quantity : remainingQty;
      totalCost += qtyToFill * ask.price;
      remainingQty -= qtyToFill;
    }

    // Not enough depth
    if (remainingQty > 0) return null;

    return totalCost / quantity; // Average price
  }

  /// Calculate slippage for market sell order
  ///
  /// Returns the average price you would get for selling [quantity] amount
  /// Returns null if orderbook depth is insufficient
  double? calculateSellSlippage(double quantity) {
    if (bids.isEmpty) return null;

    double remainingQty = quantity;
    double totalRevenue = 0;

    for (final bid in bids) {
      if (remainingQty <= 0) break;

      final qtyToFill = remainingQty > bid.quantity ? bid.quantity : remainingQty;
      totalRevenue += qtyToFill * bid.price;
      remainingQty -= qtyToFill;
    }

    // Not enough depth
    if (remainingQty > 0) return null;

    return totalRevenue / quantity; // Average price
  }

  /// Get total bid volume (total quantity of all bids)
  double get totalBidVolume {
    return bids.fold(0, (sum, bid) => sum + bid.quantity);
  }

  /// Get total ask volume (total quantity of all asks)
  double get totalAskVolume {
    return asks.fold(0, (sum, ask) => sum + ask.quantity);
  }

  /// Get bid/ask ratio (indication of market pressure)
  double get bidAskRatio {
    final askVol = totalAskVolume;
    if (askVol == 0) return 0;
    return totalBidVolume / askVol;
  }

  @override
  String toString() {
    return 'CoinoneOrderbook(symbol: $symbol, bestBid: $bestBid, bestAsk: $bestAsk, spread: $spread)';
  }
}
