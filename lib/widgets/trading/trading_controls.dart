import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

        // Update text fields when provider values change
        if (_profitController.text != provider.profitTargetPercent.toString()) {
          _profitController.text = provider.profitTargetPercent.toString();
        }
        if (_stopLossController.text != provider.stopLossPercent.toString()) {
          _stopLossController.text = provider.stopLossPercent.toString();
        }

        return Padding(
          padding: const EdgeInsets.all(ThemeConstants.spacingMedium),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Row 1: Symbol with price
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        DropdownButtonFormField<String>(
                          value: provider.symbol,
                          decoration: ThemeConstants.inputDecoration(
                            labelText: '심볼',
                            prefixIcon: Icons.currency_bitcoin,
                          ),
                          items: const [
                            DropdownMenuItem(value: 'BTCUSDT', child: Text('BTC/USDT')),
                            DropdownMenuItem(value: 'ETHUSDT', child: Text('ETH/USDT')),
                            DropdownMenuItem(value: 'SOLUSDT', child: Text('SOL/USDT')),
                            DropdownMenuItem(value: 'BNBUSDT', child: Text('BNB/USDT')),
                            DropdownMenuItem(value: 'XRPUSDT', child: Text('XRP/USDT')),
                            DropdownMenuItem(value: 'DOGEUSDT', child: Text('DOGE/USDT')),
                            DropdownMenuItem(value: 'ADAUSDT', child: Text('ADA/USDT')),
                          ],
                          onChanged: isRunning
                              ? null
                              : (value) {
                                  if (value != null) {
                                    provider.setSymbol(value);
                                  }
                                },
                        ),
                        if (provider.currentPrice != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            '현재가: \$${provider.currentPrice!.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: ThemeConstants.primaryColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: ThemeConstants.spacingSmall),

              // Row 2: Amount (USDT) and Leverage
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _amountController,
                      decoration: ThemeConstants.inputDecoration(
                        labelText: '투입 자금 (USDT)',
                        prefixIcon: Icons.attach_money,
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
                  const SizedBox(width: ThemeConstants.spacingSmall),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: provider.leverage,
                      decoration: ThemeConstants.inputDecoration(
                        labelText: '레버리지',
                        prefixIcon: Icons.trending_up,
                      ),
                      items: const [
                        DropdownMenuItem(value: '2', child: Text('2x')),
                        DropdownMenuItem(value: '3', child: Text('3x')),
                        DropdownMenuItem(value: '5', child: Text('5x')),
                        DropdownMenuItem(value: '10', child: Text('10x')),
                        DropdownMenuItem(value: '15', child: Text('15x')),
                      ],
                      onChanged: isRunning
                          ? null
                          : (value) {
                              if (value != null) {
                                provider.setLeverage(value);
                              }
                            },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: ThemeConstants.spacingSmall),

              // Row 3: Profit Target and Stop Loss
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _profitController,
                      decoration: ThemeConstants.inputDecoration(
                        labelText: '익절 ROE (%)',
                        prefixIcon: Icons.trending_up,
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,1}')),
                      ],
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
                        labelText: '손절 ROE (%)',
                        prefixIcon: Icons.trending_down,
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,1}')),
                      ],
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
              const SizedBox(height: ThemeConstants.spacingSmall),

              // Technical Indicators Display
              if (provider.technicalAnalysis != null) ...[
                Container(
                  padding: const EdgeInsets.all(ThemeConstants.spacingSmall),
                  decoration: BoxDecoration(
                    color: ThemeConstants.primaryColor.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(ThemeConstants.borderRadiusSmall),
                    border: Border.all(
                      color: ThemeConstants.primaryColor.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '기술적 지표',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: ThemeConstants.textPrimaryColor,
                        ),
                      ),
                      const SizedBox(height: 6),
                      // First row: RSI indicators
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildIndicator(
                            'RSI(6)',
                            provider.technicalAnalysis!.rsi6.toStringAsFixed(1),
                            _getRSIColor(provider.technicalAnalysis!.rsi6),
                          ),
                          _buildIndicator(
                            'RSI(12)',
                            provider.technicalAnalysis!.rsi12.toStringAsFixed(1),
                            _getRSIColor(provider.technicalAnalysis!.rsi12),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Second row: Volume MA and EMA indicators
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildIndicator(
                            'Vol MA5',
                            '${(provider.technicalAnalysis!.volumeMA5 / 1000).toStringAsFixed(1)}k',
                            ThemeConstants.textPrimaryColor,
                          ),
                          _buildIndicator(
                            'Vol MA10',
                            '${(provider.technicalAnalysis!.volumeMA10 / 1000).toStringAsFixed(1)}k',
                            ThemeConstants.textPrimaryColor,
                          ),
                          _buildIndicator(
                            'EMA(9)',
                            '\$${provider.technicalAnalysis!.ema9.toStringAsFixed(1)}',
                            ThemeConstants.textPrimaryColor,
                          ),
                          _buildIndicator(
                            'EMA(21)',
                            '\$${provider.technicalAnalysis!.ema21.toStringAsFixed(1)}',
                            ThemeConstants.textPrimaryColor,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: ThemeConstants.spacingSmall),
              ],

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

  Widget _buildIndicator(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            color: ThemeConstants.textSecondaryColor,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Color _getRSIColor(double rsi) {
    if (rsi < 30) {
      return Colors.green.shade700; // Oversold - potential buy
    } else if (rsi > 70) {
      return Colors.red.shade700; // Overbought - potential sell
    } else {
      return ThemeConstants.textPrimaryColor; // Neutral
    }
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
