import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import '../../core/result/result.dart';
import '../../models/coinone/coinone_balance.dart';
import '../../models/coinone/coinone_order.dart';
import '../../models/coinone/coinone_chart.dart';

/// Coinone API Client
///
/// Handles all REST API communication with Coinone exchange
/// Reference: https://docs.coinone.co.kr/
class CoinoneApiClient {
  final String apiKey;
  final String apiSecret;
  final String baseUrl;

  CoinoneApiClient({
    required this.apiKey,
    required this.apiSecret,
    this.baseUrl = 'https://api.coinone.co.kr',
  });

  /// Generate authentication headers for Coinone API
  ///
  /// Coinone V2.1 API uses:
  /// 1. Payload: base64(JSON({access_token, nonce(UUID), ...params}))
  /// 2. Signature: HMAC-SHA512(payload_bytes, secret_bytes).hexdigest()
  /// 3. Headers: X-COINONE-PAYLOAD and X-COINONE-SIGNATURE
  ///
  /// Note: V2.1 uses UUID for nonce, V2 uses timestamp
  /// Reference: https://docs.coinone.co.kr/docs/about-public-api#private-api-요청하기
  Map<String, String> _generateAuthHeaders({Map<String, dynamic>? params}) {
    const uuid = Uuid();
    final nonce = uuid.v4(); // UUID v4 for V2.1 API

    final payloadMap = {
      'access_token': apiKey,
      'nonce': nonce,
      ...?params,
    };

    // Encode payload to base64
    final payloadJson = json.encode(payloadMap);
    final payloadBytes = utf8.encode(payloadJson);
    final encodedPayload = base64.encode(payloadBytes);

    // Create signature: HMAC-SHA512 with bytes
    // Python: hmac.new(SECRET_KEY_bytes, encoded_payload_bytes, hashlib.sha512).hexdigest()
    final secretBytes = utf8.encode(apiSecret);
    final encodedPayloadBytes = utf8.encode(encodedPayload);
    final hmac = Hmac(sha512, secretBytes);
    final digest = hmac.convert(encodedPayloadBytes);
    final signature = digest.toString(); // hexdigest equivalent

    return {
      'X-COINONE-PAYLOAD': encodedPayload,
      'X-COINONE-SIGNATURE': signature,
    };
  }

  /// Make authenticated POST request (Coinone requires POST for all private endpoints)
  Future<Result<Map<String, dynamic>>> _post(
    String endpoint, {
    Map<String, dynamic>? params,
  }) async {
    try {
      final authHeaders = _generateAuthHeaders(params: params);
      final uri = Uri.parse('$baseUrl$endpoint');

      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          ...authHeaders,
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;

        // Debug: Print full response
        print('[CoinoneAPI] Response: $data');

        // Check for Coinone API errors
        if (data['result'] == 'error') {
          final errorCode = data['error_code']?.toString() ?? data['errorCode']?.toString() ?? 'unknown';
          final errorMsg = data['message']?.toString() ?? data['errorMsg']?.toString() ?? 'Unknown error';
          print('[CoinoneAPI] Error - Code: $errorCode, Message: $errorMsg');
          return Failure('Coinone API Error $errorCode: $errorMsg');
        }

        return Success(data);
      } else {
        print('[CoinoneAPI] HTTP Error ${response.statusCode}: ${response.body}');
        return Failure('HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      return Failure(e.toString(), e is Exception ? e : Exception(e.toString()));
    }
  }

  // ============================================================================
  // Public API Methods (No authentication required)
  // ============================================================================

  /// Get chart data
  /// Reference: https://docs.coinone.co.kr/reference/chart
  Future<Result<CoinoneChartData>> getChart({
    required String quoteCurrency,
    required String targetCurrency,
    ChartInterval interval = ChartInterval.oneMinute,
    DateTime? startTime,
    DateTime? endTime,
    int size = 500, // Default to 500 candles (API max)
  }) async {
    try {
      final queryParams = <String, String>{
        'interval': interval.value,
        'size': size.toString(), // Add size parameter
      };

      if (startTime != null) {
        queryParams['start_time'] = (startTime.millisecondsSinceEpoch ~/ 1000).toString();
      }
      if (endTime != null) {
        queryParams['end_time'] = (endTime.millisecondsSinceEpoch ~/ 1000).toString();
      }

      final uri = Uri.parse(
        '$baseUrl/public/v2/chart/$quoteCurrency/$targetCurrency',
      ).replace(queryParameters: queryParams);

      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final chartData = CoinoneChartData.fromJson(
          quoteCurrency,
          targetCurrency,
          interval,
          data['chart'] as List<dynamic>,
        );
        return Success(chartData);
      } else {
        return Failure('HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      return Failure(e.toString(), e is Exception ? e : Exception(e.toString()));
    }
  }

  // ============================================================================
  // Private API Methods (Authentication required)
  // ============================================================================

  /// Get wallet balance
  /// Reference: https://docs.coinone.co.kr/reference/find-balance
  Future<Result<CoinoneWalletBalance>> getBalance() async {
    // Coinone V2.1 API requires POST for all authenticated endpoints
    final result = await _post('/v2.1/account/balance/all');

    if (result is Success<Map<String, dynamic>>) {
      try {
        final data = result.data;

        // V2.1 API returns: { "result": "success", "balances": [ {...}, ... ] }
        // Convert to V2 format: { "KRW": {...}, "BTC": {...} }
        if (data['balances'] is List) {
          final balancesList = data['balances'] as List<dynamic>;
          final balancesMap = <String, dynamic>{};

          for (final item in balancesList) {
            if (item is Map<String, dynamic>) {
              final currency = (item['currency'] as String).toLowerCase();
              balancesMap[currency] = {
                'avail': item['available'],
                'balance': item['available'], // V2.1 doesn't have separate balance field
                'pending_withdrawal': '0',
                'pending_deposit': '0',
                'average_price': item['average_price'], // Include average buy price from API
              };
            }
          }

          return Success(CoinoneWalletBalance.fromJson(balancesMap));
        }

        return Failure('Invalid response format: balances is not a List');
      } catch (e) {
        return Failure('Failed to parse balance: $e');
      }
    } else {
      final failure = result as Failure<Map<String, dynamic>>;
      return Failure(failure.message, failure.exception);
    }
  }

  /// Place an order
  /// Reference: https://docs.coinone.co.kr/reference/place-order
  Future<Result<CoinoneOrder>> placeOrder(PlaceOrderRequest request) async {
    final params = request.toJson();
    print('[CoinoneAPI] Place Order Request: $params');
    final result = await _post('/v2.1/order', params: params);

    if (result is Success<Map<String, dynamic>>) {
      final data = result.data;
      // Coinone API returns only order_id, not full order object
      // Create CoinoneOrder from request params + response order_id
      final orderData = {
        'order_id': data['order_id'],
        'user_order_id': params['user_order_id'],
        'quote_currency': params['quote_currency'],
        'target_currency': params['target_currency'],
        'type': params['type'],
        'side': params['side'],
        'price': params['price'] ?? '0',
        'qty': params['qty'],
        'filled_qty': '0',
        'remain_qty': params['qty'],
        'status': 'placed',
        'created_at': DateTime.now().toIso8601String(),
      };
      return Success(CoinoneOrder.fromJson(orderData));
    } else {
      final failure = result as Failure<Map<String, dynamic>>;
      return Failure(failure.message, failure.exception);
    }
  }

  /// Cancel an order
  /// Reference: https://docs.coinone.co.kr/reference/cancel-order
  Future<Result<void>> cancelOrder({
    required String userOrderId,
    required String quoteCurrency,
    required String targetCurrency,
  }) async {
    final result = await _post('/v2.1/order/cancel', params: {
      'user_order_id': userOrderId,
      'quote_currency': quoteCurrency,
      'target_currency': targetCurrency,
    });

    return switch (result) {
      Success() => const Success(null),
      Failure(:final message, :final exception) => Failure(
          message,
          exception,
        ),
    };
  }

  /// Get open orders
  /// Reference: https://docs.coinone.co.kr/reference/find-active-orders
  Future<Result<List<CoinoneOrder>>> getOpenOrders({
    required String quoteCurrency,
    required String targetCurrency,
  }) async {
    final result = await _post('/v2.1/order/active_orders', params: {
      'quote_currency': quoteCurrency,
      'target_currency': targetCurrency,
    });

    if (result is Success<Map<String, dynamic>>) {
      final data = result.data;
      // Coinone API returns 'active_orders' field
      final orders = data['active_orders'] ?? [];

      if (orders is! List) {
        return Success(<CoinoneOrder>[]);
      }

      return Success(
        (orders as List<dynamic>)
            .map((e) => CoinoneOrder.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
    } else {
      final failure = result as Failure<Map<String, dynamic>>;
      return Failure(failure.message, failure.exception);
    }
  }

  /// Withdraw cryptocurrency
  /// Reference: https://docs.coinone.co.kr/reference/coin-withdrawal
  Future<Result<Map<String, dynamic>>> withdrawCoin({
    required String currency,
    required double amount,
    required String address,
    String? tag, // For currencies that require destination tag (e.g., XRP)
  }) async {
    final params = <String, dynamic>{
      'currency': currency,
      'amount': amount.toString(),
      'address': address,
    };

    if (tag != null) {
      params['destination_tag'] = tag;
    }

    final result = await _post('/v2.1/transaction/coin/withdrawal', params: params);

    return switch (result) {
      Success(:final data) => Success(data),
      Failure(:final message, :final exception) => Failure(
          message,
          exception,
        ),
    };
  }

  /// Generate unique user order ID
  static String generateUserOrderId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = Random().nextInt(9999);
    return 'order_${timestamp}_$random';
  }
}
