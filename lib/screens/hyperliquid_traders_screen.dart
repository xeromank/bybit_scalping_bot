import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:bybit_scalping_bot/providers/hyperliquid_provider.dart';
import 'package:bybit_scalping_bot/screens/hyperliquid_trader_add_screen.dart';
import 'package:bybit_scalping_bot/screens/hyperliquid_trader_detail_screen.dart';
import 'package:bybit_scalping_bot/models/hyperliquid/hyperliquid_trader.dart';
import 'package:bybit_scalping_bot/models/hyperliquid/hyperliquid_account_state.dart';
import 'package:bybit_scalping_bot/widgets/hyperliquid/whale_alert_overlay.dart';

/// Hyperliquid 트레이더 목록 화면
class HyperliquidTradersScreen extends StatefulWidget {
  const HyperliquidTradersScreen({Key? key}) : super(key: key);

  @override
  State<HyperliquidTradersScreen> createState() => _HyperliquidTradersScreenState();
}

class _HyperliquidTradersScreenState extends State<HyperliquidTradersScreen> {
  String? _selectedCoin; // 선택된 코인 필터

  @override
  void initState() {
    super.initState();
    // 초기화
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 오버레이 매니저 초기화
      WhaleAlertOverlayManager().initialize(context);
      // Provider 초기화
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

          // 모든 코인 목록 추출
          final allCoins = _getAllCoins(provider);

          // 필터링된 트레이더 목록
          final filteredTraders = _getFilteredTraders(provider);

          // 트레이더 목록
          return Column(
            children: [
              // 코인 필터 칩
              if (allCoins.isNotEmpty) _buildCoinFilter(allCoins),

              // 트레이더 리스트
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () => provider.refreshAllStates(),
                  backgroundColor: const Color(0xFF1E1E1E),
                  color: Colors.blue,
                  child: filteredTraders.isEmpty
                      ? _buildEmptyFilterResult()
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: filteredTraders.length,
                          itemBuilder: (context, index) {
                            final trader = filteredTraders[index];
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
                ),
              ),
            ],
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

  /// 모든 코인 목록 추출
  Set<String> _getAllCoins(HyperliquidProvider provider) {
    final coins = <String>{};
    for (final trader in provider.traders) {
      final state = provider.getAccountState(trader.address);
      if (state != null) {
        for (final assetPos in state.assetPositions) {
          coins.add(assetPos.position.coin);
        }
      }
    }
    final sortedCoins = coins.toList()..sort();
    return sortedCoins.toSet();
  }

  /// 필터링된 트레이더 목록
  List<HyperliquidTrader> _getFilteredTraders(HyperliquidProvider provider) {
    if (_selectedCoin == null) {
      return provider.traders;
    }

    return provider.traders.where((trader) {
      final state = provider.getAccountState(trader.address);
      if (state == null) return false;

      return state.assetPositions.any(
        (assetPos) => assetPos.position.coin == _selectedCoin,
      );
    }).toList();
  }

  /// 코인 필터 칩 위젯
  Widget _buildCoinFilter(Set<String> coins) {
    return Container(
      color: const Color(0xFF1A1A1A),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.filter_list, color: Colors.blue, size: 20),
              const SizedBox(width: 8),
              Text(
                '코인 필터',
                style: TextStyle(
                  color: Colors.grey[300],
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                // "전체" 칩
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: const Text('전체'),
                    selected: _selectedCoin == null,
                    onSelected: (selected) {
                      setState(() {
                        _selectedCoin = null;
                      });
                    },
                    backgroundColor: const Color(0xFF2D2D2D),
                    selectedColor: Colors.blue,
                    labelStyle: TextStyle(
                      color: _selectedCoin == null ? Colors.white : Colors.grey[400],
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                // 각 코인별 칩
                ...coins.map((coin) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(coin),
                      selected: _selectedCoin == coin,
                      onSelected: (selected) {
                        setState(() {
                          _selectedCoin = selected ? coin : null;
                        });
                      },
                      backgroundColor: const Color(0xFF2D2D2D),
                      selectedColor: Colors.blue,
                      labelStyle: TextStyle(
                        color: _selectedCoin == coin ? Colors.white : Colors.grey[400],
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
          // 롱/숏 비율 표시 (코인 선택 시에만)
          if (_selectedCoin != null) _buildLongShortRatio(context.read<HyperliquidProvider>()),
        ],
      ),
    );
  }

  /// 롱/숏 비율 위젯
  Widget _buildLongShortRatio(HyperliquidProvider provider) {
    if (_selectedCoin == null) return const SizedBox.shrink();

    // 선택된 코인의 롱/숏 카운트 계산
    int longCount = 0;
    int shortCount = 0;

    for (final trader in provider.traders) {
      final state = provider.getAccountState(trader.address);
      if (state == null) continue;

      for (final assetPos in state.assetPositions) {
        if (assetPos.position.coin == _selectedCoin) {
          if (assetPos.position.isLong) {
            longCount++;
          } else if (assetPos.position.isShort) {
            shortCount++;
          }
        }
      }
    }

    final total = longCount + shortCount;
    if (total == 0) return const SizedBox.shrink();

    final longPercent = (longCount / total * 100).toStringAsFixed(1);
    final shortPercent = (shortCount / total * 100).toStringAsFixed(1);

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF2D2D2D),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.pie_chart, color: Colors.amber, size: 18),
              const SizedBox(width: 6),
              Text(
                '$_selectedCoin 롱/숏 비율',
                style: TextStyle(
                  color: Colors.grey[300],
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 롱/숏 바
          Row(
            children: [
              Expanded(
                flex: longCount,
                child: Container(
                  height: 24,
                  decoration: BoxDecoration(
                    color: Colors.green,
                    borderRadius: const BorderRadius.horizontal(left: Radius.circular(4)),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    longCount > 0 ? 'LONG $longPercent%' : '',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              Expanded(
                flex: shortCount,
                child: Container(
                  height: 24,
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: const BorderRadius.horizontal(right: Radius.circular(4)),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    shortCount > 0 ? 'SHORT $shortPercent%' : '',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // 숫자 표시
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '롱: $longCount명',
                style: const TextStyle(color: Colors.green, fontSize: 12),
              ),
              Text(
                '숏: $shortCount명',
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 필터 결과 없을 때 위젯
  Widget _buildEmptyFilterResult() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.search_off, color: Colors.grey, size: 60),
          const SizedBox(height: 16),
          Text(
            _selectedCoin != null
                ? '$_selectedCoin 포지션이 있는\n트레이더가 없습니다'
                : '필터링 결과가 없습니다',
            style: TextStyle(color: Colors.grey[400], fontSize: 16),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          TextButton.icon(
            onPressed: () {
              setState(() {
                _selectedCoin = null;
              });
            },
            icon: const Icon(Icons.clear),
            label: const Text('필터 초기화'),
            style: TextButton.styleFrom(foregroundColor: Colors.blue),
          ),
        ],
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
