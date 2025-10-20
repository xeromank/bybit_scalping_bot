import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:bybit_scalping_bot/providers/bybit_trading_provider.dart';

/// Market Condition Display Card
///
/// Shows:
/// - Current market condition with emoji
/// - Analysis confidence level
/// - Analysis reasoning
/// - Last analysis timestamp
class MarketConditionCard extends StatelessWidget {
  const MarketConditionCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<BybitTradingProvider>(
      builder: (context, provider, child) {
        final lastAnalysis = provider.lastAnalysis;
        final timeSinceAnalysis = lastAnalysis != null
            ? DateTime.now().difference(lastAnalysis)
            : null;

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
                      Icons.analytics,
                      color: Colors.blue,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      '시장 상황',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    if (timeSinceAnalysis != null)
                      Text(
                        '${timeSinceAnalysis.inMinutes}분 전',
                        style: TextStyle(
                          color: Colors.grey[400],
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
                const Divider(color: Colors.grey),
                const SizedBox(height: 12),

                // Market Condition Display
                Row(
                  children: [
                    Text(
                      provider.conditionEmoji,
                      style: const TextStyle(fontSize: 40),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            provider.conditionDescription,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          _buildConfidenceBar(provider.analysisConfidence),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Analysis Reasoning
                if (provider.analysisReasoning.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1E1E),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      provider.analysisReasoning,
                      style: TextStyle(
                        color: Colors.grey[300],
                        fontSize: 13,
                        height: 1.4,
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

  Widget _buildConfidenceBar(double confidence) {
    final percentage = (confidence * 100).toInt();
    Color barColor;

    if (percentage >= 80) {
      barColor = Colors.green;
    } else if (percentage >= 60) {
      barColor = Colors.orange;
    } else {
      barColor = Colors.red;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '신뢰도: $percentage%',
          style: TextStyle(
            color: Colors.grey[400],
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: confidence,
            backgroundColor: Colors.grey[800],
            valueColor: AlwaysStoppedAnimation<Color>(barColor),
            minHeight: 6,
          ),
        ),
      ],
    );
  }
}
