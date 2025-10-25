import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:bybit_scalping_bot/providers/hyperliquid_provider.dart';
import 'package:bybit_scalping_bot/services/hyperdash_webview_client.dart';
import 'package:bybit_scalping_bot/models/hyperdash_trader.dart';

/// Hyperliquid 트레이더 추가 화면
class HyperliquidTraderAddScreen extends StatefulWidget {
  const HyperliquidTraderAddScreen({Key? key}) : super(key: key);

  @override
  State<HyperliquidTraderAddScreen> createState() => _HyperliquidTraderAddScreenState();
}

class _HyperliquidTraderAddScreenState extends State<HyperliquidTraderAddScreen> {
  final _formKey = GlobalKey<FormState>();
  final _addressController = TextEditingController();
  final _nicknameController = TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;

  // Top Traders 데이터
  List<HyperdashTrader> _topTraders = [];
  bool _isLoadingTraders = false;
  final _hyperdashClient = HyperdashWebViewClient();

  // 정렬 옵션
  String _sortBy = 'rank'; // rank, account_value, week_pnl, month_pnl, alltime_pnl

  // 필터 옵션
  Set<String> _selectedCoinsFilter = {}; // 선택된 코인 필터 (empty = 전체)

  @override
  void initState() {
    super.initState();
    _loadTopTraders();
  }

  @override
  void dispose() {
    _addressController.dispose();
    _nicknameController.dispose();
    _hyperdashClient.dispose();
    super.dispose();
  }

  /// Top Traders 로드
  Future<void> _loadTopTraders() async {
    setState(() {
      _isLoadingTraders = true;
    });

    try {
      final traders = await _hyperdashClient.fetchTopTraders();
      if (mounted) {
        setState(() {
          _topTraders = traders;
          _isLoadingTraders = false;
          _sortTraders(); // 정렬 적용
        });
      }
    } catch (e) {
      print('Top Traders 로드 실패: $e');
      if (mounted) {
        setState(() {
          _isLoadingTraders = false;
        });
      }
    }
  }

  /// 트레이더 정렬
  void _sortTraders() {
    switch (_sortBy) {
      case 'rank':
        // 원본 순서 유지 (API에서 받은 순서 = 랭킹)
        break;
      case 'account_value':
        _topTraders.sort((a, b) => b.accountValue.compareTo(a.accountValue));
        break;
      case 'week_pnl':
        _topTraders.sort((a, b) => b.perpWeekPnl.compareTo(a.perpWeekPnl));
        break;
      case 'month_pnl':
        _topTraders.sort((a, b) => b.perpMonthPnl.compareTo(a.perpMonthPnl));
        break;
      case 'alltime_pnl':
        _topTraders.sort((a, b) => b.perpAlltimePnl.compareTo(a.perpAlltimePnl));
        break;
    }
  }

  /// 정렬 변경
  void _changeSortBy(String newSortBy) {
    setState(() {
      _sortBy = newSortBy;
      _sortTraders();
    });
  }

  /// 필터링된 트레이더 목록 가져오기
  List<HyperdashTrader> get _filteredTraders {
    if (_selectedCoinsFilter.isEmpty) {
      return _topTraders;
    }
    return _topTraders.where((trader) {
      return trader.mainPosition != null &&
             _selectedCoinsFilter.contains(trader.mainPosition!.coin);
    }).toList();
  }

  /// 모든 코인 목록 추출
  Set<String> get _allCoins {
    final coins = <String>{};
    for (final trader in _topTraders) {
      if (trader.mainPosition != null && trader.mainPosition!.coin.isNotEmpty) {
        coins.add(trader.mainPosition!.coin);
      }
    }
    final sortedCoins = coins.toList()..sort();
    return sortedCoins.toSet();
  }

  /// 이미 등록된 트레이더인지 확인
  bool _isTraderRegistered(String address) {
    final provider = context.read<HyperliquidProvider>();
    return provider.traders.any((t) => t.address.toLowerCase() == address.toLowerCase());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E0E0E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text(
          '트레이더 추가',
          style: TextStyle(color: Colors.white),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 안내 카드
            Card(
              color: const Color(0xFF2D2D2D),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.blue[300], size: 24),
                        const SizedBox(width: 8),
                        const Text(
                          '트레이더 추가 방법',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '1. hyperdash.info에서 트레이더 검색\n'
                      '2. URL의 주소 복사 (0x로 시작)\n'
                      '3. 아래에 붙여넣기\n'
                      '4. 선택적으로 닉네임 입력',
                      style: TextStyle(color: Colors.grey[400], fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // 주소 입력
            TextFormField(
              controller: _addressController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: '트레이더 주소 *',
                labelStyle: TextStyle(color: Colors.grey[400]),
                hintText: '0x9263c1bd29aa87a118242f3fbba4517037f8cc7a',
                hintStyle: TextStyle(color: Colors.grey[600], fontSize: 12),
                filled: true,
                fillColor: const Color(0xFF2D2D2D),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey[700]!, width: 1),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Colors.blue, width: 2),
                ),
                errorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Colors.red, width: 1),
                ),
                prefixIcon: const Icon(Icons.link, color: Colors.blue),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.content_paste, color: Colors.grey),
                  onPressed: _pasteFromClipboard,
                  tooltip: '클립보드에서 붙여넣기',
                ),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return '주소를 입력해주세요';
                }
                if (!value.toLowerCase().startsWith('0x')) {
                  return '올바른 주소가 아닙니다 (0x로 시작)';
                }
                if (value.length != 42) {
                  return '주소 길이가 올바르지 않습니다 (42자)';
                }
                return null;
              },
              textInputAction: TextInputAction.next,
            ),

            const SizedBox(height: 16),

            // 닉네임 입력 (선택)
            TextFormField(
              controller: _nicknameController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: '닉네임 (선택)',
                labelStyle: TextStyle(color: Colors.grey[400]),
                hintText: '예: 고래 트레이더',
                hintStyle: TextStyle(color: Colors.grey[600], fontSize: 12),
                filled: true,
                fillColor: const Color(0xFF2D2D2D),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey[700]!, width: 1),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Colors.blue, width: 2),
                ),
                prefixIcon: const Icon(Icons.person, color: Colors.blue),
              ),
              maxLength: 30,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _addTrader(),
            ),

            const SizedBox(height: 8),

            // 에러 메시지
            if (_errorMessage != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.5)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error, color: Colors.red, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.red, fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 24),

            // 추가 버튼
            SizedBox(
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _addTrader,
                icon: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.add),
                label: Text(
                  _isLoading ? '추가 중...' : '트레이더 추가',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 32),

            // 구분선
            Row(
              children: [
                Expanded(child: Divider(color: Colors.grey[700])),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    '또는',
                    style: TextStyle(color: Colors.grey[500], fontSize: 14),
                  ),
                ),
                Expanded(child: Divider(color: Colors.grey[700])),
              ],
            ),

            const SizedBox(height: 16),

            // Top Traders 섹션 헤더
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.leaderboard, color: Colors.amber[700], size: 24),
                    const SizedBox(width: 8),
                    const Text(
                      'Top 1000 Traders',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                if (_isLoadingTraders)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  TextButton.icon(
                    onPressed: _loadTopTraders,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('새로고침'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.blue,
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 12),

            // 정렬 옵션
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF2D2D2D),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[700]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.sort, color: Colors.grey[400], size: 20),
                  const SizedBox(width: 8),
                  Text(
                    '정렬:',
                    style: TextStyle(color: Colors.grey[400], fontSize: 14),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _sortBy,
                        dropdownColor: const Color(0xFF2D2D2D),
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        icon: Icon(Icons.arrow_drop_down, color: Colors.grey[400]),
                        items: const [
                          DropdownMenuItem(
                            value: 'rank',
                            child: Text('기본 랭킹'),
                          ),
                          DropdownMenuItem(
                            value: 'account_value',
                            child: Text('계좌 금액'),
                          ),
                          DropdownMenuItem(
                            value: 'week_pnl',
                            child: Text('주간 수익'),
                          ),
                          DropdownMenuItem(
                            value: 'month_pnl',
                            child: Text('월간 수익'),
                          ),
                          DropdownMenuItem(
                            value: 'alltime_pnl',
                            child: Text('전체 수익'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            _changeSortBy(value);
                          }
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // 코인 필터
            if (_allCoins.isNotEmpty) _buildCoinFilter(),

            if (_allCoins.isNotEmpty) const SizedBox(height: 12),

            // Top Traders 리스트
            _buildTopTradersList(),
          ],
        ),
      ),
    );
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data != null && data.text != null) {
      _addressController.text = data.text!.trim();
    }
  }

  /// 코인 필터 위젯 (멀티 셀렉트 콤보박스)
  Widget _buildCoinFilter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF2D2D2D),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[700]!),
      ),
      child: Row(
        children: [
          Icon(Icons.filter_list, color: Colors.grey[400], size: 20),
          const SizedBox(width: 8),
          Text(
            '주요 포지션 필터:',
            style: TextStyle(color: Colors.grey[400], fontSize: 14),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: InkWell(
              onTap: _showCoinFilterDialog,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.grey[700]!),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        _selectedCoinsFilter.isEmpty
                            ? '전체'
                            : '${_selectedCoinsFilter.length}개 선택 (${_selectedCoinsFilter.join(', ')})',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(Icons.arrow_drop_down, color: Colors.grey[400]),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 코인 필터 선택 다이얼로그
  void _showCoinFilterDialog() {
    showDialog(
      context: context,
      builder: (context) {
        // 다이얼로그 내부 임시 선택 상태
        Set<String> tempSelection = Set.from(_selectedCoinsFilter);

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF2D2D2D),
              title: const Text(
                '주요 포지션 필터',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    // "전체" 옵션
                    CheckboxListTile(
                      title: const Text(
                        '전체',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      value: tempSelection.isEmpty,
                      activeColor: Colors.blue,
                      onChanged: (checked) {
                        setDialogState(() {
                          if (checked == true) {
                            tempSelection.clear();
                          }
                        });
                      },
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                    Divider(color: Colors.grey[700]),
                    // 각 코인별 체크박스
                    ..._allCoins.map((coin) {
                      return CheckboxListTile(
                        title: Text(
                          coin,
                          style: const TextStyle(color: Colors.white),
                        ),
                        value: tempSelection.contains(coin),
                        activeColor: Colors.blue,
                        onChanged: (checked) {
                          setDialogState(() {
                            if (checked == true) {
                              tempSelection.add(coin);
                            } else {
                              tempSelection.remove(coin);
                            }
                          });
                        },
                        controlAffinity: ListTileControlAffinity.leading,
                      );
                    }),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('취소'),
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _selectedCoinsFilter = tempSelection;
                    });
                    Navigator.pop(context);
                  },
                  style: TextButton.styleFrom(foregroundColor: Colors.blue),
                  child: const Text('적용'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Top Traders 리스트 위젯
  Widget _buildTopTradersList() {
    if (_isLoadingTraders) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_topTraders.isEmpty) {
      return Card(
        color: const Color(0xFF2D2D2D),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Icon(Icons.info_outline, color: Colors.grey[400], size: 48),
              const SizedBox(height: 12),
              Text(
                '트레이더 목록을 불러올 수 없습니다',
                style: TextStyle(color: Colors.grey[400], fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _loadTopTraders,
                child: const Text('다시 시도'),
              ),
            ],
          ),
        ),
      );
    }

    final filteredList = _filteredTraders;

    if (filteredList.isEmpty) {
      return Card(
        color: const Color(0xFF2D2D2D),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Icon(Icons.search_off, color: Colors.grey[400], size: 48),
              const SizedBox(height: 12),
              Text(
                '필터 조건에 맞는 트레이더가 없습니다',
                style: TextStyle(color: Colors.grey[400], fontSize: 14),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      height: 400,
      decoration: BoxDecoration(
        color: const Color(0xFF2D2D2D),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[700]!),
      ),
      child: ListView.separated(
        padding: const EdgeInsets.all(8),
        itemCount: filteredList.length,
        separatorBuilder: (context, index) => Divider(
          color: Colors.grey[800],
          height: 1,
        ),
        itemBuilder: (context, index) {
          final trader = filteredList[index];
          final originalIndex = _topTraders.indexOf(trader) + 1;
          return _buildTraderTile(trader, originalIndex);
        },
      ),
    );
  }

  /// 트레이더 타일 위젯
  Widget _buildTraderTile(HyperdashTrader trader, int rank) {
    final isProfitable = trader.isMonthPnlPositive;
    final isRegistered = _isTraderRegistered(trader.address);

    return InkWell(
      onTap: () => _selectTrader(trader),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          border: isRegistered
              ? Border.all(color: Colors.green.withValues(alpha: 0.5), width: 2)
              : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            // 순위
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: rank <= 3
                    ? Colors.amber.withValues(alpha: 0.2)
                    : Colors.grey.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: rank <= 3 ? Colors.amber : Colors.grey[700]!,
                ),
              ),
              child: Center(
                child: Text(
                  '#$rank',
                  style: TextStyle(
                    color: rank <= 3 ? Colors.amber : Colors.grey[400],
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

            const SizedBox(width: 12),

            // 트레이더 정보
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 주소 + 등록 여부 배지
                  Row(
                    children: [
                      Text(
                        trader.shortAddress,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (isRegistered) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.green, width: 1),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.check_circle, color: Colors.green, size: 12),
                              SizedBox(width: 4),
                              Text(
                                '등록됨',
                                style: TextStyle(
                                  color: Colors.green,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),

                  // 계좌 금액 & 포지션
                  Row(
                    children: [
                      Text(
                        trader.formattedAccountValue,
                        style: TextStyle(
                          color: Colors.grey[400],
                          fontSize: 12,
                        ),
                      ),
                      if (trader.mainPosition != null && trader.mainPosition!.hasPosition) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: trader.mainPosition!.side == 'LONG'
                                ? Colors.green.withValues(alpha: 0.2)
                                : Colors.red.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            trader.mainPositionDescription,
                            style: TextStyle(
                              color: trader.mainPosition!.side == 'LONG'
                                  ? Colors.green
                                  : Colors.red,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(width: 12),

            // PnL
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  trader.formattedMonthPnl,
                  style: TextStyle(
                    color: isProfitable ? Colors.green : Colors.red,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '월간',
                  style: TextStyle(
                    color: Colors.grey[500],
                    fontSize: 10,
                  ),
                ),
              ],
            ),

            const SizedBox(width: 8),

            // 선택 아이콘
            Icon(
              Icons.arrow_forward_ios,
              color: Colors.grey[600],
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  /// 트레이더 선택
  void _selectTrader(HyperdashTrader trader) {
    setState(() {
      _addressController.text = trader.address;
      _nicknameController.text = ''; // 사용자가 직접 입력하도록
    });

    // 화면 상단으로 스크롤 (주소 입력란이 보이도록)
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${trader.shortAddress} 선택됨 - 닉네임을 입력하고 추가 버튼을 눌러주세요'),
        backgroundColor: Colors.blue,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _addTrader() async {
    // 폼 검증
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final provider = context.read<HyperliquidProvider>();
      final address = _addressController.text.trim().toLowerCase();
      final nickname = _nicknameController.text.trim();

      final success = await provider.addTrader(
        address,
        nickname: nickname.isEmpty ? null : nickname,
      );

      if (success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('트레이더가 추가되었습니다'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context, true);
        }
      } else {
        setState(() {
          _errorMessage = provider.error ?? '트레이더를 추가할 수 없습니다';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = '오류가 발생했습니다: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
}
