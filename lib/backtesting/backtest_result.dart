import 'dart:math';

/// Single trade result
class TradeResult {
  final DateTime entryTime;
  final DateTime exitTime;
  final String side; // LONG or SHORT
  final String strategyType; // 추세추종 or 역추세
  final double averageEntryPrice;
  final double exitPrice;
  final double quantity;
  final double profitLoss; // In USD
  final double profitLossPercent;
  final int entryCount; // Number of split entries (1, 2, or 3)
  final Duration holdingTime;
  final String exitReason;
  final bool isEmergencyExit;

  // Entry indicators
  final double entryRSI;
  final double entryBBUpper;
  final double entryBBMiddle;
  final double entryBBLower;

  TradeResult({
    required this.entryTime,
    required this.exitTime,
    required this.side,
    required this.strategyType,
    required this.averageEntryPrice,
    required this.exitPrice,
    required this.quantity,
    required this.profitLoss,
    required this.profitLossPercent,
    required this.entryCount,
    required this.holdingTime,
    required this.exitReason,
    required this.isEmergencyExit,
    required this.entryRSI,
    required this.entryBBUpper,
    required this.entryBBMiddle,
    required this.entryBBLower,
  });

  bool get isWin => profitLoss > 0;
  bool get isLoss => profitLoss < 0;

  @override
  String toString() {
    final plSign = profitLoss >= 0 ? '+' : '';
    final plColor = profitLoss >= 0 ? '✅' : '❌';
    return '$plColor $side $strategyType | Entry: \$${averageEntryPrice.toStringAsFixed(2)} → Exit: \$${exitPrice.toStringAsFixed(2)} | '
        'P/L: $plSign\$${profitLoss.toStringAsFixed(2)} (${plSign}${(profitLossPercent * 100).toStringAsFixed(2)}%) | '
        'Entries: $entryCount | Hold: ${holdingTime.inMinutes}min | ${isEmergencyExit ? '⚠️' : ''}$exitReason';
  }
}

/// Backtest result summary
class BacktestResult {
  final String symbol;
  final DateTime startDate;
  final DateTime endDate;
  final double initialCapital;
  final int leverage;

  final List<TradeResult> trades;
  final List<double> equityCurve; // Capital over time
  final List<DateTime> equityTimestamps;

  BacktestResult({
    required this.symbol,
    required this.startDate,
    required this.endDate,
    required this.initialCapital,
    required this.leverage,
    required this.trades,
    required this.equityCurve,
    required this.equityTimestamps,
  });

  // =========================================================================
  // Performance Metrics
  // =========================================================================

  int get totalTrades => trades.length;

  int get winningTrades => trades.where((t) => t.isWin).length;

  int get losingTrades => trades.where((t) => t.isLoss).length;

  double get winRate => totalTrades > 0 ? winningTrades / totalTrades : 0.0;

  double get totalProfit => trades.where((t) => t.isWin).fold(0.0, (sum, t) => sum + t.profitLoss);

  double get totalLoss => trades.where((t) => t.isLoss).fold(0.0, (sum, t) => sum + t.profitLoss);

  double get netProfit => totalProfit + totalLoss;

  double get netProfitPercent => netProfit / initialCapital;

  double get averageWin => winningTrades > 0
      ? totalProfit / winningTrades
      : 0.0;

  double get averageLoss => losingTrades > 0
      ? totalLoss / losingTrades
      : 0.0;

  double get profitFactor => totalLoss.abs() > 0
      ? totalProfit / totalLoss.abs()
      : double.infinity;

  double get finalCapital => equityCurve.isNotEmpty ? equityCurve.last : initialCapital;

  double get returnPercent => (finalCapital - initialCapital) / initialCapital;

  /// Maximum Drawdown (MDD) as percentage
  double get maxDrawdown {
    if (equityCurve.isEmpty) return 0.0;

    double maxDD = 0.0;
    double peak = equityCurve.first;

    for (final equity in equityCurve) {
      if (equity > peak) {
        peak = equity;
      }

      final drawdown = (peak - equity) / peak;
      if (drawdown > maxDD) {
        maxDD = drawdown;
      }
    }

    return maxDD;
  }

  /// Sharpe Ratio (simplified - assuming risk-free rate = 0)
  double get sharpeRatio {
    if (trades.isEmpty) return 0.0;

    final returns = trades.map((t) => t.profitLossPercent).toList();
    final avgReturn = returns.reduce((a, b) => a + b) / returns.length;

    // Calculate standard deviation
    final variance = returns
        .map((r) => (r - avgReturn) * (r - avgReturn))
        .reduce((a, b) => a + b) / returns.length;
    final stdDev = variance > 0 ? variance : 0.0001; // Avoid division by zero

    // Annualized Sharpe (assuming ~250 trading days)
    return (avgReturn / stdDev) * sqrt(250 / trades.length);
  }

  /// Average holding time
  Duration get averageHoldingTime {
    if (trades.isEmpty) return Duration.zero;

    final totalSeconds = trades.fold(0, (sum, t) => sum + t.holdingTime.inSeconds);
    return Duration(seconds: totalSeconds ~/ trades.length);
  }

  /// Emergency exit count
  int get emergencyExits => trades.where((t) => t.isEmergencyExit).length;

  // =========================================================================
  // Strategy-specific metrics
  // =========================================================================

  List<TradeResult> get trendFollowingTrades =>
      trades.where((t) => t.strategyType == '추세추종').toList();

  List<TradeResult> get counterTrendTrades =>
      trades.where((t) => t.strategyType == '역추세').toList();

  Map<String, dynamic> get strategyAMetrics => _calculateStrategyMetrics(trendFollowingTrades);

  Map<String, dynamic> get strategyBMetrics => _calculateStrategyMetrics(counterTrendTrades);

  Map<String, dynamic> _calculateStrategyMetrics(List<TradeResult> strategyTrades) {
    if (strategyTrades.isEmpty) {
      return {
        'trades': 0,
        'winRate': 0.0,
        'profitFactor': 0.0,
        'netProfit': 0.0,
        'avgWin': 0.0,
        'avgLoss': 0.0,
      };
    }

    final wins = strategyTrades.where((t) => t.isWin).length;
    final losses = strategyTrades.where((t) => t.isLoss).length;
    final totalProfit = strategyTrades.where((t) => t.isWin).fold(0.0, (sum, t) => sum + t.profitLoss);
    final totalLoss = strategyTrades.where((t) => t.isLoss).fold(0.0, (sum, t) => sum + t.profitLoss);

    return {
      'trades': strategyTrades.length,
      'winRate': wins / strategyTrades.length,
      'profitFactor': totalLoss.abs() > 0 ? totalProfit / totalLoss.abs() : double.infinity,
      'netProfit': totalProfit + totalLoss,
      'avgWin': wins > 0 ? totalProfit / wins : 0.0,
      'avgLoss': losses > 0 ? totalLoss / losses : 0.0,
    };
  }

  // =========================================================================
  // Output Methods
  // =========================================================================

  /// Print summary to console
  void printSummary() {
    print('\n' + '=' * 80);
    print('📊 백테스트 결과 요약');
    print('=' * 80);
    print('');
    print('🔍 기본 정보');
    print('  Symbol: $symbol');
    print('  Period: ${startDate.toString().substring(0, 10)} ~ ${endDate.toString().substring(0, 10)}');
    print('  Initial Capital: \$${initialCapital.toStringAsFixed(2)}');
    print('  Leverage: ${leverage}x');
    print('');
    print('💰 수익 성과');
    print('  Final Capital: \$${finalCapital.toStringAsFixed(2)}');
    print('  Net Profit: \$${netProfit.toStringAsFixed(2)} (${(netProfitPercent * 100).toStringAsFixed(2)}%)');
    print('  Return: ${(returnPercent * 100).toStringAsFixed(2)}%');
    print('  Max Drawdown: ${(maxDrawdown * 100).toStringAsFixed(2)}%');
    print('');
    print('📈 거래 통계');
    print('  Total Trades: $totalTrades');
    print('  Win Rate: ${(winRate * 100).toStringAsFixed(1)}% ($winningTrades wins / $losingTrades losses)');
    print('  Profit Factor: ${profitFactor.toStringAsFixed(2)}');
    print('  Avg Win: \$${averageWin.toStringAsFixed(2)}');
    print('  Avg Loss: \$${averageLoss.toStringAsFixed(2)}');
    print('  Sharpe Ratio: ${sharpeRatio.toStringAsFixed(2)}');
    print('  Avg Holding Time: ${averageHoldingTime.inMinutes} min');
    print('  Emergency Exits: $emergencyExits');
    print('');
    print('🎯 전략별 성과');
    print('  Strategy A (추세추종):');
    print('    Trades: ${strategyAMetrics['trades']}');
    print('    Win Rate: ${(strategyAMetrics['winRate'] * 100).toStringAsFixed(1)}%');
    print('    Profit Factor: ${strategyAMetrics['profitFactor'].toStringAsFixed(2)}');
    print('    Net Profit: \$${strategyAMetrics['netProfit'].toStringAsFixed(2)}');
    print('');
    print('  Strategy B (역추세):');
    print('    Trades: ${strategyBMetrics['trades']}');
    print('    Win Rate: ${(strategyBMetrics['winRate'] * 100).toStringAsFixed(1)}%');
    print('    Profit Factor: ${strategyBMetrics['profitFactor'].toStringAsFixed(2)}');
    print('    Net Profit: \$${strategyBMetrics['netProfit'].toStringAsFixed(2)}');
    print('');
    print('=' * 80);
  }

  /// Print all trades
  void printAllTrades() {
    print('\n📋 전체 거래 내역:');
    print('-' * 120);

    for (int i = 0; i < trades.length; i++) {
      final trade = trades[i];
      print('${(i + 1).toString().padLeft(3)}. ${trade.toString()}');
    }

    print('-' * 120);
  }

  /// Generate CSV report
  String toCsv() {
    final buffer = StringBuffer();

    // Header
    buffer.writeln('Entry Time,Exit Time,Side,Strategy,Avg Entry,Exit Price,Qty,P/L USD,P/L %,Entries,Hold (min),Exit Reason,Emergency,Entry RSI,BB Upper,BB Middle,BB Lower');

    // Trades
    for (final trade in trades) {
      buffer.writeln([
        trade.entryTime.toIso8601String(),
        trade.exitTime.toIso8601String(),
        trade.side,
        trade.strategyType,
        trade.averageEntryPrice.toStringAsFixed(2),
        trade.exitPrice.toStringAsFixed(2),
        trade.quantity.toStringAsFixed(4),
        trade.profitLoss.toStringAsFixed(2),
        (trade.profitLossPercent * 100).toStringAsFixed(2),
        trade.entryCount,
        trade.holdingTime.inMinutes,
        trade.exitReason,
        trade.isEmergencyExit ? 'YES' : 'NO',
        trade.entryRSI.toStringAsFixed(2),
        trade.entryBBUpper.toStringAsFixed(2),
        trade.entryBBMiddle.toStringAsFixed(2),
        trade.entryBBLower.toStringAsFixed(2),
      ].join(','));
    }

    return buffer.toString();
  }
}
