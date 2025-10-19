import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:bybit_scalping_bot/core/result/result.dart';
import 'package:bybit_scalping_bot/models/coinone/coinone_balance.dart';
import 'package:bybit_scalping_bot/repositories/coinone_repository.dart';

/// Provider for Coinone balance state and operations
///
/// Responsibility: Manage Coinone wallet balance state
///
/// This provider fetches and updates balance information every 3 seconds
/// when monitoring is active. It follows the same pattern as BalanceProvider
/// but for Coinone spot trading.
///
/// Benefits:
/// - Centralized balance logic for Coinone
/// - Reactive UI updates through ChangeNotifier
/// - Automatic periodic updates
/// - Separation from Bybit balance logic
class CoinoneBalanceProvider extends ChangeNotifier {
  final CoinoneRepository _repository;

  // State
  CoinoneWalletBalance? _walletBalance;
  bool _isLoading = false;
  String? _errorMessage;
  Timer? _balanceTimer;
  bool _isMonitoring = false;

  CoinoneBalanceProvider({
    required CoinoneRepository repository,
  }) : _repository = repository;

  // Getters
  CoinoneWalletBalance? get walletBalance => _walletBalance;
  Map<String, CoinoneBalance> get balances => _walletBalance?.balances ?? {};
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isMonitoring => _isMonitoring;

  /// Get balance for specific coin
  CoinoneBalance? getBalance(String coin) {
    return _walletBalance?.getBalance(coin);
  }

  /// Get available balance for specific coin
  double getAvailableBalance(String coin) {
    return _walletBalance?.getAvailable(coin) ?? 0.0;
  }

  /// Get total balance (available + pending) for specific coin
  double getTotalBalance(String coin) {
    final balance = _walletBalance?.getBalance(coin);
    if (balance == null) return 0.0;
    return balance.balance;
  }

  /// Get total balance in KRW (for display)
  /// Requires ticker data to calculate value
  double getTotalBalanceInKRW(Map<String, double> currentPrices) {
    double total = 0.0;

    final balances = _walletBalance?.balances ?? {};
    for (final entry in balances.entries) {
      final coin = entry.key;
      final balance = entry.value;

      if (coin == 'KRW') {
        total += balance.balance;
      } else {
        final price = currentPrices[coin] ?? 0.0;
        total += balance.balance * price;
      }
    }

    return total;
  }

  /// Fetches wallet balance from Coinone API
  Future<void> fetchBalance() async {
    _setLoading(true);
    _errorMessage = null;

    try {
      final result = await _repository.getWalletBalance();

      switch (result) {
        case Success(:final data):
          _walletBalance = data;
          _errorMessage = null;
        case Failure(:final message, :final exception):
          _errorMessage = message;
          if (kDebugMode) {
            print('Balance fetch error: $message');
            if (exception != null) {
              print('Exception: $exception');
            }
          }
      }
    } catch (e) {
      _errorMessage = 'Unexpected error: ${e.toString()}';
      if (kDebugMode) {
        print('Balance fetch exception: $e');
      }
    } finally {
      _setLoading(false);
    }
  }

  /// Starts periodic balance monitoring (every 3 seconds)
  void startMonitoring() {
    if (_isMonitoring) {
      return; // Already monitoring
    }

    _isMonitoring = true;

    // Fetch immediately
    fetchBalance();

    // Then every 3 seconds
    _balanceTimer?.cancel();
    _balanceTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => fetchBalance(),
    );

    notifyListeners();
  }

  /// Stops periodic balance monitoring
  void stopMonitoring() {
    _isMonitoring = false;
    _balanceTimer?.cancel();
    _balanceTimer = null;
    notifyListeners();
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

  @override
  void dispose() {
    _balanceTimer?.cancel();
    super.dispose();
  }
}
