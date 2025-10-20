import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:bybit_scalping_bot/providers/bybit_trading_provider.dart';
import 'package:bybit_scalping_bot/widgets/bybit/balance_card.dart';
import 'package:bybit_scalping_bot/widgets/bybit/market_condition_card.dart';
import 'package:bybit_scalping_bot/widgets/bybit/top_coins_selector.dart';
import 'package:bybit_scalping_bot/widgets/bybit/strategy_info_card.dart';
import 'package:bybit_scalping_bot/widgets/bybit/trading_controls.dart';
import 'package:bybit_scalping_bot/widgets/bybit/position_display.dart';
import 'package:bybit_scalping_bot/widgets/bybit/positions_list.dart';
import 'package:bybit_scalping_bot/widgets/bybit/real_time_price_card.dart';
import 'package:bybit_scalping_bot/widgets/bybit/technical_indicators_card.dart';

/// Bybit Trading Screen (New Adaptive Strategy System)
///
/// Features:
/// - Balance Tab: 자산 현황
/// - Trading Tab: 거래 화면 (코인 선택, 시장 분석, 전략, 거래 컨트롤)
class BybitTradingScreen extends StatefulWidget {
  const BybitTradingScreen({super.key});

  @override
  State<BybitTradingScreen> createState() => _BybitTradingScreenState();
}

class _BybitTradingScreenState extends State<BybitTradingScreen>
    with SingleTickerProviderStateMixin {
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
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E1E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2D2D2D),
        title: const Text(
          'Bybit 선물 거래',
          style: TextStyle(color: Colors.white),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.blue,
          labelColor: Colors.blue,
          unselectedLabelColor: Colors.grey,
          tabs: const [
            Tab(
              icon: Icon(Icons.account_balance_wallet),
              text: '자산',
            ),
            Tab(
              icon: Icon(Icons.trending_up),
              text: '거래',
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: TabBarView(
          controller: _tabController,
          children: [
            // Balance Tab
            _buildBalanceTab(),

            // Trading Tab
            _buildTradingTab(),
          ],
        ),
      ),
    );
  }

  /// Balance Tab - 자산 현황
  Widget _buildBalanceTab() {
    return RefreshIndicator(
      onRefresh: () async {
        await context.read<BybitTradingProvider>().fetchBalance();
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Balance Card
            const BalanceCard(),
            const SizedBox(height: 16),

            // Positions List (all open positions)
            const PositionsList(),
            const SizedBox(height: 16),

            // Info Box
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.info_outline,
                        color: Colors.blue,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '자산 정보',
                        style: TextStyle(
                          color: Colors.grey[300],
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '• 총 자산: 현재 계좌의 총 가치 (포지션 손익 포함)\n'
                    '• 사용 가능: 새로운 주문에 사용할 수 있는 금액\n'
                    '• 포지션 증거금: 현재 포지션에 투입된 금액\n'
                    '• 미실현 손익: 현재 포지션의 평가 손익',
                    style: TextStyle(
                      color: Colors.grey[400],
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Trading Tab - 거래 화면
  Widget _buildTradingTab() {
    return Consumer<BybitTradingProvider>(
      builder: (context, provider, child) {
        return RefreshIndicator(
          onRefresh: () async {
            await provider.loadTopCoins();
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top 10 Coins Selector
                const TopCoinsSelector(),
                const SizedBox(height: 16),

                // Real-time Price Card
                const RealTimePriceCard(),
                const SizedBox(height: 16),

                // Technical Indicators Card
                const TechnicalIndicatorsCard(),
                const SizedBox(height: 16),

                // Market Condition Card
                const MarketConditionCard(),
                const SizedBox(height: 16),

                // Strategy Info Card
                const StrategyInfoCard(),
                const SizedBox(height: 16),

                // Trading Controls
                const TradingControls(),
                const SizedBox(height: 32),
              ],
            ),
          ),
        );
      },
    );
  }
}
