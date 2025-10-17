/// Represents a trading order
///
/// Responsibility: Encapsulate order data
///
/// This immutable value object represents an order in the trading system.
class Order {
  final String orderId;
  final String orderLinkId;
  final String symbol;
  final String side; // Buy or Sell
  final String orderType; // Market, Limit, etc.
  final String price;
  final String qty;
  final String? cumExecQty;
  final String? cumExecValue;
  final String? cumExecFee;
  final String orderStatus; // New, PartiallyFilled, Filled, Cancelled, etc.
  final String timeInForce;
  final bool reduceOnly;
  final bool closeOnTrigger;
  final DateTime? createdTime;
  final DateTime? updatedTime;

  const Order({
    required this.orderId,
    required this.orderLinkId,
    required this.symbol,
    required this.side,
    required this.orderType,
    required this.price,
    required this.qty,
    this.cumExecQty,
    this.cumExecValue,
    this.cumExecFee,
    required this.orderStatus,
    required this.timeInForce,
    required this.reduceOnly,
    required this.closeOnTrigger,
    this.createdTime,
    this.updatedTime,
  });

  /// Creates Order from API response
  factory Order.fromJson(Map<String, dynamic> json) {
    return Order(
      orderId: json['orderId'] as String,
      orderLinkId: json['orderLinkId'] as String? ?? '',
      symbol: json['symbol'] as String,
      side: json['side'] as String,
      orderType: json['orderType'] as String,
      price: json['price'] as String,
      qty: json['qty'] as String,
      cumExecQty: json['cumExecQty'] as String?,
      cumExecValue: json['cumExecValue'] as String?,
      cumExecFee: json['cumExecFee'] as String?,
      orderStatus: json['orderStatus'] as String,
      timeInForce: json['timeInForce'] as String,
      reduceOnly: json['reduceOnly'] as bool? ?? false,
      closeOnTrigger: json['closeOnTrigger'] as bool? ?? false,
      createdTime: json['createdTime'] != null
          ? DateTime.fromMillisecondsSinceEpoch(
              int.parse(json['createdTime'].toString()))
          : null,
      updatedTime: json['updatedTime'] != null
          ? DateTime.fromMillisecondsSinceEpoch(
              int.parse(json['updatedTime'].toString()))
          : null,
    );
  }

  /// Converts Order to JSON
  Map<String, dynamic> toJson() {
    return {
      'orderId': orderId,
      'orderLinkId': orderLinkId,
      'symbol': symbol,
      'side': side,
      'orderType': orderType,
      'price': price,
      'qty': qty,
      if (cumExecQty != null) 'cumExecQty': cumExecQty,
      if (cumExecValue != null) 'cumExecValue': cumExecValue,
      if (cumExecFee != null) 'cumExecFee': cumExecFee,
      'orderStatus': orderStatus,
      'timeInForce': timeInForce,
      'reduceOnly': reduceOnly,
      'closeOnTrigger': closeOnTrigger,
      if (createdTime != null)
        'createdTime': createdTime!.millisecondsSinceEpoch,
      if (updatedTime != null)
        'updatedTime': updatedTime!.millisecondsSinceEpoch,
    };
  }

  /// Returns true if this is a buy order
  bool get isBuy => side == 'Buy';

  /// Returns true if this is a sell order
  bool get isSell => side == 'Sell';

  /// Returns true if this is a market order
  bool get isMarket => orderType == 'Market';

  /// Returns true if this is a limit order
  bool get isLimit => orderType == 'Limit';

  /// Returns true if order is pending
  bool get isPending => orderStatus == 'New' || orderStatus == 'PartiallyFilled';

  /// Returns true if order is filled
  bool get isFilled => orderStatus == 'Filled';

  /// Returns true if order is cancelled
  bool get isCancelled => orderStatus == 'Cancelled' || orderStatus == 'Rejected';

  /// Returns true if order is active
  bool get isActive => isPending;

  /// Gets price as double
  double get priceAsDouble => double.tryParse(price) ?? 0.0;

  /// Gets quantity as double
  double get qtyAsDouble => double.tryParse(qty) ?? 0.0;

  /// Gets cumulative executed quantity as double
  double get cumExecQtyAsDouble => double.tryParse(cumExecQty ?? '0') ?? 0.0;

  /// Gets cumulative executed value as double
  double get cumExecValueAsDouble => double.tryParse(cumExecValue ?? '0') ?? 0.0;

  /// Gets cumulative executed fee as double
  double get cumExecFeeAsDouble => double.tryParse(cumExecFee ?? '0') ?? 0.0;

  /// Calculates fill percentage
  double get fillPercent {
    if (qtyAsDouble == 0) return 0.0;
    return (cumExecQtyAsDouble / qtyAsDouble) * 100;
  }

  /// Gets average fill price
  double get avgFillPrice {
    if (cumExecQtyAsDouble == 0) return 0.0;
    return cumExecValueAsDouble / cumExecQtyAsDouble;
  }

  /// Creates a copy with updated fields
  Order copyWith({
    String? orderId,
    String? orderLinkId,
    String? symbol,
    String? side,
    String? orderType,
    String? price,
    String? qty,
    String? cumExecQty,
    String? cumExecValue,
    String? cumExecFee,
    String? orderStatus,
    String? timeInForce,
    bool? reduceOnly,
    bool? closeOnTrigger,
    DateTime? createdTime,
    DateTime? updatedTime,
  }) {
    return Order(
      orderId: orderId ?? this.orderId,
      orderLinkId: orderLinkId ?? this.orderLinkId,
      symbol: symbol ?? this.symbol,
      side: side ?? this.side,
      orderType: orderType ?? this.orderType,
      price: price ?? this.price,
      qty: qty ?? this.qty,
      cumExecQty: cumExecQty ?? this.cumExecQty,
      cumExecValue: cumExecValue ?? this.cumExecValue,
      cumExecFee: cumExecFee ?? this.cumExecFee,
      orderStatus: orderStatus ?? this.orderStatus,
      timeInForce: timeInForce ?? this.timeInForce,
      reduceOnly: reduceOnly ?? this.reduceOnly,
      closeOnTrigger: closeOnTrigger ?? this.closeOnTrigger,
      createdTime: createdTime ?? this.createdTime,
      updatedTime: updatedTime ?? this.updatedTime,
    );
  }

  @override
  String toString() =>
      'Order(orderId: $orderId, symbol: $symbol, side: $side, type: $orderType, status: $orderStatus)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Order &&
          runtimeType == other.runtimeType &&
          orderId == other.orderId;

  @override
  int get hashCode => orderId.hashCode;
}

/// Request object for creating an order
class OrderRequest {
  final String symbol;
  final String side;
  final String orderType;
  final String? qty; // Quantity in coins (e.g., 0.1 BTC) - use for reduce-only or when qty is known
  final String? orderValue; // Order value in USDT (e.g., 100 USDT) - use for market buy/sell
  final String? price;
  final String? timeInForce;
  final int positionIdx;
  final bool reduceOnly;
  final String? orderLinkId;
  final String? takeProfit; // TP price
  final String? stopLoss; // SL price
  final String? tpTriggerBy; // TP trigger price type (default: LastPrice)
  final String? slTriggerBy; // SL trigger price type (default: LastPrice)

  const OrderRequest({
    required this.symbol,
    required this.side,
    required this.orderType,
    this.qty,
    this.orderValue,
    this.price,
    this.timeInForce = 'GTC',
    this.positionIdx = 0,
    this.reduceOnly = false,
    this.orderLinkId,
    this.takeProfit,
    this.stopLoss,
    this.tpTriggerBy,
    this.slTriggerBy,
  }) : assert(qty != null || orderValue != null, 'Either qty or orderValue must be provided');

  /// Converts OrderRequest to JSON
  Map<String, dynamic> toJson() {
    return {
      'category': 'linear',
      'symbol': symbol,
      'side': side,
      'orderType': orderType,
      if (qty != null) 'qty': qty,
      if (orderValue != null) 'orderValue': orderValue,
      if (price != null) 'price': price,
      if (timeInForce != null) 'timeInForce': timeInForce,
      'positionIdx': positionIdx,
      'reduceOnly': reduceOnly,
      if (orderLinkId != null) 'orderLinkId': orderLinkId,
      if (takeProfit != null) 'takeProfit': takeProfit,
      if (stopLoss != null) 'stopLoss': stopLoss,
      if (tpTriggerBy != null) 'tpTriggerBy': tpTriggerBy,
      if (slTriggerBy != null) 'slTriggerBy': slTriggerBy,
    };
  }

  @override
  String toString() =>
      'OrderRequest(symbol: $symbol, side: $side, type: $orderType, ${qty != null ? "qty: $qty" : "orderValue: $orderValue"})';
}
