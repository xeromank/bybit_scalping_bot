import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../models/coinone/coinone_ticker.dart';
import '../../models/coinone/coinone_orderbook.dart';

/// Coinone WebSocket Client for real-time market data
///
/// Provides public WebSocket access for ticker and orderbook streams
/// Reference: https://docs.coinone.co.kr/reference/public-websocket-ticker
/// Reference: https://docs.coinone.co.kr/reference/public-websocket-orderbook
class CoinoneWebSocketClient {
  static const String _wsUrl = 'wss://stream.coinone.co.kr';

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;

  final Map<String, StreamController<CoinoneTicker>> _tickerControllers = {};
  final Map<String, StreamController<CoinoneOrderbook>> _orderbookControllers = {};

  bool _isConnected = false;
  Timer? _pingTimer;
  Timer? _reconnectTimer;

  /// Check if WebSocket is connected
  bool get isConnected => _isConnected;

  /// Connect to Coinone WebSocket
  Future<void> connect() async {
    if (_isConnected) return;

    try {
      _channel = WebSocketChannel.connect(Uri.parse(_wsUrl));
      _isConnected = true;

      _subscription = _channel!.stream.listen(
        _handleMessage,
        onError: _handleError,
        onDone: _handleDone,
      );

      // Start ping timer to keep connection alive
      _startPingTimer();

      print('[CoinoneWebSocket] Connected');
    } catch (e) {
      print('[CoinoneWebSocket] Connection error: $e');
      _isConnected = false;
      _scheduleReconnect();
    }
  }

  /// Disconnect from WebSocket
  Future<void> disconnect() async {
    _isConnected = false;
    _pingTimer?.cancel();
    _reconnectTimer?.cancel();

    await _subscription?.cancel();
    await _channel?.sink.close();

    _channel = null;
    _subscription = null;

    // Close all stream controllers
    for (final controller in _tickerControllers.values) {
      await controller.close();
    }
    for (final controller in _orderbookControllers.values) {
      await controller.close();
    }

    _tickerControllers.clear();
    _orderbookControllers.clear();

    print('[CoinoneWebSocket] Disconnected');
  }

  /// Subscribe to ticker updates
  ///
  /// Example:
  /// ```dart
  /// final stream = client.subscribeTicker('KRW', 'XRP');
  /// stream.listen((ticker) => print(ticker.last));
  /// ```
  Stream<CoinoneTicker> subscribeTicker(String quoteCurrency, String targetCurrency) {
    final symbol = '${targetCurrency.toUpperCase()}-${quoteCurrency.toUpperCase()}';

    if (!_tickerControllers.containsKey(symbol)) {
      _tickerControllers[symbol] = StreamController<CoinoneTicker>.broadcast();

      // Coinone WebSocket subscription format
      // Reference: https://docs.coinone.co.kr/reference/public-websocket-ticker
      final subscribeMessage = {
        'request_type': 'SUBSCRIBE',
        'channel': 'TICKER',
        'topic': {
          'quote_currency': quoteCurrency.toUpperCase(),
          'target_currency': targetCurrency.toUpperCase(),
        }
      };

      print('[CoinoneWebSocket] Sending subscribe message: $subscribeMessage');
      _sendMessage(subscribeMessage);
    }

    return _tickerControllers[symbol]!.stream;
  }

  /// Subscribe to orderbook updates
  ///
  /// Example:
  /// ```dart
  /// final stream = client.subscribeOrderbook('KRW', 'XRP');
  /// stream.listen((orderbook) => print(orderbook.bestBid));
  /// ```
  Stream<CoinoneOrderbook> subscribeOrderbook(String quoteCurrency, String targetCurrency) {
    final symbol = '${targetCurrency.toUpperCase()}-${quoteCurrency.toUpperCase()}';

    if (!_orderbookControllers.containsKey(symbol)) {
      _orderbookControllers[symbol] = StreamController<CoinoneOrderbook>.broadcast();

      // Coinone WebSocket subscription format
      final subscribeMessage = {
        'request_type': 'SUBSCRIBE',
        'channel': 'ORDERBOOK',
        'topic': {
          'quote_currency': quoteCurrency.toUpperCase(),
          'target_currency': targetCurrency.toUpperCase(),
        }
      };

      _sendMessage(subscribeMessage);
    }

    return _orderbookControllers[symbol]!.stream;
  }

  /// Unsubscribe from ticker
  void unsubscribeTicker(String quoteCurrency, String targetCurrency) {
    final symbol = '${targetCurrency.toUpperCase()}-${quoteCurrency.toUpperCase()}';

    if (_tickerControllers.containsKey(symbol)) {
      final unsubscribeMessage = {
        'request_type': 'UNSUBSCRIBE',
        'channel': 'TICKER',
        'topic': {
          'quote_currency': quoteCurrency.toUpperCase(),
          'target_currency': targetCurrency.toUpperCase(),
        }
      };

      _sendMessage(unsubscribeMessage);

      _tickerControllers[symbol]?.close();
      _tickerControllers.remove(symbol);
    }
  }

  /// Unsubscribe from orderbook
  void unsubscribeOrderbook(String quoteCurrency, String targetCurrency) {
    final symbol = '${targetCurrency.toUpperCase()}-${quoteCurrency.toUpperCase()}';

    if (_orderbookControllers.containsKey(symbol)) {
      final unsubscribeMessage = {
        'request_type': 'UNSUBSCRIBE',
        'channel': 'ORDERBOOK',
        'topic': {
          'quote_currency': quoteCurrency.toUpperCase(),
          'target_currency': targetCurrency.toUpperCase(),
        }
      };

      _sendMessage(unsubscribeMessage);

      _orderbookControllers[symbol]?.close();
      _orderbookControllers.remove(symbol);
    }
  }

  /// Send message to WebSocket
  void _sendMessage(Map<String, dynamic> message) {
    if (_isConnected && _channel != null) {
      _channel!.sink.add(json.encode(message));
    }
  }

  /// Handle incoming WebSocket messages
  void _handleMessage(dynamic message) {
    try {
      final data = json.decode(message.toString()) as Map<String, dynamic>;

      // Coinone uses 'response_type' instead of 'type'
      final responseType = data['response_type']?.toString();
      if (responseType == null) {
        print('[CoinoneWebSocket] No response_type field in message');
        return;
      }

      switch (responseType) {
        case 'DATA':
          // Real-time data update
          final channel = data['channel']?.toString();
          if (channel == 'TICKER') {
            _handleTickerUpdate(data['data'] as Map<String, dynamic>);
          } else if (channel == 'ORDERBOOK') {
            _handleOrderbookUpdate(data['data'] as Map<String, dynamic>);
          }
          break;
        case 'PONG':
          print('[CoinoneWebSocket] Received PONG');
          break;
        case 'SUBSCRIBED':
          print('[CoinoneWebSocket] Subscribed to ${data['channel']}');
          break;
        case 'UNSUBSCRIBED':
          print('[CoinoneWebSocket] Unsubscribed from ${data['channel']}');
          break;
        case 'CONNECTED':
          print('[CoinoneWebSocket] Connection established');
          break;
        case 'ERROR':
          print('[CoinoneWebSocket] ERROR: ${data['error_code']} - ${data['message']}');
          break;
        default:
          print('[CoinoneWebSocket] Unknown response type: $responseType');
      }
    } catch (e) {
      print('[CoinoneWebSocket] Error handling message: $e');
      print('[CoinoneWebSocket] Original message: $message');
    }
  }

  /// Handle ticker updates
  void _handleTickerUpdate(Map<String, dynamic> data) {
    try {
      final ticker = CoinoneTicker.fromJson(data);
      final symbol = ticker.symbol;

      if (_tickerControllers.containsKey(symbol)) {
        _tickerControllers[symbol]!.add(ticker);
      }
    } catch (e) {
      print('[CoinoneWebSocket] Error parsing ticker: $e');
    }
  }

  /// Handle orderbook updates
  void _handleOrderbookUpdate(Map<String, dynamic> data) {
    try {
      final orderbook = CoinoneOrderbook.fromJson(data);
      final symbol = orderbook.symbol;

      if (_orderbookControllers.containsKey(symbol)) {
        _orderbookControllers[symbol]!.add(orderbook);
      }
    } catch (e) {
      print('[CoinoneWebSocket] Error parsing orderbook: $e');
    }
  }

  /// Handle WebSocket errors
  void _handleError(dynamic error) {
    print('[CoinoneWebSocket] Error: $error');
    _isConnected = false;
    _scheduleReconnect();
  }

  /// Handle WebSocket connection closed
  void _handleDone() {
    print('[CoinoneWebSocket] Connection closed');
    _isConnected = false;
    _scheduleReconnect();
  }

  /// Start ping timer to keep connection alive
  void _startPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_isConnected) {
        _sendMessage({'request_type': 'PING'});
      }
    });
  }

  /// Schedule automatic reconnection
  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      if (!_isConnected) {
        print('[CoinoneWebSocket] Attempting to reconnect...');
        connect();
      }
    });
  }
}
