import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:bybit_scalping_bot/utils/logger.dart';

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
  Function(bool isConnected)? onConnectionStatusChanged; // Mutable to allow setting after creation

  WebSocketChannel? _channel;
  Timer? _pingTimer;
  Timer? _pongTimeoutTimer;
  final Map<String, StreamController<Map<String, dynamic>>> _topicControllers = {};
  bool _isConnected = false;
  bool _isConnecting = false;
  bool _shouldReconnect = true;
  DateTime? _lastPingSentTime;
  DateTime? _lastPongReceivedTime;
  List<String> _subscribedTopics = [];

  BybitPublicWebSocketClient({
    this.isTestnet = false,
    this.onConnectionStatusChanged,
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
      Logger.debug('PublicWebSocket: Already connected or connecting');
      return;
    }

    _isConnecting = true;
    _shouldReconnect = true;
    Logger.debug('PublicWebSocket: Connecting to $_wsUrl');

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

      Logger.debug('PublicWebSocket: Connected');
      onConnectionStatusChanged?.call(true);

      // Start ping timer (send ping every 20 seconds)
      _startPingTimer();

      // Resubscribe to previous topics
      if (_subscribedTopics.isNotEmpty) {
        Logger.debug('PublicWebSocket: Resubscribing to ${_subscribedTopics.length} topics');
        for (final topic in _subscribedTopics) {
          await subscribe(topic);
        }
      }
    } catch (e) {
      Logger.error('PublicWebSocket: Connection error: $e');
      _isConnecting = false;
      _isConnected = false;
      onConnectionStatusChanged?.call(false);

      // Auto-reconnect after error
      if (_shouldReconnect) {
        Logger.debug('PublicWebSocket: Scheduling reconnection in 5 seconds...');
        Future.delayed(const Duration(seconds: 5), () => _reconnect());
      }
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
      Logger.error('PublicWebSocket: Cannot subscribe to $topic - not connected');
      throw Exception('WebSocket not connected. Call connect() first.');
    }

    final subscribeMessage = {
      'op': 'subscribe',
      'args': [topic],
    };

    Logger.debug('PublicWebSocket: Subscribing to $topic');
    _channel?.sink.add(jsonEncode(subscribeMessage));

    // Track subscribed topics for reconnection
    if (!_subscribedTopics.contains(topic)) {
      _subscribedTopics.add(topic);
    }

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

    // Remove from tracked topics
    _subscribedTopics.remove(topic);

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

      // Handle pong response (Public WebSocket format: {"op":"ping", "ret_msg":"pong"})
      if (data['op'] == 'ping' && data['ret_msg'] == 'pong') {
        _lastPongReceivedTime = DateTime.now();
        // Logger.debug('PublicWebSocket: Pong received');
        return;
      }

      // Also handle standard pong format (for compatibility)
      if (data['op'] == 'pong') {
        _lastPongReceivedTime = DateTime.now();
        // Logger.debug('PublicWebSocket: Pong received (standard format)');
        return;
      }

      // Handle subscription response
      if (data['op'] == 'subscribe') {
        Logger.debug('PublicWebSocket: Subscription response: ${data['success']}');
        return;
      }

      // Handle topic data
      if (data.containsKey('topic')) {
        final topic = data['topic'] as String;

        // Kline 데이터는 상세히 로깅
        if (topic.contains('kline')) {
          // Logger.debug('📊 [KLINE UPDATE] Topic: $topic');
          if (data['data'] != null) {
            final klines = data['data'] as List;
            for (var kline in klines) {
              final confirm = kline['confirm'] ?? false;
              // Logger.debug('🕯️  Kline: ${confirm ? "✅ CONFIRMED" : "⏳ UPDATING"}');
              // Logger.debug('   - start: ${kline['start']} | end: ${kline['end']}');
              // Logger.debug('   - open: ${kline['open']} | high: ${kline['high']} | low: ${kline['low']} | close: ${kline['close']}');
              // Logger.debug('   - volume: ${kline['volume']} | turnover: ${kline['turnover']}');
            }
          }
        }

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
      Logger.error('PublicWebSocket: Error parsing message: $e');
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
    Logger.error('PublicWebSocket: Error: $error');
    _isConnected = false;
    onConnectionStatusChanged?.call(false);

    // Auto-reconnect on error
    if (_shouldReconnect) {
      Logger.debug('PublicWebSocket: Scheduling reconnection in 5 seconds...');
      Future.delayed(const Duration(seconds: 5), () => _reconnect());
    }
  }

  /// Handles WebSocket close
  void _onDone() {
    Logger.debug('PublicWebSocket: Connection closed');
    final wasConnected = _isConnected;
    _isConnected = false;
    _stopPingTimer();
    _stopPongTimeoutTimer();

    if (wasConnected) {
      onConnectionStatusChanged?.call(false);
    }

    // Auto-reconnect on unexpected close
    if (_shouldReconnect) {
      Logger.debug('PublicWebSocket: Scheduling reconnection in 5 seconds...');
      Future.delayed(const Duration(seconds: 5), () => _reconnect());
    }
  }

  /// Starts ping timer to keep connection alive
  void _startPingTimer() {
    _stopPingTimer();
    _pingTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (_isConnected) {
        _lastPingSentTime = DateTime.now();
        // Public WebSocket requires req_id in ping message
        final pingMessage = {
          'req_id': DateTime.now().millisecondsSinceEpoch.toString(),
          'op': 'ping',
        };
        _channel?.sink.add(jsonEncode(pingMessage));
        // Logger.debug('PublicWebSocket: Ping sent');

        // Start pong timeout check (10 seconds)
        _startPongTimeoutTimer();
      }
    });
  }

  /// Stops ping timer
  void _stopPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = null;
  }

  /// Starts pong timeout timer (10 seconds)
  void _startPongTimeoutTimer() {
    _stopPongTimeoutTimer();
    _pongTimeoutTimer = Timer(const Duration(seconds: 30), () {
      // Check if pong was received
      if (_lastPingSentTime != null &&
          (_lastPongReceivedTime == null ||
           _lastPongReceivedTime!.isBefore(_lastPingSentTime!))) {
        Logger.warning('PublicWebSocket: Pong timeout - reconnecting...');
        _handlePongTimeout();
      }
    });
  }

  /// Stops pong timeout timer
  void _stopPongTimeoutTimer() {
    _pongTimeoutTimer?.cancel();
    _pongTimeoutTimer = null;
  }

  /// Handles pong timeout - triggers reconnection
  void _handlePongTimeout() {
    _isConnected = false;
    _stopPingTimer();
    _stopPongTimeoutTimer();
    onConnectionStatusChanged?.call(false);

    // Close current connection
    _channel?.sink.close();

    // Reconnect
    if (_shouldReconnect) {
      Logger.debug('PublicWebSocket: Reconnecting due to pong timeout...');
      _reconnect();
    }
  }

  /// Reconnects to WebSocket
  Future<void> _reconnect() async {
    if (_isConnecting || _isConnected) {
      return;
    }

    Logger.debug('PublicWebSocket: Attempting to reconnect...');

    try {
      await connect();
    } catch (e) {
      Logger.error('PublicWebSocket: Reconnection failed: $e');
      // connect() already schedules another reconnection on error
    }
  }

  /// Disconnects WebSocket
  Future<void> disconnect() async {
    _shouldReconnect = false; // Prevent auto-reconnect
    _stopPingTimer();
    _stopPongTimeoutTimer();

    // Close all stream controllers
    for (final controller in _topicControllers.values) {
      await controller.close();
    }
    _topicControllers.clear();
    _subscribedTopics.clear();

    await _channel?.sink.close();
    _channel = null;
    _isConnected = false;
    _isConnecting = false;
    onConnectionStatusChanged?.call(false);
  }

  /// Disposes resources
  void dispose() {
    disconnect();
  }
}
