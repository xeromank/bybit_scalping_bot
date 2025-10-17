/// Represents a trading position
///
/// Responsibility: Encapsulate position data
///
/// This immutable value object represents a position in a trading account.
class Position {
  final String symbol;
  final String side; // Buy (Long) or Sell (Short)
  final String size;
  final String avgPrice;
  final String markPrice;
  final String liqPrice;
  final String positionValue;
  final String unrealisedPnl;
  final String cumRealisedPnl;
  final String leverage;
  final int positionIdx;
  final String positionIM; // Position Initial Margin (증거금)
  final String? takeProfit;
  final String? stopLoss;
  final String? trailingStop;
  final DateTime? createdTime;
  final DateTime? updatedTime;

  const Position({
    required this.symbol,
    required this.side,
    required this.size,
    required this.avgPrice,
    required this.markPrice,
    required this.liqPrice,
    required this.positionValue,
    required this.unrealisedPnl,
    required this.cumRealisedPnl,
    required this.leverage,
    required this.positionIdx,
    required this.positionIM,
    this.takeProfit,
    this.stopLoss,
    this.trailingStop,
    this.createdTime,
    this.updatedTime,
  });

  /// Creates Position from API response
  factory Position.fromJson(Map<String, dynamic> json) {
    // Handle both API (avgPrice) and WebSocket (entryPrice) formats
    final avgPrice = (json['avgPrice'] ?? json['entryPrice'])?.toString() ?? '0';

    // Handle takeProfit, stopLoss, trailingStop which can be "0", "", or null
    String? takeProfit = json['takeProfit']?.toString();
    if (takeProfit == '0' || takeProfit == '' || takeProfit == null) takeProfit = null;

    String? stopLoss = json['stopLoss']?.toString();
    if (stopLoss == '0' || stopLoss == '' || stopLoss == null) stopLoss = null;

    String? trailingStop = json['trailingStop']?.toString();
    if (trailingStop == '0' || trailingStop == '' || trailingStop == null) trailingStop = null;

    return Position(
      symbol: json['symbol']?.toString() ?? '',
      side: json['side']?.toString() ?? 'Buy',
      size: json['size']?.toString() ?? '0',
      avgPrice: avgPrice,
      markPrice: json['markPrice']?.toString() ?? '0',
      liqPrice: json['liqPrice']?.toString() ?? '0',
      positionValue: json['positionValue']?.toString() ?? '0',
      unrealisedPnl: json['unrealisedPnl']?.toString() ?? '0',
      cumRealisedPnl: json['cumRealisedPnl']?.toString() ?? '0',
      leverage: json['leverage']?.toString() ?? '1',
      positionIdx: (json['positionIdx'] as num?)?.toInt() ?? 0,
      positionIM: json['positionIM']?.toString() ?? '0',
      takeProfit: takeProfit,
      stopLoss: stopLoss,
      trailingStop: trailingStop,
      createdTime: json['createdTime'] != null && json['createdTime'].toString().isNotEmpty
          ? DateTime.fromMillisecondsSinceEpoch(
              int.parse(json['createdTime'].toString()))
          : null,
      updatedTime: json['updatedTime'] != null && json['updatedTime'].toString().isNotEmpty
          ? DateTime.fromMillisecondsSinceEpoch(
              int.parse(json['updatedTime'].toString()))
          : null,
    );
  }

  /// Converts Position to JSON
  Map<String, dynamic> toJson() {
    return {
      'symbol': symbol,
      'side': side,
      'size': size,
      'avgPrice': avgPrice,
      'markPrice': markPrice,
      'liqPrice': liqPrice,
      'positionValue': positionValue,
      'unrealisedPnl': unrealisedPnl,
      'cumRealisedPnl': cumRealisedPnl,
      'leverage': leverage,
      'positionIdx': positionIdx,
      'positionIM': positionIM,
      if (takeProfit != null) 'takeProfit': takeProfit,
      if (stopLoss != null) 'stopLoss': stopLoss,
      if (trailingStop != null) 'trailingStop': trailingStop,
      if (createdTime != null)
        'createdTime': createdTime!.millisecondsSinceEpoch,
      if (updatedTime != null)
        'updatedTime': updatedTime!.millisecondsSinceEpoch,
    };
  }

  /// Returns true if this is a long position
  bool get isLong => side == 'Buy';

  /// Returns true if this is a short position
  bool get isShort => side == 'Sell';

  /// Returns true if position is open (has size)
  bool get isOpen => sizeAsDouble > 0;

  /// Returns true if position is closed
  bool get isClosed => !isOpen;

  /// Gets size as double
  double get sizeAsDouble => double.tryParse(size) ?? 0.0;

  /// Gets average entry price as double
  double get avgPriceAsDouble => double.tryParse(avgPrice) ?? 0.0;

  /// Gets mark price as double
  double get markPriceAsDouble => double.tryParse(markPrice) ?? 0.0;

  /// Gets unrealised PnL as double
  double get unrealisedPnlAsDouble => double.tryParse(unrealisedPnl) ?? 0.0;

  /// Gets cumulative realised PnL as double
  double get cumRealisedPnlAsDouble => double.tryParse(cumRealisedPnl) ?? 0.0;

  /// Gets position value as double
  double get positionValueAsDouble => double.tryParse(positionValue) ?? 0.0;

  /// Gets leverage as double
  double get leverageAsDouble => double.tryParse(leverage) ?? 1.0;

  /// Gets position IM (Initial Margin) as double
  double get positionIMAsDouble => double.tryParse(positionIM) ?? 0.0;

  /// Calculates real-time unrealised PnL based on current markPrice
  /// unrealisedPnl = (markPrice - avgPrice) × size × (Long이면 1, Short면 -1)
  double get realtimeUnrealisedPnl {
    if (sizeAsDouble == 0 || avgPriceAsDouble == 0) return 0.0;

    final priceDiff = markPriceAsDouble - avgPriceAsDouble;
    final direction = isLong ? 1.0 : -1.0;

    return priceDiff * sizeAsDouble * direction;
  }

  /// Calculates PnL percentage (ROE - Return on Equity) using positionIM
  /// ROE% = (unrealisedPnl / positionIM) × 100
  double get pnlPercent {
    if (positionIMAsDouble == 0) return 0.0;

    // Use real-time calculated unrealisedPnl
    return (realtimeUnrealisedPnl / positionIMAsDouble) * 100;
  }

  /// Returns true if position is in profit
  bool get isInProfit => realtimeUnrealisedPnl > 0;

  /// Returns true if position is in loss
  bool get isInLoss => realtimeUnrealisedPnl < 0;

  /// Gets the price change from entry
  double get priceChangePercent {
    if (avgPriceAsDouble == 0) return 0.0;
    final change = markPriceAsDouble - avgPriceAsDouble;
    return (change / avgPriceAsDouble) * 100;
  }

  /// Creates a copy with updated fields
  Position copyWith({
    String? symbol,
    String? side,
    String? size,
    String? avgPrice,
    String? markPrice,
    String? liqPrice,
    String? positionValue,
    String? unrealisedPnl,
    String? cumRealisedPnl,
    String? leverage,
    int? positionIdx,
    String? positionIM,
    String? takeProfit,
    String? stopLoss,
    String? trailingStop,
    DateTime? createdTime,
    DateTime? updatedTime,
  }) {
    return Position(
      symbol: symbol ?? this.symbol,
      side: side ?? this.side,
      size: size ?? this.size,
      avgPrice: avgPrice ?? this.avgPrice,
      markPrice: markPrice ?? this.markPrice,
      liqPrice: liqPrice ?? this.liqPrice,
      positionValue: positionValue ?? this.positionValue,
      unrealisedPnl: unrealisedPnl ?? this.unrealisedPnl,
      cumRealisedPnl: cumRealisedPnl ?? this.cumRealisedPnl,
      leverage: leverage ?? this.leverage,
      positionIdx: positionIdx ?? this.positionIdx,
      positionIM: positionIM ?? this.positionIM,
      takeProfit: takeProfit ?? this.takeProfit,
      stopLoss: stopLoss ?? this.stopLoss,
      trailingStop: trailingStop ?? this.trailingStop,
      createdTime: createdTime ?? this.createdTime,
      updatedTime: updatedTime ?? this.updatedTime,
    );
  }

  @override
  String toString() =>
      'Position(symbol: $symbol, side: $side, size: $size, avgPrice: $avgPrice, unrealisedPnl: $unrealisedPnl)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Position &&
          runtimeType == other.runtimeType &&
          symbol == other.symbol &&
          side == other.side &&
          size == other.size &&
          avgPrice == other.avgPrice;

  @override
  int get hashCode =>
      symbol.hashCode ^ side.hashCode ^ size.hashCode ^ avgPrice.hashCode;
}
