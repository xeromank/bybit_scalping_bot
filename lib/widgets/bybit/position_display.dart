import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:bybit_scalping_bot/providers/bybit_trading_provider.dart';

/// Position Display Widget
///
/// Shows current open position details:
/// - Symbol and side (Long/Short)
/// - Entry price and current price
/// - Quantity and leverage
/// - Unrealized PnL and ROE
/// - TP/SL prices
class PositionDisplay extends StatelessWidget {
  const PositionDisplay({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<BybitTradingProvider>(
      builder: (context, provider, child) {
        final position = provider.currentPosition;

        if (position == null) {
          return const SizedBox.shrink();
        }

        final isLong = position.side.toLowerCase() == 'buy';
        final sideColor = isLong ? Colors.green : Colors.red;

        // Position WebSocket에서 이미 최신 markPrice를 받으므로 그대로 사용
        final pnlPercent = position.pnlPercent; // Position 모델의 정확한 ROE 계산 사용

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
                      isLong ? Icons.arrow_upward : Icons.arrow_downward,
                      color: sideColor,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '현재 포지션',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: sideColor.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: sideColor, width: 1),
                      ),
                      child: Text(
                        isLong ? 'LONG' : 'SHORT',
                        style: TextStyle(
                          color: sideColor,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const Divider(color: Colors.grey),
                const SizedBox(height: 12),

                // Symbol
                Text(
                  position.symbol,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),

                // Price Info
                Row(
                  children: [
                    Expanded(
                      child: _buildInfoItem(
                        '진입 가격',
                        '\$${position.avgPriceAsDouble.toStringAsFixed(2)}',
                        Colors.grey,
                      ),
                    ),
                    Expanded(
                      child: _buildInfoItem(
                        '현재 가격',
                        '\$${position.markPriceAsDouble.toStringAsFixed(2)}',
                        Colors.blue,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Position Details
                Row(
                  children: [
                    Expanded(
                      child: _buildInfoItem(
                        '수량',
                        position.sizeAsDouble.toStringAsFixed(4),
                        Colors.grey,
                      ),
                    ),
                    Expanded(
                      child: _buildInfoItem(
                        '레버리지',
                        '${position.leverageAsDouble.toStringAsFixed(0)}x',
                        Colors.orange,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // PnL Display
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: pnlPercent >= 0
                        ? Colors.green.withOpacity(0.1)
                        : Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: pnlPercent >= 0 ? Colors.green : Colors.red,
                      width: 2,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '미실현 손익',
                            style: TextStyle(
                              color: Colors.grey[400],
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${pnlPercent >= 0 ? '+' : ''}${pnlPercent.toStringAsFixed(2)}%',
                            style: TextStyle(
                              color: pnlPercent >= 0 ? Colors.green : Colors.red,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      Icon(
                        pnlPercent >= 0 ? Icons.trending_up : Icons.trending_down,
                        color: pnlPercent >= 0 ? Colors.green : Colors.red,
                        size: 32,
                      ),
                    ],
                  ),
                ),

                // TP/SL Info
                if (position.takeProfit != null || position.stopLoss != null) ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      if (position.takeProfit != null)
                        Expanded(
                          child: _buildInfoItem(
                            'TP',
                            '\$${double.parse(position.takeProfit!).toStringAsFixed(2)}',
                            Colors.green,
                          ),
                        ),
                      if (position.takeProfit != null && position.stopLoss != null)
                        const SizedBox(width: 12),
                      if (position.stopLoss != null)
                        Expanded(
                          child: _buildInfoItem(
                            'SL',
                            '\$${double.parse(position.stopLoss!).toStringAsFixed(2)}',
                            Colors.red,
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildInfoItem(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.grey[400],
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

}
