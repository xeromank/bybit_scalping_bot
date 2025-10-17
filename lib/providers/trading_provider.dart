import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:bybit_scalping_bot/core/result/result.dart';
import 'package:bybit_scalping_bot/models/position.dart';
import 'package:bybit_scalping_bot/models/order.dart';
import 'package:bybit_scalping_bot/models/trade_log.dart';
import 'package:bybit_scalping_bot/repositories/bybit_repository.dart';
import 'package:bybit_scalping_bot/services/bybit_public_websocket_client.dart';
import 'package:bybit_scalping_bot/constants/api_constants.dart';
import 'package:bybit_scalping_bot/constants/app_constants.dart';
import 'package:bybit_scalping_bot/utils/technical_indicators.dart';

/// Provider for trading operations and bot state
///
/// Responsibility: Manage trading bot state and business logic
///
/// This provider orchestrates the trading bot operations, including
/// starting/stopping the bot, monitoring positions, and executing trades.
class TradingProvider extends ChangeNotifier {
  final BybitRepository _repository;
  final BybitPublicWebSocketClient? _publicWsClient;

  // Configuration
  String _symbol = AppConstants.defaultSymbol;
  double _orderAmount = AppConstants.defaultOrderAmount;
  double _profitTargetPercent = AppConstants.defaultProfitTargetPercent;
  double _stopLossPercent = AppConstants.defaultStopLossPercent;
  String _leverage = AppConstants.defaultLeverage;

  // State
  bool _isRunning = false;
  Position? _currentPosition;
  List<TradeLog> _logs = [];
  Timer? _monitoringTimer;
  StreamSubscription? _klineSubscription;
  final List<double> _realtimeClosePrices = [];
  double? _currentPrice; // Current price for selected symbol
  TechnicalAnalysis? _technicalAnalysis; // Technical indicators

  TradingProvider({
    required BybitRepository repository,
    BybitPublicWebSocketClient? publicWsClient,
  })  : _repository = repository,
        _publicWsClient = publicWsClient;

  /// Initializes the provider by subscribing to default symbol's kline
  Future<void> initialize() async {
    if (_publicWsClient != null && _publicWsClient!.isConnected) {
      await _subscribeToKline();
      print('TradingProvider: Initialized with default symbol: $_symbol');
    }

    // Foreground task initialization is done when starting the bot on Android
  }

  // Getters
  String get symbol => _symbol;
  double get orderAmount => _orderAmount;
  double get profitTargetPercent => _profitTargetPercent;
  double get stopLossPercent => _stopLossPercent;
  String get leverage => _leverage;
  bool get isRunning => _isRunning;
  Position? get currentPosition => _currentPosition;
  List<TradeLog> get logs => List.unmodifiable(_logs);
  double? get currentPrice => _currentPrice;
  TechnicalAnalysis? get technicalAnalysis => _technicalAnalysis;

  // Setters with validation
  Future<void> setSymbol(String value) async {
    if (!_isRunning && value.isNotEmpty) {
      final oldSymbol = _symbol;
      _symbol = value.toUpperCase();

      // Unsubscribe from old symbol and subscribe to new one
      if (_publicWsClient != null && _publicWsClient!.isConnected) {
        // Unsubscribe from old symbol
        _klineSubscription?.cancel();
        _klineSubscription = null;
        _realtimeClosePrices.clear();

        try {
          await _publicWsClient!.unsubscribe('kline.1.$oldSymbol');
          print('TradingProvider: Unsubscribed from kline.1.$oldSymbol');
        } catch (e) {
          print('TradingProvider: Error unsubscribing from old symbol: $e');
        }

        // Subscribe to new symbol
        await _subscribeToKline();
      }

      notifyListeners();
    }
  }

  void setOrderAmount(double value) {
    if (!_isRunning &&
        value >= AppConstants.minOrderAmount &&
        value <= AppConstants.maxOrderAmount) {
      _orderAmount = value;
      notifyListeners();
    }
  }

  void setProfitTargetPercent(double value) {
    if (!_isRunning &&
        value >= AppConstants.minProfitTargetPercent &&
        value <= AppConstants.maxProfitTargetPercent) {
      _profitTargetPercent = value;
      notifyListeners();
    }
  }

  void setStopLossPercent(double value) {
    if (!_isRunning &&
        value >= AppConstants.minStopLossPercent &&
        value <= AppConstants.maxStopLossPercent) {
      _stopLossPercent = value;
      notifyListeners();
    }
  }

  void setLeverage(String value) {
    if (!_isRunning) {
      final leverageInt = int.tryParse(value);
      if (leverageInt != null &&
          leverageInt >= AppConstants.minLeverage &&
          leverageInt <= AppConstants.maxLeverage) {
        _leverage = value;

        // Auto-adjust profit target and stop loss based on leverage
        _autoAdjustTargetsForLeverage(leverageInt);

        notifyListeners();
      }
    }
  }

  /// Auto-adjusts profit target and stop loss based on leverage
  ///
  /// Optimized approach based on price movement efficiency
  /// Fee calculation: ~0.11% (entry + exit with taker fees)
  /// ROE impact = Fee% × Leverage
  ///
  /// Strategy: Lower leverage needs less price movement for same ROE
  /// - Low leverage (2-10x): 0.3% price move
  /// - Mid leverage (15-30x): 0.2% price move
  /// - High leverage (50-100x): 0.15% price move
  void _autoAdjustTargetsForLeverage(int leverage) {
    // Fee structure: ~0.055% taker fee per trade (entry + exit = 0.11%)
    const baseFee = 0.11; // Base fee in percentage

    // Calculate ROE targets based on price movement efficiency
    if (leverage <= 2) {
      // 0.3% price move × 2x = 0.6% ROE
      // Fee impact: 0.22% → Net: 0.38%
      _profitTargetPercent = 0.6;
      _stopLossPercent = 0.3; // Half of TP
    } else if (leverage <= 3) {
      // 0.3% price move × 3x = 0.9% ROE
      // Fee impact: 0.33% → Net: 0.57%
      _profitTargetPercent = 0.9;
      _stopLossPercent = 0.45;
    } else if (leverage <= 5) {
      // 0.3% price move × 5x = 1.5% ROE
      // Fee impact: 0.55% → Net: 0.95%
      _profitTargetPercent = 1.5;
      _stopLossPercent = 0.75;
    } else if (leverage <= 10) {
      // 0.3% price move × 10x = 3% ROE
      // Fee impact: 1.1% → Net: 1.9%
      _profitTargetPercent = 3.0;
      _stopLossPercent = 1.5;
    } else if (leverage <= 15) {
      // 0.2% price move × 15x = 3% ROE
      // Fee impact: 1.65% → Net: 1.35%
      _profitTargetPercent = 3.0;
      _stopLossPercent = 1.5;
    } else if (leverage <= 20) {
      // 0.2% price move × 20x = 4% ROE
      // Fee impact: 2.2% → Net: 1.8%
      _profitTargetPercent = 4.0;
      _stopLossPercent = 2.0;
    } else if (leverage <= 30) {
      // 0.2% price move × 30x = 6% ROE
      // Fee impact: 3.3% → Net: 2.7%
      _profitTargetPercent = 6.0;
      _stopLossPercent = 3.0;
    } else if (leverage <= 50) {
      // 0.2% price move × 50x = 10% ROE
      // Fee impact: 5.5% → Net: 4.5%
      _profitTargetPercent = 10.0;
      _stopLossPercent = 5.0;
    } else if (leverage <= 75) {
      // 0.2% price move × 75x = 15% ROE
      // Fee impact: 8.25% → Net: 6.75%
      _profitTargetPercent = 15.0;
      _stopLossPercent = 7.5;
    } else {
      // 0.2% price move × 100x = 20% ROE
      // Fee impact: 11% → Net: 9.0%
      _profitTargetPercent = 20.0;
      _stopLossPercent = 10.0;
    }
  }

  /// Subscribes to kline WebSocket for real-time candlestick data
  Future<void> _subscribeToKline() async {
    if (_publicWsClient == null || !_publicWsClient!.isConnected) {
      _addLog(TradeLog.warning('Public WebSocket not available, using API polling'));
      return;
    }

    try {
      // Subscribe to 1-minute kline for the current symbol
      final topic = 'kline.1.$_symbol';
      await _publicWsClient!.subscribe(topic);
      _addLog(TradeLog.info('Subscribed to kline WebSocket: $topic'));

      // Listen to kline updates
      _klineSubscription?.cancel();
      _klineSubscription = _publicWsClient!.getStream(topic)?.listen(
        (data) {
          _handleKlineUpdate(data);
        },
        onError: (error) {
          _addLog(TradeLog.error('Kline WebSocket error: ${error.toString()}'));
        },
      );
    } catch (e) {
      _addLog(TradeLog.error('Failed to subscribe to kline: ${e.toString()}'));
    }
  }

  /// Handles kline update from WebSocket
  void _handleKlineUpdate(Map<String, dynamic> data) {
    try {
      if (data['topic'] == null || !data['topic'].toString().startsWith('kline')) {
        return;
      }

      final klineData = data['data'] as List<dynamic>;
      if (klineData.isEmpty) return;

      final kline = klineData[0] as Map<String, dynamic>;
      final closePrice = double.tryParse(kline['close']?.toString() ?? '0') ?? 0.0;
      final confirm = kline['confirm'] as bool? ?? false;

      // Update current price for UI display (even for unconfirmed candles)
      if (closePrice > 0) {
        _currentPrice = closePrice;
        notifyListeners();
      }

      // Only add confirmed candles to avoid noise
      if (confirm && closePrice > 0) {
        _realtimeClosePrices.add(closePrice);

        // Keep only the latest 50 candles for analysis
        if (_realtimeClosePrices.length > 50) {
          _realtimeClosePrices.removeAt(0);
        }

        print('TradingProvider: Received kline update - close: $closePrice, total candles: ${_realtimeClosePrices.length}');
      }
    } catch (e) {
      print('TradingProvider: Error handling kline update: $e');
    }
  }

  /// Starts the trading bot
  Future<Result<bool>> startBot() async {
    if (_isRunning) {
      return const Failure('Bot is already running');
    }

    // SAFETY: Prevent trading BTCUSDT to protect long-term positions
    if (_symbol == 'BTCUSDT') {
      const error = '⚠️ BTCUSDT is a protected symbol and cannot be traded by the bot';
      _addLog(TradeLog.error(error));
      return const Failure(error);
    }

    try {
      // Set leverage
      _addLog(TradeLog.info('Setting leverage to $_leverage...'));
      final leverageResult = await _repository.setLeverage(
        symbol: _symbol,
        buyLeverage: _leverage,
        sellLeverage: _leverage,
      );

      if (leverageResult.isFailure) {
        final errorMsg = leverageResult.errorOrNull ?? '';
        // "leverage not modified" means leverage is already set correctly - treat as success
        if (!errorMsg.toLowerCase().contains('leverage not modified')) {
          final error = 'Failed to set leverage: $errorMsg';
          _addLog(TradeLog.error(error));
          return Failure(error);
        } else {
          _addLog(TradeLog.info('Leverage already set to $_leverage'));
        }
      }

      _isRunning = true;

      // Enable wakelock to keep screen on
      await WakelockPlus.enable();
      _addLog(TradeLog.info('Screen will stay awake while bot is running'));

      // Start foreground service for background execution (Android only)
      // Note: iOS simulator doesn't support foreground services
      if (Platform.isAndroid) {
        try {
          await FlutterForegroundTask.startService(
            notificationTitle: 'Bybit Scalping Bot',
            notificationText: 'Trading $_symbol with ${_leverage}x leverage',
          );
          _addLog(TradeLog.info('Background service started'));
        } catch (e) {
          _addLog(TradeLog.warning('Background service not available: $e'));
        }
      }

      _addLog(TradeLog.success(
        'Bot started ($_symbol, Leverage ${_leverage}x)',
      ));

      // Subscribe to kline WebSocket for real-time data
      await _subscribeToKline();

      // Start monitoring
      _startMonitoring();

      notifyListeners();
      return const Success(true);
    } catch (e) {
      final error = 'Failed to start bot: ${e.toString()}';
      _addLog(TradeLog.error(error));
      return Failure(error);
    }
  }

  /// Stops the trading bot
  Future<Result<bool>> stopBot() async {
    if (!_isRunning) {
      return const Failure('Bot is not running');
    }

    try {
      _isRunning = false;
      _monitoringTimer?.cancel();
      _monitoringTimer = null;

      // Disable wakelock to allow screen to sleep
      await WakelockPlus.disable();

      // Stop foreground service (Android only)
      if (Platform.isAndroid) {
        await FlutterForegroundTask.stopService();
        _addLog(TradeLog.info('Background service stopped'));
      }

      // Unsubscribe from kline WebSocket
      _klineSubscription?.cancel();
      _klineSubscription = null;
      _realtimeClosePrices.clear();

      if (_publicWsClient != null && _publicWsClient!.isConnected) {
        await _publicWsClient!.unsubscribe('kline.1.$_symbol');
      }

      _addLog(TradeLog.info('Bot stopped (screen can sleep now)'));
      notifyListeners();

      return const Success(true);
    } catch (e) {
      final error = 'Failed to stop bot: ${e.toString()}';
      _addLog(TradeLog.error(error));
      return Failure(error);
    }
  }

  /// Starts monitoring loop
  void _startMonitoring() {
    _monitoringTimer = Timer.periodic(
      AppConstants.botMonitoringInterval,
      (timer) async {
        if (!_isRunning) {
          timer.cancel();
          return;
        }

        await _checkAndTrade();
      },
    );
  }

  /// Main trading logic - checks positions and executes trades
  Future<void> _checkAndTrade() async {
    try {
      // SAFETY: Never touch BTCUSDT positions - they are long-term holds
      if (_symbol == 'BTCUSDT') {
        _addLog(TradeLog.warning(
          '⚠️ BTCUSDT is protected - bot will not trade this symbol',
        ));
        // Stop the bot automatically to prevent accidental trading
        await stopBot();
        return;
      }

      // Fetch current position
      final positionResult = await _repository.getPosition(symbol: _symbol);

      if (positionResult.isFailure) {
        _addLog(TradeLog.warning(
          'Failed to fetch position: ${positionResult.errorOrNull}',
        ));
        return;
      }

      final position = positionResult.dataOrNull;

      if (position == null || position.isClosed) {
        // No position - look for entry signal
        await _findEntrySignal();
      } else {
        // Position exists - update UI with position info
        // TP/SL orders will automatically close the position server-side
        _currentPosition = position;
        _addLog(TradeLog.info(
          'Position: ${position.isLong ? "Long" : "Short"} | '
          'Entry: \$${position.avgPrice} | '
          'Mark: \$${position.markPrice} | '
          'PnL: ${position.pnlPercent.toStringAsFixed(2)}% | '
          'TP/SL active',
        ));
        notifyListeners();
      }
    } catch (e) {
      _addLog(TradeLog.error('Monitoring error: ${e.toString()}'));
    }
  }

  /// Finds entry signal using technical indicators
  Future<void> _findEntrySignal() async {
    try {
      List<double> closePrices;
      List<double> volumes;

      // Always fetch from API to get both price and volume data
      // Real-time WebSocket only provides price, not volume
      final klineResponse = await _repository.apiClient.getKlines(
        symbol: _symbol,
        interval: '1', // 1-minute candles for scalping
        limit: 50, // Need at least 30 for RSI(12) + EMA(21)
      );

      // Parse closing prices and volumes
      closePrices = parseClosePrices(klineResponse);
      volumes = parseVolumes(klineResponse);
      print('TradingProvider: Using ${closePrices.length} kline candles with volume data');

      // Analyze technical indicators
      final analysis = analyzePriceData(closePrices, volumes);

      // Store technical analysis for UI display
      _technicalAnalysis = analysis;
      notifyListeners();

      // Log technical analysis
      _addLog(TradeLog.info(
        'RSI(6): ${analysis.rsi6.toStringAsFixed(1)} | '
        'RSI(12): ${analysis.rsi12.toStringAsFixed(1)} | '
        'Vol: ${analysis.currentVolume.toStringAsFixed(0)} (MA5: ${analysis.volumeMA5.toStringAsFixed(0)}) | '
        'EMA(9): \$${analysis.ema9.toStringAsFixed(2)} | '
        'EMA(21): \$${analysis.ema21.toStringAsFixed(2)}',
      ));

      // Determine entry signal
      String? side;
      if (analysis.isLongSignal) {
        side = ApiConstants.orderSideBuy;
        _addLog(TradeLog.success(
          '🟢 LONG Signal: RSI(6)=${analysis.rsi6.toStringAsFixed(1)}, '
          'Vol↑, Price>${analysis.ema21.toStringAsFixed(0)}',
        ));
      } else if (analysis.isShortSignal) {
        side = ApiConstants.orderSideSell;
        _addLog(TradeLog.success(
          '🔴 SHORT Signal: RSI(6)=${analysis.rsi6.toStringAsFixed(1)}, '
          'Vol↑, Price<${analysis.ema21.toStringAsFixed(0)}',
        ));
      } else {
        // No signal - log current state
        final volStatus = analysis.currentVolume > analysis.volumeMA5 ? 'High' : 'Low';
        final priceVsEma21 = analysis.currentPrice > analysis.ema21 ? 'Above' : 'Below';
        _addLog(TradeLog.info(
          'No entry signal | Vol: $volStatus, Price: $priceVsEma21 EMA21 | '
          'RSI(6): ${analysis.rsi6.toStringAsFixed(1)} | '
          'RSI(12): ${analysis.rsi12.toStringAsFixed(1)}',
        ));
        return;
      }

      // Create order with current price
      await _createOrderWithPrice(side, analysis.currentPrice);
    } catch (e) {
      _addLog(TradeLog.error('Entry signal error: ${e.toString()}'));
    }
  }

  /// Creates a market order with price info
  Future<void> _createOrderWithPrice(String side, double price) async {
    try {
      // Get instrument info to determine correct qty precision
      final instrumentInfo = await _repository.apiClient.getInstrumentsInfo(
        category: 'linear',
        symbol: _symbol,
      );

      // Parse lot size filter to get qtyStep
      String qtyStep = '0.001'; // Default for most symbols
      String minOrderQty = '0.001'; // Default minimum

      try {
        final result = instrumentInfo['result'];
        if (result != null && result['list'] != null && (result['list'] as List).isNotEmpty) {
          final instrument = (result['list'] as List).first;
          final lotSizeFilter = instrument['lotSizeFilter'];
          if (lotSizeFilter != null) {
            qtyStep = lotSizeFilter['qtyStep']?.toString() ?? '0.001';
            minOrderQty = lotSizeFilter['minOrderQty']?.toString() ?? '0.001';
          }
        }
      } catch (e) {
        print('TradingProvider: Failed to parse instrument info, using defaults: $e');
      }

      // Calculate qty from USDT amount and current price
      // qty = (USDT amount * leverage) / price
      final leverageInt = int.parse(_leverage);
      double qty = (_orderAmount * leverageInt) / price;

      // Round qty to match qtyStep precision
      final stepDecimalPlaces = qtyStep.contains('.')
          ? qtyStep.split('.')[1].length
          : 0;

      // Round down to qtyStep precision
      final multiplier = 1 / double.parse(qtyStep);
      qty = (qty * multiplier).floor() / multiplier;

      // Check if qty meets minimum order requirement
      final minQty = double.parse(minOrderQty);
      if (qty < minQty) {
        _addLog(TradeLog.error(
          'Order qty ($qty) is below minimum ($minQty). Increase order amount or decrease leverage.',
        ));
        return;
      }

      // Format qty to appropriate decimal places
      final qtyStr = qty.toStringAsFixed(stepDecimalPlaces);

      // Calculate TP/SL prices based on ROE targets
      // ROE% = (profit / margin) * 100
      // For Long: profit = (exitPrice - entryPrice) * qty
      // For Short: profit = (entryPrice - exitPrice) * qty
      // margin = positionValue / leverage

      final isLong = side == ApiConstants.orderSideBuy;

      // Calculate TP/SL prices from ROE percentages
      // TP/SL price movement = (ROE% / 100) * (entryPrice / leverage)
      final tpPriceMove = (_profitTargetPercent / 100) * (price / leverageInt);
      final slPriceMove = (_stopLossPercent / 100) * (price / leverageInt);

      final tpPrice = isLong ? price + tpPriceMove : price - tpPriceMove;
      final slPrice = isLong ? price - slPriceMove : price + slPriceMove;

      // Round TP/SL prices to 1 decimal place as required
      final tpPriceStr = tpPrice.toStringAsFixed(1);
      final slPriceStr = slPrice.toStringAsFixed(1);

      final request = OrderRequest(
        symbol: _symbol,
        side: side,
        orderType: ApiConstants.orderTypeMarket,
        qty: qtyStr,
        positionIdx: ApiConstants.positionIdxOneWay,
        takeProfit: tpPriceStr,
        stopLoss: slPriceStr,
      );

      final sideText = side == ApiConstants.orderSideBuy ? "Long" : "Short";
      _addLog(TradeLog.info(
        'Creating $sideText order: $qtyStr $_symbol (\$${_orderAmount.toStringAsFixed(2)} USDT @ \$${price.toStringAsFixed(2)})\n'
        'TP: \$$tpPriceStr (${_profitTargetPercent.toStringAsFixed(1)}% ROE) | '
        'SL: \$$slPriceStr (${_stopLossPercent.toStringAsFixed(1)}% ROE)',
      ));

      final result = await _repository.createOrder(request: request);

      if (result.isSuccess) {
        _addLog(TradeLog.success(
          '$sideText position opened with TP/SL orders',
        ));
      } else {
        _addLog(TradeLog.error(
          'Order failed: ${result.errorOrNull}',
        ));
      }
    } catch (e) {
      _addLog(TradeLog.error('Order creation error: ${e.toString()}'));
    }
  }

  /// Adds a log entry
  void _addLog(TradeLog log) {
    _logs.insert(0, log);

    // Keep only the latest logs
    if (_logs.length > AppConstants.maxLogEntries) {
      _logs = _logs.take(AppConstants.maxLogEntries).toList();
    }

    notifyListeners();
  }

  /// Clears all logs
  void clearLogs() {
    _logs.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _monitoringTimer?.cancel();
    _klineSubscription?.cancel();
    super.dispose();
  }
}
