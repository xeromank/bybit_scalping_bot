/// Coinone wallet balance model
///
/// Represents balance information from Coinone API
/// Reference: https://docs.coinone.co.kr/reference/find-balance
class CoinoneBalance {
  final String currency;
  final double available; // 사용 가능한 수량
  final double balance; // 총 잔고
  final double pendingWithdrawal; // 출금 대기 중인 수량
  final double pendingDeposit; // 입금 대기 중인 수량
  final double? averagePrice; // 평균 매수가 (V2.1 API)

  const CoinoneBalance({
    required this.currency,
    required this.available,
    required this.balance,
    required this.pendingWithdrawal,
    required this.pendingDeposit,
    this.averagePrice,
  });

  /// Create from API JSON response
  factory CoinoneBalance.fromJson(String currency, Map<String, dynamic> json) {
    return CoinoneBalance(
      currency: currency,
      available: double.parse(json['avail']?.toString() ?? json['available']?.toString() ?? '0'),
      balance: double.parse(json['balance']?.toString() ?? '0'),
      pendingWithdrawal: double.parse(json['pending_withdrawal']?.toString() ?? '0'),
      pendingDeposit: double.parse(json['pending_deposit']?.toString() ?? '0'),
      averagePrice: json['avg_price'] != null
          ? double.tryParse(json['avg_price'].toString())
          : null,
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'currency': currency,
      'avail': available.toString(),
      'balance': balance.toString(),
      'pending_withdrawal': pendingWithdrawal.toString(),
      'pending_deposit': pendingDeposit.toString(),
    };
  }

  /// Get total value (available + pending)
  double get total => balance;

  @override
  String toString() {
    return 'CoinoneBalance(currency: $currency, available: $available, balance: $balance)';
  }
}

/// Represents the complete wallet balance response
class CoinoneWalletBalance {
  final Map<String, CoinoneBalance> balances;
  final DateTime timestamp;

  const CoinoneWalletBalance({
    required this.balances,
    required this.timestamp,
  });

  /// Create from API response
  factory CoinoneWalletBalance.fromJson(Map<String, dynamic> json) {
    final balances = <String, CoinoneBalance>{};

    // Coinone API returns balances as nested objects
    // Example: { "krw": {...}, "btc": {...}, "xrp": {...} }
    json.forEach((currency, value) {
      if (value is Map<String, dynamic>) {
        balances[currency.toUpperCase()] = CoinoneBalance.fromJson(
          currency.toUpperCase(),
          value,
        );
      }
    });

    return CoinoneWalletBalance(
      balances: balances,
      timestamp: DateTime.now(),
    );
  }

  /// Get balance for specific currency
  CoinoneBalance? getBalance(String currency) {
    return balances[currency.toUpperCase()];
  }

  /// Get available balance for currency
  double getAvailable(String currency) {
    return balances[currency.toUpperCase()]?.available ?? 0.0;
  }

  /// Get KRW balance
  CoinoneBalance? get krwBalance => balances['KRW'];

  @override
  String toString() {
    return 'CoinoneWalletBalance(currencies: ${balances.keys.join(', ')})';
  }
}
