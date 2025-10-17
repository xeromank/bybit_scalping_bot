import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:bybit_scalping_bot/core/result/result.dart';
import 'package:bybit_scalping_bot/models/position.dart';
import 'package:bybit_scalping_bot/models/order.dart';
import 'package:bybit_scalping_bot/models/ticker.dart';
import 'package:bybit_scalping_bot/models/trade_log.dart';
import 'package:bybit_scalping_bot/repositories/bybit_repository.dart';
import 'package:bybit_scalping_bot/constants/api_constants.dart';
import 'package:bybit_scalping_bot/constants/app_constants.dart';

/// Provider for trading operations and bot state
///
/// Responsibility: Manage trading bot state and business logic
///
/// This provider orchestrates the trading bot operations, including
/// starting/stopping the bot, monitoring positions, and executing trades.
class TradingProvider extends ChangeNotifier {
  final BybitRepository _repository;

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

  TradingProvider({required BybitRepository repository})
      : _repository = repository;

  // Getters
  String get symbol => _symbol;
  double get orderAmount => _orderAmount;
  double get profitTargetPercent => _profitTargetPercent;
  double get stopLossPercent => _stopLossPercent;
  String get leverage => _leverage;
  bool get isRunning => _isRunning;
  Position? get currentPosition => _currentPosition;
  List<TradeLog> get logs => List.unmodifiable(_logs);

  // Setters with validation
  void setSymbol(String value) {
    if (!_isRunning && value.isNotEmpty) {
      _symbol = value.toUpperCase();
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
        notifyListeners();
      }
    }
  }

  /// Starts the trading bot
  Future<Result<bool>> startBot() async {
    if (_isRunning) {
      return const Failure('Bot is already running');
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
        final error = 'Failed to set leverage: ${leverageResult.errorOrNull}';
        _addLog(TradeLog.error(error));
        return Failure(error);
      }

      _isRunning = true;
      _addLog(TradeLog.success(
        'Bot started ($_symbol, Leverage ${_leverage}x)',
      ));

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

      _addLog(TradeLog.info('Bot stopped'));
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
        // Position exists - check exit conditions
        _currentPosition = position;
        notifyListeners();
        await _checkExitConditions(position);
      }
    } catch (e) {
      _addLog(TradeLog.error('Monitoring error: ${e.toString()}'));
    }
  }

  /// Finds entry signal and opens position
  Future<void> _findEntrySignal() async {
    try {
      final tickerResult = await _repository.getTicker(symbol: _symbol);

      if (tickerResult.isFailure) {
        return;
      }

      final ticker = tickerResult.dataOrNull!;
      final priceChange = ticker.price24hPcntAsPercent;

      // Simple entry logic: trend-following
      String? side;
      if (priceChange > 0.5) {
        side = ApiConstants.orderSideBuy; // Long
      } else if (priceChange < -0.5) {
        side = ApiConstants.orderSideSell; // Short
      } else {
        _addLog(TradeLog.info(
          'No entry signal (Price: \$${ticker.lastPrice}, Change: ${priceChange.toStringAsFixed(2)}%)',
        ));
        return;
      }

      // Create order
      await _createOrder(side, ticker);
    } catch (e) {
      _addLog(TradeLog.error('Entry signal error: ${e.toString()}'));
    }
  }

  /// Creates a market order
  Future<void> _createOrder(String side, Ticker ticker) async {
    try {
      final request = OrderRequest(
        symbol: _symbol,
        side: side,
        orderType: ApiConstants.orderTypeMarket,
        qty: _orderAmount.toString(),
        positionIdx: ApiConstants.positionIdxOneWay,
      );

      _addLog(TradeLog.info('Creating ${side == ApiConstants.orderSideBuy ? "Long" : "Short"} order...'));

      final result = await _repository.createOrder(request: request);

      if (result.isSuccess) {
        _addLog(TradeLog.success(
          '${side == ApiConstants.orderSideBuy ? "Long" : "Short"} position opened at \$${ticker.lastPrice}',
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

  /// Checks exit conditions for current position
  Future<void> _checkExitConditions(Position position) async {
    try {
      final pnlPercent = position.pnlPercent;

      _addLog(TradeLog.info(
        'Position: ${position.isLong ? "Long" : "Short"} | '
        'Entry: \$${position.avgPrice} | '
        'Mark: \$${position.markPrice} | '
        'PnL: ${pnlPercent.toStringAsFixed(2)}%',
      ));

      // Check take profit
      if (pnlPercent >= _profitTargetPercent) {
        await _closePosition(position, 'Take Profit');
        return;
      }

      // Check stop loss
      if (pnlPercent <= -_stopLossPercent) {
        await _closePosition(position, 'Stop Loss');
        return;
      }
    } catch (e) {
      _addLog(TradeLog.error('Exit condition check error: ${e.toString()}'));
    }
  }

  /// Closes the current position
  Future<void> _closePosition(Position position, String reason) async {
    try {
      // Create opposite order to close position
      final closeSide = position.isLong
          ? ApiConstants.orderSideSell
          : ApiConstants.orderSideBuy;

      final request = OrderRequest(
        symbol: _symbol,
        side: closeSide,
        orderType: ApiConstants.orderTypeMarket,
        qty: position.size,
        positionIdx: ApiConstants.positionIdxOneWay,
        reduceOnly: true,
      );

      _addLog(TradeLog.info('Closing position ($reason)...'));

      final result = await _repository.createOrder(request: request);

      if (result.isSuccess) {
        _addLog(TradeLog.success(
          'Position closed ($reason) | PnL: ${position.pnlPercent.toStringAsFixed(2)}%',
        ));
        _currentPosition = null;
        notifyListeners();
      } else {
        _addLog(TradeLog.error(
          'Failed to close position: ${result.errorOrNull}',
        ));
      }
    } catch (e) {
      _addLog(TradeLog.error('Position closing error: ${e.toString()}'));
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
    super.dispose();
  }
}
