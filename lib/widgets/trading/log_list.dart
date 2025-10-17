import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:bybit_scalping_bot/providers/trading_provider.dart';
import 'package:bybit_scalping_bot/models/trade_log.dart';
import 'package:bybit_scalping_bot/constants/theme_constants.dart';

/// Widget displaying trading logs
///
/// Responsibility: Display a list of trading log entries
///
/// This widget observes the TradingProvider and displays log entries
/// with appropriate styling based on log level.
class LogList extends StatelessWidget {
  const LogList({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<TradingProvider>(
      builder: (context, provider, child) {
        final logs = provider.logs;

        if (logs.isEmpty) {
          return const Center(
            child: Text(
              '로그가 없습니다',
              style: TextStyle(color: ThemeConstants.textSecondaryColor),
            ),
          );
        }

        return ListView.builder(
          itemCount: logs.length,
          itemBuilder: (context, index) {
            final log = logs[index];
            return LogListItem(log: log);
          },
        );
      },
    );
  }
}

/// Individual log list item
class LogListItem extends StatelessWidget {
  final TradeLog log;

  const LogListItem({super.key, required this.log});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: ThemeConstants.spacingMedium,
        vertical: ThemeConstants.spacingSmall,
      ),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: ThemeConstants.dividerColor,
            width: 1,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Log level icon
              _buildLogIcon(),
              const SizedBox(width: ThemeConstants.spacingSmall),

              // Timestamp
              Text(
                log.formattedTime,
                style: const TextStyle(
                  fontSize: 12,
                  color: ThemeConstants.textSecondaryColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: ThemeConstants.spacingXSmall),

          // Message
          Text(
            log.message,
            style: TextStyle(
              fontSize: 14,
              color: _getTextColor(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogIcon() {
    IconData icon;
    Color color;

    switch (log.level) {
      case LogLevel.success:
        icon = Icons.check_circle;
        color = ThemeConstants.successColor;
      case LogLevel.error:
        icon = Icons.error;
        color = ThemeConstants.errorColor;
      case LogLevel.warning:
        icon = Icons.warning;
        color = ThemeConstants.warningColor;
      case LogLevel.info:
        icon = Icons.info;
        color = ThemeConstants.infoColor;
    }

    return Icon(
      icon,
      size: ThemeConstants.iconSizeSmall,
      color: color,
    );
  }

  Color _getTextColor() {
    switch (log.level) {
      case LogLevel.error:
        return ThemeConstants.errorColor;
      case LogLevel.warning:
        return ThemeConstants.warningColor;
      case LogLevel.success:
        return ThemeConstants.successColor;
      case LogLevel.info:
        return ThemeConstants.textPrimaryColor;
    }
  }
}
