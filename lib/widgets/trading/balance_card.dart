import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:bybit_scalping_bot/providers/balance_provider.dart';
import 'package:bybit_scalping_bot/constants/theme_constants.dart';

/// Widget displaying wallet balance information
///
/// Responsibility: Display wallet balance in a card format
///
/// This widget observes the BalanceProvider and displays the current
/// USDT balance with refresh capability.
class BalanceCard extends StatelessWidget {
  const BalanceCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<BalanceProvider>(
      builder: (context, provider, child) {
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(ThemeConstants.spacingMedium),
          color: ThemeConstants.primaryColor.withOpacity(0.1),
          child: Column(
            children: [
              const Text(
                'USDT 잔고',
                style: TextStyle(
                  fontSize: 14,
                  color: ThemeConstants.textSecondaryColor,
                ),
              ),
              const SizedBox(height: ThemeConstants.spacingXSmall),
              provider.isLoading
                  ? const CircularProgressIndicator()
                  : Text(
                      '\$${provider.usdtBalanceFormatted}',
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: ThemeConstants.textPrimaryColor,
                      ),
                    ),
              if (provider.errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(
                    top: ThemeConstants.spacingSmall,
                  ),
                  child: Text(
                    provider.errorMessage!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: ThemeConstants.errorColor,
                    ),
                  ),
                ),
              if (provider.lastUpdated != null)
                Padding(
                  padding: const EdgeInsets.only(
                    top: ThemeConstants.spacingSmall,
                  ),
                  child: Text(
                    '마지막 업데이트: ${_formatTime(provider.lastUpdated!)}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: ThemeConstants.textSecondaryColor,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}:'
        '${time.second.toString().padLeft(2, '0')}';
  }
}
