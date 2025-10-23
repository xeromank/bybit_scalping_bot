import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:bybit_scalping_bot/providers/live_chart_provider.dart';
import 'package:bybit_scalping_bot/widgets/trading_chart.dart';
import 'package:bybit_scalping_bot/widgets/prediction_detail_card.dart';

/// 실시간 차트 화면
///
/// 기능:
/// - Top 10 종목 선택
/// - 인터벌 선택 (1m/5m/30m/1h/4h)
/// - 실시간 차트 + WebSocket 업데이트
/// - 실시간 예측 데이터 표시
class LiveChartScreen extends StatefulWidget {
  const LiveChartScreen({Key? key}) : super(key: key);

  @override
  State<LiveChartScreen> createState() => _LiveChartScreenState();
}

class _LiveChartScreenState extends State<LiveChartScreen> {
  @override
  void initState() {
    super.initState();
    // 초기 데이터 로드 및 WebSocket 연결
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<LiveChartProvider>();
      provider.loadInitialData();
      provider.connectWebSocket();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E0E0E),
      appBar: AppBar(
        title: const Text('실시간 차트'),
        backgroundColor: const Color(0xFF1E1E1E),
        actions: [
          // 인터벌 선택 버튼
          IconButton(
            icon: const Icon(Icons.timer),
            tooltip: '인터벌 선택',
            onPressed: _showIntervalSelector,
          ),
          // 종목 선택 버튼
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: '종목 선택',
            onPressed: _showSymbolSelector,
          ),
          // 새로고침 버튼
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              context.read<LiveChartProvider>().refresh();
            },
          ),
        ],
      ),
      body: Consumer<LiveChartProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Colors.blue),
                  SizedBox(height: 16),
                  Text(
                    '데이터 로딩 중...',
                    style: TextStyle(color: Colors.white),
                  ),
                ],
              ),
            );
          }

          if (provider.error != null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error, color: Colors.red, size: 48),
                  const SizedBox(height: 16),
                  const Text(
                    '데이터 로드 실패',
                    style: TextStyle(color: Colors.white, fontSize: 18),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    provider.error!,
                    style: TextStyle(color: Colors.grey[400], fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => provider.refresh(),
                    child: const Text('다시 시도'),
                  ),
                ],
              ),
            );
          }

          if (provider.currentKlines.isEmpty) {
            return const Center(
              child: Text(
                '데이터가 없습니다',
                style: TextStyle(color: Colors.white),
              ),
            );
          }

          return Column(
            children: [
              // 종목 + 인터벌 헤더
              _buildHeader(provider),

              // 스크롤 가능한 영역
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      // 실시간 예측 범위 표시
                      if (provider.predictedHigh != null)
                        _buildPredictionBanner(provider),

                      // 이전 캔들 예측 결과 카드 (최상단 배치)
                      if (provider.previousPrediction != null && provider.currentKlines.length > 1)
                        Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: PredictionDetailCard(
                            prediction: provider.previousPrediction!,
                            currentPrice: provider.currentKlines[provider.currentKlines.length - 2].close,
                            isPrevious: true,
                            actualHigh: provider.currentKlines.last.high,
                            actualLow: provider.currentKlines.last.low,
                            actualClose: provider.currentKlines.last.close,
                          ),
                        )
                      else
                        Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Card(
                            color: const Color(0xFF2D2D2D),
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                children: [
                                  const Icon(Icons.info_outline, color: Colors.orange, size: 40),
                                  const SizedBox(height: 8),
                                  Text(
                                    '이전 예측 데이터 로딩 중...',
                                    style: TextStyle(color: Colors.grey[400], fontSize: 14),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '캔들 데이터: ${provider.currentKlines.length}개\n5분봉: ${provider.klines5m.length}개\n30분봉: ${provider.klines30m.length}개',
                                    style: TextStyle(color: Colors.grey[600], fontSize: 11),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                      // 다음 캔들 예측 카드
                      if (provider.prediction != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12.0),
                          child: PredictionDetailCard(
                            prediction: provider.prediction!,
                            currentPrice: provider.currentKlines.last.close,
                            isPrevious: false,
                          ),
                        ),

                      const SizedBox(height: 12),

                      // 메인 차트 (하단 배치)
                      SizedBox(
                        height: MediaQuery.of(context).size.height * 0.6,
                        child: TradingChart(
                          klines: provider.currentKlines,
                          prediction: provider.prediction,
                          symbol: provider.symbol,
                          interval: '${provider.selectedInterval}m',
                          predictedHigh: provider.predictedHigh,
                          predictedLow: provider.predictedLow,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 헤더 (종목 + 인터벌 + 가격 정보)
  Widget _buildHeader(LiveChartProvider provider) {
    final latestKline = provider.currentKlines.last;
    final firstKline = provider.currentKlines.first;
    final priceChange = latestKline.close - firstKline.close;
    final priceChangePercent = (priceChange / firstKline.close) * 100;
    final isUp = priceChange >= 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        border: Border(
          bottom: BorderSide(color: Colors.grey.withOpacity(0.2)),
        ),
      ),
      child: Column(
        children: [
          // 첫 번째 줄: 심볼 + 인터벌 + LIVE
          Row(
            children: [
              // 심볼
              GestureDetector(
                onTap: _showSymbolSelector,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.withOpacity(0.5)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        provider.symbol.replaceAll('USDT', '/USDT'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(Icons.arrow_drop_down, color: Colors.blue, size: 20),
                    ],
                  ),
                ),
              ),

              const SizedBox(width: 12),

              // 인터벌
              GestureDetector(
                onTap: _showIntervalSelector,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.purple.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.purple.withOpacity(0.5)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        LiveChartProvider.intervalOptions[provider.selectedInterval] ?? '',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.arrow_drop_down, color: Colors.purple, size: 18),
                    ],
                  ),
                ),
              ),

              const Spacer(),

              // 실시간 표시
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'LIVE',
                      style: TextStyle(
                        color: Colors.green,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // 두 번째 줄: 현재가 + 변화
          Row(
            children: [
              Text(
                '\$${latestKline.close.toStringAsFixed(2)}',
                style: TextStyle(
                  color: isUp ? Colors.green : Colors.red,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${isUp ? '+' : ''}${priceChange.toStringAsFixed(2)} (${priceChangePercent.toStringAsFixed(2)}%)',
                style: TextStyle(
                  color: isUp ? Colors.green : Colors.red,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 실시간 예측 범위 배너
  Widget _buildPredictionBanner(LiveChartProvider provider) {
    final currentPrice = provider.currentKlines.last.close;
    final predictedHigh = provider.predictedHigh!;
    final predictedLow = provider.predictedLow!;
    final upPotential = ((predictedHigh - currentPrice) / currentPrice * 100);
    final downPotential = ((currentPrice - predictedLow) / currentPrice * 100);

    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_graph, color: Colors.blue, size: 18),
              const SizedBox(width: 8),
              const Text(
                '다음 캔들 실시간 예측',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // 예측 최고가
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '최고가',
                    style: TextStyle(color: Colors.grey[400], fontSize: 11),
                  ),
                  Text(
                    '\$${predictedHigh.toStringAsFixed(2)}',
                    style: const TextStyle(
                      color: Colors.green,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '+${upPotential.toStringAsFixed(2)}%',
                    style: TextStyle(color: Colors.green[300], fontSize: 10),
                  ),
                ],
              ),

              // 예측 종가
              if (provider.predictedClose != null)
                Column(
                  children: [
                    Text(
                      '예상 종가',
                      style: TextStyle(color: Colors.grey[400], fontSize: 11),
                    ),
                    Text(
                      '\$${provider.predictedClose!.toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: Colors.blue,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),

              // 예측 최저가
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '최저가',
                    style: TextStyle(color: Colors.grey[400], fontSize: 11),
                  ),
                  Text(
                    '\$${predictedLow.toStringAsFixed(2)}',
                    style: const TextStyle(
                      color: Colors.red,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '-${downPotential.toStringAsFixed(2)}%',
                    style: TextStyle(color: Colors.red[300], fontSize: 10),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 인터벌 선택 다이얼로그
  void _showIntervalSelector() {
    final provider = context.read<LiveChartProvider>();

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '차트 인터벌 선택',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              ...LiveChartProvider.intervalOptions.entries.map((entry) {
                final isSelected = entry.key == provider.selectedInterval;

                return ListTile(
                  leading: Icon(
                    Icons.show_chart,
                    color: isSelected ? Colors.purple : Colors.grey,
                  ),
                  title: Text(
                    entry.value,
                    style: TextStyle(
                      color: isSelected ? Colors.purple : Colors.white,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  trailing: isSelected
                      ? const Icon(Icons.check_circle, color: Colors.purple)
                      : null,
                  onTap: () {
                    provider.changeInterval(entry.key);
                    Navigator.pop(context);
                  },
                );
              }).toList(),
            ],
          ),
        );
      },
    );
  }

  /// 종목 선택 다이얼로그
  void _showSymbolSelector() {
    final provider = context.read<LiveChartProvider>();

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(16),
          height: MediaQuery.of(context).size.height * 0.7,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    'Top 10 종목 선택',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  if (provider.isLoadingCoins)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.blue,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: provider.topCoins.isEmpty
                    ? const Center(
                        child: Text(
                          'Top 10 종목을 로딩 중...',
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : GridView.builder(
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          childAspectRatio: 2.5,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                        ),
                        itemCount: provider.topCoins.length,
                        itemBuilder: (context, index) {
                          final coin = provider.topCoins[index];
                          final isSelected = coin.symbol == provider.symbol;

                          return GestureDetector(
                            onTap: () {
                              provider.changeSymbol(coin.symbol);
                              Navigator.pop(context);
                            },
                            child: Container(
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? Colors.blue.withOpacity(0.3)
                                    : const Color(0xFF2A2A2A),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isSelected
                                      ? Colors.blue
                                      : Colors.transparent,
                                  width: 2,
                                ),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    coin.symbol.replaceAll('USDT', ''),
                                    style: TextStyle(
                                      color: isSelected ? Colors.blue : Colors.white,
                                      fontSize: 16,
                                      fontWeight: isSelected
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    coin.priceChangePercent24h >= 0
                                        ? '+${(coin.priceChangePercent24h * 100).toStringAsFixed(2)}%'
                                        : '${(coin.priceChangePercent24h * 100).toStringAsFixed(2)}%',
                                    style: TextStyle(
                                      color: coin.priceChangePercent24h >= 0
                                          ? Colors.green
                                          : Colors.red,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
