import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:bybit_scalping_bot/providers/bybit_trading_provider.dart';
import 'package:bybit_scalping_bot/models/top_coin.dart';

/// Top 10 Coins Selector
///
/// Displays top 10 coins by 24h trading volume
/// Allows user to select a coin for trading
class TopCoinsSelector extends StatelessWidget {
  const TopCoinsSelector({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<BybitTradingProvider>(
      builder: (context, provider, child) {
        if (provider.isLoadingCoins) {
          return Card(
            color: const Color(0xFF2D2D2D),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Center(
                child: Column(
                  children: [
                    const CircularProgressIndicator(color: Colors.blue),
                    const SizedBox(height: 12),
                    Text(
                      '코인 목록 로딩 중...',
                      style: TextStyle(color: Colors.grey[400]),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        if (provider.topCoins.isEmpty) {
          return Card(
            color: const Color(0xFF2D2D2D),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.warning, color: Colors.orange, size: 40),
                    const SizedBox(height: 12),
                    Text(
                      '코인 목록을 불러올 수 없습니다',
                      style: TextStyle(color: Colors.grey[400]),
                    ),
                  ],
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
                      Icons.trending_up,
                      color: Colors.green,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      '거래량 상위 10개 코인',
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

                // Coins List
                ...provider.topCoins.asMap().entries.map((entry) {
                  final index = entry.key;
                  final coin = entry.value;
                  final isSelected = coin.symbol == provider.selectedSymbol;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: _buildCoinTile(
                      context,
                      coin,
                      index + 1,
                      isSelected,
                      provider.isRunning,
                      () => provider.selectSymbol(coin.symbol),
                    ),
                  );
                }).toList(),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCoinTile(
    BuildContext context,
    TopCoin coin,
    int rank,
    bool isSelected,
    bool isBotRunning,
    VoidCallback onSelect,
  ) {
    return InkWell(
      onTap: isBotRunning ? null : onSelect,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue.withOpacity(0.2) : const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? Colors.blue : Colors.transparent,
            width: 2,
          ),
        ),
        child: Row(
          children: [
            // Rank
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: _getRankColor(rank),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  '$rank',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),

            // Symbol and Trend Emoji
            Expanded(
              flex: 2,
              child: Row(
                children: [
                  Text(
                    coin.symbol,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(coin.trendEmoji, style: const TextStyle(fontSize: 16)),
                ],
              ),
            ),

            // Price
            Expanded(
              flex: 2,
              child: Text(
                coin.formattedPrice,
                style: TextStyle(
                  color: Colors.grey[300],
                  fontSize: 13,
                ),
              ),
            ),

            // 24h Change
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: coin.priceChangePercent24h >= 0
                    ? Colors.green.withOpacity(0.2)
                    : Colors.red.withOpacity(0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                coin.formattedChange24h,
                style: TextStyle(
                  color: coin.priceChangePercent24h >= 0
                      ? Colors.green
                      : Colors.red,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

            // Volume
            Expanded(
              flex: 2,
              child: Text(
                coin.formattedVolume,
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: Colors.grey[400],
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getRankColor(int rank) {
    if (rank == 1) return Colors.amber;
    if (rank == 2) return Colors.grey[400]!;
    if (rank == 3) return Colors.brown;
    return Colors.grey[700]!;
  }
}
