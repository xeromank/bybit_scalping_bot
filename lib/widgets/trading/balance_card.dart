import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:bybit_scalping_bot/providers/balance_provider.dart';
import 'package:bybit_scalping_bot/providers/trading_provider.dart';
import 'package:bybit_scalping_bot/widgets/trading/position_card.dart';
import 'package:bybit_scalping_bot/constants/theme_constants.dart';

/// Widget displaying wallet balance and position information with tabs
///
/// Responsibility: Display wallet balance and positions in a tabbed card format
///
/// This widget observes the BalanceProvider and displays balance and positions
/// with tab navigation.
class BalanceCard extends StatefulWidget {
  const BalanceCard({super.key});

  @override
  State<BalanceCard> createState() => _BalanceCardState();
}

class _BalanceCardState extends State<BalanceCard> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<BalanceProvider>(
      builder: (context, provider, child) {
        return Column(
          children: [
            // Tab Bar with Refresh Button
            Container(
              color: ThemeConstants.primaryColor.withValues(alpha: 0.1),
              child: Stack(
                children: [
                  TabBar(
                    controller: _tabController,
                    labelColor: ThemeConstants.primaryColor,
                    unselectedLabelColor: ThemeConstants.textSecondaryColor,
                    indicatorColor: ThemeConstants.primaryColor,
                    indicatorWeight: 3,
                    tabs: [
                  Tab(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.account_balance_wallet, size: 18),
                        const SizedBox(width: 8),
                        const Text('잔고'),
                      ],
                    ),
                  ),
                  Tab(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.bar_chart, size: 18),
                        const SizedBox(width: 8),
                        const Text('포지션'),
                        if (provider.hasOpenPositions)
                          Container(
                            margin: const EdgeInsets.only(left: 6),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.red,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${provider.positions.length}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              // Refresh button overlaid on the right
              Positioned(
                right: 8,
                top: 8,
                child: IconButton(
                  icon: provider.isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: ThemeConstants.primaryColor,
                          ),
                        )
                      : const Icon(Icons.refresh, size: 20),
                  onPressed: provider.isLoading ? null : () => provider.refresh(),
                  color: ThemeConstants.primaryColor,
                  tooltip: '새로고침',
                ),
              ),
            ],
          ),
        ),

            // Tab Views
            Container(
              height: 280,
              color: ThemeConstants.primaryColor.withValues(alpha: 0.1),
              child: TabBarView(
                controller: _tabController,
                children: [
                  // Balance Tab
                  _buildBalanceTab(provider),

                  // Position Tab
                  _buildPositionTab(provider),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildBalanceTab(BalanceProvider provider) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(ThemeConstants.spacingMedium),
      child: Column(
        children: [
          // Main balance: USDT Available Balance
          provider.isLoading
              ? const CircularProgressIndicator()
              : Column(
                      children: [
                        _buildBalanceRow(
                          '사용 가능 잔고',
                          provider.usdtAvailableBalanceFormatted,
                          isMain: true,
                        ),
                        const Divider(height: 20),
                        _buildBalanceRow('현재 가치 (Equity)', provider.usdtEquityFormatted),
                        const SizedBox(height: 8),
                        _buildBalanceRow('지갑 잔고', provider.usdtWalletBalanceFormatted),
                        const SizedBox(height: 8),
                        _buildBalanceRow('포지션 투여금', provider.usdtPositionIMFormatted),
                        const SizedBox(height: 8),
                        _buildBalanceRow(
                          '미실현 손익',
                          provider.usdtUnrealisedPnlFormatted,
                          isPnL: true,
                        ),
                        const SizedBox(height: 8),
                        _buildBalanceRow(
                          '누적 실현 손익',
                          provider.usdtCumRealisedPnlFormatted,
                          isPnL: true,
                        ),
                      ],
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
  }

  Widget _buildPositionTab(BalanceProvider provider) {
    if (provider.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return PositionCard(
      positions: provider.positions,
      onClosePosition: (symbol) => _handleClosePosition(context, symbol),
    );
  }

  /// Handle closing a position
  Future<void> _handleClosePosition(BuildContext context, String symbol) async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('포지션 닫기'),
        content: Text(
          '$symbol 포지션을 시장가로 청산합니다.\n\n정말 진행하시겠습니까?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Colors.orange.shade700,
            ),
            child: const Text('청산'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Get TradingProvider and close position
    final tradingProvider = context.read<TradingProvider?>();
    if (tradingProvider == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('TradingProvider를 찾을 수 없습니다'),
          backgroundColor: ThemeConstants.errorColor,
        ),
      );
      return;
    }

    final result = await tradingProvider.closePositionBySymbol(symbol);

    if (!mounted) return;

    result.when(
      success: (data) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$symbol 포지션이 청산되었습니다'),
            backgroundColor: ThemeConstants.successColor,
          ),
        );
      },
      failure: (message, exception) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: ThemeConstants.errorColor,
          ),
        );
      },
    );
  }

  Widget _buildBalanceRow(String label, String value, {bool isMain = false, bool isPnL = false}) {
    // Parse value for PnL color determination
    final numValue = double.tryParse(value) ?? 0.0;
    Color valueColor;

    if (isPnL) {
      // PnL colors: green for positive, red for negative
      if (numValue > 0) {
        valueColor = Colors.green.shade700;
      } else if (numValue < 0) {
        valueColor = Colors.red.shade700;
      } else {
        valueColor = ThemeConstants.textPrimaryColor;
      }
    } else if (isMain) {
      valueColor = Colors.green.shade700;
    } else {
      valueColor = ThemeConstants.textPrimaryColor;
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: isMain ? 16 : 14,
            fontWeight: isMain ? FontWeight.bold : FontWeight.normal,
            color: isMain ? ThemeConstants.textPrimaryColor : Colors.black87,
          ),
        ),
        Text(
          isPnL ? (numValue >= 0 ? '+\$$value' : '-\$${value.replaceAll('-', '')}') : '\$$value',
          style: TextStyle(
            fontSize: isMain ? 24 : 14,
            fontWeight: isMain ? FontWeight.bold : FontWeight.normal,
            color: valueColor,
          ),
        ),
      ],
    );
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}:'
        '${time.second.toString().padLeft(2, '0')}';
  }
}
