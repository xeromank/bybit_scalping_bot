import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:bybit_scalping_bot/providers/bybit_trading_provider.dart';

/// Balance Card Widget
///
/// Shows:
/// - Total Equity (USDT)
/// - Available Balance
/// - Position Margin
/// - Unrealized PnL
/// - All coin balances
class BalanceCard extends StatelessWidget {
  const BalanceCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<BybitTradingProvider>(
      builder: (context, provider, child) {
        if (provider.isLoadingBalance && provider.walletBalance == null) {
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
                      '잔고 로딩 중...',
                      style: TextStyle(color: Colors.grey[400]),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final balance = provider.walletBalance;
        if (balance == null) {
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
                      '잔고 정보를 불러올 수 없습니다',
                      style: TextStyle(color: Colors.grey[400]),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final usdtBalance = balance.usdtBalance;
        final totalEquity = double.tryParse(balance.totalEquity) ?? 0.0;
        final availableBalance = usdtBalance?.availableBalance ?? 0.0;
        final positionIM = usdtBalance?.totalPositionIMAsDouble ?? 0.0;
        final unrealisedPnl = usdtBalance?.unrealisedPnlAsDouble ?? 0.0;

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
                      Icons.account_balance_wallet,
                      color: Colors.amber,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      '자산 현황',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    // 실시간 업데이트 인디케이터
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.green.withOpacity(0.5), width: 1),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: Colors.green,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Text(
                            'LIVE',
                            style: TextStyle(
                              color: Colors.green,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: provider.isLoadingBalance
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.blue,
                              ),
                            )
                          : const Icon(Icons.refresh, color: Colors.blue, size: 20),
                      onPressed: provider.isLoadingBalance ? null : () => provider.fetchBalance(),
                      tooltip: '수동 새로고침',
                    ),
                  ],
                ),
                const Divider(color: Colors.grey),
                const SizedBox(height: 12),

                // Total Equity (큰 글씨로 표시)
                Text(
                  '총 자산',
                  style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text(
                      '\$',
                      style: TextStyle(
                        color: Colors.amber,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      totalEquity.toStringAsFixed(2),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'USDT',
                      style: TextStyle(
                        color: Colors.grey,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // 상세 정보 그리드
                Row(
                  children: [
                    Expanded(
                      child: _buildInfoBox(
                        '사용 가능',
                        '\$${availableBalance.toStringAsFixed(2)}',
                        Colors.green,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildInfoBox(
                        '포지션 증거금',
                        '\$${positionIM.toStringAsFixed(2)}',
                        Colors.orange,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // 미실현 손익 (ROE)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: unrealisedPnl >= 0
                        ? Colors.green.withOpacity(0.1)
                        : Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: unrealisedPnl >= 0 ? Colors.green : Colors.red,
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '미실현 손익 (ROE)',
                            style: TextStyle(
                              color: Colors.grey[300],
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Return on Equity',
                            style: TextStyle(
                              color: Colors.grey[500],
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${unrealisedPnl >= 0 ? '+' : ''}\$${unrealisedPnl.toStringAsFixed(2)}',
                            style: TextStyle(
                              color: unrealisedPnl >= 0 ? Colors.green : Colors.red,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _calculateROE(positionIM, unrealisedPnl),
                            style: TextStyle(
                              color: unrealisedPnl >= 0 ? Colors.green : Colors.red,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // 마지막 업데이트 시간 및 주기
                if (provider.lastBalanceUpdate != null) ...[
                  const SizedBox(height: 12),
                  Center(
                    child: Column(
                      children: [
                        Text(
                          '마지막 업데이트: ${_formatTime(provider.lastBalanceUpdate!)}',
                          style: TextStyle(
                            color: Colors.grey[500],
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          positionIM > 0
                              ? '⚡ 실시간 업데이트 (2초마다)'
                              : '🕐 자동 업데이트 (10초마다)',
                          style: TextStyle(
                            color: positionIM > 0 ? Colors.green[300] : Colors.grey[600],
                            fontSize: 10,
                          ),
                        ),
                      ],
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

  Widget _buildInfoBox(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.grey[400],
              fontSize: 11,
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
      ),
    );
  }

  String _calculateROE(double positionIM, double unrealisedPnl) {
    if (positionIM == 0) return '0.00%';
    final roe = (unrealisedPnl / positionIM) * 100;
    return '${roe >= 0 ? '+' : ''}${roe.toStringAsFixed(2)}%';
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inSeconds < 60) {
      return '방금 전';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes}분 전';
    } else {
      return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    }
  }
}
