import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:bybit_scalping_bot/providers/bybit_trading_provider.dart';

/// Strategy Information Card
///
/// Shows:
/// - Current strategy description
/// - TP/SL percentages and ROE
/// - Recommended leverage
/// - Trailing stop info
/// - Current signal (if any)
class StrategyInfoCard extends StatelessWidget {
  const StrategyInfoCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<BybitTradingProvider>(
      builder: (context, provider, child) {
        final strategy = provider.currentStrategy;
        final signal = provider.currentSignal;

        if (strategy == null) {
          return Card(
            color: const Color(0xFF2D2D2D),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Center(
                child: Text(
                  '전략 로딩 중...',
                  style: TextStyle(color: Colors.grey[400]),
                ),
              ),
            ),
          );
        }

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
                    const Icon(
                      Icons.psychology,
                      color: Colors.purple,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      '현재 전략',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const Divider(color: Colors.grey),
                const SizedBox(height: 12),

                // Strategy Description
                Text(
                  strategy.description,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 16),

                // Strategy Details Grid
                Row(
                  children: [
                    Expanded(
                      child: _buildInfoBox(
                        '목표 수익',
                        '${(strategy.takeProfitPercent * 100).toStringAsFixed(2)}%',
                        '(ROE: ${strategy.takeProfitROE.toStringAsFixed(1)}%)',
                        Colors.green,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildInfoBox(
                        '손절',
                        '${(strategy.stopLossPercent * 100).toStringAsFixed(2)}%',
                        '(ROE: ${strategy.stopLossROE.toStringAsFixed(1)}%)',
                        Colors.red,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                Row(
                  children: [
                    Expanded(
                      child: _buildInfoBox(
                        '권장 레버리지',
                        '${strategy.recommendedLeverage}x',
                        null,
                        Colors.orange,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildInfoBox(
                        '트레일링 스톱',
                        strategy.useTrailingStop ? '활성' : '비활성',
                        strategy.useTrailingStop
                            ? '(${(strategy.trailingStopTrigger * 100).toStringAsFixed(1)}% 수익 시)'
                            : null,
                        strategy.useTrailingStop ? Colors.blue : Colors.grey,
                      ),
                    ),
                  ],
                ),

                // Current Signal Display
                if (signal != null && signal.hasSignal) ...[
                  const SizedBox(height: 16),
                  const Divider(color: Colors.grey),
                  const SizedBox(height: 12),
                  _buildSignalDisplay(signal),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildInfoBox(String label, String value, String? subValue, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.grey[400],
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (subValue != null) ...[
            const SizedBox(height: 2),
            Text(
              subValue,
              style: TextStyle(
                color: Colors.grey[500],
                fontSize: 10,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSignalDisplay(signal) {
    final isLong = signal.type.name == 'long';
    final color = isLong ? Colors.green : Colors.red;
    final icon = isLong ? Icons.arrow_upward : Icons.arrow_downward;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color, width: 2),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '${signal.type.name.toUpperCase()} 신호',
                      style: TextStyle(
                        color: color,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '${(signal.confidence * 100).toStringAsFixed(0)}%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  signal.reasoning,
                  style: TextStyle(
                    color: Colors.grey[300],
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
