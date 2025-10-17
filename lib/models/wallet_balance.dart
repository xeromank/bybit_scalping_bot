/// Represents a wallet balance for a specific coin
///
/// Responsibility: Encapsulate wallet balance data
///
/// This immutable value object represents the wallet balance information
/// returned by the Bybit API.
class WalletBalance {
  final String accountType;
  final List<CoinBalance> coins;
  final String totalEquity;
  final String totalWalletBalance;
  final String totalMarginBalance;
  final String totalAvailableBalance;

  const WalletBalance({
    required this.accountType,
    required this.coins,
    required this.totalEquity,
    required this.totalWalletBalance,
    required this.totalMarginBalance,
    required this.totalAvailableBalance,
  });

  /// Creates WalletBalance from API response
  factory WalletBalance.fromJson(Map<String, dynamic> json) {
    final list = json['list'] as List<dynamic>;
    final account = list.isNotEmpty ? list[0] : {};

    final coinList = account['coin'] as List<dynamic>? ?? [];

    return WalletBalance(
      accountType: json['accountType'] as String? ?? account['accountType'] as String? ?? '',
      coins: coinList.map((coin) => CoinBalance.fromJson(coin)).toList(),
      totalEquity: account['totalEquity'] as String? ?? '0',
      totalWalletBalance: account['totalWalletBalance'] as String? ?? '0',
      totalMarginBalance: account['totalMarginBalance'] as String? ?? '0',
      totalAvailableBalance: account['totalAvailableBalance'] as String? ?? '0',
    );
  }

  /// Converts WalletBalance to JSON
  Map<String, dynamic> toJson() {
    return {
      'accountType': accountType,
      'coins': coins.map((coin) => coin.toJson()).toList(),
      'totalEquity': totalEquity,
      'totalWalletBalance': totalWalletBalance,
      'totalMarginBalance': totalMarginBalance,
      'totalAvailableBalance': totalAvailableBalance,
    };
  }

  /// Gets balance for a specific coin
  CoinBalance? getCoinBalance(String coinSymbol) {
    try {
      return coins.firstWhere((coin) => coin.coin == coinSymbol);
    } catch (e) {
      return null;
    }
  }

  /// Gets USDT balance (most common for trading)
  CoinBalance? get usdtBalance => getCoinBalance('USDT');

  @override
  String toString() =>
      'WalletBalance(accountType: $accountType, totalEquity: $totalEquity)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WalletBalance &&
          runtimeType == other.runtimeType &&
          accountType == other.accountType &&
          totalEquity == other.totalEquity;

  @override
  int get hashCode => accountType.hashCode ^ totalEquity.hashCode;
}

/// Represents balance information for a specific coin
class CoinBalance {
  final String coin;
  final String equity;
  final String walletBalance;
  final String availableToWithdraw;
  final String totalOrderIM;
  final String totalPositionIM;
  final String totalPositionMM;
  final String unrealisedPnl;
  final String cumRealisedPnl;

  const CoinBalance({
    required this.coin,
    required this.equity,
    required this.walletBalance,
    required this.availableToWithdraw,
    required this.totalOrderIM,
    required this.totalPositionIM,
    required this.totalPositionMM,
    required this.unrealisedPnl,
    required this.cumRealisedPnl,
  });

  /// Creates CoinBalance from JSON
  factory CoinBalance.fromJson(Map<String, dynamic> json) {
    return CoinBalance(
      coin: json['coin'] as String,
      equity: json['equity'] as String? ?? '0',
      walletBalance: json['walletBalance'] as String? ?? '0',
      availableToWithdraw: json['availableToWithdraw'] as String? ?? '0',
      totalOrderIM: json['totalOrderIM'] as String? ?? '0',
      totalPositionIM: json['totalPositionIM'] as String? ?? '0',
      totalPositionMM: json['totalPositionMM'] as String? ?? '0',
      unrealisedPnl: json['unrealisedPnl'] as String? ?? '0',
      cumRealisedPnl: json['cumRealisedPnl'] as String? ?? '0',
    );
  }

  /// Converts CoinBalance to JSON
  Map<String, dynamic> toJson() {
    return {
      'coin': coin,
      'equity': equity,
      'walletBalance': walletBalance,
      'availableToWithdraw': availableToWithdraw,
      'totalOrderIM': totalOrderIM,
      'totalPositionIM': totalPositionIM,
      'totalPositionMM': totalPositionMM,
      'unrealisedPnl': unrealisedPnl,
      'cumRealisedPnl': cumRealisedPnl,
    };
  }

  /// Gets wallet balance as double
  double get walletBalanceAsDouble => double.tryParse(walletBalance) ?? 0.0;

  /// Gets unrealised PnL as double
  double get unrealisedPnlAsDouble => double.tryParse(unrealisedPnl) ?? 0.0;

  /// Gets equity as double (현재 잔고 가치)
  double get equityAsDouble => double.tryParse(equity) ?? 0.0;

  /// Gets total position IM as double (포지션에 투여한 금액)
  double get totalPositionIMAsDouble => double.tryParse(totalPositionIM) ?? 0.0;

  /// Gets available balance (주문 가능한 금액 = walletBalance - totalPositionIM)
  double get availableBalance => walletBalanceAsDouble - totalPositionIMAsDouble;

  @override
  String toString() => 'CoinBalance(coin: $coin, balance: $walletBalance)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CoinBalance &&
          runtimeType == other.runtimeType &&
          coin == other.coin &&
          walletBalance == other.walletBalance;

  @override
  int get hashCode => coin.hashCode ^ walletBalance.hashCode;
}
