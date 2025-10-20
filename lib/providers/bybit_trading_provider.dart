import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:bybit_scalping_bot/models/position.dart';
import 'package:bybit_scalping_bot/models/top_coin.dart';
import 'package:bybit_scalping_bot/models/market_condition.dart';
import 'package:bybit_scalping_bot/models/wallet_balance.dart';
import 'package:bybit_scalping_bot/repositories/bybit_repository.dart';
import 'package:bybit_scalping_bot/services/market_analyzer.dart';
import 'package:bybit_scalping_bot/services/adaptive_strategy.dart';
import 'package:bybit_scalping_bot/services/bybit_public_websocket_client.dart';
import 'package:bybit_scalping_bot/services/bybit_websocket_client.dart';
import 'package:bybit_scalping_bot/core/result/result.dart';
import 'package:bybit_scalping_bot/utils/logger.dart';
import 'package:bybit_scalping_bot/utils/technical_indicators.dart';

/// Bybit Trading Provider (New Adaptive Strategy System)
///
/// Features:
/// - Automatic market condition detection
/// - Adaptive strategy selection based on market
/// - Top 10 coins by volume
/// - Simplified configuration
class BybitTradingProvider extends ChangeNotifier {
  final BybitRepository _repository;
  final BybitPublicWebSocketClient? _publicWsClient;
  final BybitWebSocketClient? _privateWsClient;

  // ============================================================================
  // CONFIGURATION
  // ============================================================================
  String _selectedSymbol = 'BTCUSDT';
  double _investmentAmount = 100.0; // USDT
  String _leverage = '10';

  // ============================================================================
  // STATE
  // ============================================================================
  bool _isRunning = false;
  Position? _currentPosition;
  List<Position> _allPositions = [];

  // Balance data
  WalletBalance? _walletBalance;
  bool _isLoadingBalance = false;
  DateTime? _lastBalanceUpdate;

  // Market data
  List<TopCoin> _topCoins = [];
  bool _isLoadingCoins = false;

  // Market condition (automatically detected every 5 minutes)
  MarketCondition _currentCondition = MarketCondition.ranging;
  MarketAnalysisResult? _analysisResult;
  DateTime? _lastAnalysis;

  // Current strategy
  StrategyConfig? _currentStrategy;
  TradingSignal? _currentSignal;

  // Real-time data from WebSocket
  double? _currentPrice;
  List<double> _realtimeClosePrices = [];
  List<double> _realtimeVolumes = [];
  DateTime? _lastPriceUpdate;

  // Real-time technical indicators
  double? _currentRSI;
  BollingerBands? _currentBB;
  double? _currentEMA9;
  double? _currentEMA21;
  double? _currentEMA50;

  // WebSocket
  bool _isWebSocketConnected = false;
  StreamSubscription? _klineSubscription;
  StreamSubscription? _positionSubscription;
  final Map<String, StreamSubscription> _tickerSubscriptions = {}; // Track ticker subscriptions per symbol
  String? _subscribedSymbol;
  final Set<String> _subscribedTickers = {}; // Track ticker subscriptions for positions

  // Timers
  Timer? _marketAnalysisTimer; // Every 5 minutes
  Timer? _balanceUpdateTimer; // Every 3 seconds

  // Signal check throttling (실시간 체크, 하지만 최소 1초 간격)
  DateTime? _lastSignalCheck;
  static const _signalCheckThrottle = Duration(seconds: 1);

  // Disposed flag
  bool _disposed = false;

  // ============================================================================
  // CONSTRUCTOR
  // ============================================================================
  BybitTradingProvider({
    required BybitRepository repository,
    required BybitPublicWebSocketClient? publicWsClient,
    required BybitWebSocketClient? privateWsClient,
  })  : _repository = repository,
        _publicWsClient = publicWsClient,
        _privateWsClient = privateWsClient {
    _init();
  }

  // ============================================================================
  // GETTERS
  // ============================================================================
  // Configuration
  String get selectedSymbol => _selectedSymbol;
  double get investmentAmount => _investmentAmount;
  String get leverage => _leverage;

  // State
  bool get isRunning => _isRunning;
  Position? get currentPosition => _currentPosition;
  List<Position> get allPositions => _allPositions;
  bool get hasPositions => _allPositions.isNotEmpty;

  // Balance data
  WalletBalance? get walletBalance => _walletBalance;
  bool get isLoadingBalance => _isLoadingBalance;
  DateTime? get lastBalanceUpdate => _lastBalanceUpdate;
  CoinBalance? get usdtBalance => _walletBalance?.usdtBalance;

  // Market data
  List<TopCoin> get topCoins => _topCoins;
  bool get isLoadingCoins => _isLoadingCoins;

  // Market condition
  MarketCondition get currentCondition => _currentCondition;
  MarketAnalysisResult? get analysisResult => _analysisResult;
  DateTime? get lastAnalysis => _lastAnalysis;
  String get conditionDescription => _currentCondition.displayName;
  String get conditionEmoji => _currentCondition.emoji;

  // Strategy
  StrategyConfig? get currentStrategy => _currentStrategy;
  TradingSignal? get currentSignal => _currentSignal;
  String get strategyDescription => _currentStrategy?.description ?? 'N/A';

  // Real-time data
  double? get currentPrice => _currentPrice;
  DateTime? get lastPriceUpdate => _lastPriceUpdate;
  bool get isWebSocketConnected => _isWebSocketConnected;

  // Real-time technical indicators
  double? get currentRSI => _currentRSI;
  BollingerBands? get currentBB => _currentBB;
  double? get currentEMA9 => _currentEMA9;
  double? get currentEMA21 => _currentEMA21;
  double? get currentEMA50 => _currentEMA50;

  // Analysis details for UI
  String get analysisReasoning => _analysisResult?.reasoning ?? '';
  double get analysisConfidence => _analysisResult?.confidence ?? 0.0;

  // ============================================================================
  // INITIALIZATION
  // ============================================================================
  Future<void> _init() async {
    Logger.debug('BybitTradingProvider: Initializing...');

    // Step 1: Connect WebSockets first
    // Connect Public WebSocket (for kline and ticker data)
    if (_publicWsClient != null && !_publicWsClient!.isConnected) {
      await _publicWsClient!.connect();
    }
    _isWebSocketConnected = _publicWsClient?.isConnected ?? false;

    // Connect Private WebSocket (for position updates)
    if (_privateWsClient != null && !_privateWsClient!.isConnected) {
      Logger.debug('BybitTradingProvider: Connecting to private WebSocket...');
      await _privateWsClient!.connect();

      // Subscribe to position updates
      await _subscribeToPositions();
    }

    // Step 2: Load top coins (doesn't require WebSocket)
    await loadTopCoins();

    // Step 3: Load balance and positions (will subscribe to tickers for open positions)
    await fetchBalance();

    // Step 4: Subscribe to default symbol (kline)
    await _subscribeToSymbol(_selectedSymbol);

    // Step 5: Load initial candle data
    await _loadInitialCandles();

    // Step 6: Analyze market once
    await _analyzeMarket();

    Logger.success('BybitTradingProvider: Initialized!');
  }

  // ============================================================================
  // TOP COINS MANAGEMENT
  // ============================================================================
  /// Load top 10 coins by 24h trading volume
  Future<void> loadTopCoins() async {
    if (_isLoadingCoins) return;

    _isLoadingCoins = true;
    notifyListeners();

    try {
      Logger.debug('BybitTradingProvider: Loading top coins...');

      final response = await _repository.apiClient.getTickers(category: 'linear');

      if (response['retCode'] == 0) {
        final list = response['result']['list'] as List<dynamic>;

        // Filter USDT perpetual contracts only
        final usdtCoins = list
            .where((item) => item['symbol'].toString().endsWith('USDT'))
            .map((item) => TopCoin.fromJson(item))
            .toList();

        // Sort by 24h turnover (trading volume in USDT)
        usdtCoins.sort((a, b) => b.turnover24h.compareTo(a.turnover24h));

        // Take top 10
        _topCoins = usdtCoins.take(10).toList();

        Logger.success('BybitTradingProvider: Loaded ${_topCoins.length} top coins');
      } else {
        Logger.error('BybitTradingProvider: Failed to load top coins - ${response['retMsg']}');
      }
    } catch (e) {
      Logger.error('BybitTradingProvider: Error loading top coins - $e');
    } finally {
      _isLoadingCoins = false;
      notifyListeners();
    }
  }

  // ============================================================================
  // BALANCE MANAGEMENT
  // ============================================================================
  /// Fetch wallet balance and positions from API
  Future<void> fetchBalance() async {
    if (_isLoadingBalance) return;

    _isLoadingBalance = true;
    notifyListeners();

    try {
      Logger.debug('BybitTradingProvider: Fetching balance and positions...');

      // Fetch balance and positions in parallel
      final results = await Future.wait([
        _repository.getWalletBalance(accountType: 'UNIFIED'),
        _repository.getAllPositions(),
      ]);

      final balanceResult = results[0] as Result<WalletBalance>;
      final positionsResult = results[1] as Result<List<Position>>;

      // Handle balance
      switch (balanceResult) {
        case Success(:final data):
          _walletBalance = data;
          _lastBalanceUpdate = DateTime.now();
          Logger.success('BybitTradingProvider: Balance loaded (Equity: ${data.totalEquity} USDT)');
        case Failure(:final message):
          Logger.error('BybitTradingProvider: Failed to load balance - $message');
      }

      // Handle positions
      switch (positionsResult) {
        case Success(:final data):
          _allPositions = data;
          Logger.success('BybitTradingProvider: ${data.length} positions loaded');

          // Subscribe to tickers for all open positions
          for (final position in data) {
            if (position.isOpen && !_subscribedTickers.contains(position.symbol)) {
              _subscribeToTicker(position.symbol);
            }
          }

          // Update current position if selected symbol has position
          if (data.isNotEmpty) {
            try {
              _currentPosition = data.firstWhere((p) => p.symbol == _selectedSymbol);
            } catch (e) {
              _currentPosition = data.first;
            }
          } else {
            _currentPosition = null;
          }
        case Failure(:final message):
          Logger.error('BybitTradingProvider: Failed to load positions - $message');
      }
    } catch (e) {
      Logger.error('BybitTradingProvider: Error loading balance - $e');
    } finally {
      _isLoadingBalance = false;
      notifyListeners();
    }
  }

  // ============================================================================
  // SYMBOL SELECTION
  // ============================================================================
  Future<void> selectSymbol(String symbol) async {
    if (_selectedSymbol == symbol) return;
    if (_isRunning) {
      Logger.warning('BybitTradingProvider: Cannot change symbol while bot is running');
      return;
    }

    Logger.debug('BybitTradingProvider: Changing symbol to $symbol');

    // Unsubscribe from old symbol
    if (_subscribedSymbol != null) {
      await _unsubscribeFromSymbol(_subscribedSymbol!);
    }

    _selectedSymbol = symbol;

    // Subscribe to new symbol
    await _subscribeToSymbol(symbol);

    // Load candles for new symbol
    await _loadInitialCandles();

    // Analyze market for new symbol
    await _analyzeMarket();

    notifyListeners();
  }

  // ============================================================================
  // WEBSOCKET MANAGEMENT
  // ============================================================================
  Future<void> _subscribeToSymbol(String symbol) async {
    if (_publicWsClient == null || !_publicWsClient!.isConnected) {
      Logger.warning('BybitTradingProvider: WebSocket not connected');
      return;
    }

    try {
      final topic = 'kline.5.$symbol'; // 5-minute candles
      await _publicWsClient!.subscribe(topic);

      final stream = _publicWsClient!.getStream(topic);
      if (stream != null) {
        _klineSubscription = stream.listen((data) {
          _handleKlineUpdate(data);
        });
      }

      _subscribedSymbol = symbol;
      Logger.success('BybitTradingProvider: Subscribed to $topic');
    } catch (e) {
      Logger.error('BybitTradingProvider: Failed to subscribe - $e');
    }
  }

  Future<void> _unsubscribeFromSymbol(String symbol) async {
    if (_publicWsClient == null) return;

    try {
      await _publicWsClient!.unsubscribe('kline.5.$symbol');
      _klineSubscription?.cancel();
      _klineSubscription = null;
      _subscribedSymbol = null;
      Logger.debug('BybitTradingProvider: Unsubscribed from $symbol');
    } catch (e) {
      Logger.error('BybitTradingProvider: Failed to unsubscribe - $e');
    }
  }

  /// Subscribe to position updates via Private WebSocket
  Future<void> _subscribeToPositions() async {
    if (_privateWsClient == null || !_privateWsClient!.isConnected) {
      Logger.warning('BybitTradingProvider: Private WebSocket not connected');
      return;
    }

    try {
      // Subscribe to position topic
      await _privateWsClient!.subscribe('position');

      final stream = _privateWsClient!.getStream('position');
      if (stream != null) {
        _positionSubscription = stream.listen((data) {
          _handlePositionUpdate(data);
        });
      }

      Logger.success('BybitTradingProvider: Subscribed to position updates');
    } catch (e) {
      Logger.error('BybitTradingProvider: Failed to subscribe to positions - $e');
    }
  }

  /// Handle position updates from WebSocket
  void _handlePositionUpdate(Map<String, dynamic> data) {
    try {
      if (data['topic'] == null || !data['topic'].toString().startsWith('position')) {
        return;
      }

      Logger.debug('📍 [실시간 포지션 업데이트] WebSocket 데이터 수신');

      final positionsData = data['data'] as List<dynamic>?;
      if (positionsData == null || positionsData.isEmpty) {
        return;
      }

      // Update all positions
      final updatedPositions = <Position>[];
      final openPositionSymbols = <String>{};

      for (final posData in positionsData) {
        try {
          final position = Position.fromJson(posData as Map<String, dynamic>);

          // Only add if position is open (has size)
          if (position.isOpen) {
            updatedPositions.add(position);
            openPositionSymbols.add(position.symbol);

            // Subscribe to ticker for this symbol if not already subscribed
            if (!_subscribedTickers.contains(position.symbol)) {
              _subscribeToTicker(position.symbol);
            }
          }

          // Log detailed position info
          Logger.debug('💰 ${position.symbol} | ${position.side} | Size: ${position.size}');
          Logger.debug('   - avgPrice: ${position.avgPrice} | markPrice: ${position.markPrice}');
          Logger.debug('   - unrealisedPnl: ${position.unrealisedPnl} | positionIM: ${position.positionIM}');
          Logger.debug('   - ROE: ${position.pnlPercent.toStringAsFixed(2)}%');
        } catch (e) {
          Logger.error('BybitTradingProvider: Error parsing position - $e');
        }
      }

      // Unsubscribe from tickers of closed positions
      final closedSymbols = _subscribedTickers.difference(openPositionSymbols);
      for (final symbol in closedSymbols) {
        _unsubscribeFromTicker(symbol);
      }

      // Update all positions list
      _allPositions = updatedPositions;

      // Update current position if selected symbol has position
      try {
        _currentPosition = updatedPositions.firstWhere((p) => p.symbol == _selectedSymbol);
        Logger.success('✅ 현재 포지션 업데이트: ${_currentPosition!.symbol} ROE=${_currentPosition!.pnlPercent.toStringAsFixed(2)}%');
      } catch (e) {
        // Selected symbol has no position
        if (updatedPositions.isNotEmpty) {
          _currentPosition = updatedPositions.first;
        } else {
          _currentPosition = null;
        }
      }

      notifyListeners();
    } catch (e) {
      Logger.error('BybitTradingProvider: Error handling position update - $e');
    }
  }

  /// Subscribe to ticker for a symbol to get real-time markPrice
  Future<void> _subscribeToTicker(String symbol) async {
    if (_publicWsClient == null || !_publicWsClient!.isConnected) {
      Logger.warning('BybitTradingProvider: Cannot subscribe to ticker - WebSocket not connected');
      return;
    }

    try {
      final topic = 'tickers.$symbol';
      await _publicWsClient!.subscribe(topic);

      final stream = _publicWsClient!.getStream(topic);
      if (stream != null) {
        final subscription = stream.listen((data) {
          _handleTickerUpdate(data);
        });
        _tickerSubscriptions[symbol] = subscription;
      }

      _subscribedTickers.add(symbol);
      Logger.success('BybitTradingProvider: Subscribed to ticker for $symbol');
    } catch (e) {
      Logger.error('BybitTradingProvider: Failed to subscribe to ticker - $e');
    }
  }

  /// Unsubscribe from ticker when position is closed
  Future<void> _unsubscribeFromTicker(String symbol) async {
    if (_publicWsClient == null) return;

    try {
      // Cancel subscription
      await _tickerSubscriptions[symbol]?.cancel();
      _tickerSubscriptions.remove(symbol);

      // Unsubscribe from WebSocket
      await _publicWsClient!.unsubscribe('tickers.$symbol');
      _subscribedTickers.remove(symbol);
      Logger.debug('BybitTradingProvider: Unsubscribed from ticker for $symbol');
    } catch (e) {
      Logger.error('BybitTradingProvider: Failed to unsubscribe from ticker - $e');
    }
  }

  /// Handle ticker updates - update position markPrice in real-time
  void _handleTickerUpdate(Map<String, dynamic> data) {
    try {
      if (data['topic'] == null || !data['topic'].toString().startsWith('tickers')) {
        return;
      }

      final tickerData = data['data'] as Map<String, dynamic>?;
      if (tickerData == null) return;

      final symbol = tickerData['symbol']?.toString();
      final markPrice = tickerData['markPrice']?.toString();

      if (symbol == null || markPrice == null) return;

      // Logger.debug('📈 [TICKER UPDATE] $symbol - markPrice: $markPrice');

      // Update position markPrice
      bool updated = false;

      for (int i = 0; i < _allPositions.length; i++) {
        if (_allPositions[i].symbol == symbol) {
          _allPositions[i] = _allPositions[i].copyWith(markPrice: markPrice);
          updated = true;

          // Logger.debug('✅ Position markPrice updated: ${_allPositions[i].symbol} -> $markPrice (ROE: ${_allPositions[i].pnlPercent.toStringAsFixed(2)}%)');

          // Update current position if it's the same symbol
          if (_currentPosition?.symbol == symbol) {
            _currentPosition = _allPositions[i];
          }
        }
      }

      if (updated) {
        notifyListeners();
      }
    } catch (e) {
      Logger.error('BybitTradingProvider: Error handling ticker update - $e');
    }
  }

  void _handleKlineUpdate(Map<String, dynamic> data) {
    try {
      if (data['topic'] == null || !data['topic'].toString().startsWith('kline')) {
        return;
      }

      final klineData = data['data'] as List<dynamic>;
      if (klineData.isEmpty) return;

      final kline = klineData[0] as Map<String, dynamic>;
      final closePrice = double.tryParse(kline['close']?.toString() ?? '0') ?? 0.0;
      final volume = double.tryParse(kline['volume']?.toString() ?? '0') ?? 0.0;
      final confirm = kline['confirm'] as bool? ?? false;

      if (closePrice > 0) {
        _currentPrice = closePrice;
        _lastPriceUpdate = DateTime.now();

        if (volume > 0) {
          if (confirm) {
            // Confirmed candle - add new
            _realtimeClosePrices.add(closePrice);
            _realtimeVolumes.add(volume);

            // Keep last 50 candles
            if (_realtimeClosePrices.length > 50) {
              _realtimeClosePrices.removeAt(0);
              _realtimeVolumes.removeAt(0);
            }

            Logger.success('BybitTradingProvider: New candle - \$${closePrice.toStringAsFixed(2)}');
          } else {
            // Unconfirmed - update last
            if (_realtimeClosePrices.isNotEmpty) {
              _realtimeClosePrices[_realtimeClosePrices.length - 1] = closePrice;
              _realtimeVolumes[_realtimeVolumes.length - 1] = volume;
            }
          }
        }

        // 실시간 기술적 지표 계산
        _updateTechnicalIndicators();

        // 실시간 신호 체크 (throttling 적용: 최소 1초 간격)
        if (_isRunning) {
          final now = DateTime.now();
          if (_lastSignalCheck == null ||
              now.difference(_lastSignalCheck!) >= _signalCheckThrottle) {
            _lastSignalCheck = now;
            _checkTradingSignal();
          }
        }

        notifyListeners();
      }
    } catch (e) {
      Logger.error('BybitTradingProvider: Error handling kline - $e');
    }
  }

  // ============================================================================
  // TECHNICAL INDICATORS UPDATE
  // ============================================================================
  void _updateTechnicalIndicators() {
    if (_realtimeClosePrices.length < 30) {
      return;
    }

    try {
      // Calculate RSI(14)
      final rsiValues = calculateRSISeries(_realtimeClosePrices, 14);
      if (rsiValues.isNotEmpty) {
        _currentRSI = rsiValues.last;
      }

      // Calculate Bollinger Bands
      _currentBB = calculateBollingerBandsDefault(_realtimeClosePrices);

      // Calculate EMAs
      final ema9Values = calculateEMASeries(_realtimeClosePrices, 9);
      if (ema9Values.isNotEmpty) {
        _currentEMA9 = ema9Values.last;
      }

      final ema21Values = calculateEMASeries(_realtimeClosePrices, 21);
      if (ema21Values.isNotEmpty) {
        _currentEMA21 = ema21Values.last;
      }

      final ema50Values = calculateEMASeries(_realtimeClosePrices, 50);
      if (ema50Values.isNotEmpty) {
        _currentEMA50 = ema50Values.last;
      }
    } catch (e) {
      Logger.error('BybitTradingProvider: Error updating indicators - $e');
    }
  }

  // ============================================================================
  // INITIAL DATA LOADING
  // ============================================================================
  Future<void> _loadInitialCandles() async {
    try {
      Logger.debug('BybitTradingProvider: Loading initial candles for $_selectedSymbol');

      final result = await _repository.apiClient.getKlines(
        symbol: _selectedSymbol,
        interval: '5',
        limit: 50,
      );

      if (result['retCode'] == 0) {
        final list = result['result']['list'] as List<dynamic>;

        _realtimeClosePrices.clear();
        _realtimeVolumes.clear();

        // Reverse list (newest first -> oldest first)
        final reversedList = list.reversed.toList();

        for (var kline in reversedList) {
          final closePrice = double.tryParse(kline[4]?.toString() ?? '0') ?? 0.0;
          final volume = double.tryParse(kline[5]?.toString() ?? '0') ?? 0.0;

          if (closePrice > 0 && volume > 0) {
            _realtimeClosePrices.add(closePrice);
            _realtimeVolumes.add(volume);
          }
        }

        if (_realtimeClosePrices.isNotEmpty) {
          _currentPrice = _realtimeClosePrices.last;
        }

        Logger.success('BybitTradingProvider: Loaded ${_realtimeClosePrices.length} candles');
        notifyListeners();
      }
    } catch (e) {
      Logger.error('BybitTradingProvider: Error loading candles - $e');
    }
  }

  // ============================================================================
  // MARKET ANALYSIS
  // ============================================================================
  Future<void> _analyzeMarket() async {
    if (_realtimeClosePrices.length < 30) {
      Logger.warning('BybitTradingProvider: Not enough data for analysis (${_realtimeClosePrices.length}/30)');
      return;
    }

    try {
      Logger.debug('BybitTradingProvider: Analyzing market...');

      final result = MarketAnalyzer.analyzeMarket(
        closePrices: _realtimeClosePrices,
        volumes: _realtimeVolumes,
      );

      _currentCondition = result.condition;
      _analysisResult = result;
      _lastAnalysis = DateTime.now();

      // Update strategy config
      _currentStrategy = AdaptiveStrategy.getStrategyConfig(_currentCondition);

      Logger.success('BybitTradingProvider: Market = ${_currentCondition.displayName}');
      Logger.debug('BybitTradingProvider: ${result.reasoning}');

      notifyListeners();
    } catch (e) {
      Logger.error('BybitTradingProvider: Error analyzing market - $e');
    }
  }

  // ============================================================================
  // TRADING SIGNAL CHECK
  // ============================================================================
  void _checkTradingSignal() {
    if (_realtimeClosePrices.length < 30 || _currentPrice == null) {
      return;
    }

    try {
      Logger.debug('🔍 신호 체크 시작 - 캔들: ${_realtimeClosePrices.length}개, 현재가: \$${_currentPrice!.toStringAsFixed(2)}');

      final signal = AdaptiveStrategy.analyzeSignal(
        condition: _currentCondition,
        closePrices: _realtimeClosePrices,
        volumes: _realtimeVolumes,
        currentPrice: _currentPrice!,
      );

      _currentSignal = signal;

      if (signal.hasSignal) {
        Logger.debug('BybitTradingProvider: ${signal.type.name.toUpperCase()} signal (${(signal.confidence * 100).toStringAsFixed(0)}%) - ${signal.reasoning}');

        // TODO: Execute trade based on signal
        // if (_isRunning && _currentPosition == null) {
        //   _executeTrade(signal);
        // }
      }

      notifyListeners();
    } catch (e) {
      Logger.error('BybitTradingProvider: Error checking signal - $e');
    }
  }

  // ============================================================================
  // BOT CONTROL
  // ============================================================================
  Future<void> startBot() async {
    if (_isRunning) return;

    Logger.debug('BybitTradingProvider: Starting bot...');

    _isRunning = true;

    // Start market analysis timer (every 5 minutes)
    _marketAnalysisTimer = Timer.periodic(const Duration(minutes: 5), (timer) {
      if (!_disposed) {
        _analyzeMarket();
      }
    });

    // 신호 체크는 웹소켓 실시간 가격 업데이트 시 자동 실행 (throttling 적용)
    // Timer 제거 - 더 이상 필요 없음

    // Start balance update timer (every 3 seconds)
    _balanceUpdateTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (!_disposed) {
        fetchBalance();
      }
    });

    // 초기 신호 체크 실행
    _checkTradingSignal();

    Logger.success('BybitTradingProvider: Bot started! (실시간 신호 체크 활성화)');
    notifyListeners();
  }

  Future<void> stopBot() async {
    if (!_isRunning) return;

    Logger.debug('BybitTradingProvider: Stopping bot...');

    _isRunning = false;

    _marketAnalysisTimer?.cancel();
    _marketAnalysisTimer = null;

    _balanceUpdateTimer?.cancel();
    _balanceUpdateTimer = null;

    _lastSignalCheck = null;

    Logger.success('BybitTradingProvider: Bot stopped!');
    notifyListeners();
  }

  // ============================================================================
  // CONFIGURATION SETTERS
  // ============================================================================
  void setInvestmentAmount(double amount) {
    if (!_isRunning && amount >= 10.0) {
      _investmentAmount = amount;
      notifyListeners();
    }
  }

  void setLeverage(String leverage) {
    if (!_isRunning) {
      _leverage = leverage;
      notifyListeners();
    }
  }

  // ============================================================================
  // DISPOSE
  // ============================================================================
  @override
  void dispose() {
    _disposed = true;
    _marketAnalysisTimer?.cancel();
    _balanceUpdateTimer?.cancel();
    _klineSubscription?.cancel();
    _positionSubscription?.cancel();

    // Cancel all ticker subscriptions
    for (final subscription in _tickerSubscriptions.values) {
      subscription.cancel();
    }
    _tickerSubscriptions.clear();

    super.dispose();
  }
}
