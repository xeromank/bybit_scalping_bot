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
import 'package:bybit_scalping_bot/models/candle_progress.dart';
import 'package:bybit_scalping_bot/repositories/bybit_repository.dart';
import 'package:bybit_scalping_bot/services/bybit_public_websocket_client.dart';
import 'package:bybit_scalping_bot/constants/api_constants.dart';
import 'package:bybit_scalping_bot/constants/app_constants.dart';
import 'package:bybit_scalping_bot/utils/technical_indicators.dart';
import 'package:bybit_scalping_bot/utils/signal_strength.dart';
import 'package:bybit_scalping_bot/utils/notification_helper.dart';
import 'package:bybit_scalping_bot/services/database_service.dart';
import 'package:bybit_scalping_bot/utils/logger.dart';

/// Trading signal status
enum TradingStatus {
  noSignal,  // No trading conditions met
  ready,     // At least one indicator condition met
  ordered,   // Order has been placed
}

/// Provider for trading operations and bot state
///
/// Responsibility: Manage trading bot state and business logic
///
/// This provider orchestrates the trading bot operations, including
/// starting/stopping the bot, monitoring positions, and executing trades.
class TradingProvider extends ChangeNotifier {
  final BybitRepository _repository;
  final BybitPublicWebSocketClient? _publicWsClient;
  final DatabaseService _databaseService = DatabaseService();

  // Configuration
  String _symbol = AppConstants.defaultSymbol;
  double _orderAmount = AppConstants.defaultOrderAmount;
  String _leverage = AppConstants.defaultLeverage;

  // Trading Mode (configurable by user)
  TradingMode _tradingMode = TradingMode.bollinger; // Default to Bollinger Band strategy

  // Bollinger Band Mode Settings (configurable by user)
  int _bollingerPeriod = AppConstants.defaultBollingerPeriod;
  double _bollingerStdDev = AppConstants.defaultBollingerStdDev;
  int _bollingerRsiPeriod = AppConstants.defaultBollingerRsiPeriod;
  double _bollingerRsiOverbought = AppConstants.defaultBollingerRsiOverbought;
  double _bollingerRsiOversold = AppConstants.defaultBollingerRsiOversold;

  // EMA Mode Settings (configurable by user)
  double _rsi6LongThreshold = AppConstants.defaultRsi6LongThreshold;
  double _rsi6ShortThreshold = AppConstants.defaultRsi6ShortThreshold;
  int _rsi14Period = AppConstants.defaultRsi14Period; // Changed from RSI 12 to RSI 14
  double _rsi14LongThreshold = AppConstants.defaultRsi14LongThreshold;
  double _rsi14ShortThreshold = AppConstants.defaultRsi14ShortThreshold;

  // Volume Filter Settings (common for both modes)
  bool _useVolumeFilter = AppConstants.defaultUseVolumeFilter;
  double _volumeMultiplier = AppConstants.defaultVolumeMultiplier;

  // Dynamic TP/SL (calculated based on mode and leverage)
  double _profitTargetPercent = AppConstants.defaultBollingerProfitPercent;
  double _stopLossPercent = AppConstants.defaultBollingerStopLossPercent;

  // Automatic TP/SL based on signal strength
  bool _useAutomaticTpSl = true; // Default to automatic

  // State
  bool _isRunning = false;
  Position? _currentPosition;
  List<TradeLog> _logs = [];
  Timer? _monitoringTimer;
  StreamSubscription? _klineSubscription;
  final List<double> _realtimeClosePrices = [];
  final List<double> _realtimeVolumes = []; // Store volumes from WebSocket
  double? _currentPrice; // Current price for selected symbol
  TechnicalAnalysis? _technicalAnalysis; // Technical indicators
  CandleProgress? _currentCandleProgress; // Current candle progress tracking
  SignalStrength? _currentSignalStrength; // Current signal strength
  TradingStatus _tradingStatus = TradingStatus.noSignal; // Current trading status
  DateTime? _lastStatusUpdate; // Last status update time
  DateTime? _lastDataUpdate; // Last data update time (WebSocket)
  bool _isWebSocketConnected = false; // WebSocket connection status
  bool _disposed = false; // Track if provider is disposed
  bool _isKlineSubscribed = false; // Track if kline is already subscribed
  String? _subscribedSymbol; // Track which symbol is subscribed

  TradingProvider({
    required BybitRepository repository,
    BybitPublicWebSocketClient? publicWsClient,
  })  : _repository = repository,
        _publicWsClient = publicWsClient {
    // Initialize WebSocket connection status
    _isWebSocketConnected = _publicWsClient?.isConnected ?? false;
  }

  /// Handles WebSocket connection status changes
  void handleWebSocketStatusChange(bool isConnected) {
    if (_isWebSocketConnected != isConnected) {
      _isWebSocketConnected = isConnected;
      notifyListeners();

      if (isConnected) {
        _addLog(TradeLog.info('WebSocket connected'));
      } else {
        _addLog(TradeLog.warning('WebSocket disconnected'));
      }
    }
  }

  /// Handles immediate position closure notification from BalanceProvider
  ///
  /// This is called via WebSocket when a position is closed (TP/SL hit),
  /// allowing instant re-entry detection instead of waiting for polling timer
  void handlePositionClosed(String symbol) {
    if (symbol == _symbol && _currentPosition != null) {
      Logger.log('TradingProvider: Position closed via WebSocket for $symbol - enabling immediate re-entry');
      _currentPosition = null;
      _addLog(TradeLog.info('Position closed (TP/SL hit) - ready for re-entry'));
      notifyListeners();
    }
  }

  /// Initializes the provider by subscribing to default symbol's kline
  Future<void> initialize() async {
    // Load trade logs from database
    await _loadLogsFromDatabase();
    if (_disposed) return;

    // Load initial kline data from API first for immediate indicator display
    await _loadInitialKlineData();
    if (_disposed) return;

    if (_publicWsClient != null && _publicWsClient!.isConnected) {
      await _subscribeToKline();
      if (_disposed) return;
      Logger.log('TradingProvider: Initialized with default symbol: $_symbol');
    }

    // If bot is running (e.g., after hot reload), immediately check position
    if (_isRunning && !_disposed) {
      Logger.log('TradingProvider: Bot is running after reload, checking position...');
      await _updatePositionStatus();
    }

    // Foreground task initialization is done when starting the bot on Android
  }

  /// Loads initial kline data from API to populate indicators immediately
  Future<void> _loadInitialKlineData() async {
    try {
      Logger.log('TradingProvider: Loading initial kline data for $_symbol...');

      // Fetch 50 candles of 5-minute kline data
      final result = await _repository.apiClient.getKlines(
        symbol: _symbol,
        interval: AppConstants.defaultMainInterval,
        limit: 50,
      );

      if (result['retCode'] == 0) {
        final list = result['result']['list'] as List<dynamic>;

        Logger.log('TradingProvider: API response - ${list.length} candles received');
        if (list.isNotEmpty) {
          Logger.log('TradingProvider: First candle sample: ${list[0]}');
        }

        // Clear existing data
        _realtimeClosePrices.clear();
        _realtimeVolumes.clear();

        // Kline data comes in reverse chronological order (newest first), so reverse it
        final reversedList = list.reversed.toList();

        for (final kline in reversedList) {
          final closePrice = double.tryParse(kline[4]?.toString() ?? '0') ?? 0.0;
          final volume = double.tryParse(kline[5]?.toString() ?? '0') ?? 0.0;

          if (closePrice > 0 && volume > 0) {
            _realtimeClosePrices.add(closePrice);
            _realtimeVolumes.add(volume);
          }
        }

        Logger.log('TradingProvider: Parsed ${_realtimeClosePrices.length} valid candles');

        // Update current price from the latest candle
        if (_realtimeClosePrices.isNotEmpty) {
          _currentPrice = _realtimeClosePrices.last;
        }

        Logger.log('TradingProvider: Loaded ${_realtimeClosePrices.length} candles from API');

        // Calculate indicators immediately if we have enough data
        if (_realtimeClosePrices.length >= 30) {
          _calculateRealtimeIndicators();
        }

        notifyListeners();
      } else {
        Logger.error('TradingProvider: Failed to load initial kline data: ${result['retMsg']}');
      }
    } catch (e) {
      Logger.error('TradingProvider: Error loading initial kline data: $e');
    }
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
  CandleProgress? get currentCandleProgress => _currentCandleProgress;
  SignalStrength? get currentSignalStrength => _currentSignalStrength;
  TradingStatus get tradingStatus => _tradingStatus;
  DateTime? get lastStatusUpdate => _lastStatusUpdate;
  DateTime? get lastDataUpdate => _lastDataUpdate;
  bool get isWebSocketConnected => _isWebSocketConnected;

  // Trading Mode Getters
  TradingMode get tradingMode => _tradingMode;

  // Bollinger Band Mode Getters
  int get bollingerPeriod => _bollingerPeriod;
  double get bollingerStdDev => _bollingerStdDev;
  int get bollingerRsiPeriod => _bollingerRsiPeriod;
  double get bollingerRsiOverbought => _bollingerRsiOverbought;
  double get bollingerRsiOversold => _bollingerRsiOversold;

  // EMA Mode Getters
  double get rsi6LongThreshold => _rsi6LongThreshold;
  double get rsi6ShortThreshold => _rsi6ShortThreshold;
  int get rsi14Period => _rsi14Period;
  double get rsi14LongThreshold => _rsi14LongThreshold;
  double get rsi14ShortThreshold => _rsi14ShortThreshold;

  // Volume Filter Getters
  bool get useVolumeFilter => _useVolumeFilter;
  double get volumeMultiplier => _volumeMultiplier;

  // TP/SL Getters
  bool get useAutomaticTpSl => _useAutomaticTpSl;

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

        try {
          await _publicWsClient!.unsubscribe('kline.${AppConstants.defaultMainInterval}.$oldSymbol');
          Logger.log('TradingProvider: Unsubscribed from kline.${AppConstants.defaultMainInterval}.$oldSymbol');
        } catch (e) {
          Logger.error('TradingProvider: Error unsubscribing from old symbol: $e');
        }

        // Load initial kline data for new symbol from API
        await _loadInitialKlineData();

        // Subscribe to new symbol for WebSocket updates
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

  // Trading Mode Setter
  void setTradingMode(TradingMode value) {
    if (!_isRunning) {
      _tradingMode = value;

      // Auto-adjust TP/SL based on mode
      if (_tradingMode == TradingMode.bollinger) {
        // Bollinger mode: tighter TP/SL
        _profitTargetPercent = AppConstants.defaultBollingerProfitPercent;
        _stopLossPercent = AppConstants.defaultBollingerStopLossPercent;
      } else {
        // EMA mode: wider TP/SL
        _profitTargetPercent = AppConstants.defaultEmaProfitPercent;
        _stopLossPercent = AppConstants.defaultEmaStopLossPercent;
      }

      notifyListeners();
    }
  }

  // Bollinger Band Mode Setters
  void setBollingerPeriod(int value) {
    if (!_isRunning &&
        value >= AppConstants.minBollingerPeriod &&
        value <= AppConstants.maxBollingerPeriod) {
      _bollingerPeriod = value;
      notifyListeners();
    }
  }

  void setBollingerStdDev(double value) {
    if (!_isRunning &&
        value >= AppConstants.minBollingerStdDev &&
        value <= AppConstants.maxBollingerStdDev) {
      _bollingerStdDev = value;
      notifyListeners();
    }
  }

  void setBollingerRsiPeriod(int value) {
    if (!_isRunning &&
        value >= AppConstants.minRsiPeriod &&
        value <= AppConstants.maxRsiPeriod) {
      _bollingerRsiPeriod = value;
      notifyListeners();
    }
  }

  void setBollingerRsiOverbought(double value) {
    if (!_isRunning &&
        value >= AppConstants.minRsiThreshold &&
        value <= AppConstants.maxRsiThreshold) {
      _bollingerRsiOverbought = value;
      notifyListeners();
    }
  }

  void setBollingerRsiOversold(double value) {
    if (!_isRunning &&
        value >= AppConstants.minRsiThreshold &&
        value <= AppConstants.maxRsiThreshold) {
      _bollingerRsiOversold = value;
      notifyListeners();
    }
  }

  // EMA Mode Setters
  void setRsi6LongThreshold(double value) {
    if (!_isRunning &&
        value >= AppConstants.minRsiThreshold &&
        value <= AppConstants.maxRsiThreshold) {
      _rsi6LongThreshold = value;
      notifyListeners();
    }
  }

  void setRsi6ShortThreshold(double value) {
    if (!_isRunning &&
        value >= AppConstants.minRsiThreshold &&
        value <= AppConstants.maxRsiThreshold) {
      _rsi6ShortThreshold = value;
      notifyListeners();
    }
  }

  void setRsi14Period(int value) {
    if (!_isRunning &&
        value >= AppConstants.minRsiPeriod &&
        value <= AppConstants.maxRsiPeriod) {
      _rsi14Period = value;
      notifyListeners();
    }
  }

  void setRsi14LongThreshold(double value) {
    if (!_isRunning &&
        value >= AppConstants.minRsiThreshold &&
        value <= AppConstants.maxRsiThreshold) {
      _rsi14LongThreshold = value;
      notifyListeners();
    }
  }

  void setRsi14ShortThreshold(double value) {
    if (!_isRunning &&
        value >= AppConstants.minRsiThreshold &&
        value <= AppConstants.maxRsiThreshold) {
      _rsi14ShortThreshold = value;
      notifyListeners();
    }
  }

  // Volume Filter Setters
  void setUseVolumeFilter(bool value) {
    if (!_isRunning) {
      _useVolumeFilter = value;
      notifyListeners();
    }
  }

  void setVolumeMultiplier(double value) {
    if (!_isRunning &&
        value >= AppConstants.minVolumeMultiplier &&
        value <= AppConstants.maxVolumeMultiplier) {
      _volumeMultiplier = value;
      notifyListeners();
    }
  }

  // TP/SL Setter
  void setUseAutomaticTpSl(bool value) {
    if (!_isRunning) {
      _useAutomaticTpSl = value;
      notifyListeners();
    }
  }

  /// Calculates dynamic TP/SL based on signal strength and Bollinger deviation
  ///
  /// Strategy:
  /// - Strong signals (7-10): Quick profit-taking, wider SL for protection
  /// - Medium signals (4-6): Larger TP target, wider SL for volatility
  /// - Weak signals (1-3): Conservative approach, tighter SL to limit loss
  ///
  /// Bollinger deviation also affects TP/SL:
  /// - Optimal zone (near band): Relaxed conditions
  /// - Risk zone (far from band): Stricter conditions
  Map<String, double> _calculateDynamicTpSl({
    required double signalStrength,
    required int leverage,
    TechnicalAnalysis? analysis,
    bool isLong = true,
  }) {
    double tpPercent;
    double slPercent;

    // Base TP/SL based on signal strength
    if (signalStrength >= 7.0) {
      // Strong signal: Quick profit-taking strategy
      tpPercent = 3.0;  // Fast profit realization
      slPercent = 5.0;  // Wide SL for protection
    } else if (signalStrength >= 4.0) {
      // Medium signal: Allow room for bigger moves
      tpPercent = 6.0;  // Larger target
      slPercent = 6.0;  // Wide SL for volatility
    } else {
      // Weak signal: Conservative approach
      tpPercent = 4.0;  // Moderate target
      slPercent = 4.0;  // Moderate SL
    }

    // Adjust for Bollinger deviation if in Bollinger mode
    if (_tradingMode == TradingMode.bollinger && analysis?.bollingerBands != null) {
      final bb = analysis!.bollingerBands!;
      final price = analysis.currentPrice;

      // Calculate distance from Bollinger band
      final bandDistance = isLong
          ? ((price - bb.lower) / bb.lower * 100).abs()  // Distance from lower band for Long
          : ((price - bb.upper) / bb.upper * 100).abs(); // Distance from upper band for Short

      if (bandDistance < 0.1) {
        // Optimal zone: Price very close to band (< 0.1%)
        // Increase TP, relax SL
        tpPercent *= 1.2;
        slPercent *= 1.3;
      } else if (bandDistance > 0.5) {
        // Risk zone: Price far from band (> 0.5%)
        // Decrease TP, tighten SL
        tpPercent *= 0.8;
        slPercent *= 0.7;
      }
    }

    // Ensure min/max limits
    tpPercent = tpPercent.clamp(
      AppConstants.minProfitTargetPercent,
      AppConstants.maxProfitTargetPercent,
    );
    slPercent = slPercent.clamp(
      AppConstants.minStopLossPercent,
      AppConstants.maxStopLossPercent,
    );

    return {
      'tp': tpPercent,
      'sl': slPercent,
    };
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

    // Conservative ROE targets for realistic scalping (0.5% avg price move)
    // Risk-reward ratio: 1.67:1 (TP:SL)
    if (leverage <= 2) {
      // 0.5% price move × 2x = 1% ROE
      _profitTargetPercent = 1.0;
      _stopLossPercent = 0.6;
    } else if (leverage <= 3) {
      // 0.5% price move × 3x = 1.5% ROE
      _profitTargetPercent = 1.5;
      _stopLossPercent = 0.9;
    } else if (leverage <= 5) {
      // 0.5% price move × 5x = 2.5% ROE
      _profitTargetPercent = 2.5;
      _stopLossPercent = 1.5;
    } else if (leverage <= 10) {
      // 0.5% price move × 10x = 5% ROE (Conservative default)
      _profitTargetPercent = 5.0;
      _stopLossPercent = 3.0;
    } else if (leverage <= 15) {
      // 0.4% price move × 15x = 6% ROE
      _profitTargetPercent = 6.0;
      _stopLossPercent = 3.6;
    } else if (leverage <= 20) {
      // 0.4% price move × 20x = 8% ROE
      _profitTargetPercent = 8.0;
      _stopLossPercent = 4.8;
    } else if (leverage <= 30) {
      // 0.3% price move × 30x = 9% ROE
      _profitTargetPercent = 9.0;
      _stopLossPercent = 5.4;
    } else if (leverage <= 50) {
      // 0.2% price move × 50x = 10% ROE
      _profitTargetPercent = 10.0;
      _stopLossPercent = 6.0;
    } else if (leverage <= 75) {
      // 0.15% price move × 75x = 11.25% ROE
      _profitTargetPercent = 11.0;
      _stopLossPercent = 6.6;
    } else {
      // 0.15% price move × 100x = 15% ROE
      _profitTargetPercent = 15.0;
      _stopLossPercent = 9.0;
    }
  }

  /// Subscribes to kline WebSocket for real-time candlestick data
  Future<void> _subscribeToKline() async {
    if (_publicWsClient == null || !_publicWsClient!.isConnected) {
      _addLog(TradeLog.warning('Public WebSocket not available, using API polling'));
      return;
    }

    // Check if already subscribed to the same symbol
    if (_isKlineSubscribed && _subscribedSymbol == _symbol) {
      Logger.log('TradingProvider: Already subscribed to kline for $_symbol');
      return;
    }

    try {
      // Unsubscribe from previous symbol if different
      if (_isKlineSubscribed && _subscribedSymbol != null && _subscribedSymbol != _symbol) {
        final oldTopic = 'kline.${AppConstants.defaultMainInterval}.$_subscribedSymbol';
        await _publicWsClient!.unsubscribe(oldTopic);
        _klineSubscription?.cancel();
        Logger.log('TradingProvider: Unsubscribed from $oldTopic');
      }

      // Subscribe to 5-minute kline for the current symbol
      final topic = 'kline.${AppConstants.defaultMainInterval}.$_symbol';
      await _publicWsClient!.subscribe(topic);
      _addLog(TradeLog.info('Subscribed to kline WebSocket: $topic'));

      // Mark as subscribed
      _isKlineSubscribed = true;
      _subscribedSymbol = _symbol;

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
      if (klineData.isEmpty) {
        return;
      }

      final kline = klineData[0] as Map<String, dynamic>;

      final closePrice = double.tryParse(kline['close']?.toString() ?? '0') ?? 0.0;
      final volume = double.tryParse(kline['volume']?.toString() ?? '0') ?? 0.0;
      final confirm = kline['confirm'] as bool? ?? false;

      // Track candle progress for hybrid entry strategy
      _currentCandleProgress = CandleProgress.fromKline(kline);

      // Update current price for UI display (even for unconfirmed candles)
      if (closePrice > 0) {
        _currentPrice = closePrice;
        _lastDataUpdate = DateTime.now();
      }

      if (closePrice > 0 && volume > 0) {
        if (confirm) {
          // Confirmed candle - add as new candle
          _realtimeClosePrices.add(closePrice);
          _realtimeVolumes.add(volume);

          // Keep only the latest 50 candles for analysis
          if (_realtimeClosePrices.length > 50) {
            _realtimeClosePrices.removeAt(0);
            _realtimeVolumes.removeAt(0);
          }

          Logger.success('TradingProvider: CONFIRMED candle added - close: $closePrice, volume: ${volume.toStringAsFixed(2)}, total candles: ${_realtimeClosePrices.length}');
        } else {
          // Unconfirmed candle - update the last candle in real-time
          if (_realtimeClosePrices.isNotEmpty) {
            _realtimeClosePrices[_realtimeClosePrices.length - 1] = closePrice;
            _realtimeVolumes[_realtimeVolumes.length - 1] = volume;
            Logger.log('TradingProvider: 🔄 UPDATING last candle - close: $closePrice, volume: ${volume.toStringAsFixed(2)}');
          }
        }

        // Calculate technical indicators if we have enough data (for both confirmed and unconfirmed)
        if (_realtimeClosePrices.length >= 30) {
          _calculateRealtimeIndicators();
        } else {
          Logger.warning('TradingProvider: Not enough data yet (${_realtimeClosePrices.length}/30 candles) - skipping indicator calculation');
        }
      }
    } catch (e) {
      Logger.error('TradingProvider: Error handling kline update: $e');
    }
  }

  /// Calculates technical indicators from real-time WebSocket data
  void _calculateRealtimeIndicators() {
    try {
      // Analyze technical indicators based on trading mode using WebSocket data
      final analysis = analyzePriceData(
        _realtimeClosePrices,
        _realtimeVolumes,
        mode: _tradingMode,
        // Bollinger mode parameters
        bollingerPeriod: _bollingerPeriod,
        bollingerStdDev: _bollingerStdDev,
        bollingerRsiPeriod: _bollingerRsiPeriod,
        bollingerRsiOverbought: _bollingerRsiOverbought,
        bollingerRsiOversold: _bollingerRsiOversold,
        useVolumeFilter: _useVolumeFilter,
        volumeMultiplier: _volumeMultiplier,
        // EMA mode parameters
        rsi6LongThreshold: _rsi6LongThreshold,
        rsi6ShortThreshold: _rsi6ShortThreshold,
        rsi14LongThreshold: _rsi14LongThreshold,
        rsi14ShortThreshold: _rsi14ShortThreshold,
        useEmaFilter: false, // Not used in current implementation
        emaPeriod: 21, // Not used in current implementation
      );

      // Store technical analysis for UI display
      _technicalAnalysis = analysis;

      // Calculate signal strength for hybrid entry strategy
      if (analysis.isLongSignal || analysis.isShortSignal) {
        final isLong = analysis.isLongSignal;

        if (_tradingMode == TradingMode.bollinger && analysis.bollingerBands != null) {
          _currentSignalStrength = calculateBollingerSignalStrength(
            analysis: analysis,
            isLongSignal: isLong,
            recentClosePrices: _realtimeClosePrices,
          );
        } else if (_tradingMode == TradingMode.ema) {
          _currentSignalStrength = calculateEmaSignalStrength(
            analysis: analysis,
            isLongSignal: isLong,
            recentClosePrices: _realtimeClosePrices,
          );
        }

        Logger.log('TradingProvider: 📊 Signal: ${isLong ? "LONG" : "SHORT"} | ${_currentSignalStrength?.toString() ?? "N/A"}');
      } else {
        _currentSignalStrength = null;
      }

      notifyListeners();

      // 🚀 IMMEDIATE ENTRY SIGNAL CHECK (WebSocket-driven trading)
      // Check for entry signals immediately when bot is running and no position exists
      if (_isRunning && (_currentPosition == null || _currentPosition!.isClosed)) {
        _findEntrySignal();
      }
    } catch (e) {
      Logger.error('TradingProvider: Error calculating realtime indicators: $e');
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

      // Keep WebSocket subscription active to continue displaying real-time RSI
      // Do NOT unsubscribe or clear data - this allows indicators to update even when bot is stopped
      _addLog(TradeLog.info('Bot stopped (RSI indicators will continue to update)'));
      notifyListeners();

      return const Success(true);
    } catch (e) {
      final error = 'Failed to stop bot: ${e.toString()}';
      _addLog(TradeLog.error(error));
      return Failure(error);
    }
  }

  /// Clears all data (logs and database)
  Future<Result<bool>> clearAllData() async {
    if (_isRunning) {
      return const Failure('Cannot clear data while bot is running. Please stop the bot first.');
    }

    try {
      // Clear database
      await _databaseService.clearAllData();

      // Clear in-memory logs
      _logs.clear();

      _addLog(TradeLog.success('All data cleared (logs and order history)'));
      notifyListeners();

      return const Success(true);
    } catch (e) {
      final error = 'Failed to clear data: ${e.toString()}';
      _addLog(TradeLog.error(error));
      return Failure(error);
    }
  }

  /// Close a specific position by symbol
  ///
  /// Creates a market order in the opposite direction to close the position
  Future<Result<bool>> closePositionBySymbol(String symbol) async {
    try {
      // Get the position for this symbol
      final positionResult = await _repository.getPosition(symbol: symbol);
      if (positionResult.isFailure) {
        return Failure('Failed to fetch position: ${positionResult.errorOrNull}');
      }

      final position = positionResult.dataOrNull;
      if (position == null || position.isClosed) {
        return const Failure('No open position to close');
      }

      _addLog(TradeLog.info('🔧 Closing ${position.isLong ? "Long" : "Short"} position for $symbol...'));

      // Create opposite side order to close position
      final closeSide = position.isLong ? ApiConstants.orderSideSell : ApiConstants.orderSideBuy;
      final qty = position.size;

      final request = OrderRequest(
        symbol: symbol,
        side: closeSide,
        orderType: ApiConstants.orderTypeMarket,
        qty: qty,
        positionIdx: ApiConstants.positionIdxOneWay,
        reduceOnly: true, // Important: only reduce position, don't open new one
      );

      _addLog(TradeLog.info(
        'Closing ${position.isLong ? "Long" : "Short"} position: $qty $symbol @ Market',
      ));

      final result = await _repository.createOrder(request: request);

      if (result.isSuccess) {
        _addLog(TradeLog.success('✅ Position closed successfully for $symbol'));

        // Clear current position if it matches
        if (_currentPosition?.symbol == symbol) {
          _currentPosition = null;
        }
        notifyListeners();

        return const Success(true);
      } else {
        final error = 'Failed to close position: ${result.errorOrNull}';
        _addLog(TradeLog.error(error));
        return Failure(error);
      }
    } catch (e) {
      final error = 'Position close error: ${e.toString()}';
      _addLog(TradeLog.error(error));
      return Failure(error);
    }
  }

  /// Manual Long Entry (for testing)
  ///
  /// Creates a Long position using current settings without checking entry signals
  Future<Result<bool>> manualLongEntry() async {
    if (_isRunning) {
      return const Failure('Cannot manually enter while bot is running. Stop the bot first.');
    }

    // Check if we have position already
    final positionResult = await _repository.getPosition(symbol: _symbol);
    if (positionResult.isSuccess) {
      final position = positionResult.dataOrNull;
      if (position != null && !position.isClosed) {
        return const Failure('Position already exists. Close it before manual entry.');
      }
    }

    // Check if we have technical analysis data
    if (_technicalAnalysis == null) {
      return const Failure('No market data available. Wait for data to load.');
    }

    try {
      // Set leverage first
      _addLog(TradeLog.info('🔧 [Manual Long] Setting leverage to $_leverage...'));
      final leverageResult = await _repository.setLeverage(
        symbol: _symbol,
        buyLeverage: _leverage,
        sellLeverage: _leverage,
      );

      if (leverageResult.isFailure) {
        final errorMsg = leverageResult.errorOrNull ?? '';
        if (!errorMsg.toLowerCase().contains('leverage not modified')) {
          final error = 'Failed to set leverage: $errorMsg';
          _addLog(TradeLog.error(error));
          return Failure(error);
        }
      }

      _addLog(TradeLog.success('🟢 [Manual Long] Creating Long position...'));

      // Create a basic signal strength for manual entry
      final manualSignalStrength = SignalStrength(
        totalScore: 5.0, // Medium strength for manual entry
        bollingerScore: 1.5,
        rsiScore: 1.5,
        volumeScore: 1.0,
        candleSizeScore: 1.0,
        signalGrade: 'B (Manual)',
        recommendation: 'Manual entry - bypassing signal detection',
      );

      await _createOrderWithPrice(
        ApiConstants.orderSideBuy,
        _technicalAnalysis!,
        manualSignalStrength,
      );

      return const Success(true);
    } catch (e) {
      final error = 'Manual Long entry failed: ${e.toString()}';
      _addLog(TradeLog.error(error));
      return Failure(error);
    }
  }

  /// Manual Short Entry (for testing)
  ///
  /// Creates a Short position using current settings without checking entry signals
  Future<Result<bool>> manualShortEntry() async {
    if (_isRunning) {
      return const Failure('Cannot manually enter while bot is running. Stop the bot first.');
    }

    // Check if we have position already
    final positionResult = await _repository.getPosition(symbol: _symbol);
    if (positionResult.isSuccess) {
      final position = positionResult.dataOrNull;
      if (position != null && !position.isClosed) {
        return const Failure('Position already exists. Close it before manual entry.');
      }
    }

    // Check if we have technical analysis data
    if (_technicalAnalysis == null) {
      return const Failure('No market data available. Wait for data to load.');
    }

    try {
      // Set leverage first
      _addLog(TradeLog.info('🔧 [Manual Short] Setting leverage to $_leverage...'));
      final leverageResult = await _repository.setLeverage(
        symbol: _symbol,
        buyLeverage: _leverage,
        sellLeverage: _leverage,
      );

      if (leverageResult.isFailure) {
        final errorMsg = leverageResult.errorOrNull ?? '';
        if (!errorMsg.toLowerCase().contains('leverage not modified')) {
          final error = 'Failed to set leverage: $errorMsg';
          _addLog(TradeLog.error(error));
          return Failure(error);
        }
      }

      _addLog(TradeLog.success('🔴 [Manual Short] Creating Short position...'));

      // Create a basic signal strength for manual entry
      final manualSignalStrength = SignalStrength(
        totalScore: 5.0, // Medium strength for manual entry
        bollingerScore: 1.5,
        rsiScore: 1.5,
        volumeScore: 1.0,
        candleSizeScore: 1.0,
        signalGrade: 'B (Manual)',
        recommendation: 'Manual entry - bypassing signal detection',
      );

      await _createOrderWithPrice(
        ApiConstants.orderSideSell,
        _technicalAnalysis!,
        manualSignalStrength,
      );

      return const Success(true);
    } catch (e) {
      final error = 'Manual Short entry failed: ${e.toString()}';
      _addLog(TradeLog.error(error));
      return Failure(error);
    }
  }

  /// Starts monitoring loop (periodic position status check)
  void _startMonitoring() {
    _monitoringTimer = Timer.periodic(
      AppConstants.botMonitoringInterval,
      (timer) async {
        if (!_isRunning) {
          timer.cancel();
          return;
        }

        await _updatePositionStatus();
      },
    );
  }

  /// Updates current position status (called periodically)
  ///
  /// This runs every 3 seconds to sync position state from API.
  /// Entry signal detection happens immediately in WebSocket handler.
  Future<void> _updatePositionStatus() async {
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

      // Fetch current position to sync state
      final positionResult = await _repository.getPosition(symbol: _symbol);

      if (positionResult.isFailure) {
        _addLog(TradeLog.warning(
          'Failed to fetch position: ${positionResult.errorOrNull}',
        ));
        return;
      }

      final position = positionResult.dataOrNull;

      if (position == null || position.isClosed) {
        // No position - update state
        _currentPosition = null;
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
      }

      notifyListeners();
    } catch (e) {
      _addLog(TradeLog.error('Position status update error: ${e.toString()}'));
    }
  }

  /// Finds entry signal using technical indicators (Hybrid Strategy)
  Future<void> _findEntrySignal() async {
    try {
      // Use real-time analysis from WebSocket
      final analysis = _technicalAnalysis;
      if (analysis == null) {
        return;
      }

      // Determine entry signal
      String? side;
      bool isLong = false;

      if (analysis.isLongSignal) {
        side = ApiConstants.orderSideBuy;
        isLong = true;
      } else if (analysis.isShortSignal) {
        side = ApiConstants.orderSideSell;
        isLong = false;
      } else {
        // No signal - update status
        _updateTradingStatus(TradingStatus.noSignal);
        return;
      }

      // Hybrid Entry Strategy: Check if immediate entry is allowed
      final candleProgress = _currentCandleProgress;
      final signalStrength = _currentSignalStrength;

      if (candleProgress == null || signalStrength == null) {
        _addLog(TradeLog.warning('Missing candle progress or signal strength data'));
        return;
      }

      // Evaluate hybrid entry decision
      final decision = HybridEntryDecision.evaluate(
        candleProgress: candleProgress,
        signalStrength: signalStrength.totalScore,
      );

      // Log signal detection
      _addLog(TradeLog.success(
        '${isLong ? "🟢 LONG" : "🔴 SHORT"} Signal | '
        '${signalStrength.signalGrade} (${signalStrength.totalScore.toStringAsFixed(1)}점) | '
        '캔들: ${candleProgress.stageName} ${candleProgress.progressPercent.toStringAsFixed(0)}%',
      ));

      _addLog(TradeLog.info(
        '판단: ${decision.reason} → ${decision.recommendation}',
      ));

      // Update trading status based on signal strength and candle progress
      // Ready: Signal detected with high probability (80%+)
      // - Candle progress >= 80% OR
      // - Signal strength >= 6.0 (strong signal)
      final isReadyState = candleProgress.progressPercent >= 80.0 || signalStrength.totalScore >= 6.0;

      if (isReadyState) {
        _updateTradingStatus(TradingStatus.ready);
      }

      // Check if immediate entry is allowed
      if (!decision.canEnterImmediately) {
        _addLog(TradeLog.warning(
          '진입 보류: ${candleProgress.remainingTimeString} 후 캔들 클로즈 대기',
        ));
        return;
      }

      // Entry allowed - create order
      _addLog(TradeLog.success(
        '✅ 진입 조건 충족: ${decision.reason}',
      ));

      // ========== BOLLINGER BAND ENTRY FILTER ==========
      // Check Bollinger band distance for additional entry validation
      if (_tradingMode == TradingMode.bollinger && analysis.bollingerBands != null) {
        final bb = analysis.bollingerBands!;
        final price = analysis.currentPrice;

        // Calculate distance from Bollinger band
        final bandDistance = isLong
            ? ((price - bb.lower) / bb.lower * 100)  // Long: distance from lower
            : ((bb.upper - price) / bb.upper * 100); // Short: distance from upper

        // Determine minimum signal strength required based on distance
        double minSignalRequired;
        String zone;

        if (bandDistance < 0) {
          // Price is BEYOND the band (very risky!)
          zone = '위험 (밴드 밖)';
          minSignalRequired = 999.0; // Block entry
        } else if (bandDistance < 0.1) {
          // Optimal zone: very close to band
          zone = '최적 (밴드 터치)';
          minSignalRequired = 2.0;
        } else if (bandDistance < 0.3) {
          // Good zone: near band
          zone = '양호 (밴드 근처)';
          minSignalRequired = 3.5;
        } else if (bandDistance < 0.5) {
          // Caution zone: getting farther
          zone = '주의 (밴드 이탈)';
          minSignalRequired = 5.0;
        } else {
          // Risk zone: too far from band
          zone = '위험 (밴드 멀리)';
          minSignalRequired = 999.0; // Block entry
        }

        // Check if signal strength meets requirement
        if (signalStrength.totalScore < minSignalRequired) {
          _addLog(TradeLog.warning(
            '⛔ 진입 차단 | 구간: $zone | '
            '밴드 거리: ${bandDistance.toStringAsFixed(2)}% | '
            '신호: ${signalStrength.totalScore.toStringAsFixed(1)}점 '
            '< 필요: ${minSignalRequired == 999.0 ? "차단" : "${minSignalRequired.toStringAsFixed(1)}점"}',
          ));
          return; // Block entry
        }

        // Entry allowed - log the approval
        _addLog(TradeLog.success(
          '✅ 진입 허용 | 구간: $zone | '
          '밴드 거리: ${bandDistance.toStringAsFixed(2)}% | '
          '신호: ${signalStrength.totalScore.toStringAsFixed(1)}점',
        ));
      }

      // Log detailed technical indicators at order time
      _logTechnicalIndicatorsSnapshot(analysis, signalStrength, isLong);

      await _createOrderWithPrice(side, analysis, signalStrength);
    } catch (e) {
      _addLog(TradeLog.error('Entry signal error: ${e.toString()}'));
    }
  }

  /// Creates a market order with price info
  Future<void> _createOrderWithPrice(
    String side,
    TechnicalAnalysis analysis,
    SignalStrength signalStrength,
  ) async {
    final double price = analysis.currentPrice;
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
        Logger.warning('TradingProvider: Failed to parse instrument info, using defaults: $e');
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

      // Determine if this is a Long or Short position
      final isLong = side == ApiConstants.orderSideBuy;

      // Calculate TP/SL: Use automatic if enabled, otherwise use manual values
      double effectiveProfitPercent;
      double effectiveStopLossPercent;

      if (_useAutomaticTpSl) {
        // Calculate dynamic TP/SL based on signal strength and Bollinger deviation
        final dynamicTpSl = _calculateDynamicTpSl(
          signalStrength: signalStrength.totalScore,
          leverage: leverageInt,
          analysis: analysis,
          isLong: isLong,
        );
        effectiveProfitPercent = dynamicTpSl['tp']!;
        effectiveStopLossPercent = dynamicTpSl['sl']!;

        _addLog(TradeLog.info(
          '🎯 Auto TP/SL | Signal: ${signalStrength.totalScore.toStringAsFixed(1)}/10 → '
          'TP: ${effectiveProfitPercent.toStringAsFixed(1)}% · SL: ${effectiveStopLossPercent.toStringAsFixed(1)}%',
        ));
      } else {
        // Use manual TP/SL from UI
        effectiveProfitPercent = _profitTargetPercent;
        effectiveStopLossPercent = _stopLossPercent;
      }

      // Calculate TP/SL prices based on ROE targets
      // ROE% = (profit / margin) * 100
      // For Long: profit = (exitPrice - entryPrice) * qty
      // For Short: profit = (entryPrice - exitPrice) * qty
      // margin = positionValue / leverage

      // Calculate TP/SL prices from ROE percentages
      // TP/SL price movement = (ROE% / 100) * (entryPrice / leverage)
      final tpPriceMove = (effectiveProfitPercent / 100) * (price / leverageInt);
      final slPriceMove = (effectiveStopLossPercent / 100) * (price / leverageInt);

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
      final modeText = _tradingMode == TradingMode.auto
          ? '(Auto: ${_technicalAnalysis?.mode == TradingMode.bollinger ? "Bollinger" : "EMA"})'
          : '';
      _addLog(TradeLog.info(
        'Creating $sideText order $modeText: $qtyStr $_symbol (\$${_orderAmount.toStringAsFixed(2)} USDT @ \$${price.toStringAsFixed(2)})\n'
        'TP: \$$tpPriceStr (${effectiveProfitPercent.toStringAsFixed(1)}% ROE) | '
        'SL: \$$slPriceStr (${effectiveStopLossPercent.toStringAsFixed(1)}% ROE)',
      ));

      final result = await _repository.createOrder(request: request);

      if (result.isSuccess) {
        _addLog(TradeLog.success(
          '$sideText position opened with TP/SL orders $modeText',
        ));

        // Update status to Ordered
        _updateTradingStatus(TradingStatus.ordered);

        // Trigger notification (vibration + haptic feedback)
        await NotificationHelper.notifyOrderEvent();

        // Save order to database
        await _databaseService.insertOrderHistory(
          symbol: _symbol,
          side: side,
          entryPrice: price,
          quantity: double.parse(qtyStr),
          leverage: int.parse(_leverage),
          tpPrice: double.parse(tpPriceStr),
          slPrice: double.parse(slPriceStr),
          signalStrength: signalStrength.totalScore,
          rsi6: analysis.rsi6,
          rsi14: analysis.rsi14,
          ema9: analysis.ema9,
          ema21: analysis.ema21,
          volume: analysis.currentVolume,
          volumeMa5: analysis.volumeMA5,
          bollingerUpper: analysis.bollingerBands?.upper,
          bollingerMiddle: analysis.bollingerBands?.middle,
          bollingerLower: analysis.bollingerBands?.lower,
        );
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

    // Keep only the latest logs in memory (100)
    if (_logs.length > AppConstants.maxLogEntries) {
      _logs = _logs.take(AppConstants.maxLogEntries).toList();
    }

    // Save to database
    _databaseService.insertTradeLog(
      type: log.level.name,
      message: log.message,
      symbol: _symbol,
    );

    notifyListeners();
  }

  /// Clears all logs
  void clearLogs() {
    _logs.clear();
    notifyListeners();
  }

  /// Loads recent logs from database on app startup
  Future<void> _loadLogsFromDatabase() async {
    try {
      final dbLogs = await _databaseService.getRecentTradeLogs(
        limit: AppConstants.maxLogEntries,
        symbol: _symbol,
      );

      // Convert database records to TradeLog objects
      _logs = dbLogs.map((record) {
        final timestamp = DateTime.fromMillisecondsSinceEpoch(record['timestamp'] as int);
        final type = record['type'] as String;
        final message = record['message'] as String;

        // Map type string to LogLevel
        LogLevel level;
        switch (type) {
          case 'success':
            level = LogLevel.success;
            break;
          case 'warning':
            level = LogLevel.warning;
            break;
          case 'error':
            level = LogLevel.error;
            break;
          default:
            level = LogLevel.info;
        }

        return TradeLog(
          timestamp: timestamp,
          message: message,
          level: level,
        );
      }).toList();

      Logger.log('TradingProvider: Loaded ${_logs.length} logs from database');
      notifyListeners();
    } catch (e) {
      Logger.error('TradingProvider: Error loading logs from database: $e');
    }
  }

  /// Updates trading status and timestamp
  void _updateTradingStatus(TradingStatus newStatus) {
    if (_tradingStatus != newStatus) {
      _tradingStatus = newStatus;
      _lastStatusUpdate = DateTime.now();
      notifyListeners();

      // Trigger haptic feedback for Ready state
      if (newStatus == TradingStatus.ready) {
        NotificationHelper.notifyReadyState();
      }
    }
  }

  /// Logs detailed technical indicators snapshot at order time
  void _logTechnicalIndicatorsSnapshot(
    TechnicalAnalysis analysis,
    SignalStrength signalStrength,
    bool isLong,
  ) {
    // Basic info
    _addLog(TradeLog.info(
      '📊 ${isLong ? "LONG" : "SHORT"} Entry Indicators:',
    ));

    // Price and RSI
    _addLog(TradeLog.info(
      'Price: \$${analysis.currentPrice.toStringAsFixed(2)} | '
      'RSI(6): ${analysis.rsi6.toStringAsFixed(1)} | '
      'RSI(14): ${analysis.rsi14.toStringAsFixed(1)}',
    ));

    // EMA
    _addLog(TradeLog.info(
      'EMA(9): \$${analysis.ema9.toStringAsFixed(2)} | '
      'EMA(21): \$${analysis.ema21.toStringAsFixed(2)}',
    ));

    // Bollinger Bands (if available)
    if (analysis.bollingerBands != null) {
      final bb = analysis.bollingerBands!;
      _addLog(TradeLog.info(
        'BB Upper: \$${bb.upper.toStringAsFixed(2)} | '
        'BB Middle: \$${bb.middle.toStringAsFixed(2)} | '
        'BB Lower: \$${bb.lower.toStringAsFixed(2)}',
      ));
      if (analysis.bollingerRsi != null) {
        _addLog(TradeLog.info(
          'BB RSI(14): ${analysis.bollingerRsi!.toStringAsFixed(1)}',
        ));
      }
    }

    // Volume
    _addLog(TradeLog.info(
      'Volume: ${analysis.currentVolume.toStringAsFixed(2)} | '
      'Vol MA5: ${analysis.volumeMA5.toStringAsFixed(2)} | '
      'Vol MA10: ${analysis.volumeMA10.toStringAsFixed(2)} | '
      'Ratio: ${(analysis.currentVolume / analysis.volumeMA5).toStringAsFixed(2)}x',
    ));

    // Signal Strength Breakdown
    _addLog(TradeLog.info(
      '💪 Signal Breakdown: Total ${signalStrength.totalScore.toStringAsFixed(1)}/10 | '
      'BB: ${signalStrength.bollingerScore.toStringAsFixed(1)} | '
      'RSI: ${signalStrength.rsiScore.toStringAsFixed(1)} | '
      'Vol: ${signalStrength.volumeScore.toStringAsFixed(1)} | '
      'Candle: ${signalStrength.candleSizeScore.toStringAsFixed(1)}',
    ));
  }

  @override
  void dispose() {
    _disposed = true;
    _monitoringTimer?.cancel();
    _klineSubscription?.cancel();
    _isKlineSubscribed = false;
    _subscribedSymbol = null;
    super.dispose();
  }
}
