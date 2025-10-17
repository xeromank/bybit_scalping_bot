import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:bybit_scalping_bot/models/wallet_balance.dart';
import 'package:bybit_scalping_bot/models/position.dart';
import 'package:bybit_scalping_bot/repositories/bybit_repository.dart';
import 'package:bybit_scalping_bot/services/bybit_websocket_client.dart';
import 'package:bybit_scalping_bot/services/bybit_public_websocket_client.dart';

// For CoinBalance type
export 'package:bybit_scalping_bot/models/wallet_balance.dart' show CoinBalance;

/// Provider for wallet balance state and operations
///
/// Responsibility: Manage wallet balance state and business logic
///
/// This provider manages wallet balance data and provides methods
/// to fetch and refresh balance information.
class BalanceProvider extends ChangeNotifier {
  final BybitRepository _repository;
  final BybitWebSocketClient? _wsClient;
  final BybitPublicWebSocketClient? _publicWsClient;

  // State
  WalletBalance? _balance;
  List<Position> _positions = [];
  bool _isLoading = false;
  String? _errorMessage;
  DateTime? _lastUpdated;
  StreamSubscription? _positionSubscription;
  final Map<String, StreamSubscription> _klineSubscriptions = {};
  Timer? _autoRefreshTimer;

  BalanceProvider({
    required BybitRepository repository,
    BybitWebSocketClient? wsClient,
    BybitPublicWebSocketClient? publicWsClient,
  })  : _repository = repository,
        _wsClient = wsClient,
        _publicWsClient = publicWsClient;

  // Getters
  WalletBalance? get balance => _balance;
  List<Position> get positions => List.unmodifiable(_positions);
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  DateTime? get lastUpdated => _lastUpdated;

  /// Checks if there are any open positions
  bool get hasOpenPositions => _positions.isNotEmpty;

  /// Gets USDT coin balance object
  CoinBalance? get usdtCoin => _balance?.usdtBalance;

  /// Gets USDT wallet balance (총 지갑 잔고)
  String get usdtWalletBalanceFormatted {
    final usdt = usdtCoin;
    if (usdt == null) return '0.00';
    return usdt.walletBalanceAsDouble.toStringAsFixed(2);
  }

  /// Gets USDT equity (현재 가치, unrealised PnL 포함)
  String get usdtEquityFormatted {
    final usdt = usdtCoin;
    if (usdt == null) return '0.00';
    return usdt.equityAsDouble.toStringAsFixed(2);
  }

  /// Gets USDT position IM (포지션에 투여한 금액)
  String get usdtPositionIMFormatted {
    final usdt = usdtCoin;
    if (usdt == null) return '0.00';
    return usdt.totalPositionIMAsDouble.toStringAsFixed(2);
  }

  /// Gets USDT available balance (주문 가능 금액 = walletBalance - totalPositionIM)
  String get usdtAvailableBalanceFormatted {
    final usdt = usdtCoin;
    if (usdt == null) return '0.00';
    return usdt.availableBalance.toStringAsFixed(2);
  }

  /// Gets USDT unrealised PnL (미실현 손익)
  String get usdtUnrealisedPnlFormatted {
    final usdt = usdtCoin;
    if (usdt == null) return '0.00';
    return usdt.unrealisedPnlAsDouble.toStringAsFixed(2);
  }

  /// Gets USDT cumulative realised PnL (누적 실현 손익)
  String get usdtCumRealisedPnlFormatted {
    final usdt = usdtCoin;
    if (usdt == null) return '0.00';
    final pnl = double.tryParse(usdt.cumRealisedPnl) ?? 0.0;
    return pnl.toStringAsFixed(2);
  }

  /// Fetches wallet balance and positions
  Future<void> fetchBalance({String accountType = 'UNIFIED'}) async {
    _setLoading(true);
    _errorMessage = null;

    // Start auto-refresh timer if not already running
    _startAutoRefresh();

    // Fetch balance
    final balanceResult = await _repository.getWalletBalance(
      accountType: accountType,
    );

    balanceResult.when(
      success: (balance) {
        _balance = balance;
        _lastUpdated = DateTime.now();
        _errorMessage = null;
      },
      failure: (message, exception) {
        _errorMessage = message;
      },
    );

    // If WebSocket is available, subscribe to position updates
    if (_wsClient != null && _wsClient!.isConnected) {
      print('BalanceProvider: Using WebSocket for positions');
      await _subscribeToPositions();
    } else {
      // Fallback to API polling
      print('BalanceProvider: Using API polling for positions (WebSocket: ${_wsClient != null ? "not connected" : "null"})');
      final positionsResult = await _repository.getAllPositions();

      positionsResult.when(
        success: (positions) {
          _positions = positions;
          print('BalanceProvider: Loaded ${positions.length} positions from API');
          for (final pos in positions) {
            print('  - ${pos.symbol}: ${pos.isLong ? "LONG" : "SHORT"}');
            print('    Entry: \$${pos.avgPrice}, Mark: \$${pos.markPrice}, Size: ${pos.size}');
            print('    Position IM: \$${pos.positionIM}, Leverage: ${pos.leverage}x');
            print('    Real-time unrealisedPnl: \$${pos.realtimeUnrealisedPnl.toStringAsFixed(2)}');
            print('    ROE: ${pos.pnlPercent.toStringAsFixed(2)}%');

            // Subscribe to kline for real-time price updates
            _subscribeToKlineForSymbol(pos.symbol);
          }
        },
        failure: (message, exception) {
          // Don't override error message if balance fetch already failed
          if (_errorMessage == null) {
            _errorMessage = message;
          }
          print('BalanceProvider: Failed to load positions: $message');
        },
      );
    }

    _setLoading(false);
  }

  /// Subscribes to position updates via WebSocket
  Future<void> _subscribeToPositions() async {
    if (_wsClient == null || !_wsClient!.isConnected) {
      return;
    }

    try {
      // Subscribe to position topic
      await _wsClient!.subscribe('position');

      // Listen to position updates
      _positionSubscription?.cancel();
      _positionSubscription = _wsClient!.getStream('position')?.listen(
        (data) {
          _handlePositionUpdate(data);
        },
        onError: (error) {
          _errorMessage = 'Position WebSocket error: ${error.toString()}';
          notifyListeners();
        },
      );
    } catch (e) {
      _errorMessage = 'Failed to subscribe to positions: ${e.toString()}';
      notifyListeners();
    }
  }

  /// Handles position update from WebSocket
  void _handlePositionUpdate(Map<String, dynamic> data) {
    try {
      print('BalanceProvider: Handling position update');
      if (data['topic'] != 'position') {
        return;
      }

      final positionData = data['data'] as List<dynamic>;
      print('BalanceProvider: Processing ${positionData.length} position(s)');

      // Update positions
      for (final item in positionData) {
        final position = Position.fromJson(item as Map<String, dynamic>);
        print('BalanceProvider: Position - ${position.symbol} ${position.isLong ? "LONG" : "SHORT"} size: ${position.size}');

        // Find existing position by symbol
        final index = _positions.indexWhere((p) => p.symbol == position.symbol);

        if (position.isOpen) {
          if (index >= 0) {
            // Update existing position
            print('BalanceProvider: Updating existing position');
            _positions[index] = position;
          } else {
            // Add new position
            print('BalanceProvider: Adding new position');
            _positions.add(position);

            // Subscribe to kline for this position's symbol
            _subscribeToKlineForSymbol(position.symbol);
          }
        } else {
          if (index >= 0) {
            // Remove closed position
            print('BalanceProvider: Removing closed position');
            _positions.removeAt(index);

            // Unsubscribe from kline for this symbol
            _unsubscribeFromKlineForSymbol(position.symbol);
          }
        }
      }

      print('BalanceProvider: Total positions: ${_positions.length}');
      _lastUpdated = DateTime.now();
      notifyListeners();
    } catch (e) {
      print('BalanceProvider: Error handling position update: $e');
      _errorMessage = 'Failed to parse position update: ${e.toString()}';
      notifyListeners();
    }
  }

  /// Subscribes to kline WebSocket for a specific symbol to get real-time price
  Future<void> _subscribeToKlineForSymbol(String symbol) async {
    if (_publicWsClient == null || !_publicWsClient!.isConnected) {
      print('BalanceProvider: Public WebSocket not available for kline subscription');
      return;
    }

    // Don't subscribe if already subscribed
    if (_klineSubscriptions.containsKey(symbol)) {
      print('BalanceProvider: Already subscribed to kline for $symbol');
      return;
    }

    try {
      final topic = 'kline.1.$symbol';
      await _publicWsClient!.subscribe(topic);
      print('BalanceProvider: Subscribed to kline for $symbol');

      // Listen to kline updates for real-time price
      final subscription = _publicWsClient!.getStream(topic)?.listen(
        (data) {
          _handleKlineUpdate(data, symbol);
        },
        onError: (error) {
          print('BalanceProvider: Kline WebSocket error for $symbol: $error');
        },
      );

      if (subscription != null) {
        _klineSubscriptions[symbol] = subscription;
      }
    } catch (e) {
      print('BalanceProvider: Failed to subscribe to kline for $symbol: $e');
    }
  }

  /// Handles kline update to update position's mark price
  void _handleKlineUpdate(Map<String, dynamic> data, String symbol) {
    try {
      if (data['topic'] == null || !data['topic'].toString().startsWith('kline')) {
        return;
      }

      final klineData = data['data'] as List<dynamic>;
      if (klineData.isEmpty) return;

      final kline = klineData[0] as Map<String, dynamic>;
      final closePrice = double.tryParse(kline['close']?.toString() ?? '0') ?? 0.0;

      if (closePrice <= 0) return;

      // Update the position's mark price
      final index = _positions.indexWhere((p) => p.symbol == symbol);
      if (index >= 0) {
        final oldPosition = _positions[index];
        _positions[index] = oldPosition.copyWith(
          markPrice: closePrice.toString(),
        );

        // Notify listeners to update UI
        notifyListeners();

        print('BalanceProvider: Updated $symbol markPrice to \$${closePrice.toStringAsFixed(2)} → unrealisedPnl: \$${_positions[index].realtimeUnrealisedPnl.toStringAsFixed(2)}, ROE: ${_positions[index].pnlPercent.toStringAsFixed(2)}%');
      }
    } catch (e) {
      print('BalanceProvider: Error handling kline update: $e');
    }
  }

  /// Unsubscribes from kline WebSocket for a specific symbol
  Future<void> _unsubscribeFromKlineForSymbol(String symbol) async {
    final subscription = _klineSubscriptions[symbol];
    if (subscription != null) {
      await subscription.cancel();
      _klineSubscriptions.remove(symbol);

      if (_publicWsClient != null && _publicWsClient!.isConnected) {
        await _publicWsClient!.unsubscribe('kline.1.$symbol');
      }

      print('BalanceProvider: Unsubscribed from kline for $symbol');
    }
  }

  /// Refreshes wallet balance (same as fetch but with explicit name)
  Future<void> refresh() async {
    await fetchBalance();
  }

  /// Clears error message
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  /// Sets loading state
  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  /// Starts auto-refresh timer (every 10 seconds)
  void _startAutoRefresh() {
    // Cancel existing timer if any
    _autoRefreshTimer?.cancel();

    // Start new timer for auto-refresh every 10 seconds
    _autoRefreshTimer = Timer.periodic(
      const Duration(seconds: 10),
      (timer) async {
        print('BalanceProvider: Auto-refreshing balance...');
        await _refreshBalanceOnly();
      },
    );

    print('BalanceProvider: Auto-refresh timer started (every 10 seconds)');
  }

  /// Refreshes only the balance (without reloading positions)
  Future<void> _refreshBalanceOnly() async {
    // Don't show loading indicator for auto-refresh
    final balanceResult = await _repository.getWalletBalance(
      accountType: 'UNIFIED',
    );

    balanceResult.when(
      success: (balance) {
        _balance = balance;
        _lastUpdated = DateTime.now();
        _errorMessage = null;
        notifyListeners();
      },
      failure: (message, exception) {
        // Silently fail for auto-refresh
        print('BalanceProvider: Auto-refresh failed: $message');
      },
    );
  }

  /// Stops auto-refresh timer
  void stopAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = null;
    print('BalanceProvider: Auto-refresh timer stopped');
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _autoRefreshTimer?.cancel();

    // Cancel all kline subscriptions
    for (final subscription in _klineSubscriptions.values) {
      subscription.cancel();
    }
    _klineSubscriptions.clear();

    super.dispose();
  }
}
