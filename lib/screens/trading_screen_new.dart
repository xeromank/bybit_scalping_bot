import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:bybit_scalping_bot/providers/auth_provider.dart';
import 'package:bybit_scalping_bot/providers/balance_provider.dart';
import 'package:bybit_scalping_bot/providers/trading_provider.dart';
import 'package:bybit_scalping_bot/screens/login_screen_new.dart';
import 'package:bybit_scalping_bot/widgets/trading/balance_card.dart';
import 'package:bybit_scalping_bot/widgets/trading/trading_controls.dart';
import 'package:bybit_scalping_bot/widgets/trading/log_list.dart';
import 'package:bybit_scalping_bot/constants/theme_constants.dart';
import 'package:bybit_scalping_bot/constants/app_constants.dart';

/// Trading screen using new architecture
///
/// Responsibility: Provide UI for trading operations
///
/// This screen uses the TradingProvider and BalanceProvider to display
/// trading controls, balance information, and trading logs.
class TradingScreenNew extends StatefulWidget {
  const TradingScreenNew({super.key});

  @override
  State<TradingScreenNew> createState() => _TradingScreenNewState();
}

class _TradingScreenNewState extends State<TradingScreenNew> {
  @override
  void initState() {
    super.initState();
    // Load initial balance
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<BalanceProvider>().fetchBalance();
    });
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(AppConstants.dialogLogoutTitle),
        content: const Text(AppConstants.dialogLogoutMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(AppConstants.dialogCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(AppConstants.dialogConfirm),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    // Stop bot if running
    final tradingProvider = context.read<TradingProvider>();
    if (tradingProvider.isRunning) {
      await tradingProvider.stopBot();
    }

    // Logout
    final authProvider = context.read<AuthProvider>();
    final result = await authProvider.logout();

    if (!mounted) return;

    result.when(
      success: (data) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => const LoginScreenNew(),
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

  Future<void> _refreshBalance() async {
    await context.read<BalanceProvider>().refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(AppConstants.appName),
        backgroundColor: ThemeConstants.primaryColor,
        foregroundColor: ThemeConstants.textOnPrimaryColor,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshBalance,
            tooltip: '잔고 새로고침',
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _logout,
            tooltip: '로그아웃',
          ),
        ],
      ),
      body: Column(
        children: [
          // Balance Card
          const BalanceCard(),

          // Trading Controls
          const TradingControls(),

          // Log Section Header
          const Padding(
            padding: EdgeInsets.symmetric(
              horizontal: ThemeConstants.spacingMedium,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '거래 로그',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: ThemeConstants.spacingSmall),

          // Log List
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(
                horizontal: ThemeConstants.spacingMedium,
              ),
              decoration: BoxDecoration(
                border: Border.all(
                  color: ThemeConstants.borderColor,
                ),
                borderRadius: BorderRadius.circular(
                  ThemeConstants.borderRadiusMedium,
                ),
              ),
              child: const LogList(),
            ),
          ),
          const SizedBox(height: ThemeConstants.spacingMedium),
        ],
      ),
    );
  }
}
