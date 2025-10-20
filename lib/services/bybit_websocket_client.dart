import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:crypto/crypto.dart';
import 'package:bybit_scalping_bot/utils/logger.dart';

/// WebSocket client for Bybit private channels
///
/// Responsibility: Manage WebSocket connection and subscriptions for real-time data
///
/// This client handles:
/// - WebSocket connection lifecycle
/// - Authentication with API key and signature
/// - Subscription management for private channels (position, order, wallet)
/// - Message parsing and error handling
/// - Auto-reconnection on disconnect
class BybitWebSocketClient {
  final String apiKey;
  final String apiSecret;
  final bool isTestnet;
  final Function(bool isConnected)? onConnectionStatusChanged;

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

  BybitWebSocketClient({
    required this.apiKey,
    required this.apiSecret,
    this.isTestnet = false,
    this.onConnectionStatusChanged,
  });

  /// WebSocket URL for private channels
  String get _wsUrl {
    if (isTestnet) {
      return 'wss://stream-testnet.bybit.com/v5/private';
    }
    return 'wss://stream.bybit.com/v5/private';
  }

  /// Checks if WebSocket is connected
  bool get isConnected => _isConnected;

  /// Connects to WebSocket and authenticates
  Future<void> connect() async {
    if (_isConnected || _isConnecting) {
      Logger.debug('WebSocket: Already connected or connecting');
      return;
    }

    _isConnecting = true;
    _shouldReconnect = true;
    Logger.debug('WebSocket: Connecting to $_wsUrl');

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

      // Authenticate
      await _authenticate();

      _isConnected = true;
      _isConnecting = false;

      Logger.debug('WebSocket: Connected and authenticated');
      onConnectionStatusChanged?.call(true);

      // Start ping timer (send ping every 20 seconds)
      _startPingTimer();

      // Resubscribe to previous topics
      if (_subscribedTopics.isNotEmpty) {
        Logger.debug('WebSocket: Resubscribing to ${_subscribedTopics.length} topics');
        for (final topic in _subscribedTopics) {
          await subscribe(topic);
        }
      }
    } catch (e) {
      Logger.error('WebSocket: Connection error: $e');
      _isConnecting = false;
      _isConnected = false;
      onConnectionStatusChanged?.call(false);

      // Auto-reconnect after error
      if (_shouldReconnect) {
        Logger.debug('WebSocket: Scheduling reconnection in 5 seconds...');
        Future.delayed(const Duration(seconds: 5), () => _reconnect());
      }
      rethrow;
    }
  }

  /// Authenticates with API key and signature
  Future<void> _authenticate() async {
    final expires = DateTime.now().millisecondsSinceEpoch + 10000;
    final signature = _generateSignature(expires);

    final authMessage = {
      'op': 'auth',
      'args': [apiKey, expires.toString(), signature],
    };

    _channel?.sink.add(jsonEncode(authMessage));

    // Wait for auth response
    await Future.delayed(const Duration(milliseconds: 500));
  }

  /// Generates HMAC SHA256 signature for authentication
  String _generateSignature(int expires) {
    final message = 'GET/realtime$expires';
    final key = utf8.encode(apiSecret);
    final bytes = utf8.encode(message);
    final hmac = Hmac(sha256, key);
    final digest = hmac.convert(bytes);
    return digest.toString();
  }

  /// Subscribes to a topic
  ///
  /// Example topics:
  /// - 'position' - Position updates
  /// - 'order' - Order updates
  /// - 'wallet' - Wallet updates
  Future<void> subscribe(String topic) async {
    if (!_isConnected) {
      Logger.warning('WebSocket: Cannot subscribe to $topic - not connected');
      throw Exception('WebSocket not connected. Call connect() first.');
    }

    final subscribeMessage = {
      'op': 'subscribe',
      'args': [topic],
    };

    Logger.debug('WebSocket: Subscribing to $topic');
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
      Logger.debug('WebSocket: Received message: $message');
      final data = jsonDecode(message as String) as Map<String, dynamic>;

      // Handle pong response
      if (data['op'] == 'pong') {
        _lastPongReceivedTime = DateTime.now();
        Logger.debug('WebSocket: Pong received');
        return;
      }

      // Handle auth response
      if (data['op'] == 'auth') {
        if (data['success'] == true) {
          Logger.debug('WebSocket: Authentication successful');
        } else {
          Logger.error('WebSocket: Authentication failed: ${data['ret_msg']}');
        }
        return;
      }

      // Handle subscription response
      if (data['op'] == 'subscribe') {
        Logger.debug('WebSocket: Subscription response: ${data['success']}');
        return;
      }

      // Handle topic data
      if (data.containsKey('topic')) {
        final topic = data['topic'] as String;
        Logger.debug('WebSocket: Topic data received: $topic');

        // Find matching controller (handle wildcard topics)
        for (final entry in _topicControllers.entries) {
          if (topic.startsWith(entry.key)) {
            Logger.debug('WebSocket: Adding data to stream controller');
            entry.value.add(data);
            break;
          }
        }
      }
    } catch (e) {
      Logger.error('WebSocket: Error parsing message: $e');
    }
  }

  /// Handles WebSocket errors
  void _onError(error) {
    Logger.error('WebSocket: Error: $error');
    _isConnected = false;
    onConnectionStatusChanged?.call(false);

    // Auto-reconnect on error
    if (_shouldReconnect) {
      Logger.debug('WebSocket: Scheduling reconnection in 5 seconds...');
      Future.delayed(const Duration(seconds: 5), () => _reconnect());
    }
  }

  /// Handles WebSocket close
  void _onDone() {
    Logger.debug('WebSocket: Connection closed');
    final wasConnected = _isConnected;
    _isConnected = false;
    _stopPingTimer();
    _stopPongTimeoutTimer();

    if (wasConnected) {
      onConnectionStatusChanged?.call(false);
    }

    // Auto-reconnect on unexpected close
    if (_shouldReconnect) {
      Logger.debug('WebSocket: Scheduling reconnection in 5 seconds...');
      Future.delayed(const Duration(seconds: 5), () => _reconnect());
    }
  }

  /// Starts ping timer to keep connection alive
  void _startPingTimer() {
    _stopPingTimer();
    _pingTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (_isConnected) {
        _lastPingSentTime = DateTime.now();
        final pingMessage = {'op': 'ping'};
        _channel?.sink.add(jsonEncode(pingMessage));
        Logger.debug('WebSocket: Ping sent');

        // Start pong timeout check (3 seconds)
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
    _pongTimeoutTimer = Timer(const Duration(seconds: 10), () {
      // Check if pong was received
      if (_lastPingSentTime != null &&
          (_lastPongReceivedTime == null ||
              _lastPongReceivedTime!.isBefore(_lastPingSentTime!))) {
        Logger.warning('WebSocket: Pong timeout - reconnecting...');
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
      Logger.debug('WebSocket: Reconnecting due to pong timeout...');
      _reconnect();
    }
  }

  /// Reconnects to WebSocket
  Future<void> _reconnect() async {
    if (_isConnecting || _isConnected) {
      return;
    }

    Logger.debug('WebSocket: Attempting to reconnect...');

    try {
      await connect();
    } catch (e) {
      Logger.error('WebSocket: Reconnection failed: $e');
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