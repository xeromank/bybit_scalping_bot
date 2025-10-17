import 'package:flutter/foundation.dart';
import 'package:bybit_scalping_bot/models/wallet_balance.dart';
import 'package:bybit_scalping_bot/repositories/bybit_repository.dart';

/// Provider for wallet balance state and operations
///
/// Responsibility: Manage wallet balance state and business logic
///
/// This provider manages wallet balance data and provides methods
/// to fetch and refresh balance information.
class BalanceProvider extends ChangeNotifier {
  final BybitRepository _repository;

  // State
  WalletBalance? _balance;
  bool _isLoading = false;
  String? _errorMessage;
  DateTime? _lastUpdated;

  BalanceProvider({required BybitRepository repository})
      : _repository = repository;

  // Getters
  WalletBalance? get balance => _balance;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  DateTime? get lastUpdated => _lastUpdated;

  /// Gets USDT balance as a formatted string
  String get usdtBalanceFormatted {
    final usdtBalance = _balance?.usdtBalance;
    if (usdtBalance == null) return '0.00';

    final balance = usdtBalance.walletBalanceAsDouble;
    return balance.toStringAsFixed(2);
  }

  /// Gets USDT balance as double
  double get usdtBalance {
    return _balance?.usdtBalance?.walletBalanceAsDouble ?? 0.0;
  }

  /// Fetches wallet balance
  Future<void> fetchBalance({String accountType = 'UNIFIED'}) async {
    _setLoading(true);
    _errorMessage = null;

    final result = await _repository.getWalletBalance(
      accountType: accountType,
    );

    result.when(
      success: (balance) {
        _balance = balance;
        _lastUpdated = DateTime.now();
        _errorMessage = null;
      },
      failure: (message, exception) {
        _errorMessage = message;
      },
    );

    _setLoading(false);
  }

  /// Refreshes wallet balance (same as fetch but with explicit name)
  Future<void> refresh() async {
    await fetchBalance();
  }

  /// Clears error message
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  /// Sets loading state
  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }
}
