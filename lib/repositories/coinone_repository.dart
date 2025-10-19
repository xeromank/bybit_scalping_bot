import '../core/result/result.dart';
import '../models/coinone/coinone_balance.dart';
import '../models/coinone/coinone_order.dart';
import '../models/coinone/coinone_chart.dart';
import '../services/coinone/coinone_api_client.dart';

/// Repository for Coinone exchange data operations
///
/// Wraps CoinoneApiClient and provides a clean interface for data access
class CoinoneRepository {
  final CoinoneApiClient _apiClient;

  CoinoneRepository({required CoinoneApiClient apiClient})
      : _apiClient = apiClient;

  // ============================================================================
  // Balance Operations
  // ============================================================================

  /// Get wallet balance for all currencies
  Future<Result<CoinoneWalletBalance>> getWalletBalance() async {
    return await _apiClient.getBalance();
  }

  /// Get balance for specific currency
  Future<Result<double>> getAvailableBalance(String currency) async {
    final result = await _apiClient.getBalance();

    return switch (result) {
      Success(:final data) => Success(
          data.getAvailable(currency),
        ),
      Failure(:final message, :final exception) => Failure(
          message,
          exception,
        ),
    };
  }

  // ============================================================================
  // Chart Operations
  // ============================================================================

  /// Get chart data for symbol
  Future<Result<CoinoneChartData>> getChartData({
    required String quoteCurrency,
    required String targetCurrency,
    ChartInterval interval = ChartInterval.oneMinute,
    DateTime? startTime,
    DateTime? endTime,
  }) async {
    return await _apiClient.getChart(
      quoteCurrency: quoteCurrency,
      targetCurrency: targetCurrency,
      interval: interval,
      startTime: startTime,
      endTime: endTime,
    );
  }

  // ============================================================================
  // Order Operations
  // ============================================================================

  /// Place a market buy order with KRW amount (required for Coinone market buy)
  Future<Result<CoinoneOrder>> placeMarketBuyWithAmount({
    required String quoteCurrency,
    required String targetCurrency,
    required double amount, // KRW amount
  }) async {
    final request = PlaceOrderRequest(
      quoteCurrency: quoteCurrency,
      targetCurrency: targetCurrency,
      type: 'market',
      side: 'buy',
      amount: amount, // Use amount instead of quantity
      userOrderId: CoinoneApiClient.generateUserOrderId(),
    );

    return await _apiClient.placeOrder(request);
  }

  /// Place a market buy order (legacy - use placeMarketBuyWithAmount for market buy)
  Future<Result<CoinoneOrder>> placeMarketBuy({
    required String quoteCurrency,
    required String targetCurrency,
    required double quantity,
  }) async {
    final request = PlaceOrderRequest(
      quoteCurrency: quoteCurrency,
      targetCurrency: targetCurrency,
      type: 'market',
      side: 'buy',
      quantity: quantity,
      userOrderId: CoinoneApiClient.generateUserOrderId(),
    );

    return await _apiClient.placeOrder(request);
  }

  /// Place a market sell order
  Future<Result<CoinoneOrder>> placeMarketSell({
    required String quoteCurrency,
    required String targetCurrency,
    required double quantity,
  }) async {
    final request = PlaceOrderRequest(
      quoteCurrency: quoteCurrency,
      targetCurrency: targetCurrency,
      type: 'market',
      side: 'sell',
      quantity: quantity,
      userOrderId: CoinoneApiClient.generateUserOrderId(),
    );

    return await _apiClient.placeOrder(request);
  }

  /// Place a limit buy order
  Future<Result<CoinoneOrder>> placeLimitBuy({
    required String quoteCurrency,
    required String targetCurrency,
    required double quantity,
    required double price,
  }) async {
    final request = PlaceOrderRequest(
      quoteCurrency: quoteCurrency,
      targetCurrency: targetCurrency,
      type: 'limit',
      side: 'buy',
      quantity: quantity,
      price: price,
      userOrderId: CoinoneApiClient.generateUserOrderId(),
    );

    return await _apiClient.placeOrder(request);
  }

  /// Place a limit sell order
  Future<Result<CoinoneOrder>> placeLimitSell({
    required String quoteCurrency,
    required String targetCurrency,
    required double quantity,
    required double price,
  }) async {
    final request = PlaceOrderRequest(
      quoteCurrency: quoteCurrency,
      targetCurrency: targetCurrency,
      type: 'limit',
      side: 'sell',
      quantity: quantity,
      price: price,
      userOrderId: CoinoneApiClient.generateUserOrderId(),
    );

    return await _apiClient.placeOrder(request);
  }

  /// Cancel an order by user order ID
  Future<Result<void>> cancelOrder({
    required String userOrderId,
    required String quoteCurrency,
    required String targetCurrency,
  }) async {
    return await _apiClient.cancelOrder(
      userOrderId: userOrderId,
      quoteCurrency: quoteCurrency,
      targetCurrency: targetCurrency,
    );
  }

  /// Get all open orders
  Future<Result<List<CoinoneOrder>>> getOpenOrders({
    required String quoteCurrency,
    required String targetCurrency,
  }) async {
    return await _apiClient.getOpenOrders(
      quoteCurrency: quoteCurrency,
      targetCurrency: targetCurrency,
    );
  }

  // ============================================================================
  // Withdrawal Operations
  // ============================================================================

  /// Withdraw cryptocurrency to external address
  Future<Result<Map<String, dynamic>>> withdrawCoin({
    required String currency,
    required double amount,
    required String address,
    String? tag,
  }) async {
    return await _apiClient.withdrawCoin(
      currency: currency,
      amount: amount,
      address: address,
      tag: tag,
    );
  }

  // ============================================================================
  // Utility Methods
  // ============================================================================

  /// Generate unique user order ID
  String generateOrderId() {
    return CoinoneApiClient.generateUserOrderId();
  }
}
