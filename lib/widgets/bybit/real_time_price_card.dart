import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:bybit_scalping_bot/providers/bybit_trading_provider.dart';

/// Real-Time Price Card
///
/// Shows:
/// - Current price of selected symbol
/// - WebSocket connection status
/// - Last update timestamp
class RealTimePriceCard extends StatelessWidget {
  const RealTimePriceCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<BybitTradingProvider>(
      builder: (context, provider, child) {
        final currentPrice = provider.currentPrice;
        final lastUpdate = provider.lastPriceUpdate;
        final isConnected = provider.isWebSocketConnected;

        final timeSinceUpdate = lastUpdate != null
            ? DateTime.now().difference(lastUpdate)
            : null;

        return Card(
          color: const Color(0xFF2D2D2D),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header with Connection Status
                Row(
                  children: [
                    const Icon(
                      Icons.show_chart,
                      color: Colors.cyan,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      '실시간 가격',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    _buildConnectionStatus(isConnected),
                  ],
                ),
                const Divider(color: Colors.grey),
                const SizedBox(height: 12),

                // Symbol
                Text(
                  provider.selectedSymbol,
                  style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),

                // Price Display
                if (currentPrice != null) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text(
                        '\$',
                        style: TextStyle(
                          color: Colors.cyan,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        currentPrice.toStringAsFixed(2),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (timeSinceUpdate != null)
                    Text(
                      '${timeSinceUpdate.inSeconds}초 전 업데이트',
                      style: TextStyle(
                        color: Colors.grey[500],
                        fontSize: 11,
                      ),
                    ),
                ] else ...[
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                      child: Column(
                        children: [
                          const CircularProgressIndicator(
                            color: Colors.cyan,
                            strokeWidth: 2,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '가격 로딩 중...',
                            style: TextStyle(
                              color: Colors.grey[400],
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
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

  Widget _buildConnectionStatus(bool isConnected) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isConnected
            ? Colors.green.withOpacity(0.2)
            : Colors.red.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: isConnected ? Colors.green : Colors.red,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            isConnected ? 'LIVE' : 'OFFLINE',
            style: TextStyle(
              color: isConnected ? Colors.green : Colors.red,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
