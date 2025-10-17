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
    this.takeProfit,
    this.stopLoss,
    this.trailingStop,
    this.createdTime,
    this.updatedTime,
  });

  /// Creates Position from API response
  factory Position.fromJson(Map<String, dynamic> json) {
    return Position(
      symbol: json['symbol'] as String,
      side: json['side'] as String,
      size: json['size'] as String,
      avgPrice: json['avgPrice'] as String,
      markPrice: json['markPrice'] as String? ?? '0',
      liqPrice: json['liqPrice'] as String? ?? '0',
      positionValue: json['positionValue'] as String,
      unrealisedPnl: json['unrealisedPnl'] as String,
      cumRealisedPnl: json['cumRealisedPnl'] as String? ?? '0',
      leverage: json['leverage'] as String,
      positionIdx: json['positionIdx'] as int,
      takeProfit: json['takeProfit'] as String?,
      stopLoss: json['stopLoss'] as String?,
      trailingStop: json['trailingStop'] as String?,
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

  /// Calculates PnL percentage
  double get pnlPercent {
    if (positionValueAsDouble == 0) return 0.0;
    return (unrealisedPnlAsDouble / positionValueAsDouble) * 100;
  }

  /// Returns true if position is in profit
  bool get isInProfit => unrealisedPnlAsDouble > 0;

  /// Returns true if position is in loss
  bool get isInLoss => unrealisedPnlAsDouble < 0;

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
