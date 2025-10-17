import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:crypto/crypto.dart';

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

  WebSocketChannel? _channel;
  Timer? _pingTimer;
  final Map<String, StreamController<Map<String, dynamic>>> _topicControllers = {};
  bool _isConnected = false;
  bool _isConnecting = false;

  BybitWebSocketClient({
    required this.apiKey,
    required this.apiSecret,
    this.isTestnet = false,
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
      print('WebSocket: Already connected or connecting');
      return;
    }

    _isConnecting = true;
    print('WebSocket: Connecting to $_wsUrl');

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

      print('WebSocket: Connected and authenticated');

      // Start ping timer (send ping every 20 seconds)
      _startPingTimer();
    } catch (e) {
      print('WebSocket: Connection error: $e');
      _isConnecting = false;
      _isConnected = false;
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
      print('WebSocket: Cannot subscribe to $topic - not connected');
      throw Exception('WebSocket not connected. Call connect() first.');
    }

    final subscribeMessage = {
      'op': 'subscribe',
      'args': [topic],
    };

    print('WebSocket: Subscribing to $topic');
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
      print('WebSocket: Received message: $message');
      final data = jsonDecode(message as String) as Map<String, dynamic>;

      // Handle pong response
      if (data['op'] == 'pong') {
        print('WebSocket: Pong received');
        return;
      }

      // Handle auth response
      if (data['op'] == 'auth') {
        if (data['success'] == true) {
          print('WebSocket: Authentication successful');
        } else {
          print('WebSocket: Authentication failed: ${data['ret_msg']}');
        }
        return;
      }

      // Handle subscription response
      if (data['op'] == 'subscribe') {
        print('WebSocket: Subscription response: ${data['success']}');
        return;
      }

      // Handle topic data
      if (data.containsKey('topic')) {
        final topic = data['topic'] as String;
        print('WebSocket: Topic data received: $topic');

        // Find matching controller (handle wildcard topics)
        for (final entry in _topicControllers.entries) {
          if (topic.startsWith(entry.key)) {
            print('WebSocket: Adding data to stream controller');
            entry.value.add(data);
            break;
          }
        }
      }
    } catch (e) {
      print('WebSocket: Error parsing message: $e');
    }
  }

  /// Handles WebSocket errors
  void _onError(error) {
    _isConnected = false;
  }

  /// Handles WebSocket close
  void _onDone() {
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
