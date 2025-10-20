import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:bybit_scalping_bot/core/result/result.dart';
import 'package:bybit_scalping_bot/models/coinone/coinone_chart.dart';
import 'package:bybit_scalping_bot/models/coinone/coinone_order.dart';
import 'package:bybit_scalping_bot/models/coinone/coinone_ticker.dart';
import 'package:bybit_scalping_bot/models/coinone/coinone_orderbook.dart';
import 'package:bybit_scalping_bot/models/coinone/technical_indicators.dart';
import 'package:bybit_scalping_bot/models/coinone/trading_signal.dart';
import 'package:bybit_scalping_bot/repositories/coinone_repository.dart';
import 'package:bybit_scalping_bot/services/coinone/coinone_database_service.dart';
import 'package:bybit_scalping_bot/services/coinone/technical_indicator_calculator.dart';
import 'package:bybit_scalping_bot/services/coinone/coinone_websocket_client.dart';
import 'package:bybit_scalping_bot/services/coinone/market_trend_detector.dart';
import 'package:bybit_scalping_bot/services/coinone/volatility_calculator.dart';
import 'package:bybit_scalping_bot/services/coinone/strategies/uptrend_strategy.dart';
import 'package:bybit_scalping_bot/services/coinone/strategies/sideways_strategy.dart';

/// Provider for Coinone trading operations
///
/// Responsibility: Manage Coinone spot trading bot logic
///
/// Features:
/// - Market-adaptive trading strategy (uptrend/sideways/downtrend)
/// - Real-time ticker and orderbook via WebSocket
/// - Automatic order placement and tracking
/// - Trade logging to SQLite
/// - WebSocket-based market monitoring
/// - Dynamic parameter adjustment based on volatility
///
/// Benefits:
/// - Completely separate from Bybit trading logic
/// - Real-time market data updates
/// - Adaptive strategy selection based on market conditions
/// - Full trade history in database
class CoinoneTradingProvider extends ChangeNotifier {
  final CoinoneRepository _repository;
  final CoinoneDatabaseService _databaseService = CoinoneDatabaseService();
  final TechnicalIndicatorCalculator _indicatorCalculator = TechnicalIndicatorCalculator();
  final MarketTrendDetector _trendDetector = MarketTrendDetector();
  final VolatilityCalculator _volatilityCalculator = VolatilityCalculator();
  final UptrendStrategy _uptrendStrategy = UptrendStrategy();
  final SidewaysStrategy _sidewaysStrategy = SidewaysStrategy();
  final CoinoneWebSocketClient _wsClient;

  // State
  String _symbol = 'XRP'; // Trading pair (e.g., BTC, ETH)
  bool _isBotRunning = false;
  bool _isLoading = false;
  bool _isTestTrading = false;
  String? _errorMessage;
  Timer? _testTradeTimer;

  // Market data
  CoinoneTicker? _currentTicker;
  CoinoneOrderbook? _currentOrderbook;
  TechnicalIndicators? _technicalIndicators;
  Timer? _indicatorUpdateTimer;

  // Strategy state
  MarketTrend? _currentTrend;
  VolatilityLevel? _currentVolatility;
  double _volatilityPercent = 0.0;
  TradingSignal? _lastSignal;
  double? _entryPrice; // Track entry price for position management
  double? _stopLossPrice; // Stop loss price from signal
  double? _takeProfitPrice; // Take profit price from signal

  // Trading state
  CoinoneOrder? _activeOrder; // Current open order
  List<CoinoneOrder> _orderHistory = [];
  Timer? _botTimer;
  StreamSubscription? _tickerSubscription;
  StreamSubscription? _orderbookSubscription;

  // Trading parameters
  double _orderKrwAmount = 50000.0; // KRW amount for market buy/bot trading (default: 50,000 KRW)
  double _orderQuantity = 10.0; // Coin quantity for limit orders only
  bool _useMarketOrder = true; // Market vs Limit orders
  double _orderPrice = 0.0; // Price for limit orders
  String _orderSide = 'buy'; // 'buy' or 'sell'
  bool _useAllKrwBalance = false; // Use all available KRW balance for trading

  CoinoneTradingProvider({
    required CoinoneRepository repository,
    required CoinoneWebSocketClient wsClient,
  })  : _repository = repository,
        _wsClient = wsClient;

  // Getters
  String get symbol => _symbol;
  bool get isBotRunning => _isBotRunning;
  bool get isLoading => _isLoading;
  bool get isTestTrading => _isTestTrading;
  String? get errorMessage => _errorMessage;
  CoinoneTicker? get currentTicker => _currentTicker;
  CoinoneOrderbook? get currentOrderbook => _currentOrderbook;
  TechnicalIndicators? get technicalIndicators => _technicalIndicators;
  CoinoneOrder? get activeOrder => _activeOrder;
  List<CoinoneOrder> get orderHistory => _orderHistory;
  double get orderQuantity => _orderQuantity;
  bool get useMarketOrder => _useMarketOrder;
  double get orderPrice => _orderPrice;
  double get orderKrwAmount => _orderKrwAmount;
  String get orderSide => _orderSide;
  bool get useAllKrwBalance => _useAllKrwBalance;

  // Strategy getters
  MarketTrend? get currentTrend => _currentTrend;
  VolatilityLevel? get currentVolatility => _currentVolatility;
  double get volatilityPercent => _volatilityPercent;
  TradingSignal? get lastSignal => _lastSignal;
  String get currentStrategyName {
    if (_currentTrend == null) return 'Unknown';
    switch (_currentTrend!) {
      case MarketTrend.uptrend:
        return _uptrendStrategy.name;
      case MarketTrend.sideways:
        return _sidewaysStrategy.name;
      case MarketTrend.downtrend:
        return 'No Trade (Downtrend)';
    }
  }

  /// Set trading symbol
  void setSymbol(String newSymbol) {
    if (_isBotRunning) {
      _logTrade('error', 'Cannot change symbol while bot is running');
      return;
    }

    _symbol = newSymbol;
    _currentTicker = null;
    _currentOrderbook = null;
    _technicalIndicators = null;
    _currentTrend = null;
    _currentVolatility = null;
    _volatilityPercent = 0.0;
    _lastSignal = null;

    // Restart indicator updates if already started
    if (_indicatorUpdateTimer != null) {
      startIndicatorUpdates();
    }

    notifyListeners();
  }

  /// Start periodic technical indicator updates
  Future<void> startIndicatorUpdates() async {
    // Cancel existing timer
    _indicatorUpdateTimer?.cancel();

    // Fetch initial data
    await _updateTechnicalIndicators();

    // Update every 0.5 seconds
    _indicatorUpdateTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => _updateTechnicalIndicators(),
    );
  }

  /// Stop technical indicator updates
  void stopIndicatorUpdates() {
    _indicatorUpdateTimer?.cancel();
    _indicatorUpdateTimer = null;
  }

  /// Update technical indicators
  Future<void> _updateTechnicalIndicators() async {
    try {
      // Fetch chart data
      final result = await _repository.getChartData(
        quoteCurrency: 'KRW',
        targetCurrency: _symbol,
        interval: ChartInterval.fiveMinutes,
      );

      if (result is Success<CoinoneChartData>) {
        // Calculate technical indicators
        _technicalIndicators = _indicatorCalculator.calculate(result.data.candles);

        // Update trend and volatility
        if (_technicalIndicators != null) {
          _currentTrend = _trendDetector.detectTrend(_technicalIndicators!);
          _volatilityPercent = _volatilityCalculator.calculateVolatility(result.data.candles);
          _currentVolatility = _volatilityCalculator.classifyVolatility(_volatilityPercent);
        }

        notifyListeners();
      } else if (result is Failure<CoinoneChartData>) {
        debugPrint('[TechnicalIndicators] Failed to fetch chart data: ${result.message}');
      }
    } catch (e) {
      debugPrint('[TechnicalIndicators] Error updating indicators: $e');
    }
  }

  /// Set order quantity
  void setOrderQuantity(double quantity) {
    _orderQuantity = quantity;
    notifyListeners();
  }

  /// Set order KRW amount
  void setOrderKrwAmount(double amount) {
    _orderKrwAmount = amount;
    notifyListeners();
  }

  /// Set order type (market vs limit)
  void setUseMarketOrder(bool useMarket) {
    _useMarketOrder = useMarket;
    notifyListeners();
  }

  /// Set order price (for limit orders)
  void setOrderPrice(double price) {
    _orderPrice = price;
    notifyListeners();
  }

  /// Set order side (buy or sell)
  void setOrderSide(String side) {
    _orderSide = side;
    notifyListeners();
  }

  /// Set whether to use all available KRW balance
  void setUseAllKrwBalance(bool useAll) {
    _useAllKrwBalance = useAll;
    notifyListeners();
  }

  /// Get actual order amount (either fixed amount or all balance)
  Future<double> getActualOrderAmount() async {
    if (!_useAllKrwBalance) {
      return _orderKrwAmount;
    }

    // Fetch current KRW balance
    final balanceResult = await _repository.getAvailableBalance('KRW');
    if (balanceResult is Success<double>) {
      final balance = balanceResult.data;
      // Use 99% of balance to avoid insufficient balance errors
      return balance * 0.99;
    }

    // Fallback to fixed amount if balance fetch fails
    return _orderKrwAmount;
  }

  /// Start the trading bot
  Future<void> startBot() async {
    if (_isBotRunning) {
      return;
    }

    _setLoading(true);
    _errorMessage = null;

    try {
      // Initialize database
      await _databaseService.database;

      // Fetch initial chart data and calculate indicators
      await _updateTechnicalIndicators();

      if (_technicalIndicators == null) {
        throw Exception('Failed to calculate technical indicators (need at least 200 candles)');
      }

      // Connect WebSocket
      await _wsClient.connect();

      // Subscribe to ticker and orderbook and listen to streams
      _tickerSubscription = _wsClient.subscribeTicker('KRW', _symbol).listen((ticker) {
        _currentTicker = ticker;
        notifyListeners();
      });

      _orderbookSubscription = _wsClient.subscribeOrderbook('KRW', _symbol).listen((orderbook) {
        _currentOrderbook = orderbook;
        notifyListeners();
      });

      // Fetch order history
      await _fetchOrderHistory();

      // Start bot timer (check every 1 second)
      _botTimer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => _runBotCycle(),
      );

      _isBotRunning = true;

      // Enable wakelock to keep screen on
      await WakelockPlus.enable();
      _logTrade('info', 'Screen will stay awake while bot is running');

      _logTrade('success', 'Trading bot started for $symbol');
    } catch (e) {
      _errorMessage = e.toString();
      _logTrade('error', 'Failed to start bot: $e');
    } finally {
      _setLoading(false);
    }
  }

  /// Stop the trading bot
  Future<void> stopBot() async {
    if (!_isBotRunning) {
      return;
    }

    _isBotRunning = false;

    // Cancel timer
    _botTimer?.cancel();
    _botTimer = null;

    // Cancel WebSocket subscriptions
    await _tickerSubscription?.cancel();
    await _orderbookSubscription?.cancel();
    _tickerSubscription = null;
    _orderbookSubscription = null;

    // Disconnect WebSocket
    _wsClient.disconnect();

    // Disable wakelock to allow screen to sleep
    await WakelockPlus.disable();

    _logTrade('success', 'Trading bot stopped');
    notifyListeners();
  }

  /// Main bot cycle - runs every 3 seconds
  Future<void> _runBotCycle() async {
    if (!_isBotRunning) return;

    try {
      // Update indicators and trend
      await _updateTechnicalIndicators();

      if (_technicalIndicators == null || _currentTrend == null) {
        return;
      }

      // Log current market state
      final trendDesc = _trendDetector.getTrendDescription(_currentTrend!);
      final volatilityDesc = _currentVolatility != null
          ? _volatilityCalculator.getVolatilityDescription(_currentVolatility!)
          : '알 수 없음';

      debugPrint('[Bot Cycle] Trend: $trendDesc, Volatility: $volatilityDesc (${_volatilityPercent.toStringAsFixed(2)}%)');

      // Check if we should close existing position
      if (_activeOrder != null && _entryPrice != null) {
        final currentPrice = _technicalIndicators!.currentPrice;
        final shouldClose = _checkShouldClosePosition(currentPrice);

        if (shouldClose) {
          _logTrade('info', 'Exit condition met - closing position');
          await _executeSell(1.0); // High strength for exit
          _entryPrice = null;
          _stopLossPrice = null;
          _takeProfitPrice = null;
          return;
        }
      }

      // Don't open new position if we have active order
      if (_activeOrder != null) {
        return;
      }

      // Select strategy based on trend
      TradingSignal signal;
      switch (_currentTrend!) {
        case MarketTrend.uptrend:
          signal = _uptrendStrategy.generateSignal(_technicalIndicators!);
          break;
        case MarketTrend.sideways:
          signal = _sidewaysStrategy.generateSignal(_technicalIndicators!);
          break;
        case MarketTrend.downtrend:
          // No trading in downtrend
          signal = TradingSignal.hold(
            reason: '하락 추세 - 매매 중단',
            timestamp: _technicalIndicators!.timestamp,
          );
          break;
      }

      _lastSignal = signal;

      // Log signal
      _logTrade('info', '[$currentStrategyName] ${signal.reason} (strength: ${signal.strength.toStringAsFixed(2)})');

      // Execute trade if signal is strong enough
      if (signal.type == SignalType.buy && signal.strength >= 0.7) {
        _entryPrice = signal.entryPrice;
        _stopLossPrice = signal.stopLoss;
        _takeProfitPrice = signal.takeProfit;
        await _executeBuy(signal);
      }

      notifyListeners();
    } catch (e) {
      if (kDebugMode) {
        print('Bot cycle error: $e');
      }
      _logTrade('error', 'Bot cycle error: $e');
    }
  }

  /// Check if should close position based on current strategy
  bool _checkShouldClosePosition(double currentPrice) {
    if (_entryPrice == null || _technicalIndicators == null) {
      return false;
    }

    // First check Stop Loss and Take Profit (highest priority)
    if (_stopLossPrice != null && currentPrice <= _stopLossPrice!) {
      _logTrade('info', 'Stop Loss hit: ${currentPrice.toStringAsFixed(2)} <= ${_stopLossPrice!.toStringAsFixed(2)}');
      return true;
    }

    if (_takeProfitPrice != null && currentPrice >= _takeProfitPrice!) {
      _logTrade('info', 'Take Profit hit: ${currentPrice.toStringAsFixed(2)} >= ${_takeProfitPrice!.toStringAsFixed(2)}');
      return true;
    }

    // Then check strategy-specific exit logic (momentum loss, etc.)
    switch (_currentTrend!) {
      case MarketTrend.uptrend:
        return _uptrendStrategy.shouldClosePosition(
          _technicalIndicators!,
          _entryPrice!,
          currentPrice,
        );
      case MarketTrend.sideways:
        return _sidewaysStrategy.shouldClosePosition(
          _technicalIndicators!,
          _entryPrice!,
          currentPrice,
        );
      case MarketTrend.downtrend:
        // Always close in downtrend
        return true;
    }
  }

  /// Execute buy order
  Future<void> _executeBuy(TradingSignal signal) async {
    // Get actual order amount (fixed or all balance)
    final baseAmount = await getActualOrderAmount();

    // Apply position size multiplier from signal (gradual entry)
    final actualAmount = baseAmount * signal.positionSizeMultiplier;

    _logTrade('info', 'Attempting BUY - Amount: ${actualAmount.toStringAsFixed(0)} KRW (${(signal.positionSizeMultiplier * 100).toStringAsFixed(0)}% position), Signal strength: ${signal.strength.toStringAsFixed(2)}');

    try {
      Result<CoinoneOrder> result;

      if (_useMarketOrder) {
        // Market buy: use KRW amount
        result = await _repository.placeMarketBuyWithAmount(
          quoteCurrency: 'KRW',
          targetCurrency: _symbol,
          amount: actualAmount,
        );
      } else {
        // Limit order at current price
        final price = _currentTicker?.last ?? _technicalIndicators?.currentPrice ?? 0.0;
        result = await _repository.placeLimitBuy(
          quoteCurrency: 'KRW',
          targetCurrency: _symbol,
          price: price,
          quantity: _orderQuantity,
        );
      }

      switch (result) {
        case Success(:final data):
          _activeOrder = data;
          _orderHistory.insert(0, data);

          // Log to database
          await _databaseService.insertOrderHistory(
            symbol: _symbol,
            side: 'buy',
            price: data.price,
            quantity: data.quantity,
            userOrderId: data.userOrderId ?? '',
            orderId: data.orderId,
            status: data.status,
            bollingerUpper: _technicalIndicators?.bollingerUpper,
            bollingerMiddle: _technicalIndicators?.bollingerMiddle,
            bollingerLower: _technicalIndicators?.bollingerLower,
          );

          _logTrade('success', 'BUY order placed: ${data.orderId} - '
              'Price: ${data.price.toStringAsFixed(2)}, '
              'Qty: ${data.quantity.toStringAsFixed(4)}, '
              'Strategy: $currentStrategyName');

        case Failure(:final message):
          _logTrade('error', 'BUY order failed: $message');
      }
    } catch (e) {
      _logTrade('error', 'BUY execution error: $e');
    }
  }

  /// Execute sell order
  Future<void> _executeSell(double signalStrength) async {
    _logTrade('info', 'Attempting SELL - Quantity: $_orderQuantity, Signal strength: ${signalStrength.toStringAsFixed(2)}');

    try {
      Result<CoinoneOrder> result;

      if (_useMarketOrder) {
        result = await _repository.placeMarketSell(
          quoteCurrency: 'KRW',
          targetCurrency: _symbol,
          quantity: _orderQuantity,
        );
      } else {
        // Limit order at current price
        final price = _currentTicker?.last ?? _technicalIndicators?.currentPrice ?? 0.0;
        result = await _repository.placeLimitSell(
          quoteCurrency: 'KRW',
          targetCurrency: _symbol,
          price: price,
          quantity: _orderQuantity,
        );
      }

      switch (result) {
        case Success(:final data):
          _activeOrder = data;
          _orderHistory.insert(0, data);

          // Log to database
          await _databaseService.insertOrderHistory(
            symbol: _symbol,
            side: 'sell',
            price: data.price,
            quantity: data.quantity,
            userOrderId: data.userOrderId ?? '',
            orderId: data.orderId,
            status: data.status,
            bollingerUpper: _technicalIndicators?.bollingerUpper,
            bollingerMiddle: _technicalIndicators?.bollingerMiddle,
            bollingerLower: _technicalIndicators?.bollingerLower,
          );

          _logTrade('success', 'SELL order placed: ${data.orderId} - '
              'Price: ${data.price.toStringAsFixed(2)}, '
              'Qty: ${data.quantity.toStringAsFixed(4)}, '
              'Strategy: $currentStrategyName');

        case Failure(:final message):
          _logTrade('error', 'SELL order failed: $message');
      }
    } catch (e) {
      _logTrade('error', 'SELL execution error: $e');
    }
  }


  /// Fetch order history (public method for UI refresh)
  Future<void> refreshOrderHistory() async {
    _setLoading(true);
    await _fetchOrderHistory();
    _setLoading(false);
  }

  /// Fetch order history (internal)
  Future<void> _fetchOrderHistory() async {
    try {
      final result = await _repository.getOpenOrders(
        quoteCurrency: 'KRW',
        targetCurrency: _symbol,
      );

      switch (result) {
        case Success(:final data):
          // Filter out market orders (they should be filled immediately)
          // Only show limit orders in open orders list
          _orderHistory = data.where((order) => order.type.toLowerCase() != 'market').toList();

          // Find active order (most recent unfilled)
          if (_orderHistory.isNotEmpty) {
            _activeOrder = _orderHistory.firstWhere(
              (order) => order.status == 'unfilled' || order.status == 'partially_filled',
              orElse: () => _orderHistory.first,
            );
          } else {
            // Clear active order if no orders exist
            _activeOrder = null;
          }
        case Failure(:final message):
          if (kDebugMode) {
            print('Order history fetch error: $message');
          }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Order history fetch exception: $e');
      }
    }
  }

  /// Manual order placement (for UI)
  Future<void> placeManualOrder({
    required String side,
    required double quantity,
    double? price,
  }) async {
    _setLoading(true);

    try {
      Result<CoinoneOrder> result;

      if (price == null) {
        // Market order
        if (side == 'buy') {
          result = await _repository.placeMarketBuy(
            quoteCurrency: 'KRW',
            targetCurrency: _symbol,
            quantity: quantity,
          );
        } else {
          result = await _repository.placeMarketSell(
            quoteCurrency: 'KRW',
            targetCurrency: _symbol,
            quantity: quantity,
          );
        }
      } else {
        // Limit order
        if (side == 'buy') {
          result = await _repository.placeLimitBuy(
            quoteCurrency: 'KRW',
            targetCurrency: _symbol,
            price: price,
            quantity: quantity,
          );
        } else {
          result = await _repository.placeLimitSell(
            quoteCurrency: 'KRW',
            targetCurrency: _symbol,
            price: price,
            quantity: quantity,
          );
        }
      }

      switch (result) {
        case Success(:final data):
          _orderHistory.insert(0, data);
          _logTrade('success', 'Manual $side order placed: ${data.orderId}');

          // Log to database
          await _databaseService.insertOrderHistory(
            symbol: _symbol,
            side: side,
            price: data.price,
            quantity: data.quantity,
            userOrderId: data.userOrderId ?? '',
            orderId: data.orderId,
            status: data.status,
            bollingerUpper: _technicalIndicators?.bollingerUpper,
            bollingerMiddle: _technicalIndicators?.bollingerMiddle,
            bollingerLower: _technicalIndicators?.bollingerLower,
          );

        case Failure(:final message):
          _errorMessage = message;
          _logTrade('error', 'Manual $side order failed: $message');
      }
    } finally {
      _setLoading(false);
    }
  }

  /// Cancel an order
  Future<void> cancelOrder(String userOrderId) async {
    _setLoading(true);

    try {
      final result = await _repository.cancelOrder(
        quoteCurrency: 'KRW',
        targetCurrency: _symbol,
        userOrderId: userOrderId,
      );

      switch (result) {
        case Success():
          // Remove from history or mark as cancelled
          final index = _orderHistory.indexWhere((o) => o.userOrderId == userOrderId);
          if (index != -1) {
            _orderHistory.removeAt(index);
          }

          if (_activeOrder?.userOrderId == userOrderId) {
            _activeOrder = null;
          }

          _logTrade('success', 'Order cancelled: $userOrderId');

        case Failure(:final message):
          _errorMessage = message;
          _logTrade('error', 'Cancel order failed: $message');
      }
    } finally {
      _setLoading(false);
    }
  }

  /// Test trade: Market buy → Wait for balance increase → Market sell
  Future<void> executeTestTrade() async {
    if (_isTestTrading) {
      _logTrade('warning', 'Test trade already in progress');
      return;
    }

    _isTestTrading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _logTrade('info', '🧪 Test Trade Started - Symbol: $_symbol, Amount: $_orderKrwAmount KRW');

      // Step 1: Get initial balance
      final initialBalanceResult = await _repository.getAvailableBalance(_symbol);

      if (initialBalanceResult is! Success<double>) {
        throw Exception('Failed to get initial balance');
      }

      final initialBalance = initialBalanceResult.data;
      _logTrade('info', '📊 Initial balance: $initialBalance $_symbol');

      // Step 2: Market buy with KRW amount
      _logTrade('info', '💰 Executing market BUY with $_orderKrwAmount KRW...');
      final buyResult = await _repository.placeMarketBuyWithAmount(
        quoteCurrency: 'KRW',
        targetCurrency: _symbol,
        amount: _orderKrwAmount,
      );

      if (buyResult is! Success<CoinoneOrder>) {
        final failure = buyResult as Failure<CoinoneOrder>;
        throw Exception('Market buy failed: ${failure.message}');
      }

      final buyOrder = buyResult.data;
      _logTrade('success', '✅ Market BUY executed - Order ID: ${buyOrder.orderId}');

      // Step 3: Wait and check balance increase
      _logTrade('info', '⏳ Waiting for balance update...');
      double newBalance = initialBalance;
      int attempts = 0;
      const maxAttempts = 10; // 10 attempts, 2 seconds each = 20 seconds max

      _testTradeTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
        attempts++;

        final balanceResult = await _repository.getAvailableBalance(_symbol);

        if (balanceResult is Success<double>) {
          newBalance = balanceResult.data;
          _logTrade('info', '📊 Current balance: $newBalance $_symbol (attempt $attempts/$maxAttempts)');

          // Check if balance increased (wait for at least 50% of expected amount)
          // Expected quantity: orderKrwAmount / estimated price
          final currentPrice = _currentTicker?.last ?? 3600.0; // Fallback price
          final expectedQuantity = _orderKrwAmount / currentPrice;

          if (newBalance > initialBalance + (expectedQuantity * 0.5)) {
            timer.cancel();
            _testTradeTimer = null;

            final balanceIncrease = newBalance - initialBalance;
            _logTrade('success', '✅ Balance increased by $balanceIncrease $_symbol');

            // Step 4: Market sell
            _logTrade('info', '💸 Executing market SELL...');
            final sellResult = await _repository.placeMarketSell(
              quoteCurrency: 'KRW',
              targetCurrency: _symbol,
              quantity: balanceIncrease,
            );

            if (sellResult is Success<CoinoneOrder>) {
              final sellOrder = sellResult.data;
              _logTrade('success', '🎉 Test Trade Complete! Market SELL executed - Order ID: ${sellOrder.orderId}');
              _logTrade('success', '📈 Buy: ${buyOrder.orderId} → Sell: ${sellOrder.orderId}');
            } else {
              final failure = sellResult as Failure<CoinoneOrder>;
              _logTrade('error', '❌ Market sell failed: ${failure.message}');
            }

            _isTestTrading = false;
            notifyListeners();
          }
        }

        // Timeout
        if (attempts >= maxAttempts) {
          timer.cancel();
          _testTradeTimer = null;
          _logTrade('error', '⏱️ Timeout: Balance did not increase after $maxAttempts attempts');
          _logTrade('warning', '💡 You may need to manually sell the purchased coins');
          _isTestTrading = false;
          notifyListeners();
        }
      });

    } catch (e) {
      _errorMessage = e.toString();
      _logTrade('error', '❌ Test trade failed: $e');
      _isTestTrading = false;
      _testTradeTimer?.cancel();
      _testTradeTimer = null;
      notifyListeners();
    }
  }

  /// Cancel test trade
  void cancelTestTrade() {
    if (_testTradeTimer != null) {
      _testTradeTimer!.cancel();
      _testTradeTimer = null;
      _isTestTrading = false;
      _logTrade('info', 'Test trade cancelled');
      notifyListeners();
    }
  }

  /// Log trade activity to database
  void _logTrade(String type, String message) {
    _databaseService.insertTradeLog(
      type: type,
      message: message,
      symbol: _symbol,
    );

    if (kDebugMode) {
      print('[$type] $message');
    }
  }

  /// Get recent trade logs from database
  Future<List<Map<String, dynamic>>> getTradeLogs({int limit = 50}) async {
    return await _databaseService.getRecentTradeLogs(
      limit: limit,
      symbol: _symbol,
    );
  }

  /// Clear all trade logs
  Future<void> clearTradeLogs() async {
    await _databaseService.deleteAllTradeLogs();
    _logTrade('info', 'Trade logs cleared');
  }

  /// Clear all order history
  Future<void> clearOrderHistory() async {
    await _databaseService.deleteAllOrderHistory();
    _orderHistory.clear();
    _activeOrder = null;
    _logTrade('info', 'Order history cleared');
    notifyListeners();
  }

  /// Clear error message
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  /// Set loading state
  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  @override
  void dispose() {
    stopBot();
    _databaseService.close();
    super.dispose();
  }
}
