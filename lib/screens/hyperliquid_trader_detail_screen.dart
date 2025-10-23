import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:bybit_scalping_bot/providers/hyperliquid_provider.dart';
import 'package:bybit_scalping_bot/models/hyperliquid/hyperliquid_trader.dart';
import 'package:bybit_scalping_bot/models/hyperliquid/hyperliquid_account_state.dart';

/// Hyperliquid 트레이더 상세 화면
class HyperliquidTraderDetailScreen extends StatefulWidget {
  final HyperliquidTrader trader;

  const HyperliquidTraderDetailScreen({
    Key? key,
    required this.trader,
  }) : super(key: key);

  @override
  State<HyperliquidTraderDetailScreen> createState() => _HyperliquidTraderDetailScreenState();
}

class _HyperliquidTraderDetailScreenState extends State<HyperliquidTraderDetailScreen> {
  @override
  void initState() {
    super.initState();
    // 화면 진입 시 데이터 갱신
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<HyperliquidProvider>().refreshTraderState(widget.trader.address);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E0E0E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.trader.displayName,
              style: const TextStyle(color: Colors.white, fontSize: 18),
            ),
            if (widget.trader.nickname != null)
              Text(
                widget.trader.shortAddress,
                style: TextStyle(color: Colors.grey[500], fontSize: 12),
              ),
          ],
        ),
        actions: [
          Consumer<HyperliquidProvider>(
            builder: (context, provider, child) {
              return IconButton(
                icon: const Icon(Icons.refresh, color: Colors.blue),
                onPressed: () => provider.refreshTraderState(widget.trader.address),
              );
            },
          ),
        ],
      ),
      body: Consumer<HyperliquidProvider>(
        builder: (context, provider, child) {
          final state = provider.getAccountState(widget.trader.address);

          if (state == null) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.blue),
            );
          }

          return RefreshIndicator(
            onRefresh: () => provider.refreshTraderState(widget.trader.address),
            backgroundColor: const Color(0xFF1E1E1E),
            color: Colors.blue,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // 계정 요약 카드
                _buildAccountSummaryCard(state),

                const SizedBox(height: 16),

                // 포지션 목록
                Text(
                  '보유 포지션 (${state.assetPositions.length})',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),

                ...state.assetPositions.map((assetPos) {
                  return _buildPositionCard(assetPos.position);
                }).toList(),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildAccountSummaryCard(HyperliquidAccountState state) {
    final accountValue = state.marginSummary.accountValueAsDouble;
    final totalPnl = state.totalUnrealizedPnl;
    final totalROE = state.totalROE;
    final marginUsage = state.marginUsagePercent;
    final withdrawable = double.tryParse(state.withdrawable) ?? 0.0;

    return Card(
      color: const Color(0xFF2D2D2D),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.account_balance_wallet, color: Colors.amber, size: 24),
                SizedBox(width: 8),
                Text(
                  '계정 요약',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const Divider(color: Colors.grey),
            const SizedBox(height: 12),

            // 총 자산
            _buildSummaryRow(
              '총 자산',
              '\$${_formatNumber(accountValue)}',
              Colors.amber,
              fontSize: 24,
            ),
            const SizedBox(height: 16),

            // 미실현 손익
            _buildSummaryRow(
              '미실현 손익',
              '${totalPnl >= 0 ? '+' : ''}\$${_formatNumber(totalPnl)}',
              totalPnl >= 0 ? Colors.green : Colors.red,
              fontSize: 20,
            ),
            const SizedBox(height: 12),

            // ROE
            _buildSummaryRow(
              'ROE (수익률)',
              '${totalROE >= 0 ? '+' : ''}${totalROE.toStringAsFixed(2)}%',
              totalROE >= 0 ? Colors.green : Colors.red,
            ),
            const SizedBox(height: 12),

            // 출금 가능
            _buildSummaryRow(
              '출금 가능',
              '\$${_formatNumber(withdrawable)}',
              Colors.blue,
            ),
            const SizedBox(height: 12),

            // 마진 사용률
            _buildSummaryRow(
              '마진 사용률',
              '${marginUsage.toStringAsFixed(2)}%',
              marginUsage > 80 ? Colors.red : (marginUsage > 50 ? Colors.orange : Colors.green),
            ),

            // 마진 사용률 바
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: marginUsage / 100,
                backgroundColor: Colors.grey[800],
                valueColor: AlwaysStoppedAnimation<Color>(
                  marginUsage > 80 ? Colors.red : (marginUsage > 50 ? Colors.orange : Colors.green),
                ),
                minHeight: 8,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPositionCard(Position position) {
    final isLong = position.isLong;
    final sideColor = isLong ? Colors.green : Colors.red;
    final pnlColor = position.unrealizedPnlAsDouble >= 0 ? Colors.green : Colors.red;

    return Card(
      color: const Color(0xFF2D2D2D),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 헤더: 코인 + 롱/숏
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: sideColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: sideColor),
                  ),
                  child: Text(
                    isLong ? 'LONG' : 'SHORT',
                    style: TextStyle(
                      color: sideColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  position.coin,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Text(
                  '${position.leverage.value}x',
                  style: TextStyle(
                    color: Colors.orange[300],
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),

            const Divider(color: Colors.grey),

            // 포지션 크기
            _buildInfoRow('포지션 크기', '${position.sizeAbs.toStringAsFixed(4)} ${position.coin}'),
            const SizedBox(height: 8),

            // 진입가
            _buildInfoRow('진입가', '\$${position.entryPxAsDouble.toStringAsFixed(2)}'),
            const SizedBox(height: 8),

            // 포지션 가치
            _buildInfoRow('포지션 가치', '\$${_formatNumber(position.positionValueAsDouble)}'),
            const SizedBox(height: 8),

            // 청산가
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('청산가', style: TextStyle(color: Colors.grey[400])),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '\$${position.liquidationPxAsDouble.toStringAsFixed(2)}',
                      style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '여유: ${position.liquidationBuffer.toStringAsFixed(1)}%',
                      style: TextStyle(
                        color: position.liquidationBuffer > 20 ? Colors.green : Colors.orange,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),

            const Divider(color: Colors.grey),

            // 미실현 손익
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('미실현 손익', style: TextStyle(color: Colors.grey[400])),
                Text(
                  '${position.unrealizedPnlAsDouble >= 0 ? '+' : ''}\$${_formatNumber(position.unrealizedPnlAsDouble)}',
                  style: TextStyle(
                    color: pnlColor,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // ROE
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('ROE', style: TextStyle(color: Colors.grey[400])),
                Text(
                  '${position.roePercent >= 0 ? '+' : ''}${position.roePercent.toStringAsFixed(2)}%',
                  style: TextStyle(
                    color: pnlColor,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),

            const Divider(color: Colors.grey),

            // 펀딩비
            _buildInfoRow(
              '누적 펀딩비',
              '${position.cumFunding.allTimeAsDouble >= 0 ? '+' : ''}\$${_formatNumber(position.cumFunding.allTimeAsDouble)}',
              valueColor: position.cumFunding.allTimeAsDouble >= 0 ? Colors.green : Colors.red,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value, Color valueColor, {double? fontSize}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(color: Colors.grey[400], fontSize: 14),
        ),
        Text(
          value,
          style: TextStyle(
            color: valueColor,
            fontSize: fontSize ?? 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value, {Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: Colors.grey[400])),
        Text(
          value,
          style: TextStyle(
            color: valueColor ?? Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  String _formatNumber(double value) {
    if (value.abs() >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(2)}M';
    } else if (value.abs() >= 1000) {
      return '${(value / 1000).toStringAsFixed(2)}K';
    }
    return value.toStringAsFixed(2);
  }
}
