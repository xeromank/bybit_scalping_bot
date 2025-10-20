import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:bybit_scalping_bot/providers/bybit_trading_provider.dart';
import 'package:bybit_scalping_bot/models/position.dart';

/// Positions List Widget
///
/// Shows all open positions in a list format
class PositionsList extends StatelessWidget {
  const PositionsList({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<BybitTradingProvider>(
      builder: (context, provider, child) {
        if (provider.allPositions.isEmpty) {
          return const SizedBox.shrink();
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
                      Icons.list_alt,
                      color: Colors.cyan,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      '보유 포지션',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.cyan.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${provider.allPositions.length}개',
                        style: const TextStyle(
                          color: Colors.cyan,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const Divider(color: Colors.grey),
                const SizedBox(height: 8),

                // Positions List
                ...provider.allPositions.map((position) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12.0),
                    child: _buildPositionTile(position),
                  );
                }).toList(),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPositionTile(Position position) {
    final isLong = position.side.toLowerCase() == 'buy';
    final sideColor = isLong ? Colors.green : Colors.red;

    // Position WebSocket에서 이미 최신 markPrice를 받으므로 그대로 사용
    final pnlPercent = position.pnlPercent; // Position 모델의 정확한 ROE 계산 사용
    final unrealisedPnl = position.unrealisedPnlAsDouble;
    final pnlColor = pnlPercent >= 0 ? Colors.green : Colors.red;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: sideColor.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Symbol and Side
          Row(
            children: [
              // Symbol
              Text(
                position.symbol,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 8),

              // Side Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: sideColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: sideColor, width: 1),
                ),
                child: Text(
                  isLong ? 'LONG' : 'SHORT',
                  style: TextStyle(
                    color: sideColor,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Leverage
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${position.leverageAsDouble.toStringAsFixed(0)}x',
                  style: const TextStyle(
                    color: Colors.orange,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),

              const Spacer(),

              // ROE and Unrealized PnL
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // ROE (%)
                  Text(
                    '${pnlPercent >= 0 ? '+' : ''}${pnlPercent.toStringAsFixed(2)}%',
                    style: TextStyle(
                      color: pnlColor,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  // Unrealized PnL (USDT)
                  Text(
                    '${unrealisedPnl >= 0 ? '+' : ''}\$${unrealisedPnl.toStringAsFixed(2)}',
                    style: TextStyle(
                      color: pnlColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Position Details
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildDetailItem(
                '수량',
                position.sizeAsDouble.toStringAsFixed(4),
                Colors.grey,
              ),
              _buildDetailItem(
                '진입가',
                '\$${position.avgPriceAsDouble.toStringAsFixed(2)}',
                Colors.grey,
              ),
              _buildDetailItem(
                '현재가',
                '\$${position.markPriceAsDouble.toStringAsFixed(2)}',
                Colors.blue,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDetailItem(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.grey[500],
            fontSize: 10,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

}
