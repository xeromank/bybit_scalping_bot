import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:bybit_scalping_bot/providers/bybit_trading_provider.dart';
import 'package:intl/intl.dart';

/// Trade logs card widget for Bybit trading screen
///
/// Displays recent trade logs from SQLite database
class TradeLogsCard extends StatelessWidget {
  const TradeLogsCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<BybitTradingProvider>(
      builder: (context, provider, child) {
        final logs = provider.tradeLogs;

        return Card(
          color: const Color(0xFF2D2D2D),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.history, color: Colors.blue, size: 20),
                        SizedBox(width: 8),
                        Text(
                          '거래 로그',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    if (logs.isNotEmpty)
                      TextButton(
                        onPressed: () async {
                          final shouldClear = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              backgroundColor: const Color(0xFF2D2D2D),
                              title: const Text(
                                '로그 삭제',
                                style: TextStyle(color: Colors.white),
                              ),
                              content: const Text(
                                '모든 로그를 삭제하시겠습니까?',
                                style: TextStyle(color: Colors.white70),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context, false),
                                  child: const Text('취소'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  child: const Text(
                                    '삭제',
                                    style: TextStyle(color: Colors.red),
                                  ),
                                ),
                              ],
                            ),
                          );

                          if (shouldClear == true) {
                            provider.clearTradeLogs();
                          }
                        },
                        child: const Text(
                          '전체 삭제',
                          style: TextStyle(
                            color: Colors.red,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),

                // Logs list
                if (logs.isEmpty)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32.0),
                      child: Text(
                        '아직 로그가 없습니다',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  )
                else
                  SizedBox(
                    height: 300,
                    child: ListView.separated(
                      itemCount: logs.length,
                      separatorBuilder: (context, index) => const Divider(
                        color: Colors.grey,
                        height: 1,
                      ),
                      itemBuilder: (context, index) {
                        final log = logs[index];
                        return _buildLogItem(log);
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildLogItem(Map<String, dynamic> log) {
    final type = log['type'] as String;
    final message = log['message'] as String;
    final timestamp = log['timestamp'] as int;

    Color color;
    IconData icon;

    switch (type) {
      case 'SIGNAL':
        color = Colors.amber;
        icon = Icons.lightbulb;
      case 'INFO':
        color = Colors.blue;
        icon = Icons.info;
      case 'SUCCESS':
        color = Colors.green;
        icon = Icons.check_circle;
      case 'ERROR':
        color = Colors.red;
        icon = Icons.error;
      default:
        color = Colors.grey;
        icon = Icons.circle;
    }

    final dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final timeStr = DateFormat('HH:mm:ss').format(dateTime);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),

          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message,
                  style: TextStyle(
                    color: Colors.grey[300],
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  timeStr,
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 11,
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
