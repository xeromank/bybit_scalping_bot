import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:bybit_scalping_bot/providers/auth_provider.dart';
import 'package:bybit_scalping_bot/providers/coinone_balance_provider.dart';
import 'package:bybit_scalping_bot/providers/coinone_trading_provider.dart';
import 'package:bybit_scalping_bot/screens/login_screen_new.dart';
import 'package:bybit_scalping_bot/screens/coinone_withdrawal_screen.dart';
import 'package:bybit_scalping_bot/constants/theme_constants.dart';
import 'package:bybit_scalping_bot/models/coinone/coinone_balance.dart';
import 'package:bybit_scalping_bot/models/coinone/coinone_ticker.dart';
import 'package:bybit_scalping_bot/models/coinone/coinone_order.dart';
import 'package:bybit_scalping_bot/services/coinone/coinone_websocket_client.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';

/// Coinone trading screen - main screen for spot trading
///
/// Responsibility: Display trading interface for Coinone
///
/// Features:
/// - Separate balance tab showing all holdings
/// - Trading tab with top 10 coins by volume
/// - Real-time ticker and orderbook
/// - Buy/sell orders with KRW amount or coin quantity
/// - Bollinger Band strategy
class CoinoneTradingScreen extends StatefulWidget {
  const CoinoneTradingScreen({super.key});

  @override
  State<CoinoneTradingScreen> createState() => _CoinoneTradingScreenState();
}

class _CoinoneTradingScreenState extends State<CoinoneTradingScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, dynamic>> _topCoins = [];
  bool _isLoadingTopCoins = false;
  bool _isTopCoinsExpanded = true; // Collapsible state for top coins card

  // WebSocket for balance tickers
  final CoinoneWebSocketClient _balanceWsClient = CoinoneWebSocketClient();
  final Map<String, CoinoneTicker> _balanceTickers = {};
  final List<StreamSubscription<CoinoneTicker>> _tickerSubscriptions = [];

  // Controllers for bot settings
  final TextEditingController _orderAmountController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    // Start balance monitoring
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // First, fetch balance
      await context.read<CoinoneBalanceProvider>().fetchBalance();

      // Then start monitoring
      context.read<CoinoneBalanceProvider>().startMonitoring();

      // Fetch top coins
      _fetchTopCoinsByVolume();

      // Subscribe to WebSocket after balance is loaded
      await _subscribeToBalanceTickers();

      // Start technical indicator updates
      context.read<CoinoneTradingProvider>().startIndicatorUpdates();

      // Initialize order amount controller with current value
      final tradingProvider = context.read<CoinoneTradingProvider>();
      _orderAmountController.text = tradingProvider.orderKrwAmount.toStringAsFixed(0);
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _orderAmountController.dispose();

    // Stop balance monitoring
    context.read<CoinoneBalanceProvider>().stopMonitoring();

    // Stop technical indicator updates
    context.read<CoinoneTradingProvider>().stopIndicatorUpdates();

    // Cleanup WebSocket
    for (final subscription in _tickerSubscriptions) {
      subscription.cancel();
    }
    _balanceWsClient.disconnect();

    super.dispose();
  }

  /// Fetch top 10 coins by volume from ticker API
  Future<void> _fetchTopCoinsByVolume() async {
    setState(() {
      _isLoadingTopCoins = true;
    });

    try {
      final uri = Uri.parse(
        'https://api.coinone.co.kr/public/v2/ticker_utc_new/KRW?additional_data=true',
      );
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['result'] == 'success') {
          final tickers = data['tickers'] as List<dynamic>;

          // Sort by quote_volume (KRW trading volume) descending
          tickers.sort((a, b) {
            final volumeA = double.tryParse(a['quote_volume']?.toString() ?? '0') ?? 0;
            final volumeB = double.tryParse(b['quote_volume']?.toString() ?? '0') ?? 0;
            return volumeB.compareTo(volumeA);
          });

          // Take top 10
          setState(() {
            _topCoins = tickers.take(10).map((ticker) {
              final currency = ticker['target_currency'].toString().toUpperCase();
              final lastPrice = double.tryParse(ticker['last']?.toString() ?? '0') ?? 0.0;

              // Initialize ticker data for top coins
              _balanceTickers[currency] = CoinoneTicker(
                quoteCurrency: 'KRW',
                targetCurrency: currency,
                last: lastPrice,
                high: double.tryParse(ticker['high']?.toString() ?? '0') ?? 0.0,
                low: double.tryParse(ticker['low']?.toString() ?? '0') ?? 0.0,
                first: double.tryParse(ticker['first']?.toString() ?? '0') ?? 0.0,
                volume: double.tryParse(ticker['volume']?.toString() ?? '0') ?? 0.0,
                quoteVolume: double.tryParse(ticker['quote_volume']?.toString() ?? '0') ?? 0.0,
                bid: 0.0,
                ask: 0.0,
                timestamp: DateTime.now(),
              );

              return {
                'target_currency': currency,
                'last': lastPrice,
                'quote_volume': double.tryParse(ticker['quote_volume']?.toString() ?? '0') ?? 0.0,
                'volume': double.tryParse(ticker['volume']?.toString() ?? '0') ?? 0.0,
                'change': _calculateChangePercent(
                  double.tryParse(ticker['first']?.toString() ?? '0') ?? 0.0,
                  lastPrice,
                ),
              };
            }).toList();
          });

          // Subscribe to top coins WebSocket after fetching
          _subscribeToTopCoins();
        }
      }
    } catch (e) {
      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        messenger.showSnackBar(
          SnackBar(
            content: Text('Failed to fetch top coins: $e'),
            backgroundColor: ThemeConstants.errorColor,
          ),
        );
      }
    } finally {
      setState(() {
        _isLoadingTopCoins = false;
      });
    }
  }

  /// Subscribe to WebSocket for top 10 coins
  void _subscribeToTopCoins() {
    for (final coin in _topCoins) {
      final currency = coin['target_currency'] as String;

      final subscription = _balanceWsClient
          .subscribeTicker('KRW', currency)
          .listen((ticker) {
        if (mounted) {
          setState(() {
            _balanceTickers[currency] = ticker;

            // Update top coins list with new price
            final coinIndex = _topCoins.indexWhere((c) => c['target_currency'] == currency);
            if (coinIndex != -1) {
              _topCoins[coinIndex]['last'] = ticker.last;
              _topCoins[coinIndex]['change'] = ticker.changePercent;
            }
          });
        }
      });

      _tickerSubscriptions.add(subscription);
    }
  }

  double _calculateChangePercent(double first, double last) {
    if (first == 0) return 0;
    return ((last - first) / first) * 100;
  }

  /// Subscribe to WebSocket tickers for balance coins
  Future<void> _subscribeToBalanceTickers() async {
    try {
      // Get current balances before async operations
      final balanceProvider = context.read<CoinoneBalanceProvider>();
      final balances = balanceProvider.balances;

      // Connect WebSocket
      await _balanceWsClient.connect();

      // Wait a bit for connection
      await Future.delayed(const Duration(seconds: 2));

      // Subscribe to all coins with balance > 0 (except KRW)
      for (final entry in balances.entries) {
        final currency = entry.key;
        final balance = entry.value;

        if (currency != 'KRW' && balance.available > 0) {
          final subscription = _balanceWsClient
              .subscribeTicker('KRW', currency)
              .listen((ticker) {
            if (mounted) {
              setState(() {
                _balanceTickers[currency] = ticker;
              });
            }
          });

          _tickerSubscriptions.add(subscription);
        }
      }
    } catch (e) {
      print('[BalanceTab] Failed to subscribe to tickers: $e');
    }
  }

  /// Get total portfolio value in KRW
  double _getTotalPortfolioValue() {
    final balanceProvider = context.read<CoinoneBalanceProvider>();
    final balances = balanceProvider.balances;

    double total = 0.0;

    // Add KRW balance
    final krwBalance = balances['KRW'];
    if (krwBalance != null) {
      total += krwBalance.available;
    }

    // Add value of all coins
    for (final entry in balances.entries) {
      final currency = entry.key;
      final balance = entry.value;

      if (currency != 'KRW' && balance.available > 0) {
        final ticker = _balanceTickers[currency];
        if (ticker != null) {
          total += balance.available * ticker.last;
        }
      }
    }

    return total;
  }

  Future<void> _logout() async {
    final authProvider = context.read<AuthProvider>();

    // Stop trading bot if running
    final tradingProvider = context.read<CoinoneTradingProvider>();
    if (tradingProvider.isBotRunning) {
      await tradingProvider.stopBot();
    }

    // Stop balance monitoring
    context.read<CoinoneBalanceProvider>().stopMonitoring();

    // Logout
    await authProvider.logout();

    if (!mounted) return;

    // Navigate to login screen
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (context) => const LoginScreenNew()),
    );
  }

  void _navigateToWithdrawal() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => const CoinoneWithdrawalScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Coinone 현물 거래'),
        backgroundColor: ThemeConstants.primaryColor,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '💰 잔고', icon: Icon(Icons.account_balance_wallet)),
            Tab(text: '📊 거래', icon: Icon(Icons.show_chart)),
          ],
        ),
        actions: [
          // Withdrawal button
          IconButton(
            icon: const Icon(Icons.send),
            tooltip: '출금',
            onPressed: _navigateToWithdrawal,
          ),
          // Logout button
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: '로그아웃',
            onPressed: _logout,
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildBalanceTab(),
          _buildTradingTab(),
        ],
      ),
    );
  }

  // ============================================================================
  // Balance Tab - Shows all holdings (KRW + all coins with balance > 0)
  // ============================================================================

  Widget _buildBalanceTab() {
    return Consumer<CoinoneBalanceProvider>(
      builder: (context, provider, child) {
        final allBalances = provider.balances;

        // Filter: KRW (always shown) + coins with available > 0
        final displayBalances = <String, CoinoneBalance>{};

        // Always add KRW first
        if (allBalances.containsKey('KRW')) {
          displayBalances['KRW'] = allBalances['KRW']!;
        }

        // Add all other coins with available > 0
        allBalances.forEach((currency, balance) {
          if (currency != 'KRW' && balance.available > 0) {
            displayBalances[currency] = balance;
          }
        });

        return RefreshIndicator(
          onRefresh: () => provider.fetchBalance(),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(ThemeConstants.spacingMedium),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header with total portfolio value
                Card(
                  elevation: 4,
                  child: Padding(
                    padding: const EdgeInsets.all(ThemeConstants.spacingMedium),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              '💰 보유 자산',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (provider.isLoading)
                              const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                          ],
                        ),
                        const SizedBox(height: ThemeConstants.spacingMedium),
                        const Divider(),
                        const SizedBox(height: ThemeConstants.spacingSmall),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              '총 평가액',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey,
                              ),
                            ),
                            Text(
                              '${_getTotalPortfolioValue().toStringAsFixed(0)} 원',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: ThemeConstants.primaryColor,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: ThemeConstants.spacingMedium),

                // Balance list
                if (provider.errorMessage != null)
                  Card(
                    elevation: 2,
                    color: ThemeConstants.errorColor.withOpacity(0.1),
                    child: Padding(
                      padding: const EdgeInsets.all(ThemeConstants.spacingMedium),
                      child: Text(
                        provider.errorMessage!,
                        style: const TextStyle(color: ThemeConstants.errorColor),
                      ),
                    ),
                  )
                else if (displayBalances.isEmpty)
                  const Card(
                    elevation: 2,
                    child: Padding(
                      padding: EdgeInsets.all(ThemeConstants.spacingLarge),
                      child: Center(
                        child: Text(
                          '보유 자산이 없습니다',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    ),
                  )
                else
                  ...displayBalances.entries.map((entry) {
                    final currency = entry.key;
                    final balance = entry.value;

                    return _buildBalanceCard(currency, balance);
                  }).toList(),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBalanceCard(String currency, CoinoneBalance balance) {
    final isKRW = currency == 'KRW';
    final ticker = _balanceTickers[currency];
    final currentPrice = ticker?.last ?? 0.0;
    final krwValue = isKRW ? balance.available : (balance.available * currentPrice);
    final changePercent = ticker?.changePercent ?? 0.0;

    // Calculate profit/loss
    final averagePrice = balance.averagePrice ?? 0.0;
    final profitLossPercent = averagePrice > 0 && currentPrice > 0
        ? ((currentPrice - averagePrice) / averagePrice) * 100
        : 0.0;
    final profitLossAmount = averagePrice > 0 && currentPrice > 0
        ? (currentPrice - averagePrice) * balance.available
        : 0.0;

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: ThemeConstants.spacingSmall),
      child: Padding(
        padding: const EdgeInsets.all(ThemeConstants.spacingMedium),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isKRW
                            ? ThemeConstants.primaryColor.withOpacity(0.1)
                            : ThemeConstants.successColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        isKRW ? '💵' : '🪙',
                        style: const TextStyle(fontSize: 20),
                      ),
                    ),
                    const SizedBox(width: ThemeConstants.spacingSmall),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          currency,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (!isKRW && ticker != null) ...[
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Text(
                                '${currentPrice.toStringAsFixed(currentPrice > 1000 ? 0 : 2)} 원',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: changePercent >= 0
                                      ? ThemeConstants.successColor.withOpacity(0.2)
                                      : ThemeConstants.errorColor.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '${changePercent >= 0 ? '+' : ''}${changePercent.toStringAsFixed(2)}%',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: changePercent >= 0
                                        ? ThemeConstants.successColor
                                        : ThemeConstants.errorColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (isKRW)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: ThemeConstants.primaryColor.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          '원화',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: ThemeConstants.primaryColor,
                          ),
                        ),
                      )
                    else if (ticker != null)
                      Text(
                        '≈ ${krwValue.toStringAsFixed(0)} 원',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: ThemeConstants.primaryColor,
                        ),
                      )
                    else
                      const Text(
                        '시세 로딩중...',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                        ),
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: ThemeConstants.spacingSmall),
            const Divider(height: 1),
            const SizedBox(height: ThemeConstants.spacingSmall),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '사용가능',
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                ),
                Text(
                  isKRW
                      ? '${balance.available.toStringAsFixed(0)} 원'
                      : balance.available.toStringAsFixed(8),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            if (balance.balance != balance.available) ...[
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '총 잔고',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  Text(
                    isKRW
                        ? '${balance.balance.toStringAsFixed(0)} 원'
                        : balance.balance.toStringAsFixed(8),
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ],

            // Show profit/loss for non-KRW coins
            if (!isKRW && averagePrice > 0 && ticker != null) ...[
              const SizedBox(height: ThemeConstants.spacingSmall),
              const Divider(height: 1),
              const SizedBox(height: ThemeConstants.spacingSmall),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '평균 매수가',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  Text(
                    '${averagePrice.toStringAsFixed(averagePrice > 1000 ? 0 : 2)} 원',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Text(
                        '수익률',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: profitLossPercent >= 0
                              ? ThemeConstants.successColor.withOpacity(0.2)
                              : ThemeConstants.errorColor.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${profitLossPercent >= 0 ? '+' : ''}${profitLossPercent.toStringAsFixed(2)}%',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: profitLossPercent >= 0
                                ? ThemeConstants.successColor
                                : ThemeConstants.errorColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    '${profitLossAmount >= 0 ? '+' : ''}${profitLossAmount.toStringAsFixed(0)} 원',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: profitLossAmount >= 0
                          ? ThemeConstants.successColor
                          : ThemeConstants.errorColor,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ============================================================================
  // Trading Tab - Shows top 10 coins by volume + bot controls
  // ============================================================================

  Widget _buildTradingTab() {
    return RefreshIndicator(
      onRefresh: () => _fetchTopCoinsByVolume(),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(ThemeConstants.spacingMedium),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top coins by volume
            _buildTopCoinsCard(),
            const SizedBox(height: ThemeConstants.spacingMedium),

            // Trading controls
            _buildTradingControls(),
            const SizedBox(height: ThemeConstants.spacingMedium),

            // Bollinger Bands
            _buildBollingerBandsCard(),
            const SizedBox(height: ThemeConstants.spacingMedium),

            // Market Data
            _buildMarketDataCard(),
            const SizedBox(height: ThemeConstants.spacingMedium),

            // Active/Pending Orders
            _buildActiveOrdersCard(),
            const SizedBox(height: ThemeConstants.spacingMedium),

            // Order History
            _buildOrderHistoryCard(),
            const SizedBox(height: ThemeConstants.spacingMedium),

            // Trade Logs
            _buildTradeLogsCard(),

            // Buy/Sell UI
            _buildOrderPanel(),
            const SizedBox(height: ThemeConstants.spacingMedium),
          ],
        ),
      ),
    );
  }

  Widget _buildTopCoinsCard() {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(ThemeConstants.spacingMedium),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: () {
                setState(() {
                  _isTopCoinsExpanded = !_isTopCoinsExpanded;
                });
              },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '📈 거래량 상위 10개 코인',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Row(
                    children: [
                      if (_isLoadingTopCoins)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      const SizedBox(width: 8),
                      Icon(
                        _isTopCoinsExpanded
                            ? Icons.expand_less
                            : Icons.expand_more,
                        color: Colors.grey,
                      ),
                    ],
                  ),
                ],
              ),
            ),

            if (_isTopCoinsExpanded) ...[
              const SizedBox(height: ThemeConstants.spacingSmall),

              if (_topCoins.isEmpty && !_isLoadingTopCoins)
                const Text(
                  '데이터를 불러오는 중...',
                  style: TextStyle(color: Colors.grey),
                )
              else
                ..._topCoins.map((coin) {
                final symbol = coin['target_currency'] as String;
                final price = coin['last'] as double;
                final volume = coin['quote_volume'] as double;
                final change = coin['change'] as double;

                return Consumer<CoinoneTradingProvider>(
                  builder: (context, provider, child) {
                    final isSelected = provider.symbol == symbol;

                    return InkWell(
                      onTap: () {
                        if (!provider.isBotRunning) {
                          provider.setSymbol(symbol);
                        }
                      },
                      child: Container(
                        margin: const EdgeInsets.only(
                          bottom: ThemeConstants.spacingSmall,
                        ),
                        padding: const EdgeInsets.all(ThemeConstants.spacingSmall),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? ThemeConstants.primaryColor.withOpacity(0.1)
                              : Colors.grey[100],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isSelected
                                ? ThemeConstants.primaryColor
                                : Colors.grey[300]!,
                            width: isSelected ? 2 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            // Symbol
                            Expanded(
                              flex: 2,
                              child: Text(
                                symbol,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                            ),
                            // Price
                            Expanded(
                              flex: 3,
                              child: Text(
                                '${price.toStringAsFixed(price > 1000 ? 0 : 2)} 원',
                                style: const TextStyle(fontSize: 12),
                                textAlign: TextAlign.right,
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Change
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: change >= 0
                                    ? ThemeConstants.successColor.withOpacity(0.2)
                                    : ThemeConstants.errorColor.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '${change >= 0 ? '+' : ''}${change.toStringAsFixed(2)}%',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: change >= 0
                                      ? ThemeConstants.successColor
                                      : ThemeConstants.errorColor,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Volume (in millions)
                            Text(
                              '${(volume / 1000000).toStringAsFixed(1)}M',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              }).toList(),
            ], // Close if (_isTopCoinsExpanded)
          ],
        ),
      ),
    );
  }

  Widget _buildTradingControls() {
    return Consumer<CoinoneTradingProvider>(
      builder: (context, provider, child) {
        return Card(
          elevation: 4,
          child: Padding(
            padding: const EdgeInsets.all(ThemeConstants.spacingMedium),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Text(
                      '선택된 코인:',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: ThemeConstants.spacingSmall),
                    Text(
                      provider.symbol,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: ThemeConstants.primaryColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: ThemeConstants.spacingMedium),

                // Bot settings
                if (!provider.isBotRunning) ...[
                  Container(
                    padding: const EdgeInsets.all(ThemeConstants.spacingMedium),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue[200]!),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.settings, size: 16, color: Colors.blue),
                            SizedBox(width: 4),
                            Text(
                              '봇 설정',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: ThemeConstants.spacingSmall),

                        // Use all KRW balance checkbox
                        CheckboxListTile(
                          title: const Text(
                            '보유 원화 전체 사용',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                          subtitle: const Text(
                            '체크 시 보유한 KRW 전체로 매수 (99%)',
                            style: TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                          value: provider.useAllKrwBalance,
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          onChanged: (bool? value) {
                            if (value != null) {
                              provider.setUseAllKrwBalance(value);
                            }
                          },
                        ),
                        const SizedBox(height: ThemeConstants.spacingSmall),

                        // Order amount input field
                        TextField(
                          decoration: const InputDecoration(
                            labelText: '주문 금액 (KRW)',
                            hintText: '예: 50000 (5만원)',
                            prefixIcon: Icon(Icons.attach_money),
                            suffixText: 'KRW',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          keyboardType: const TextInputType.numberWithOptions(decimal: false),
                          controller: _orderAmountController,
                          enabled: !provider.useAllKrwBalance, // Disable when using all balance
                          onChanged: (value) {
                            final amount = double.tryParse(value);
                            if (amount != null && amount > 0) {
                              provider.setOrderKrwAmount(amount);
                            }
                          },
                        ),
                        const SizedBox(height: ThemeConstants.spacingSmall),
                        Text(
                          provider.useAllKrwBalance
                              ? '💡 전체 잔고로 매수됩니다 (99%)'
                              : '💡 시장가 매수는 KRW 금액 입력, 매도는 전량 매도됩니다\n최소 주문: 10,000원',
                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: ThemeConstants.spacingMedium),
                ],

                // Bot control buttons
                if (provider.isLoading)
                  const Center(child: CircularProgressIndicator())
                else ...[
                  // Test trade button
                  if (!provider.isBotRunning)
                    ElevatedButton.icon(
                      onPressed: provider.isTestTrading
                          ? () => provider.cancelTestTrade()
                          : () => provider.executeTestTrade(),
                      icon: Icon(provider.isTestTrading ? Icons.stop : Icons.science),
                      label: Text(
                        provider.isTestTrading ? '테스트 매매 취소' : '🧪 테스트 매매',
                        style: const TextStyle(fontSize: 16),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: provider.isTestTrading
                            ? Colors.orange
                            : Colors.purple,
                        padding: const EdgeInsets.symmetric(
                          vertical: ThemeConstants.spacingMedium,
                        ),
                      ),
                    ),

                  if (!provider.isBotRunning)
                    const SizedBox(height: ThemeConstants.spacingSmall),

                  // Bot control button
                  ElevatedButton.icon(
                    onPressed: provider.isBotRunning
                        ? () => provider.stopBot()
                        : () => provider.startBot(),
                    icon: Icon(provider.isBotRunning ? Icons.stop : Icons.play_arrow),
                    label: Text(
                      provider.isBotRunning ? '자동매매 봇 중지' : '자동매매 봇 시작',
                      style: const TextStyle(fontSize: 16),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: provider.isBotRunning
                          ? ThemeConstants.errorColor
                          : ThemeConstants.successColor,
                      padding: const EdgeInsets.symmetric(
                        vertical: ThemeConstants.spacingMedium,
                      ),
                    ),
                  ),
                ],

                if (provider.errorMessage != null) ...[
                  const SizedBox(height: ThemeConstants.spacingSmall),
                  Text(
                    provider.errorMessage!,
                    style: const TextStyle(
                      color: ThemeConstants.errorColor,
                      fontSize: 12,
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

  // ============================================================================
  // Order Panel - Buy/Sell with KRW amount or coin quantity
  // ============================================================================

  Widget _buildOrderPanel() {
    return Consumer<CoinoneTradingProvider>(
      builder: (context, provider, child) {
        return Card(
          elevation: 4,
          child: Padding(
            padding: const EdgeInsets.all(ThemeConstants.spacingMedium),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '💸 수동 주문',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: ThemeConstants.spacingMedium),

                // Buy/Sell selector
                Row(
                  children: [
                    Expanded(
                      child: RadioListTile<String>(
                        title: const Text('매수'),
                        value: 'buy',
                        groupValue: provider.orderSide,
                        onChanged: provider.isBotRunning
                            ? null
                            : (value) {
                                if (value != null) {
                                  provider.setOrderSide(value);
                                }
                              },
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    Expanded(
                      child: RadioListTile<String>(
                        title: const Text('매도'),
                        value: 'sell',
                        groupValue: provider.orderSide,
                        onChanged: provider.isBotRunning
                            ? null
                            : (value) {
                                if (value != null) {
                                  provider.setOrderSide(value);
                                }
                              },
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: ThemeConstants.spacingSmall),

                // Order type selector (Market vs Limit)
                Row(
                  children: [
                    Expanded(
                      child: RadioListTile<bool>(
                        title: const Text('시장가'),
                        value: true,
                        groupValue: provider.useMarketOrder,
                        onChanged: provider.isBotRunning
                            ? null
                            : (value) {
                                if (value != null) {
                                  provider.setUseMarketOrder(value);
                                }
                              },
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    Expanded(
                      child: RadioListTile<bool>(
                        title: const Text('지정가'),
                        value: false,
                        groupValue: provider.useMarketOrder,
                        onChanged: provider.isBotRunning
                            ? null
                            : (value) {
                                if (value != null) {
                                  provider.setUseMarketOrder(value);
                                }
                              },
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: ThemeConstants.spacingSmall),

                // Input fields based on order type and side
                if (!provider.useMarketOrder) ...[
                  // Limit order: show price input
                  Row(
                    children: [
                      const Text(
                        '주문 가격:',
                        style: TextStyle(fontSize: 14),
                      ),
                      const SizedBox(width: ThemeConstants.spacingSmall),
                      Expanded(
                        child: TextField(
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            hintText: provider.currentTicker?.last.toString() ?? '0',
                            suffix: const Text('원'),
                            border: const OutlineInputBorder(),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: ThemeConstants.spacingSmall,
                              vertical: ThemeConstants.spacingSmall,
                            ),
                          ),
                          onChanged: (value) {
                            final price = double.tryParse(value);
                            if (price != null) {
                              provider.setOrderPrice(price);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: ThemeConstants.spacingSmall),
                ],

                // Amount input
                if (provider.useMarketOrder && provider.orderSide == 'buy') ...[
                  // Market buy: KRW amount
                  Row(
                    children: [
                      const Text(
                        '주문 금액:',
                        style: TextStyle(fontSize: 14),
                      ),
                      const SizedBox(width: ThemeConstants.spacingSmall),
                      Expanded(
                        child: TextField(
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            hintText: provider.orderKrwAmount.toString(),
                            suffix: const Text('원'),
                            border: const OutlineInputBorder(),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: ThemeConstants.spacingSmall,
                              vertical: ThemeConstants.spacingSmall,
                            ),
                          ),
                          onChanged: (value) {
                            final amount = double.tryParse(value);
                            if (amount != null) {
                              provider.setOrderKrwAmount(amount);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  // Market sell or limit order: coin quantity
                  Row(
                    children: [
                      const Text(
                        '주문 수량:',
                        style: TextStyle(fontSize: 14),
                      ),
                      const SizedBox(width: ThemeConstants.spacingSmall),
                      Expanded(
                        child: TextField(
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            hintText: provider.orderQuantity.toString(),
                            suffix: Text(provider.symbol),
                            border: const OutlineInputBorder(),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: ThemeConstants.spacingSmall,
                              vertical: ThemeConstants.spacingSmall,
                            ),
                          ),
                          onChanged: (value) {
                            final quantity = double.tryParse(value);
                            if (quantity != null) {
                              provider.setOrderQuantity(quantity);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: ThemeConstants.spacingMedium),

                // Submit button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: provider.isBotRunning || provider.isLoading
                        ? null
                        : () async {
                            // Calculate quantity for market buy
                            double quantity = provider.orderQuantity;
                            if (provider.useMarketOrder && provider.orderSide == 'buy') {
                              final currentPrice = provider.currentTicker?.last ?? 0;
                              if (currentPrice > 0) {
                                quantity = provider.orderKrwAmount / currentPrice;
                              }
                            }

                            await provider.placeManualOrder(
                              side: provider.orderSide,
                              quantity: quantity,
                              price: provider.useMarketOrder
                                  ? null
                                  : provider.orderPrice,
                            );

                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('${provider.orderSide == 'buy' ? '매수' : '매도'} 주문 제출 완료'),
                                  backgroundColor: provider.orderSide == 'buy'
                                      ? ThemeConstants.successColor
                                      : ThemeConstants.errorColor,
                                ),
                              );
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: provider.orderSide == 'buy'
                          ? ThemeConstants.successColor
                          : ThemeConstants.errorColor,
                      padding: const EdgeInsets.symmetric(
                        vertical: ThemeConstants.spacingMedium,
                      ),
                    ),
                    child: Text(
                      provider.orderSide == 'buy' ? '매수 주문' : '매도 주문',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBollingerBandsCard() {
    return Consumer<CoinoneTradingProvider>(
      builder: (context, provider, child) {
        final indicators = provider.technicalIndicators;

        if (indicators == null) {
          return Card(
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(ThemeConstants.spacingMedium),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '📊 기술적 지표',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: ThemeConstants.spacingSmall),
                  const Text(
                    '데이터 로딩 중...',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            ),
          );
        }

        return Card(
          elevation: 4,
          child: Padding(
            padding: const EdgeInsets.all(ThemeConstants.spacingMedium),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      '📊 기술적 지표',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: indicators.isUptrend ? Colors.green[100] : Colors.red[100],
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        indicators.trendDescription,
                        style: TextStyle(
                          fontSize: 12,
                          color: indicators.isUptrend ? Colors.green[800] : Colors.red[800],
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: ThemeConstants.spacingMedium),

                // RSI
                _buildIndicatorSection(
                  '📈 RSI (14)',
                  indicators.rsi.toStringAsFixed(2),
                  indicators.rsiStatus,
                  indicators.rsi < 30
                      ? ThemeConstants.successColor
                      : indicators.rsi > 70
                          ? ThemeConstants.errorColor
                          : Colors.grey,
                ),

                const Divider(),

                // EMA
                const Text(
                  'EMA (지수이동평균)',
                  style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                _buildIndicatorRow('EMA9', indicators.ema9, Colors.purple),
                _buildIndicatorRow('EMA21', indicators.ema21, Colors.blue),
                _buildIndicatorRow('EMA50', indicators.ema50, Colors.orange),
                _buildIndicatorRow('EMA200', indicators.ema200, Colors.red),

                const Divider(),

                // Bollinger Bands
                const Text(
                  'Bollinger Bands',
                  style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                _buildIndicatorRow('상단', indicators.bollingerUpper, ThemeConstants.errorColor),
                _buildIndicatorRow('중간', indicators.bollingerMiddle, Colors.blue),
                _buildIndicatorRow('하단', indicators.bollingerLower, ThemeConstants.successColor),
                const SizedBox(height: 4),
                Text(
                  '위치: ${indicators.bollingerPosition}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),

                const Divider(),

                // Current Price
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      '현재가',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '${indicators.currentPrice.toStringAsFixed(2)} KRW',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildIndicatorSection(String label, String value, String status, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: color),
              ),
              child: Text(
                status,
                style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildIndicatorRow(String label, double value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 13, color: color),
          ),
          Text(
            value.toStringAsFixed(2),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBandRow(String label, double value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 14, color: color),
          ),
          Text(
            value.toStringAsFixed(2),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMarketDataCard() {
    return Consumer<CoinoneTradingProvider>(
      builder: (context, provider, child) {
        // Try to get ticker from WebSocket first, fallback to provider
        final ticker = _balanceTickers[provider.symbol] ?? provider.currentTicker;

        return Card(
          elevation: 4,
          child: Padding(
            padding: const EdgeInsets.all(ThemeConstants.spacingMedium),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      '📈 실시간 시세',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      provider.symbol,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: ThemeConstants.primaryColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: ThemeConstants.spacingSmall),

                if (ticker == null)
                  const Text(
                    '시세 로딩중...',
                    style: TextStyle(color: Colors.grey),
                  )
                else ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('현재가', style: TextStyle(fontSize: 14)),
                      Text(
                        '${ticker.last.toStringAsFixed(2)} 원',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('변동률', style: TextStyle(fontSize: 14)),
                      Text(
                        '${ticker.changePercent.toStringAsFixed(2)}%',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: ticker.changePercent >= 0
                              ? ThemeConstants.successColor
                              : ThemeConstants.errorColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('거래량', style: TextStyle(fontSize: 14)),
                      Text(
                        ticker.volume.toStringAsFixed(2),
                        style: const TextStyle(fontSize: 14),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildOrderHistoryCard() {
    return Consumer<CoinoneTradingProvider>(
      builder: (context, provider, child) {
        final orders = provider.orderHistory;

        return Card(
          elevation: 4,
          child: Padding(
            padding: const EdgeInsets.all(ThemeConstants.spacingMedium),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      '📋 주문 내역',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (orders.isNotEmpty)
                      TextButton(
                        onPressed: () => provider.clearOrderHistory(),
                        child: const Text('전체 삭제'),
                      ),
                  ],
                ),
                const SizedBox(height: ThemeConstants.spacingSmall),

                if (orders.isEmpty)
                  const Text(
                    '주문 내역이 없습니다',
                    style: TextStyle(color: Colors.grey),
                  )
                else
                  ...orders.take(5).map((order) => _buildOrderItem(order)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildActiveOrdersCard() {
    return Consumer<CoinoneTradingProvider>(
      builder: (context, provider, child) {
        // Filter for active orders (placed, partially filled)
        final activeOrders = provider.orderHistory
            .where((order) => order.status == 'placed' || order.status == 'partial_filled')
            .toList();

        return Card(
          elevation: 4,
          child: Padding(
            padding: const EdgeInsets.all(ThemeConstants.spacingMedium),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      '⏳ 미체결 주문',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    TextButton(
                      onPressed: provider.isLoading
                          ? null
                          : () async {
                              await provider.refreshOrderHistory();
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('미체결 주문 목록을 새로고침했습니다'),
                                    duration: Duration(seconds: 1),
                                  ),
                                );
                              }
                            },
                      child: provider.isLoading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('새로고침'),
                    ),
                  ],
                ),
                const SizedBox(height: ThemeConstants.spacingSmall),

                if (activeOrders.isEmpty)
                  const Text(
                    '미체결 주문이 없습니다',
                    style: TextStyle(color: Colors.grey),
                  )
                else
                  ...activeOrders.map((order) => _buildActiveOrderItem(order)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildActiveOrderItem(CoinoneOrder order) {
    return Container(
      margin: const EdgeInsets.only(bottom: ThemeConstants.spacingSmall),
      padding: const EdgeInsets.all(ThemeConstants.spacingSmall),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(
                    order.side.toUpperCase(),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: order.side.toLowerCase() == 'buy'
                          ? ThemeConstants.successColor
                          : ThemeConstants.errorColor,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.orange[100],
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      order.type.toUpperCase(),
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              Consumer<CoinoneTradingProvider>(
                builder: (context, provider, _) {
                  return IconButton(
                    icon: const Icon(Icons.cancel, size: 20),
                    color: ThemeConstants.errorColor,
                    onPressed: provider.isBotRunning || provider.isLoading
                        ? null
                        : () async {
                            // Cancel order
                            if (order.userOrderId != null) {
                              await provider.cancelOrder(order.userOrderId!);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('주문 취소 완료'),
                                  ),
                                );
                              }
                            }
                          },
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '가격: ${order.price.toStringAsFixed(0)} 원',
            style: const TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '수량: ${order.quantity.toStringAsFixed(4)}',
                style: const TextStyle(fontSize: 12),
              ),
              Text(
                '미체결: ${order.remainingQuantity.toStringAsFixed(4)}',
                style: const TextStyle(fontSize: 12, color: Colors.orange),
              ),
            ],
          ),
          if (order.filledQuantity > 0) ...[
            const SizedBox(height: 2),
            LinearProgressIndicator(
              value: order.fillPercentage / 100,
              backgroundColor: Colors.grey[300],
              valueColor: AlwaysStoppedAnimation<Color>(
                order.side.toLowerCase() == 'buy'
                    ? ThemeConstants.successColor
                    : ThemeConstants.errorColor,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '체결률: ${order.fillPercentage.toStringAsFixed(1)}%',
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildOrderItem(order) {
    return Container(
      margin: const EdgeInsets.only(bottom: ThemeConstants.spacingSmall),
      padding: const EdgeInsets.all(ThemeConstants.spacingSmall),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                order.side.toUpperCase(),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: order.side == 'buy'
                      ? ThemeConstants.successColor
                      : ThemeConstants.errorColor,
                ),
              ),
              Text(
                order.status,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '가격: ${order.price.toStringAsFixed(2)} | 수량: ${order.quantity.toStringAsFixed(4)}',
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildTradeLogsCard() {
    return Consumer<CoinoneTradingProvider>(
      builder: (context, provider, child) {
        return Card(
          elevation: 4,
          child: Padding(
            padding: const EdgeInsets.all(ThemeConstants.spacingMedium),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      '📝 거래 로그',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    TextButton(
                      onPressed: () => provider.clearTradeLogs(),
                      child: const Text('전체 삭제'),
                    ),
                  ],
                ),
                const SizedBox(height: ThemeConstants.spacingSmall),

                FutureBuilder<List<Map<String, dynamic>>>(
                  future: provider.getTradeLogs(limit: 10),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Text(
                        '로그 로딩 중...',
                        style: TextStyle(color: Colors.grey),
                      );
                    }

                    final logs = snapshot.data!;

                    if (logs.isEmpty) {
                      return const Text(
                        '로그가 없습니다',
                        style: TextStyle(color: Colors.grey),
                      );
                    }

                    return Column(
                      children: logs.map((log) => _buildLogItem(log)).toList(),
                    );
                  },
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
    Color color;

    switch (type) {
      case 'success':
        color = ThemeConstants.successColor;
        break;
      case 'error':
        color = ThemeConstants.errorColor;
        break;
      default:
        color = Colors.grey;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: ThemeConstants.spacingSmall),
      padding: const EdgeInsets.all(ThemeConstants.spacingSmall),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        log['message'] as String,
        style: TextStyle(fontSize: 12, color: color),
      ),
    );
  }
}
