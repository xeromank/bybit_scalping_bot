import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

/// WebSocket client for Bybit public channels (ticker, kline, orderbook, etc.)
///
/// Responsibility: Manage WebSocket connection for public market data
///
/// Public channels don't require authentication and provide real-time:
/// - Ticker data (price, volume)
/// - K-line data (candlesticks)
/// - Order book data
/// - Trades
class BybitPublicWebSocketClient {
  final bool isTestnet;

  WebSocketChannel? _channel;
  Timer? _pingTimer;
  final Map<String, StreamController<Map<String, dynamic>>> _topicControllers = {};
  bool _isConnected = false;
  bool _isConnecting = false;

  BybitPublicWebSocketClient({
    this.isTestnet = false,
  });

  /// WebSocket URL for public channels
  String get _wsUrl {
    if (isTestnet) {
      return 'wss://stream-testnet.bybit.com/v5/public/linear';
    }
    return 'wss://stream.bybit.com/v5/public/linear';
  }

  /// Checks if WebSocket is connected
  bool get isConnected => _isConnected;

  /// Connects to WebSocket (no authentication needed for public channels)
  Future<void> connect() async {
    if (_isConnected || _isConnecting) {
      print('PublicWebSocket: Already connected or connecting');
      return;
    }

    _isConnecting = true;
    print('PublicWebSocket: Connecting to $_wsUrl');

    try {
      // Create WebSocket connection
      _channel = WebSocketChannel.connect(Uri.parse(_wsUrl));

      // Listen to messages
      _channel!.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDone,
        cancelOnError: false,
      );

      // Wait for connection
      await Future.delayed(const Duration(milliseconds: 500));

      _isConnected = true;
      _isConnecting = false;

      print('PublicWebSocket: Connected');

      // Start ping timer (send ping every 20 seconds)
      _startPingTimer();
    } catch (e) {
      print('PublicWebSocket: Connection error: $e');
      _isConnecting = false;
      _isConnected = false;
      rethrow;
    }
  }

  /// Subscribes to a topic
  ///
  /// Example topics:
  /// - 'tickers.BTCUSDT' - Ticker for BTCUSDT
  /// - 'kline.1.BTCUSDT' - 1-minute kline for BTCUSDT
  /// - 'orderbook.50.BTCUSDT' - Order book with depth 50
  /// - 'publicTrade.BTCUSDT' - Public trades
  Future<void> subscribe(String topic) async {
    if (!_isConnected) {
      print('PublicWebSocket: Cannot subscribe to $topic - not connected');
      throw Exception('WebSocket not connected. Call connect() first.');
    }

    final subscribeMessage = {
      'op': 'subscribe',
      'args': [topic],
    };

    print('PublicWebSocket: Subscribing to $topic');
    _channel?.sink.add(jsonEncode(subscribeMessage));

    // Create stream controller for this topic if not exists
    if (!_topicControllers.containsKey(topic)) {
      _topicControllers[topic] = StreamController<Map<String, dynamic>>.broadcast();
    }
  }

  /// Unsubscribes from a topic
  Future<void> unsubscribe(String topic) async {
    if (!_isConnected) {
      return;
    }

    final unsubscribeMessage = {
      'op': 'unsubscribe',
      'args': [topic],
    };

    _channel?.sink.add(jsonEncode(unsubscribeMessage));

    // Close and remove stream controller
    await _topicControllers[topic]?.close();
    _topicControllers.remove(topic);
  }

  /// Gets stream for a specific topic
  Stream<Map<String, dynamic>>? getStream(String topic) {
    return _topicControllers[topic]?.stream;
  }

  /// Handles incoming WebSocket messages
  void _onMessage(dynamic message) {
    try {
      final data = jsonDecode(message as String) as Map<String, dynamic>;

      // Handle pong response
      if (data['op'] == 'pong') {
        return;
      }

      // Handle subscription response
      if (data['op'] == 'subscribe') {
        print('PublicWebSocket: Subscription response: ${data['success']}');
        return;
      }

      // Handle topic data
      if (data.containsKey('topic')) {
        final topic = data['topic'] as String;

        // Find matching controller (exact match or wildcard)
        for (final entry in _topicControllers.entries) {
          // Check if topic matches (support wildcard patterns)
          if (_topicMatches(topic, entry.key)) {
            entry.value.add(data);
            break;
          }
        }
      }
    } catch (e) {
      print('PublicWebSocket: Error parsing message: $e');
    }
  }

  /// Checks if topic matches pattern (supports wildcards)
  bool _topicMatches(String topic, String pattern) {
    // Exact match
    if (topic == pattern) return true;

    // Pattern match (e.g., "tickers" matches "tickers.BTCUSDT")
    if (topic.startsWith(pattern)) return true;

    return false;
  }

  /// Handles WebSocket errors
  void _onError(error) {
    print('PublicWebSocket: Error: $error');
    _isConnected = false;
  }

  /// Handles WebSocket close
  void _onDone() {
    print('PublicWebSocket: Connection closed');
    _isConnected = false;
    _stopPingTimer();
  }

  /// Starts ping timer to keep connection alive
  void _startPingTimer() {
    _stopPingTimer();
    _pingTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (_isConnected) {
        final pingMessage = {'op': 'ping'};
        _channel?.sink.add(jsonEncode(pingMessage));
      }
    });
  }

  /// Stops ping timer
  void _stopPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = null;
  }

  /// Disconnects WebSocket
  Future<void> disconnect() async {
    _stopPingTimer();

    // Close all stream controllers
    for (final controller in _topicControllers.values) {
      await controller.close();
    }
    _topicControllers.clear();

    await _channel?.sink.close();
    _channel = null;
    _isConnected = false;
    _isConnecting = false;
  }

  /// Disposes resources
  void dispose() {
    disconnect();
  }
}
