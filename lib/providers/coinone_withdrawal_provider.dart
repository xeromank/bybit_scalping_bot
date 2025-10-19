import 'package:flutter/foundation.dart';
import 'package:bybit_scalping_bot/core/result/result.dart';
import 'package:bybit_scalping_bot/repositories/coinone_repository.dart';
import 'package:bybit_scalping_bot/services/coinone/coinone_database_service.dart';

/// Provider for Coinone withdrawal operations
///
/// Responsibility: Manage cryptocurrency withdrawals from Coinone
///
/// Features:
/// - Withdraw coins to external addresses
/// - Cache frequently used addresses in SQLite
/// - Retrieve recent withdrawal addresses
/// - Validate withdrawal parameters
///
/// Benefits:
/// - Simplified withdrawal UX with address caching
/// - Full audit trail in database
/// - Type-safe error handling
/// - Separation from trading logic
class CoinoneWithdrawalProvider extends ChangeNotifier {
  final CoinoneRepository _repository;
  final CoinoneDatabaseService _databaseService = CoinoneDatabaseService();

  // State
  bool _isLoading = false;
  String? _errorMessage;
  List<WithdrawalAddress> _recentAddresses = [];

  CoinoneWithdrawalProvider({
    required CoinoneRepository repository,
  }) : _repository = repository;

  // Getters
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  List<WithdrawalAddress> get recentAddresses => _recentAddresses;

  /// Initialize provider
  Future<void> initialize() async {
    await _databaseService.database;
  }

  /// Get recent withdrawal addresses for specific coin
  Future<void> loadRecentAddresses(String coin) async {
    _setLoading(true);

    try {
      final addresses = await _databaseService.getWithdrawalAddresses(coin: coin);
      _recentAddresses = addresses.map((row) {
        return WithdrawalAddress(
          coin: row['coin'] as String,
          address: row['address'] as String,
          label: row['label'] as String?,
          lastUsed: DateTime.fromMillisecondsSinceEpoch(row['last_used'] as int),
        );
      }).toList();
    } catch (e) {
      _errorMessage = 'Failed to load addresses: ${e.toString()}';
      if (kDebugMode) {
        print('Load addresses error: $e');
      }
    } finally {
      _setLoading(false);
    }
  }

  /// Withdraw cryptocurrency to external address
  ///
  /// [coin] - Cryptocurrency symbol (e.g., 'BTC', 'ETH')
  /// [address] - Destination address
  /// [amount] - Amount to withdraw
  /// [label] - Optional label for the address (for caching)
  Future<bool> withdrawCoin({
    required String coin,
    required String address,
    required double amount,
    String? label,
  }) async {
    _setLoading(true);
    _errorMessage = null;

    try {
      // Validate parameters
      if (coin.isEmpty) {
        _errorMessage = 'Coin symbol is required';
        _setLoading(false);
        return false;
      }

      if (address.isEmpty) {
        _errorMessage = 'Withdrawal address is required';
        _setLoading(false);
        return false;
      }

      if (amount <= 0) {
        _errorMessage = 'Amount must be greater than 0';
        _setLoading(false);
        return false;
      }

      // Execute withdrawal
      final result = await _repository.withdrawCoin(
        currency: coin,
        address: address,
        amount: amount,
      );

      switch (result) {
        case Success():
          // Cache the address for future use
          await _cacheAddress(
            coin: coin,
            address: address,
            label: label,
          );

          // Log withdrawal
          await _databaseService.insertTradeLog(
            type: 'success',
            message: 'Withdrawal: $amount $coin to $address',
            symbol: coin,
          );

          // Reload recent addresses
          await loadRecentAddresses(coin);

          _setLoading(false);
          return true;

        case Failure(:final message):
          _errorMessage = message;

          // Log failure
          await _databaseService.insertTradeLog(
            type: 'error',
            message: 'Withdrawal failed: $message',
            symbol: coin,
          );

          _setLoading(false);
          return false;
      }
    } catch (e) {
      _errorMessage = 'Withdrawal error: ${e.toString()}';

      await _databaseService.insertTradeLog(
        type: 'error',
        message: 'Withdrawal exception: $e',
        symbol: coin,
      );

      if (kDebugMode) {
        print('Withdrawal exception: $e');
      }

      _setLoading(false);
      return false;
    }
  }

  /// Cache withdrawal address in database
  Future<void> _cacheAddress({
    required String coin,
    required String address,
    String? label,
  }) async {
    try {
      await _databaseService.saveWithdrawalAddress(
        coin: coin,
        address: address,
        label: label,
      );
    } catch (e) {
      if (kDebugMode) {
        print('Cache address error: $e');
      }
    }
  }

  /// Delete a cached address
  Future<void> deleteAddress(String coin, String address) async {
    _setLoading(true);

    try {
      // Delete from database (we'll add this method to the database service)
      final db = await _databaseService.database;
      await db.delete(
        'withdrawal_addresses',
        where: 'coin = ? AND address = ?',
        whereArgs: [coin, address],
      );

      // Reload addresses
      await loadRecentAddresses(coin);
    } catch (e) {
      _errorMessage = 'Failed to delete address: ${e.toString()}';
      if (kDebugMode) {
        print('Delete address error: $e');
      }
    } finally {
      _setLoading(false);
    }
  }

  /// Update address label
  Future<void> updateAddressLabel({
    required String coin,
    required String address,
    required String label,
  }) async {
    _setLoading(true);

    try {
      // Update in database
      await _cacheAddress(
        coin: coin,
        address: address,
        label: label,
      );

      // Reload addresses
      await loadRecentAddresses(coin);
    } catch (e) {
      _errorMessage = 'Failed to update label: ${e.toString()}';
      if (kDebugMode) {
        print('Update label error: $e');
      }
    } finally {
      _setLoading(false);
    }
  }

  /// Validate withdrawal address format
  ///
  /// Basic validation - you may want to add coin-specific validation
  bool isValidAddress(String coin, String address) {
    if (address.isEmpty) return false;

    // Add coin-specific validation here
    switch (coin.toUpperCase()) {
      case 'BTC':
        // Bitcoin address validation (basic)
        return address.length >= 26 && address.length <= 35;
      case 'ETH':
        // Ethereum address validation (basic)
        return address.startsWith('0x') && address.length == 42;
      case 'XRP':
        // Ripple address validation (basic)
        return address.startsWith('r') && address.length >= 25 && address.length <= 35;
      default:
        // Generic validation
        return address.length >= 20 && address.length <= 100;
    }
  }

  /// Clear error message
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  /// Set loading state
  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _databaseService.close();
    super.dispose();
  }
}

/// Withdrawal address data model
class WithdrawalAddress {
  final String coin;
  final String address;
  final String? label;
  final DateTime lastUsed;

  WithdrawalAddress({
    required this.coin,
    required this.address,
    this.label,
    required this.lastUsed,
  });

  /// Get display name for UI
  String get displayName {
    if (label != null && label!.isNotEmpty) {
      return label!;
    }
    // Show first 8 and last 6 characters
    if (address.length > 14) {
      return '${address.substring(0, 8)}...${address.substring(address.length - 6)}';
    }
    return address;
  }

  /// Get masked address for display
  String get maskedAddress {
    if (address.length > 14) {
      return '${address.substring(0, 8)}...${address.substring(address.length - 6)}';
    }
    return address;
  }
}
