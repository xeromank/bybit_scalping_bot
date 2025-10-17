import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:bybit_scalping_bot/core/api/api_client.dart';

/// Bybit API client implementation
///
/// Responsibility: Implement API communication with Bybit exchange
///
/// This class implements the ApiClient interface and handles all HTTP
/// communication with the Bybit API, including authentication and request signing.
///
/// Features:
/// - HMAC-SHA256 request signing
/// - Automatic timestamp generation
/// - Request/response handling
/// - Error handling
class BybitApiClient implements ApiClient {
  @override
  final String apiKey;
  final String apiSecret;
  @override
  final String baseUrl;
  final int recvWindow;

  BybitApiClient({
    required this.apiKey,
    required this.apiSecret,
    this.baseUrl = 'https://api.bybit.com',
    this.recvWindow = 5000,
  });

  // HMAC-SHA256 서명 생성
  String _generateSignature({
    required String timestamp,
    required String queryString,
  }) {
    final paramStr = '$timestamp$apiKey$recvWindow$queryString';
    final key = utf8.encode(apiSecret);
    final bytes = utf8.encode(paramStr);
    final hmacSha256 = Hmac(sha256, key);
    final digest = hmacSha256.convert(bytes);
    return digest.toString();
  }

  // HTTP 요청 헤더 생성
  Map<String, String> _getHeaders({
    required String timestamp,
    required String signature,
  }) {
    return {
      'X-BAPI-API-KEY': apiKey,
      'X-BAPI-TIMESTAMP': timestamp,
      'X-BAPI-SIGN': signature,
      'X-BAPI-RECV-WINDOW': recvWindow.toString(),
      'Content-Type': 'application/json',
    };
  }

  // GET 요청
  @override
  Future<Map<String, dynamic>> get(
    String endpoint, {
    Map<String, dynamic>? params,
  }) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final queryString = params != null
        ? params.entries.map((e) => '${e.key}=${e.value}').join('&')
        : '';

    final signature = _generateSignature(
      timestamp: timestamp,
      queryString: queryString,
    );

    final url = queryString.isEmpty
        ? Uri.parse('$baseUrl$endpoint')
        : Uri.parse('$baseUrl$endpoint?$queryString');

    final response = await http.get(
      url,
      headers: _getHeaders(timestamp: timestamp, signature: signature),
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to fetch data: ${response.statusCode} - ${response.body}');
    }
  }

  // POST 요청
  @override
  Future<Map<String, dynamic>> post(
    String endpoint, {
    Map<String, dynamic>? body,
  }) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final jsonBody = body != null ? json.encode(body) : '';

    final signature = _generateSignature(
      timestamp: timestamp,
      queryString: jsonBody,
    );

    final url = Uri.parse('$baseUrl$endpoint');

    final response = await http.post(
      url,
      headers: _getHeaders(timestamp: timestamp, signature: signature),
      body: jsonBody,
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to post data: ${response.statusCode} - ${response.body}');
    }
  }

  // DELETE 요청 (ApiClient 인터페이스 구현)
  @override
  Future<Map<String, dynamic>> delete(
    String endpoint, {
    Map<String, dynamic>? body,
  }) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final jsonBody = body != null ? json.encode(body) : '';

    final signature = _generateSignature(
      timestamp: timestamp,
      queryString: jsonBody,
    );

    final url = Uri.parse('$baseUrl$endpoint');

    final response = await http.delete(
      url,
      headers: _getHeaders(timestamp: timestamp, signature: signature),
      body: jsonBody.isNotEmpty ? jsonBody : null,
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to delete data: ${response.statusCode} - ${response.body}');
    }
  }

  // PUT 요청 (ApiClient 인터페이스 구현)
  @override
  Future<Map<String, dynamic>> put(
    String endpoint, {
    Map<String, dynamic>? body,
  }) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final jsonBody = body != null ? json.encode(body) : '';

    final signature = _generateSignature(
      timestamp: timestamp,
      queryString: jsonBody,
    );

    final url = Uri.parse('$baseUrl$endpoint');

    final response = await http.put(
      url,
      headers: _getHeaders(timestamp: timestamp, signature: signature),
      body: jsonBody,
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to put data: ${response.statusCode} - ${response.body}');
    }
  }

  // 서버 시간 조회
  Future<Map<String, dynamic>> getServerTime() async {
    final url = Uri.parse('$baseUrl/v5/market/time');
    final response = await http.get(url);

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to fetch server time: ${response.statusCode}');
    }
  }

  // 지갑 잔고 조회
  Future<Map<String, dynamic>> getWalletBalance({
    required String accountType,
    String? coin,
  }) async {
    final params = <String, dynamic>{
      'accountType': accountType,
    };

    if (coin != null) {
      params['coin'] = coin;
    }

    return await get('/v5/account/wallet-balance', params: params);
  }

  // 레버리지 설정
  Future<Map<String, dynamic>> setLeverage({
    required String symbol,
    required String buyLeverage,
    required String sellLeverage,
  }) async {
    return await post('/v5/position/set-leverage', body: {
      'category': 'linear',
      'symbol': symbol,
      'buyLeverage': buyLeverage,
      'sellLeverage': sellLeverage,
    });
  }

  // 주문 생성
  Future<Map<String, dynamic>> createOrder({
    required String symbol,
    required String side, // Buy or Sell
    required String orderType, // Market or Limit
    String? qty,
    String? orderValue,
    String? price,
    String? timeInForce = 'GTC',
    int positionIdx = 0,
    bool reduceOnly = false,
    String? orderLinkId,
    String? takeProfit, // TP price
    String? stopLoss, // SL price
    String? tpTriggerBy, // TP trigger price type (default: LastPrice)
    String? slTriggerBy, // SL trigger price type (default: LastPrice)
  }) async {
    final body = <String, dynamic>{
      'category': 'linear',
      'symbol': symbol,
      'side': side,
      'orderType': orderType,
      'positionIdx': positionIdx,
      'reduceOnly': reduceOnly,
    };

    if (qty != null) {
      body['qty'] = qty;
    }

    if (orderValue != null) {
      body['orderValue'] = orderValue;
    }

    if (price != null) {
      body['price'] = price;
    }

    if (timeInForce != null) {
      body['timeInForce'] = timeInForce;
    }

    if (orderLinkId != null) {
      body['orderLinkId'] = orderLinkId;
    }

    if (takeProfit != null) {
      body['takeProfit'] = takeProfit;
      body['tpTriggerBy'] = tpTriggerBy ?? 'LastPrice';
    }

    if (stopLoss != null) {
      body['stopLoss'] = stopLoss;
      body['slTriggerBy'] = slTriggerBy ?? 'LastPrice';
    }

    return await post('/v5/order/create', body: body);
  }

  // 포지션 정보 조회
  Future<Map<String, dynamic>> getPositionInfo({
    String? symbol,
  }) async {
    final params = <String, dynamic>{
      'category': 'linear',
      'settleCoin': 'USDT',
    };

    if (symbol != null) {
      params['symbol'] = symbol;
    }

    return await get('/v5/position/list', params: params);
  }

  // 티커 정보 조회
  Future<Map<String, dynamic>> getTicker({
    required String symbol,
  }) async {
    return await get('/v5/market/tickers', params: {
      'category': 'linear',
      'symbol': symbol,
    });
  }

  // 주문 취소
  Future<Map<String, dynamic>> cancelOrder({
    required String symbol,
    String? orderId,
    String? orderLinkId,
  }) async {
    final body = <String, dynamic>{
      'category': 'linear',
      'symbol': symbol,
    };

    if (orderId != null) {
      body['orderId'] = orderId;
    }

    if (orderLinkId != null) {
      body['orderLinkId'] = orderLinkId;
    }

    return await post('/v5/order/cancel', body: body);
  }

  // 전체 주문 취소
  Future<Map<String, dynamic>> cancelAllOrders({
    required String symbol,
  }) async {
    return await post('/v5/order/cancel-all', body: {
      'category': 'linear',
      'symbol': symbol,
    });
  }

  // 활성 주문 조회
  Future<Map<String, dynamic>> getActiveOrders({
    required String symbol,
  }) async {
    return await get('/v5/order/realtime', params: {
      'category': 'linear',
      'symbol': symbol,
    });
  }

  // K-line (캔들스틱) 데이터 조회
  Future<Map<String, dynamic>> getKlines({
    required String symbol,
    required String interval, // 1, 3, 5, 15, 30, 60, 120, 240, 360, 720, D, W, M
    int limit = 200, // 최대 1000
  }) async {
    return await get('/v5/market/kline', params: {
      'category': 'linear',
      'symbol': symbol,
      'interval': interval,
      'limit': limit.toString(),
    });
  }

  // 거래 상품 정보 조회
  Future<Map<String, dynamic>> getInstrumentsInfo({
    required String category, // linear, inverse, spot, option
    String? symbol,
    int limit = 500,
  }) async {
    final params = <String, dynamic>{
      'category': category,
      'limit': limit.toString(),
    };

    if (symbol != null) {
      params['symbol'] = symbol;
    }

    return await get('/v5/market/instruments-info', params: params);
  }
}
