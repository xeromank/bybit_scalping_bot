/// Hyperdash Top Trader Model
///
/// Represents a top trader from Hyperdash API
class HyperdashTrader {
  final String address;
  final double accountValue;
  final MainPosition? mainPosition;
  final double? directionBias;
  final double perpDayPnl;
  final double perpWeekPnl;
  final double perpMonthPnl;
  final double perpAlltimePnl;

  HyperdashTrader({
    required this.address,
    required this.accountValue,
    this.mainPosition,
    this.directionBias,
    required this.perpDayPnl,
    required this.perpWeekPnl,
    required this.perpMonthPnl,
    required this.perpAlltimePnl,
  });

  factory HyperdashTrader.fromJson(Map<String, dynamic> json) {
    return HyperdashTrader(
      address: json['address'] ?? '',
      accountValue: (json['account_value'] ?? 0).toDouble(),
      mainPosition: json['main_position'] != null
          ? MainPosition.fromJson(json['main_position'])
          : null,
      directionBias: json['direction_bias'] != null
          ? (json['direction_bias']).toDouble()
          : null,
      perpDayPnl: (json['perp_day_pnl'] ?? 0).toDouble(),
      perpWeekPnl: (json['perp_week_pnl'] ?? 0).toDouble(),
      perpMonthPnl: (json['perp_month_pnl'] ?? 0).toDouble(),
      perpAlltimePnl: (json['perp_alltime_pnl'] ?? 0).toDouble(),
    );
  }

  /// Get formatted address (0x...1234)
  String get shortAddress {
    if (address.length <= 10) return address;
    return '${address.substring(0, 6)}...${address.substring(address.length - 4)}';
  }

  /// Get formatted account value
  String get formattedAccountValue {
    if (accountValue >= 1000000) {
      return '\$${(accountValue / 1000000).toStringAsFixed(2)}M';
    } else if (accountValue >= 1000) {
      return '\$${(accountValue / 1000).toStringAsFixed(2)}K';
    }
    return '\$${accountValue.toStringAsFixed(2)}';
  }

  /// Get formatted PnL
  String get formattedMonthPnl {
    final sign = perpMonthPnl >= 0 ? '+' : '';
    if (perpMonthPnl.abs() >= 1000000) {
      return '$sign\$${(perpMonthPnl / 1000000).toStringAsFixed(2)}M';
    } else if (perpMonthPnl.abs() >= 1000) {
      return '$sign\$${(perpMonthPnl / 1000).toStringAsFixed(2)}K';
    }
    return '$sign\$${perpMonthPnl.toStringAsFixed(2)}';
  }

  /// Get formatted all-time PnL
  String get formattedAlltimePnl {
    final sign = perpAlltimePnl >= 0 ? '+' : '';
    if (perpAlltimePnl.abs() >= 1000000) {
      return '$sign\$${(perpAlltimePnl / 1000000).toStringAsFixed(2)}M';
    } else if (perpAlltimePnl.abs() >= 1000) {
      return '$sign\$${(perpAlltimePnl / 1000).toStringAsFixed(2)}K';
    }
    return '$sign\$${perpAlltimePnl.toStringAsFixed(2)}';
  }

  /// Get PnL color
  bool get isMonthPnlPositive => perpMonthPnl >= 0;

  /// Get main position description
  String get mainPositionDescription {
    if (mainPosition == null || mainPosition!.coin.isEmpty) {
      return 'No position';
    }
    return '${mainPosition!.coin} ${mainPosition!.side ?? ''}';
  }

  @override
  String toString() {
    return 'HyperdashTrader(address: $shortAddress, accountValue: $formattedAccountValue, monthPnl: $formattedMonthPnl)';
  }
}

/// Main Position Model
class MainPosition {
  final String coin;
  final double value;
  final String? side;

  MainPosition({
    required this.coin,
    required this.value,
    this.side,
  });

  factory MainPosition.fromJson(Map<String, dynamic> json) {
    return MainPosition(
      coin: json['coin'] ?? '',
      value: (json['value'] ?? 0).toDouble(),
      side: json['side'],
    );
  }

  /// Get formatted position value
  String get formattedValue {
    if (value >= 1000000) {
      return '\$${(value / 1000000).toStringAsFixed(2)}M';
    } else if (value >= 1000) {
      return '\$${(value / 1000).toStringAsFixed(2)}K';
    }
    return '\$${value.toStringAsFixed(2)}';
  }

  bool get hasPosition => coin.isNotEmpty && value > 0;
}
