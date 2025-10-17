import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:bybit_scalping_bot/providers/trading_provider.dart';
import 'package:bybit_scalping_bot/constants/theme_constants.dart';
import 'package:bybit_scalping_bot/widgets/common/loading_button.dart';

/// Widget for trading bot controls
///
/// Responsibility: Provide UI controls for trading bot configuration
///
/// This widget provides input fields for trading parameters and
/// start/stop buttons for the bot.
class TradingControls extends StatefulWidget {
  const TradingControls({super.key});

  @override
  State<TradingControls> createState() => _TradingControlsState();
}

class _TradingControlsState extends State<TradingControls> {
  late TextEditingController _symbolController;
  late TextEditingController _amountController;
  late TextEditingController _profitController;
  late TextEditingController _stopLossController;

  @override
  void initState() {
    super.initState();
    final provider = context.read<TradingProvider>();
    _symbolController = TextEditingController(text: provider.symbol);
    _amountController =
        TextEditingController(text: provider.orderAmount.toString());
    _profitController =
        TextEditingController(text: provider.profitTargetPercent.toString());
    _stopLossController =
        TextEditingController(text: provider.stopLossPercent.toString());
  }

  @override
  void dispose() {
    _symbolController.dispose();
    _amountController.dispose();
    _profitController.dispose();
    _stopLossController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<TradingProvider>(
      builder: (context, provider, child) {
        final isRunning = provider.isRunning;

        return Padding(
          padding: const EdgeInsets.all(ThemeConstants.spacingMedium),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Symbol and Amount
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _symbolController,
                      decoration: ThemeConstants.inputDecoration(
                        labelText: '심볼',
                        prefixIcon: Icons.currency_bitcoin,
                      ),
                      enabled: !isRunning,
                      onChanged: (value) => provider.setSymbol(value),
                    ),
                  ),
                  const SizedBox(width: ThemeConstants.spacingSmall),
                  Expanded(
                    child: TextField(
                      controller: _amountController,
                      decoration: ThemeConstants.inputDecoration(
                        labelText: '수량',
                        prefixIcon: Icons.pie_chart,
                      ),
                      keyboardType: TextInputType.number,
                      enabled: !isRunning,
                      onChanged: (value) {
                        final amount = double.tryParse(value);
                        if (amount != null) {
                          provider.setOrderAmount(amount);
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: ThemeConstants.spacingSmall),

              // Profit Target and Stop Loss
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _profitController,
                      decoration: ThemeConstants.inputDecoration(
                        labelText: '익절 (%)',
                        prefixIcon: Icons.trending_up,
                      ),
                      keyboardType: TextInputType.number,
                      enabled: !isRunning,
                      onChanged: (value) {
                        final profit = double.tryParse(value);
                        if (profit != null) {
                          provider.setProfitTargetPercent(profit);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: ThemeConstants.spacingSmall),
                  Expanded(
                    child: TextField(
                      controller: _stopLossController,
                      decoration: ThemeConstants.inputDecoration(
                        labelText: '손절 (%)',
                        prefixIcon: Icons.trending_down,
                      ),
                      keyboardType: TextInputType.number,
                      enabled: !isRunning,
                      onChanged: (value) {
                        final stopLoss = double.tryParse(value);
                        if (stopLoss != null) {
                          provider.setStopLossPercent(stopLoss);
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: ThemeConstants.spacingMedium),

              // Start/Stop Button
              isRunning
                  ? DangerButton(
                      text: '봇 중지',
                      onPressed: () => _stopBot(provider),
                    )
                  : SuccessButton(
                      text: '봇 시작',
                      onPressed: () => _startBot(provider),
                    ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _startBot(TradingProvider provider) async {
    final result = await provider.startBot();

    if (!mounted) return;

    result.when(
      success: (data) {
        // Success handled by provider
      },
      failure: (message, exception) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: ThemeConstants.errorColor,
          ),
        );
      },
    );
  }

  Future<void> _stopBot(TradingProvider provider) async {
    final result = await provider.stopBot();

    if (!mounted) return;

    result.when(
      success: (data) {
        // Success handled by provider
      },
      failure: (message, exception) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: ThemeConstants.errorColor,
          ),
        );
      },
    );
  }
}
