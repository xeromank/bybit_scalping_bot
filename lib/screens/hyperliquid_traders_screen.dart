import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:bybit_scalping_bot/providers/hyperliquid_provider.dart';
import 'package:bybit_scalping_bot/screens/hyperliquid_trader_add_screen.dart';
import 'package:bybit_scalping_bot/screens/hyperliquid_trader_detail_screen.dart';
import 'package:bybit_scalping_bot/models/hyperliquid/hyperliquid_trader.dart';
import 'package:bybit_scalping_bot/models/hyperliquid/hyperliquid_account_state.dart';

/// Hyperliquid 트레이더 목록 화면
class HyperliquidTradersScreen extends StatefulWidget {
  const HyperliquidTradersScreen({Key? key}) : super(key: key);

  @override
  State<HyperliquidTradersScreen> createState() => _HyperliquidTradersScreenState();
}

class _HyperliquidTradersScreenState extends State<HyperliquidTradersScreen> {
  @override
  void initState() {
    super.initState();
    // 초기화
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<HyperliquidProvider>().initialize();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E0E0E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Row(
          children: [
            Icon(Icons.track_changes, color: Colors.blue, size: 24),
            SizedBox(width: 8),
            Text(
              'Hyperliquid 트레이더',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          // 새로고침 버튼
          Consumer<HyperliquidProvider>(
            builder: (context, provider, child) {
              return IconButton(
                icon: provider.isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.blue,
                        ),
                      )
                    : const Icon(Icons.refresh, color: Colors.blue),
                onPressed: provider.isLoading
                    ? null
                    : () => provider.refreshAllStates(),
              );
            },
          ),
        ],
      ),
      body: Consumer<HyperliquidProvider>(
        builder: (context, provider, child) {
          // 에러 표시
          if (provider.error != null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 60),
                  const SizedBox(height: 16),
                  Text(
                    provider.error!,
                    style: TextStyle(color: Colors.grey[400], fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () => provider.refreshAllStates(),
                    icon: const Icon(Icons.refresh),
                    label: const Text('다시 시도'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                    ),
                  ),
                ],
              ),
            );
          }

          // 트레이더 없음
          if (provider.traders.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.person_add, color: Colors.grey, size: 80),
                  const SizedBox(height: 16),
                  Text(
                    '추적 중인 트레이더가 없습니다',
                    style: TextStyle(color: Colors.grey[400], fontSize: 18),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '+ 버튼을 눌러 트레이더를 추가하세요',
                    style: TextStyle(color: Colors.grey[600], fontSize: 14),
                  ),
                ],
              ),
            );
          }

          // 트레이더 목록
          return RefreshIndicator(
            onRefresh: () => provider.refreshAllStates(),
            backgroundColor: const Color(0xFF1E1E1E),
            color: Colors.blue,
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: provider.traders.length,
              itemBuilder: (context, index) {
                final trader = provider.traders[index];
                final state = provider.getAccountState(trader.address);
                return _TraderCard(
                  trader: trader,
                  state: state,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => HyperliquidTraderDetailScreen(
                          trader: trader,
                        ),
                      ),
                    );
                  },
                  onDelete: () => _confirmDelete(context, trader),
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final provider = context.read<HyperliquidProvider>();
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const HyperliquidTraderAddScreen(),
            ),
          );
          if (!mounted) return;

          if (result == true) {
            // 추가 완료 후 새로고침
            provider.refreshAllStates();
          }
        },
        backgroundColor: Colors.blue,
        icon: const Icon(Icons.add),
        label: const Text('트레이더 추가'),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, HyperliquidTrader trader) async {
    final provider = context.read<HyperliquidProvider>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2D2D2D),
        title: const Text('트레이더 삭제', style: TextStyle(color: Colors.white)),
        content: Text(
          '${trader.displayName}을(를) 삭제하시겠습니까?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('삭제'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      if (!mounted) return;
      await provider.removeTrader(trader.address);
    }
  }
}

/// 트레이더 카드 위젯
class _TraderCard extends StatelessWidget {
  final HyperliquidTrader trader;
  final HyperliquidAccountState? state;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _TraderCard({
    Key? key,
    required this.trader,
    this.state,
    required this.onTap,
    required this.onDelete,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF2D2D2D),
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 헤더: 이름 + 삭제 버튼
              Row(
                children: [
                  Icon(
                    Icons.account_circle,
                    color: Colors.blue[300],
                    size: 24,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          trader.displayName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (trader.nickname != null)
                          Text(
                            trader.shortAddress,
                            style: TextStyle(
                              color: Colors.grey[500],
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                    onPressed: onDelete,
                  ),
                ],
              ),

              const SizedBox(height: 12),
              const Divider(color: Colors.grey),
              const SizedBox(height: 12),

              // 계정 정보
              ..._buildAccountInfo(state),
              if (state == null)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.blue,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '데이터 로딩 중...',
                          style: TextStyle(color: Colors.grey[500], fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildAccountInfo(HyperliquidAccountState? state) {
    if (state == null) return [];

    final accountValue = state.marginSummary.accountValueAsDouble;
    final pnl = state.totalUnrealizedPnl;
    final roe = state.totalROE;
    final posCount = state.assetPositions.length;

    return [
      _buildInfoRow(
        '총 자산',
        '\$${_formatNumber(accountValue)}',
        Colors.amber,
      ),
      const SizedBox(height: 8),
      _buildInfoRow(
        '미실현 손익',
        '${pnl >= 0 ? '+' : ''}\$${_formatNumber(pnl)}',
        pnl >= 0 ? Colors.green : Colors.red,
      ),
      const SizedBox(height: 8),
      _buildInfoRow(
        'ROE',
        '${roe >= 0 ? '+' : ''}${roe.toStringAsFixed(2)}%',
        roe >= 0 ? Colors.green : Colors.red,
      ),
      const SizedBox(height: 8),
      _buildInfoRow(
        '포지션',
        '$posCount개',
        Colors.blue,
      ),
    ];
  }

  Widget _buildInfoRow(String label, String value, Color valueColor) {
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
            fontSize: 16,
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
