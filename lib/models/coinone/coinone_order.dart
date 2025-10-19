/// Coinone order model
///
/// Represents an order on Coinone exchange
/// Reference: https://docs.coinone.co.kr/reference/place-order
class CoinoneOrder {
  final String orderId; // Coinone's order ID
  final String? userOrderId; // User-defined order ID (UUID)
  final String quoteCurrency; // e.g., "KRW"
  final String targetCurrency; // e.g., "XRP"
  final String type; // "limit" or "market"
  final String side; // "buy" or "sell"
  final double price; // Order price (0 for market orders)
  final double quantity; // Order quantity
  final double filledQuantity; // Filled quantity
  final double remainingQuantity; // Remaining quantity
  final String status; // "placed", "filled", "cancelled", "partial_filled"
  final DateTime createdAt;
  final DateTime? updatedAt;

  const CoinoneOrder({
    required this.orderId,
    this.userOrderId,
    required this.quoteCurrency,
    required this.targetCurrency,
    required this.type,
    required this.side,
    required this.price,
    required this.quantity,
    required this.filledQuantity,
    required this.remainingQuantity,
    required this.status,
    required this.createdAt,
    this.updatedAt,
  });

  /// Create from API JSON response
  factory CoinoneOrder.fromJson(Map<String, dynamic> json) {
    return CoinoneOrder(
      orderId: json['order_id'].toString(),
      userOrderId: json['user_order_id']?.toString(),
      quoteCurrency: json['quote_currency']?.toString() ?? 'KRW',
      targetCurrency: json['target_currency']?.toString() ?? '',
      type: json['type']?.toString() ?? 'limit',
      side: json['side']?.toString() ?? 'buy',
      price: double.parse(json['price']?.toString() ?? '0'),
      quantity: double.parse(json['qty']?.toString() ?? '0'),
      filledQuantity: double.parse(json['filled_qty']?.toString() ?? '0'),
      remainingQuantity: double.parse(json['remain_qty']?.toString() ?? '0'),
      status: json['status']?.toString() ?? 'unknown',
      createdAt: DateTime.parse(json['created_at'].toString()),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'].toString())
          : null,
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'order_id': orderId,
      'user_order_id': userOrderId,
      'quote_currency': quoteCurrency,
      'target_currency': targetCurrency,
      'type': type,
      'side': side,
      'price': price.toString(),
      'qty': quantity.toString(),
      'filled_qty': filledQuantity.toString(),
      'remain_qty': remainingQuantity.toString(),
      'status': status,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  /// Get trading pair symbol (e.g., "XRP-KRW")
  String get symbol => '$targetCurrency-$quoteCurrency';

  /// Check if order is completely filled
  bool get isFilled => status == 'filled' || remainingQuantity == 0;

  /// Check if order is cancelled
  bool get isCancelled => status == 'cancelled';

  /// Check if order is active
  bool get isActive => status == 'placed' || status == 'partial_filled';

  /// Get fill percentage
  double get fillPercentage {
    if (quantity == 0) return 0;
    return (filledQuantity / quantity) * 100;
  }

  @override
  String toString() {
    return 'CoinoneOrder(id: $orderId, symbol: $symbol, side: $side, qty: $quantity, status: $status)';
  }
}

/// Request model for placing an order
class PlaceOrderRequest {
  final String quoteCurrency;
  final String targetCurrency;
  final String type; // "limit" or "market"
  final String side; // "buy" or "sell"
  final double? price; // Required for limit orders
  final double? quantity; // Coin quantity (for limit/market sell)
  final double? amount; // KRW amount (for market buy ONLY)
  final String userOrderId; // UUID

  const PlaceOrderRequest({
    required this.quoteCurrency,
    required this.targetCurrency,
    required this.type,
    required this.side,
    this.price,
    this.quantity,
    this.amount,
    required this.userOrderId,
  });

  /// Convert to API request JSON
  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'quote_currency': quoteCurrency,
      'target_currency': targetCurrency,
      'type': type.toUpperCase(), // Coinone API requires uppercase (LIMIT, MARKET)
      'side': side.toUpperCase(), // Coinone API requires uppercase (BUY, SELL)
      'user_order_id': userOrderId,
    };

    // For market buy: use 'amount' (KRW amount)
    if (type.toLowerCase() == 'market' && side.toLowerCase() == 'buy') {
      if (amount != null) {
        json['amount'] = amount.toString();
      }
    } else {
      // For limit orders or market sell: use 'qty' (coin quantity)
      if (quantity != null) {
        json['qty'] = quantity.toString();
      }
    }

    if (price != null && type.toLowerCase() == 'limit') {
      json['price'] = price.toString();
      json['post_only'] = false; // Allow order to match immediately
    }

    return json;
  }

  @override
  String toString() {
    return 'PlaceOrderRequest(symbol: $targetCurrency-$quoteCurrency, side: $side, type: $type, qty: $quantity)';
  }
}
