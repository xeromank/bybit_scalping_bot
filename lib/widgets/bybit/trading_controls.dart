import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:bybit_scalping_bot/providers/bybit_trading_provider.dart';

/// Trading Controls Widget
///
/// Provides:
/// - Investment amount input
/// - Leverage selector
/// - Start/Stop bot button
class TradingControls extends StatefulWidget {
  const TradingControls({super.key});

  @override
  State<TradingControls> createState() => _TradingControlsState();
}

class _TradingControlsState extends State<TradingControls> {
  final TextEditingController _amountController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final provider = context.read<BybitTradingProvider>();
    _amountController.text = provider.investmentAmount.toString();
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<BybitTradingProvider>(
      builder: (context, provider, child) {
        return Card(
          color: const Color(0xFF2D2D2D),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Icon(
                      provider.isRunning ? Icons.play_circle : Icons.settings,
                      color: provider.isRunning ? Colors.green : Colors.grey,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      provider.isRunning ? '봇 실행 중' : '거래 설정',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const Divider(color: Colors.grey),
                const SizedBox(height: 16),

                // Investment Amount
                Text(
                  '투자 금액 (USDT)',
                  style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _amountController,
                  enabled: !provider.isRunning,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: '최소 10 USDT',
                    hintStyle: TextStyle(color: Colors.grey[600]),
                    filled: true,
                    fillColor: const Color(0xFF1E1E1E),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    prefixIcon: const Icon(Icons.attach_money, color: Colors.green),
                    suffixText: 'USDT',
                    suffixStyle: TextStyle(color: Colors.grey[400]),
                  ),
                  onChanged: (value) {
                    final amount = double.tryParse(value);
                    if (amount != null && amount >= 10.0) {
                      provider.setInvestmentAmount(amount);
                    }
                  },
                ),
                const SizedBox(height: 16),

                // Leverage Selector
                Text(
                  '레버리지',
                  style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: ['5', '10', '15', '20', '25'].map((leverage) {
                    final isSelected = provider.leverage == leverage;
                    final isRecommended =
                        provider.currentStrategy?.recommendedLeverage.toString() == leverage;

                    return ChoiceChip(
                      label: Text(
                        '${leverage}x${isRecommended ? ' ⭐' : ''}',
                        style: TextStyle(
                          color: isSelected ? Colors.white : Colors.grey[400],
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      selected: isSelected,
                      onSelected: provider.isRunning
                          ? null
                          : (selected) {
                              if (selected) {
                                provider.setLeverage(leverage);
                              }
                            },
                      selectedColor: Colors.blue,
                      backgroundColor: const Color(0xFF1E1E1E),
                      disabledColor: Colors.grey[800],
                    );
                  }).toList(),
                ),
                const SizedBox(height: 24),

                // Start/Stop Button
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: () async {
                      if (provider.isRunning) {
                        await provider.stopBot();
                      } else {
                        await provider.startBot();
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: provider.isRunning ? Colors.red : Colors.green,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          provider.isRunning ? Icons.stop : Icons.play_arrow,
                          color: Colors.white,
                          size: 24,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          provider.isRunning ? '봇 중지' : '봇 시작',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Status Info
                if (provider.isRunning) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green, width: 1),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline, color: Colors.green, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '자동 거래가 실행 중입니다. 3초마다 신호를 확인합니다.',
                            style: TextStyle(
                              color: Colors.grey[300],
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
