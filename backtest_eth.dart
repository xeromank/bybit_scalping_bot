import 'package:bybit_scalping_bot/models/market_condition.dart';
import 'package:bybit_scalping_bot/services/market_analyzer.dart';
import 'package:bybit_scalping_bot/services/adaptive_strategy.dart';

// Backtest ETH with adaptive strategy
void main() {
  print('🚀 ETH Backtesting - Adaptive Strategy System');
  print('💰 Seed Money: \$1000 USDT');
  print('📅 Period: Last 12 hours (144 x 5min candles)');
  print('=' * 80);

  // ETH 5min candle data (reversed - oldest first)
  final rawCandles = [
    [3995.75, 4003.21, 3991.59, 4002.34, 2309.14], // [0]: open, high, low, close, volume
    [4002.34, 4009.96, 4000.0, 4003.0, 6208.23],
    [4003.0, 4016.19, 4000.75, 4013.96, 5277.6],
    [4013.96, 4014.23, 4005.98, 4010.47, 3382.65],
    [4010.47, 4019.06, 4007.86, 4014.4, 4349.66],
    [4014.4, 4019.37, 4008.75, 4013.59, 3145.17],
    [4013.59, 4021.28, 4012.54, 4018.32, 4443.9],
    [4018.32, 4023.36, 4017.74, 4022.08, 3528.01],
    [4022.08, 4025.96, 4017.61, 4023.23, 6270.38],
    [4023.23, 4031.62, 4017.57, 4020.19, 5613.94],
    [4020.19, 4021.72, 4017.39, 4019.23, 1807.13],
    [4019.23, 4019.23, 4002.73, 4009.05, 9169.43],
    [4009.05, 4009.25, 4001.26, 4004.45, 2631.85],
    [4004.45, 4006.62, 3996.9, 4000.85, 10788.24],
    [4000.85, 4000.9, 3996.01, 3997.67, 2587.96],
    [3997.67, 3997.72, 3993.01, 3994.16, 2002.19],
    [3994.16, 3994.57, 3990.21, 3992.41, 1696.91],
    [3992.41, 3995.93, 3985.73, 3989.35, 2233.32],
    [3989.35, 3989.35, 3975.73, 3982.17, 7851.3],
    [3982.17, 3982.76, 3967.17, 3974.32, 17415.78],
    [3974.32, 3978.45, 3972.55, 3976.56, 4403.7],
    [3976.56, 3986.17, 3976.39, 3983.86, 4338.17],
    [3983.86, 3984.06, 3978.05, 3980.97, 1625.38],
    [3980.97, 3981.08, 3966.0, 3968.2, 7753.43],
    [3968.2, 3971.47, 3961.96, 3962.18, 7856.21],
    [3962.18, 3965.6, 3952.6, 3954.79, 8678.72],
    [3954.79, 3958.72, 3945.24, 3946.0, 21777.79],
    [3946.0, 3951.0, 3922.02, 3928.45, 33412.68],
    [3928.45, 3931.19, 3918.07, 3923.6, 10473.74],
    [3923.6, 3924.1, 3906.5, 3915.51, 13631.23],
    [3915.51, 3926.91, 3914.71, 3925.44, 11507.32],
    [3925.44, 3940.61, 3924.34, 3931.02, 9564.42],
    [3931.02, 3940.88, 3925.97, 3935.09, 6183.5],
    [3935.09, 3937.67, 3926.43, 3933.57, 9128.66],
    [3933.57, 3943.97, 3933.57, 3939.77, 4198.84],
    [3939.77, 3950.81, 3935.31, 3936.4, 7569.95],
    [3936.4, 3938.99, 3927.86, 3938.91, 3336.53],
    [3938.91, 3948.99, 3938.4, 3941.21, 4034.28],
    [3941.21, 3947.58, 3937.26, 3943.61, 2075.38],
    [3943.61, 3946.71, 3938.27, 3940.41, 6829.41],
    [3940.41, 3952.4, 3938.11, 3945.35, 4088.17],
    [3945.35, 3948.98, 3937.55, 3938.21, 3458.15],
    [3938.21, 3943.68, 3935.0, 3935.48, 2178.65],
    [3935.48, 3943.62, 3932.59, 3941.77, 2662.02],
    [3941.77, 3946.54, 3934.49, 3945.25, 2468.67],
    [3945.25, 3948.53, 3936.24, 3942.9, 1978.03],
    [3942.9, 3943.33, 3935.06, 3935.86, 2045.55],
    [3935.86, 3935.86, 3927.87, 3931.95, 3224.25],
    [3931.95, 3931.96, 3920.01, 3922.38, 5914.13],
    [3922.38, 3931.07, 3916.41, 3926.21, 4546.72],
    [3926.21, 3949.06, 3923.4, 3939.37, 5931.48],
    [3939.37, 3947.52, 3938.14, 3943.54, 1937.37],
    [3943.54, 3945.59, 3942.3, 3944.21, 1003.28],
    [3944.21, 3944.93, 3939.36, 3944.43, 1805.45],
    [3944.43, 3962.58, 3944.42, 3957.14, 11147.05],
    [3957.14, 3962.02, 3953.74, 3956.07, 4245.22],
    [3956.07, 3961.85, 3952.0, 3954.41, 3490.21],
    [3954.41, 3964.82, 3951.54, 3952.9, 5582.95],
    [3952.9, 3956.18, 3948.6, 3954.16, 2250.86],
    [3954.16, 3955.16, 3949.07, 3950.79, 892.1],
    [3950.79, 3954.98, 3944.05, 3946.39, 3476.52],
    [3946.39, 3954.52, 3946.11, 3954.24, 818.09],
    [3954.24, 3967.14, 3952.4, 3963.48, 3318.37],
    [3963.48, 3963.5, 3955.9, 3956.28, 1480.64],
    [3956.28, 3959.89, 3953.11, 3959.89, 1082.83],
    [3959.89, 3962.58, 3952.29, 3953.61, 2168.22],
    [3953.61, 3963.0, 3953.46, 3962.0, 1464.8],
    [3962.0, 3985.73, 3961.39, 3977.42, 14609.64],
    [3977.42, 3994.59, 3973.0, 3993.71, 11730.73],
    [3993.71, 4039.25, 3993.7, 4026.16, 33460.32],
    [4026.16, 4032.28, 4017.83, 4025.37, 9189.05],
    [4025.37, 4038.62, 4025.37, 4036.61, 9310.35],
    [4036.61, 4046.94, 4026.55, 4028.4, 12948.5],
    [4028.4, 4034.39, 4023.0, 4033.01, 4576.65],
    [4033.01, 4037.45, 4022.86, 4025.07, 4492.66],
    [4025.07, 4028.72, 4020.69, 4025.87, 4436.73],
    [4025.87, 4032.97, 4024.11, 4029.19, 2874.41],
    [4029.19, 4045.4, 4029.19, 4033.88, 7392.91],
    [4033.88, 4042.8, 4033.61, 4038.18, 4229.96],
    [4038.18, 4043.14, 4033.6, 4039.05, 5594.79],
    [4039.05, 4041.37, 4034.4, 4035.99, 2019.36],
    [4035.99, 4044.63, 4034.08, 4043.24, 2496.02],
    [4043.24, 4054.22, 4042.25, 4053.01, 10206.54],
    [4053.01, 4053.02, 4041.92, 4043.92, 4042.08],
    [4043.92, 4051.85, 4038.26, 4051.03, 19385.05],
    [4051.03, 4053.99, 4046.4, 4052.39, 4263.5],
    [4052.39, 4052.39, 4041.78, 4044.56, 3964.75],
    [4044.56, 4054.76, 4044.56, 4050.85, 3655.69],
    [4050.85, 4054.89, 4048.73, 4052.34, 2577.11],
    [4052.34, 4065.0, 4050.4, 4060.57, 16321.0],
    [4060.57, 4061.82, 4053.11, 4056.39, 2420.88],
    [4056.39, 4057.86, 4051.65, 4057.86, 1756.57],
    [4057.86, 4059.29, 4053.0, 4058.91, 1891.21],
    [4058.91, 4074.35, 4057.16, 4072.06, 14425.37],
    [4072.06, 4072.29, 4056.01, 4059.71, 6233.76],
    [4059.71, 4066.17, 4055.0, 4065.21, 3573.32],
    [4065.21, 4071.75, 4058.89, 4071.04, 3342.54],
    [4071.04, 4078.0, 4068.93, 4069.27, 7681.88],
    [4069.27, 4079.98, 4066.58, 4078.67, 6326.74],
    [4078.67, 4084.83, 4072.07, 4074.1, 5470.51],
    [4074.1, 4078.0, 4069.67, 4072.43, 3199.61],
    [4072.43, 4082.83, 4072.08, 4080.87, 5837.56],
    [4080.87, 4082.91, 4071.3, 4072.37, 5850.97],
    [4072.37, 4080.97, 4071.52, 4079.74, 2911.04],
    [4079.74, 4082.2, 4072.0, 4075.7, 4309.08],
    [4075.7, 4079.36, 4072.58, 4077.89, 2802.95],
    [4077.89, 4080.13, 4072.87, 4073.53, 1528.22],
    [4073.53, 4073.53, 4063.65, 4072.11, 7196.55],
    [4072.11, 4074.81, 4060.55, 4066.88, 7142.0],
    [4066.88, 4073.64, 4066.88, 4071.73, 2647.96],
    [4071.73, 4073.21, 4068.12, 4072.5, 2378.07],
    [4072.5, 4076.07, 4068.8, 4069.58, 3722.35],
    [4069.58, 4072.78, 4066.25, 4067.36, 2017.52],
    [4067.36, 4068.16, 4064.17, 4066.72, 1914.16],
    [4066.72, 4067.48, 4060.85, 4061.4, 2791.65],
    [4061.4, 4063.37, 4055.07, 4058.97, 5605.79],
    [4058.97, 4059.27, 4052.53, 4054.94, 4328.19],
    [4054.94, 4060.5, 4052.69, 4054.63, 4473.66],
    [4054.63, 4055.05, 4050.24, 4053.67, 2993.99],
    [4053.67, 4056.29, 4046.84, 4048.52, 4958.18],
    [4048.52, 4049.92, 4043.74, 4044.57, 4081.87],
    [4044.57, 4046.48, 4037.36, 4046.43, 5947.21],
    [4046.43, 4046.65, 4041.63, 4042.24, 4243.23],
    [4042.24, 4042.88, 4032.63, 4033.62, 4806.38],
    [4033.62, 4048.24, 4033.42, 4047.76, 4254.37],
    [4047.76, 4065.46, 4044.49, 4061.98, 10928.26],
    [4061.98, 4071.03, 4044.0, 4047.0, 9209.29],
    [4047.0, 4050.75, 4040.33, 4049.54, 4860.31],
    [4049.54, 4058.64, 4044.19, 4044.8, 4165.35],
    [4044.8, 4045.2, 4038.78, 4042.08, 3523.66],
    [4042.08, 4046.04, 4040.68, 4043.54, 1390.51],
    [4043.54, 4043.54, 4035.48, 4038.27, 2640.18],
    [4038.27, 4043.5, 4034.45, 4041.96, 3175.65],
    [4041.96, 4050.56, 4041.31, 4046.5, 2536.08],
    [4046.5, 4047.81, 4033.37, 4037.88, 3103.99],
    [4037.88, 4041.07, 4033.69, 4039.9, 1992.27],
    [4039.9, 4039.9, 4035.58, 4037.91, 1426.75],
    [4037.91, 4040.06, 4033.0, 4033.57, 1190.26],
    [4033.57, 4037.8, 4033.0, 4036.31, 1610.93],
    [4036.31, 4042.73, 4036.22, 4039.37, 1726.6],
    [4039.37, 4042.43, 4034.43, 4042.17, 1421.74],
    [4042.17, 4042.47, 4036.56, 4041.67, 1087.0],
    [4041.67, 4045.67, 4039.75, 4042.9, 3438.42],
    [4042.9, 4049.8, 4042.88, 4048.13, 1965.09],
  ];

  // Initialize tracking variables
  double balance = 1000.0; // USDT
  double? entryPrice;
  double? takeProfitPrice;
  double? stopLossPrice;
  String? positionSide; // 'long' or 'short'
  double? positionSize; // Contract size
  int? leverage;

  final List<double> closePrices = [];
  final List<double> volumes = [];
  final List<String> trades = [];
  int totalTrades = 0;
  int winTrades = 0;
  int lossTrades = 0;
  double maxBalance = 1000.0;
  double minBalance = 1000.0;

  // Process each candle
  for (int i = 0; i < rawCandles.length; i++) {
    final candle = rawCandles[i];
    final close = candle[3].toDouble();
    final volume = candle[4].toDouble();

    closePrices.add(close);
    volumes.add(volume);

    // Need at least 30 candles for analysis
    if (closePrices.length < 30) continue;

    // Check if we have an open position - check TP/SL
    if (entryPrice != null && positionSide != null) {
      bool shouldClose = false;
      String closeReason = '';
      double closePrice = close;

      if (positionSide == 'long') {
        // Check TP/SL for long
        if (close >= takeProfitPrice!) {
          shouldClose = true;
          closeReason = 'TP';
          closePrice = takeProfitPrice!;
        } else if (close <= stopLossPrice!) {
          shouldClose = true;
          closeReason = 'SL';
          closePrice = stopLossPrice!;
        }
      } else {
        // Check TP/SL for short
        if (close <= takeProfitPrice!) {
          shouldClose = true;
          closeReason = 'TP';
          closePrice = takeProfitPrice!;
        } else if (close >= stopLossPrice!) {
          shouldClose = true;
          closeReason = 'SL';
          closePrice = stopLossPrice!;
        }
      }

      if (shouldClose) {
        // Calculate PnL
        double pnl;
        if (positionSide == 'long') {
          pnl = (closePrice - entryPrice!) * positionSize!;
        } else {
          pnl = (entryPrice! - closePrice) * positionSize!;
        }

        balance += pnl;
        totalTrades++;

        if (pnl > 0) {
          winTrades++;
        } else {
          lossTrades++;
        }

        // Track max/min balance
        if (balance > maxBalance) maxBalance = balance;
        if (balance < minBalance) minBalance = balance;

        final pnlPercent = (pnl / balance) * 100;
        trades.add('[$i] CLOSE $positionSide @ \$$closePrice ($closeReason) | PnL: \$${pnl.toStringAsFixed(2)} (${pnlPercent.toStringAsFixed(2)}%) | Balance: \$${balance.toStringAsFixed(2)}');

        // Reset position
        entryPrice = null;
        positionSide = null;
        positionSize = null;
        leverage = null;
      }
    }

    // If no position, check for entry signal
    if (entryPrice == null && balance > 0) {
      // Analyze market
      final analysisResult = MarketAnalyzer.analyzeMarket(
        closePrices: closePrices,
        volumes: volumes,
      );

      // Get trading signal
      final signal = AdaptiveStrategy.analyzeSignal(
        condition: analysisResult.condition,
        closePrices: closePrices,
        volumes: volumes,
        currentPrice: close,
      );

      // Execute trade if signal exists
      if (signal.hasSignal) {
        leverage = signal.strategyConfig.recommendedLeverage;
        final investmentAmount = balance; // Use full balance
        positionSize = (investmentAmount * leverage!) / close;
        entryPrice = close;
        positionSide = signal.type == SignalType.long ? 'long' : 'short';

        if (signal.type == SignalType.long) {
          takeProfitPrice = close * (1 + signal.strategyConfig.takeProfitPercent);
          stopLossPrice = close * (1 - signal.strategyConfig.stopLossPercent);
        } else {
          takeProfitPrice = close * (1 - signal.strategyConfig.takeProfitPercent);
          stopLossPrice = close * (1 + signal.strategyConfig.stopLossPercent);
        }

        trades.add('[$i] OPEN $positionSide @ \$$close ${leverage}x | Condition: ${analysisResult.condition.displayName} | Signal: ${signal.reasoning}');
      }
    }
  }

  // Close any remaining position at market price
  if (entryPrice != null && positionSide != null) {
    final closePrice = closePrices.last;
    double pnl;
    if (positionSide == 'long') {
      pnl = (closePrice - entryPrice!) * positionSize!;
    } else {
      pnl = (entryPrice! - closePrice) * positionSize!;
    }

    balance += pnl;
    totalTrades++;

    if (pnl > 0) {
      winTrades++;
    } else {
      lossTrades++;
    }

    trades.add('[END] CLOSE $positionSide @ \$$closePrice (Market) | PnL: \$${pnl.toStringAsFixed(2)} | Balance: \$${balance.toStringAsFixed(2)}');
  }

  // Print results
  print('\n📊 BACKTEST RESULTS');
  print('=' * 80);
  print('💵 Starting Balance: \$1000.00');
  print('💵 Ending Balance: \$${balance.toStringAsFixed(2)}');
  print('📈 Max Balance: \$${maxBalance.toStringAsFixed(2)}');
  print('📉 Min Balance: \$${minBalance.toStringAsFixed(2)}');
  print('💰 Total P/L: \$${(balance - 1000).toStringAsFixed(2)} (${((balance - 1000) / 1000 * 100).toStringAsFixed(2)}%)');
  print('\n📊 Trade Statistics:');
  print('  - Total Trades: $totalTrades');
  print('  - Win Trades: $winTrades (${totalTrades > 0 ? (winTrades / totalTrades * 100).toStringAsFixed(1) : 0}%)');
  print('  - Loss Trades: $lossTrades (${totalTrades > 0 ? (lossTrades / totalTrades * 100).toStringAsFixed(1) : 0}%)');
  print('  - Win Rate: ${totalTrades > 0 ? (winTrades / totalTrades * 100).toStringAsFixed(1) : 0}%');

  print('\n📝 Trade Log:');
  print('=' * 80);
  for (final trade in trades) {
    print(trade);
  }

  print('\n' + '=' * 80);
  print('✅ Backtesting Complete!');
}
