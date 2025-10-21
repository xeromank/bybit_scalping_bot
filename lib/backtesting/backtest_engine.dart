import 'package:bybit_scalping_bot/backtesting/backtest_result.dart';
import 'package:bybit_scalping_bot/backtesting/position_tracker.dart';
import 'package:bybit_scalping_bot/backtesting/split_entry_strategy.dart';
import 'package:bybit_scalping_bot/services/market_analyzer.dart';
import 'package:bybit_scalping_bot/utils/technical_indicators.dart';

/// Kline data for backtesting
class KlineData {
  final DateTime timestamp;
  final double open;
  final double high;
  final double low;
  final double close;
  final double volume;

  KlineData({
    required this.timestamp,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.volume,
  });

  factory KlineData.fromBybitKline(List<dynamic> kline) {
    // Bybit kline format: [startTime, open, high, low, close, volume, turnover]
    return KlineData(
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        int.parse(kline[0].toString()),
        isUtc: true,
      ),
      open: double.parse(kline[1].toString()),
      high: double.parse(kline[2].toString()),
      low: double.parse(kline[3].toString()),
      close: double.parse(kline[4].toString()),
      volume: double.parse(kline[5].toString()),
    );
  }

  @override
  String toString() {
    return 'Kline[${timestamp.toString().substring(0, 16)} C:\$${close.toStringAsFixed(2)} V:${volume.toStringAsFixed(0)}]';
  }
}

/// Backtest configuration
class BacktestConfig {
  final String symbol;
  final double initialCapital;
  final int leverage;
  final double positionSizePercent; // Position size as % of capital per entry
  final double makerFee; // -0.00025 for Bybit
  final double takerFee; // 0.00055 for Bybit
  final bool printProgress; // Print progress during backtest

  BacktestConfig({
    required this.symbol,
    this.initialCapital = 10000.0,
    this.leverage = 10,
    this.positionSizePercent = 0.05, // 5% per entry
    this.makerFee = -0.00025,
    this.takerFee = 0.00055,
    this.printProgress = true,
  });
}

/// Backtest engine
class BacktestEngine {
  final BacktestConfig config;
  final List<KlineData> klines;

  // State
  double _capital;
  final PositionTracker _position = PositionTracker();
  final List<TradeResult> _trades = [];
  final List<double> _equityCurve = [];
  final List<DateTime> _equityTimestamps = [];

  // Entry indicators (saved when position is first opened)
  double? _entryRSI;
  double? _entryBBUpper;
  double? _entryBBMiddle;
  double? _entryBBLower;

  // Cache for market analysis
  final Map<int, MarketAnalysisResult> _marketAnalysisCache = {};

  BacktestEngine({
    required this.config,
    required this.klines,
  }) : _capital = config.initialCapital;

  /// Run backtest
  Future<BacktestResult> run() async {
    if (klines.length < 100) {
      throw ArgumentError('Need at least 100 klines for backtest');
    }

    if (config.printProgress) {
      print('\n🚀 백테스트 시작');
      print('Symbol: ${config.symbol}');
      print('Period: ${klines.first.timestamp} ~ ${klines.last.timestamp}');
      print('Initial Capital: \$${config.initialCapital}');
      print('Leverage: ${config.leverage}x');
      print('Total Klines: ${klines.length}');
      print('');
    }

    // Reset state
    _capital = config.initialCapital;
    _position.reset();
    _trades.clear();
    _equityCurve.clear();
    _equityTimestamps.clear();

    // Start from candle 50 (need history for indicators)
    for (int i = 50; i < klines.length; i++) {
      await _processCandle(i);

      // Print progress every 100 candles
      if (config.printProgress && i % 100 == 0) {
        final progressPercent = (i / klines.length * 100).toStringAsFixed(1);
        print('Progress: $progressPercent% (${i}/${klines.length}) | Trades: ${_trades.length} | Capital: \$${_capital.toStringAsFixed(2)}');
      }
    }

    // Close any remaining position
    if (_position.hasPosition) {
      final lastCandle = klines.last;
      _closePosition(
        exitPrice: lastCandle.close,
        exitTime: lastCandle.timestamp,
        exitReason: '백테스트 종료',
        isEmergency: false,
      );
    }

    if (config.printProgress) {
      print('\n✅ 백테스트 완료!');
      print('Total Trades: ${_trades.length}');
      print('Final Capital: \$${_capital.toStringAsFixed(2)}');
      print('');
    }

    return BacktestResult(
      symbol: config.symbol,
      startDate: klines.first.timestamp,
      endDate: klines.last.timestamp,
      initialCapital: config.initialCapital,
      leverage: config.leverage,
      trades: _trades,
      equityCurve: _equityCurve,
      equityTimestamps: _equityTimestamps,
    );
  }

  /// Process single candle
  Future<void> _processCandle(int index) async {
    final currentCandle = klines[index];

    // Get recent data for analysis
    final recentKlines = klines.sublist(0, index + 1);
    final closePrices = recentKlines.map((k) => k.close).toList();
    final volumes = recentKlines.map((k) => k.volume).toList();

    // Analyze market condition
    final marketAnalysis = _getMarketAnalysis(index, closePrices, volumes);

    // Check exit signal first (if we have position)
    if (_position.hasPosition) {
      final exitSignal = SplitEntryStrategy.checkExitSignal(
        marketCondition: marketAnalysis.condition,
        closePrices: closePrices,
        currentPrice: currentCandle.close,
        currentTime: currentCandle.timestamp,
        position: _position,
        leverage: config.leverage,
      );

      if (exitSignal != null && exitSignal.hasSignal) {
        // Full exit
        if (exitSignal.exitPercent >= 0.99) {
          _closePosition(
            exitPrice: exitSignal.exitPrice,
            exitTime: currentCandle.timestamp,
            exitReason: exitSignal.reasoning,
            isEmergency: exitSignal.isEmergency,
          );
        } else {
          // Partial exit
          _closePartialPosition(
            exitPrice: exitSignal.exitPrice,
            exitPercent: exitSignal.exitPercent,
            exitTime: currentCandle.timestamp,
            exitReason: exitSignal.reasoning,
          );
        }
      }
    }

    // Check entry signal (if no position or adding to existing)
    if (!_position.hasPosition || _position.latestEntryLevel < 3) {
      final entrySignal = SplitEntryStrategy.checkEntrySignal(
        marketCondition: marketAnalysis.condition,
        closePrices: closePrices,
        volumes: volumes,
        currentPrice: currentCandle.close,
        currentTime: currentCandle.timestamp,
        position: _position,
      );

      if (entrySignal != null && entrySignal.hasSignal) {
        // Calculate entry indicators
        final bb = calculateBollingerBandsDefault(closePrices);
        final rsiSeries = calculateRSISeries(closePrices, 14);
        final currentRSI = rsiSeries.isNotEmpty ? rsiSeries.last : 50.0;

        _openPosition(
          side: entrySignal.side,
          entryPrice: entrySignal.entryPrice,
          entryTime: currentCandle.timestamp,
          entryLevel: entrySignal.entryLevel,
          strategyType: entrySignal.strategyType,
          reasoning: entrySignal.reasoning,
          rsi: currentRSI,
          bbUpper: bb.upper,
          bbMiddle: bb.middle,
          bbLower: bb.lower,
        );
      }
    }

    // Record equity
    final equity = _calculateEquity(currentCandle.close);
    _equityCurve.add(equity);
    _equityTimestamps.add(currentCandle.timestamp);
  }

  /// Get market analysis (with caching)
  MarketAnalysisResult _getMarketAnalysis(
    int index,
    List<double> closePrices,
    List<double> volumes,
  ) {
    if (_marketAnalysisCache.containsKey(index)) {
      return _marketAnalysisCache[index]!;
    }

    final result = MarketAnalyzer.analyzeMarket(
      closePrices: closePrices,
      volumes: volumes,
    );

    _marketAnalysisCache[index] = result;
    return result;
  }

  /// Open new position or add to existing
  void _openPosition({
    required PositionSide side,
    required double entryPrice,
    required DateTime entryTime,
    required int entryLevel,
    required StrategyType strategyType,
    required String reasoning,
    required double rsi,
    required double bbUpper,
    required double bbMiddle,
    required double bbLower,
  }) {
    // Save entry indicators on first entry
    if (entryLevel == 1) {
      _entryRSI = rsi;
      _entryBBUpper = bbUpper;
      _entryBBMiddle = bbMiddle;
      _entryBBLower = bbLower;
    }

    // Calculate position size
    final positionValue = _capital * config.positionSizePercent;
    final quantity = (positionValue * config.leverage) / entryPrice;

    // Add entry
    _position.addEntry(
      price: entryPrice,
      quantity: quantity,
      entryTime: entryTime,
      entryLevel: entryLevel,
      side: side,
      strategy: strategyType,
    );

    if (config.printProgress && entryLevel == 1) {
      print('');
      print('📍 NEW POSITION: ${side.name.toUpperCase()} ${strategyType.name} @\$${entryPrice.toStringAsFixed(2)}');
      print('   Reason: $reasoning');
    } else if (config.printProgress) {
      print('   ➕ Entry Lv$entryLevel: @\$${entryPrice.toStringAsFixed(2)} (Avg: \$${_position.averagePrice.toStringAsFixed(2)})');
    }
  }

  /// Close partial position
  void _closePartialPosition({
    required double exitPrice,
    required double exitPercent,
    required DateTime exitTime,
    required String exitReason,
  }) {
    final result = _position.closePartial(
      closePrice: exitPrice,
      closePercent: exitPercent,
      closeTime: exitTime,
    );

    // Calculate fees
    final fee = result.closedQty * exitPrice * config.takerFee;
    final netProfit = result.profit - fee;

    // Update capital
    _capital += netProfit;

    if (config.printProgress) {
      print('   📤 Partial Exit: ${(exitPercent * 100).toStringAsFixed(0)}% @\$${exitPrice.toStringAsFixed(2)} | '
          'P/L: \$${netProfit.toStringAsFixed(2)} | Remaining: ${_position.totalSize.toStringAsFixed(4)}');
    }
  }

  /// Close full position
  void _closePosition({
    required double exitPrice,
    required DateTime exitTime,
    required String exitReason,
    required bool isEmergency,
  }) {
    if (!_position.hasPosition) return;

    // Safety check: if strategyType is null, something went wrong
    if (_position.strategyType == null || _position.firstEntryTime == null) {
      // Reset position to clean state
      _position.reset();
      return;
    }

    final avgEntryPrice = _position.averagePrice;
    final totalQty = _position.totalSize;
    final entryCount = _position.entryCount;
    final strategyType = _position.strategyType!;
    final side = _position.currentSide;
    final entryTime = _position.firstEntryTime!;

    // Calculate profit
    final profit = _position.closeAll(
      closePrice: exitPrice,
      closeTime: exitTime,
    );

    // Calculate fees
    final fee = totalQty * exitPrice * config.takerFee;
    final netProfit = profit - fee;

    // Calculate PnL%
    final profitPercent = (exitPrice - avgEntryPrice) / avgEntryPrice;
    final actualProfitPercent = side == PositionSide.long
        ? profitPercent
        : -profitPercent;

    // Update capital
    _capital += netProfit;

    // Record trade
    final trade = TradeResult(
      entryTime: entryTime,
      exitTime: exitTime,
      side: side.name.toUpperCase(),
      strategyType: strategyType.name,
      averageEntryPrice: avgEntryPrice,
      exitPrice: exitPrice,
      quantity: totalQty,
      profitLoss: netProfit,
      profitLossPercent: actualProfitPercent,
      entryCount: entryCount,
      holdingTime: exitTime.difference(entryTime),
      exitReason: exitReason,
      isEmergencyExit: isEmergency,
      entryRSI: _entryRSI ?? 50.0,
      entryBBUpper: _entryBBUpper ?? 0.0,
      entryBBMiddle: _entryBBMiddle ?? 0.0,
      entryBBLower: _entryBBLower ?? 0.0,
    );

    _trades.add(trade);

    // Reset entry indicators
    _entryRSI = null;
    _entryBBUpper = null;
    _entryBBMiddle = null;
    _entryBBLower = null;

    if (config.printProgress) {
      final plSign = netProfit >= 0 ? '+' : '';
      final plEmoji = netProfit >= 0 ? '✅' : '❌';
      print('');
      print('$plEmoji CLOSE POSITION: ${side.name.toUpperCase()} ${strategyType.name}');
      print('   Entry: \$${avgEntryPrice.toStringAsFixed(2)} x $entryCount entries');
      print('   Exit: \$${exitPrice.toStringAsFixed(2)}');
      print('   P/L: $plSign\$${netProfit.toStringAsFixed(2)} (${plSign}${(actualProfitPercent * 100).toStringAsFixed(2)}%)');
      print('   Reason: $exitReason ${isEmergency ? '⚠️' : ''}');
      print('   Capital: \$${_capital.toStringAsFixed(2)}');
      print('');
    }
  }

  /// Calculate current equity (capital + unrealized PnL)
  double _calculateEquity(double currentPrice) {
    if (!_position.hasPosition) return _capital;

    final unrealizedPnl = _position.calculateUnrealizedPnlPercent(currentPrice);
    final positionValue = _position.totalSize * _position.averagePrice;
    final unrealizedPnlUsd = positionValue * unrealizedPnl;

    return _capital + unrealizedPnlUsd;
  }
}
