import 'package:flutter/material.dart';
import 'package:bybit_scalping_bot/models/position.dart';
import 'package:bybit_scalping_bot/constants/theme_constants.dart';

/// Widget displaying position information
///
/// Responsibility: Display current positions
class PositionCard extends StatelessWidget {
  final List<Position> positions;

  const PositionCard({
    super.key,
    required this.positions,
  });

  @override
  Widget build(BuildContext context) {
    if (positions.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(ThemeConstants.spacingLarge),
          child: Text(
            '포지션 없음',
            style: TextStyle(
              fontSize: 16,
              color: ThemeConstants.textSecondaryColor,
            ),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(ThemeConstants.spacingSmall),
      child: Column(
        children: positions.map((position) => _buildPositionItem(position)).toList(),
      ),
    );
  }

  Widget _buildPositionItem(Position position) {
    final pnl = position.pnlPercent;
    final pnlColor = pnl >= 0 ? Colors.green.shade700 : Colors.red.shade700;
    final sideText = position.isLong ? 'Long' : 'Short';
    final sideColor = position.isLong ? Colors.blue.shade700 : Colors.orange.shade700;

    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: ThemeConstants.spacingMedium,
        vertical: ThemeConstants.spacingSmall,
      ),
      padding: const EdgeInsets.all(ThemeConstants.spacingMedium),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(ThemeConstants.borderRadiusMedium),
        border: Border.all(
          color: pnl >= 0 ? Colors.green.shade200 : Colors.red.shade200,
          width: 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Symbol, Leverage, and Side
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(
                    position.symbol,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: ThemeConstants.textPrimaryColor,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: ThemeConstants.primaryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: ThemeConstants.primaryColor,
                        width: 1,
                      ),
                    ),
                    child: Text(
                      '${position.leverage}x',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: ThemeConstants.primaryColor,
                      ),
                    ),
                  ),
                ],
              ),
              Text(
                sideText,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: sideColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: ThemeConstants.spacingSmall),

          // Position Details: Size / Entry Price
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '수량 / 진입가',
                style: TextStyle(
                  fontSize: 14,
                  color: ThemeConstants.textSecondaryColor,
                ),
              ),
              Text(
                '${position.size} / \$${position.avgPrice}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: ThemeConstants.textPrimaryColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Current Price
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '현재가',
                style: TextStyle(
                  fontSize: 14,
                  color: ThemeConstants.textSecondaryColor,
                ),
              ),
              Text(
                '\$${position.markPrice}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: ThemeConstants.textPrimaryColor,
                ),
              ),
            ],
          ),

          const Divider(height: 20),

          // ROE (Return on Equity)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'ROE (손익률)',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: ThemeConstants.textPrimaryColor,
                ),
              ),
              Text(
                '${pnl >= 0 ? '+' : ''}${pnl.toStringAsFixed(2)}%',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: pnlColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Price Change %
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '가격 변동률',
                style: TextStyle(
                  fontSize: 14,
                  color: ThemeConstants.textSecondaryColor,
                ),
              ),
              Text(
                '${position.priceChangePercent >= 0 ? '+' : ''}${position.priceChangePercent.toStringAsFixed(2)}%',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: position.priceChangePercent >= 0 ? Colors.green.shade700 : Colors.red.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '미실현 손익',
                style: TextStyle(
                  fontSize: 14,
                  color: ThemeConstants.textSecondaryColor,
                ),
              ),
              Text(
                '\$${position.realtimeUnrealisedPnl.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: pnlColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            color: ThemeConstants.textSecondaryColor,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: ThemeConstants.textPrimaryColor,
          ),
        ),
      ],
    );
  }
}
