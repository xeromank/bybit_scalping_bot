import 'package:bybit_scalping_bot/core/result/result.dart';
import 'package:bybit_scalping_bot/models/wallet_balance.dart';
import 'package:bybit_scalping_bot/models/position.dart';
import 'package:bybit_scalping_bot/models/order.dart';
import 'package:bybit_scalping_bot/models/ticker.dart';
import 'package:bybit_scalping_bot/services/bybit_api_client.dart';

/// Repository for Bybit trading operations
///
/// Responsibility: Abstract data access logic for Bybit API
///
/// This repository implements the Repository pattern, providing a clean
/// abstraction over the Bybit API client. It handles data transformation
/// from API responses to domain models and provides type-safe error handling.
///
/// Benefits:
/// - Separates data access from business logic
/// - Easy to test with mock implementations
/// - Type-safe error handling with Result type
/// - Transforms API DTOs to domain models
class BybitRepository {
  final BybitApiClient _apiClient;

  BybitRepository({required BybitApiClient apiClient})
      : _apiClient = apiClient;

  /// Fetches wallet balance for the account
  ///
  /// Returns [Result<WalletBalance>] - Success with balance or Failure with error
  Future<Result<WalletBalance>> getWalletBalance({
    String accountType = 'UNIFIED',
    String? coin,
  }) async {
    try {
      final response = await _apiClient.getWalletBalance(
        accountType: accountType,
        coin: coin,
      );

      if (response['retCode'] == 0) {
        final balance = WalletBalance.fromJson(response['result']);
        return Success(balance);
      } else {
        return Failure(
          'Failed to fetch wallet balance: ${response['retMsg']}',
        );
      }
    } catch (e) {
      return Failure(
        'Failed to fetch wallet balance',
        Exception(e.toString()),
      );
    }
  }

  /// Fetches position information for a symbol
  ///
  /// Returns [Result<Position?>] - Success with position (or null if no position) or Failure
  Future<Result<Position?>> getPosition({required String symbol}) async {
    try {
      final response = await _apiClient.getPositionInfo(symbol: symbol);

      if (response['retCode'] == 0) {
        final positions = response['result']['list'] as List;

        if (positions.isEmpty) {
          return const Success(null);
        }

        final position = Position.fromJson(positions[0]);

        // Return null if position is closed
        if (!position.isOpen) {
          return const Success(null);
        }

        return Success(position);
      } else {
        return Failure(
          'Failed to fetch position: ${response['retMsg']}',
        );
      }
    } catch (e) {
      return Failure(
        'Failed to fetch position',
        Exception(e.toString()),
      );
    }
  }

  /// Fetches all open positions
  ///
  /// Returns [Result<List<Position>>] - Success with list of positions or Failure
  Future<Result<List<Position>>> getAllPositions() async {
    try {
      final response = await _apiClient.getPositionInfo();

      if (response['retCode'] == 0) {
        final positions = response['result']['list'] as List;

        final positionList = positions
            .map((p) => Position.fromJson(p))
            .where((p) => p.isOpen)
            .toList();

        return Success(positionList);
      } else {
        return Failure(
          'Failed to fetch positions: ${response['retMsg']}',
        );
      }
    } catch (e) {
      return Failure(
        'Failed to fetch positions',
        Exception(e.toString()),
      );
    }
  }

  /// Fetches ticker information for a symbol
  ///
  /// Returns [Result<Ticker>] - Success with ticker or Failure
  Future<Result<Ticker>> getTicker({required String symbol}) async {
    try {
      final response = await _apiClient.getTicker(symbol: symbol);

      if (response['retCode'] == 0) {
        final list = response['result']['list'] as List;

        if (list.isEmpty) {
          return Failure('No ticker data found for $symbol');
        }

        final ticker = Ticker.fromJson(list[0]);
        return Success(ticker);
      } else {
        return Failure(
          'Failed to fetch ticker: ${response['retMsg']}',
        );
      }
    } catch (e) {
      return Failure(
        'Failed to fetch ticker',
        Exception(e.toString()),
      );
    }
  }

  /// Creates a new order
  ///
  /// Returns [Result<Order>] - Success with created order or Failure
  Future<Result<Order>> createOrder({required OrderRequest request}) async {
    try {
      final response = await _apiClient.createOrder(
        symbol: request.symbol,
        side: request.side,
        orderType: request.orderType,
        qty: request.qty,
        price: request.price,
        timeInForce: request.timeInForce,
        positionIdx: request.positionIdx,
        reduceOnly: request.reduceOnly,
        orderLinkId: request.orderLinkId,
      );

      if (response['retCode'] == 0) {
        final result = response['result'];

        // For successful order creation, we need to fetch order details
        // since create response might not contain full order info
        final orderId = result['orderId'] as String;

        // Create a basic order object with available data
        final order = Order(
          orderId: orderId,
          orderLinkId: result['orderLinkId'] as String? ?? '',
          symbol: request.symbol,
          side: request.side,
          orderType: request.orderType,
          price: request.price ?? '0',
          qty: request.qty,
          orderStatus: 'New',
          timeInForce: request.timeInForce ?? 'GTC',
          reduceOnly: request.reduceOnly,
          closeOnTrigger: false,
          createdTime: DateTime.now(),
        );

        return Success(order);
      } else {
        return Failure(
          'Failed to create order: ${response['retMsg']}',
        );
      }
    } catch (e) {
      return Failure(
        'Failed to create order',
        Exception(e.toString()),
      );
    }
  }

  /// Cancels an order
  ///
  /// Returns [Result<bool>] - Success(true) or Failure
  Future<Result<bool>> cancelOrder({
    required String symbol,
    String? orderId,
    String? orderLinkId,
  }) async {
    try {
      final response = await _apiClient.cancelOrder(
        symbol: symbol,
        orderId: orderId,
        orderLinkId: orderLinkId,
      );

      if (response['retCode'] == 0) {
        return const Success(true);
      } else {
        return Failure(
          'Failed to cancel order: ${response['retMsg']}',
        );
      }
    } catch (e) {
      return Failure(
        'Failed to cancel order',
        Exception(e.toString()),
      );
    }
  }

  /// Cancels all orders for a symbol
  ///
  /// Returns [Result<bool>] - Success(true) or Failure
  Future<Result<bool>> cancelAllOrders({required String symbol}) async {
    try {
      final response = await _apiClient.cancelAllOrders(symbol: symbol);

      if (response['retCode'] == 0) {
        return const Success(true);
      } else {
        return Failure(
          'Failed to cancel all orders: ${response['retMsg']}',
        );
      }
    } catch (e) {
      return Failure(
        'Failed to cancel all orders',
        Exception(e.toString()),
      );
    }
  }

  /// Fetches active orders for a symbol
  ///
  /// Returns [Result<List<Order>>] - Success with list of orders or Failure
  Future<Result<List<Order>>> getActiveOrders({required String symbol}) async {
    try {
      final response = await _apiClient.getActiveOrders(symbol: symbol);

      if (response['retCode'] == 0) {
        final list = response['result']['list'] as List;

        final orders = list.map((o) => Order.fromJson(o)).toList();

        return Success(orders);
      } else {
        return Failure(
          'Failed to fetch active orders: ${response['retMsg']}',
        );
      }
    } catch (e) {
      return Failure(
        'Failed to fetch active orders',
        Exception(e.toString()),
      );
    }
  }

  /// Sets leverage for a symbol
  ///
  /// Returns [Result<bool>] - Success(true) or Failure
  Future<Result<bool>> setLeverage({
    required String symbol,
    required String buyLeverage,
    required String sellLeverage,
  }) async {
    try {
      final response = await _apiClient.setLeverage(
        symbol: symbol,
        buyLeverage: buyLeverage,
        sellLeverage: sellLeverage,
      );

      if (response['retCode'] == 0) {
        return const Success(true);
      } else {
        return Failure(
          'Failed to set leverage: ${response['retMsg']}',
        );
      }
    } catch (e) {
      return Failure(
        'Failed to set leverage',
        Exception(e.toString()),
      );
    }
  }

  /// Tests API connection by fetching server time
  ///
  /// Returns [Result<DateTime>] - Success with server time or Failure
  Future<Result<DateTime>> testConnection() async {
    try {
      final response = await _apiClient.getServerTime();

      if (response['retCode'] == 0) {
        final timeString = response['result']['timeNano'] as String;
        final timestamp = int.parse(timeString) ~/ 1000000;
        final serverTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
        return Success(serverTime);
      } else {
        return Failure('Failed to connect to server');
      }
    } catch (e) {
      return Failure(
        'Failed to connect to server',
        Exception(e.toString()),
      );
    }
  }
}
