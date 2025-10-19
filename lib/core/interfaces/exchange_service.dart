import '../result/result.dart';

/// Common interface for exchange services
///
/// Defines the contract that all exchange-specific services must implement.
/// This enables polymorphic usage of different exchanges.
abstract class ExchangeService {
  /// Get wallet balance
  Future<Result<Map<String, dynamic>>> getBalance();

  /// Place a market order
  Future<Result<Map<String, dynamic>>> placeMarketOrder({
    required String symbol,
    required String side, // 'buy' or 'sell'
    required double quantity,
    String? clientOrderId,
  });

  /// Place a limit order
  Future<Result<Map<String, dynamic>>> placeLimitOrder({
    required String symbol,
    required String side,
    required double quantity,
    required double price,
    String? clientOrderId,
  });

  /// Cancel an order
  Future<Result<void>> cancelOrder({
    String? orderId,
    String? clientOrderId,
  });

  /// Get open orders
  Future<Result<List<Map<String, dynamic>>>> getOpenOrders({
    String? symbol,
  });

  /// Get ticker information
  Future<Result<Map<String, dynamic>>> getTicker({
    required String symbol,
  });

  /// Close all connections (WebSocket, timers, etc.)
  Future<void> dispose();
}
