import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:bybit_scalping_bot/services/bybit_api_client.dart';
import 'package:bybit_scalping_bot/services/bybit_public_websocket_client.dart';
import 'package:bybit_scalping_bot/services/bybit_websocket_client.dart';
import 'package:bybit_scalping_bot/services/secure_storage_service.dart';
import 'package:bybit_scalping_bot/repositories/bybit_repository.dart';
import 'package:bybit_scalping_bot/repositories/credential_repository.dart';
import 'package:bybit_scalping_bot/providers/auth_provider.dart';
import 'package:bybit_scalping_bot/providers/bybit_trading_provider.dart';
import 'package:bybit_scalping_bot/screens/bybit_login_screen.dart';
import 'package:bybit_scalping_bot/screens/bybit_trading_screen.dart';
import 'package:bybit_scalping_bot/constants/theme_constants.dart';
import 'package:bybit_scalping_bot/constants/app_constants.dart';

// Coinone imports
import 'package:bybit_scalping_bot/services/coinone/coinone_api_client.dart';
import 'package:bybit_scalping_bot/services/coinone/coinone_websocket_client.dart';
import 'package:bybit_scalping_bot/repositories/coinone_repository.dart';
import 'package:bybit_scalping_bot/providers/coinone_balance_provider.dart';
import 'package:bybit_scalping_bot/providers/coinone_trading_provider.dart';
import 'package:bybit_scalping_bot/providers/coinone_withdrawal_provider.dart';
import 'package:bybit_scalping_bot/screens/coinone_trading_screen.dart';
import 'package:bybit_scalping_bot/core/enums/exchange_type.dart';

// Live Chart imports
import 'package:bybit_scalping_bot/providers/live_chart_provider.dart';
import 'package:bybit_scalping_bot/screens/live_chart_screen.dart';

/// Main entry point for the refactored application
///
/// This file demonstrates proper dependency injection and follows
/// SOLID principles, particularly Dependency Inversion.
///
/// Architecture:
/// - Services layer (bottom): Low-level implementations
/// - Repository layer: Data access abstraction
/// - Provider layer: Business logic and state management
/// - UI layer (top): Presentation
///
/// Dependencies flow from top to bottom, but abstractions
/// flow from bottom to top (Dependency Inversion Principle).
void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Create services (infrastructure layer)
    final secureStorageService = SecureStorageService();
    final credentialRepository = CredentialRepository(
      storageService: secureStorageService,
    );

    // Shared WebSocket clients (created once per authentication session)
    BybitPublicWebSocketClient? sharedPublicWsClient;
    BybitWebSocketClient? sharedPrivateWsClient;
    CoinoneWebSocketClient? sharedCoinoneWsClient;

    return MultiProvider(
      providers: [
        // Live Chart Provider (실시간 차트 - 인증 불필요)
        ChangeNotifierProvider(
          create: (context) => LiveChartProvider(),
        ),

        // Auth Provider (manages authentication state)
        ChangeNotifierProvider(
          create: (context) => AuthProvider(
            credentialRepository: credentialRepository,
            createBybitRepository: (credentials) {
              final apiClient = BybitApiClient(
                apiKey: credentials.apiKey,
                apiSecret: credentials.apiSecret,
              );
              return BybitRepository(apiClient: apiClient);
            },
          ),
        ),

        // Bybit Trading Provider (new adaptive strategy system)
        ChangeNotifierProxyProvider<AuthProvider, BybitTradingProvider?>(
          create: (context) => null,
          update: (context, authProvider, previous) {
            if (authProvider.isAuthenticated &&
                authProvider.credentials != null &&
                authProvider.currentExchange == ExchangeType.bybit) {
              // Reuse previous provider to preserve state
              if (previous != null) {
                return previous;
              }

              // Create new provider
              final apiClient = BybitApiClient(
                apiKey: authProvider.credentials!.apiKey,
                apiSecret: authProvider.credentials!.apiSecret,
              );
              final repository = BybitRepository(apiClient: apiClient);

              // Create or reuse public WebSocket client (for kline data)
              sharedPublicWsClient ??= BybitPublicWebSocketClient(
                isTestnet: false,
              );

              // Create or reuse private WebSocket client (for position updates)
              sharedPrivateWsClient ??= BybitWebSocketClient(
                apiKey: authProvider.credentials!.apiKey,
                apiSecret: authProvider.credentials!.apiSecret,
                isTestnet: false,
              );

              return BybitTradingProvider(
                repository: repository,
                publicWsClient: sharedPublicWsClient!,
                privateWsClient: sharedPrivateWsClient!,
              );
            } else {
              // Disconnect WebSocket when logged out
              sharedPublicWsClient?.disconnect();
              sharedPublicWsClient = null;
              sharedPrivateWsClient?.disconnect();
              sharedPrivateWsClient = null;
            }
            return null;
          },
        ),

        // ============================================================================
        // Coinone Providers (for spot trading)
        // ============================================================================

        // Coinone Balance Provider
        ChangeNotifierProxyProvider<AuthProvider, CoinoneBalanceProvider?>(
          create: (context) => null,
          update: (context, authProvider, previous) {
            if (authProvider.isAuthenticated &&
                authProvider.credentials != null &&
                authProvider.currentExchange == ExchangeType.coinone) {
              final apiClient = CoinoneApiClient(
                apiKey: authProvider.credentials!.apiKey,
                apiSecret: authProvider.credentials!.apiSecret,
              );
              final repository = CoinoneRepository(apiClient: apiClient);

              return previous ?? CoinoneBalanceProvider(repository: repository);
            }
            return null;
          },
        ),

        // Coinone Trading Provider
        ChangeNotifierProxyProvider<AuthProvider, CoinoneTradingProvider?>(
          create: (context) => null,
          update: (context, authProvider, previous) {
            if (authProvider.isAuthenticated &&
                authProvider.credentials != null &&
                authProvider.currentExchange == ExchangeType.coinone) {
              final apiClient = CoinoneApiClient(
                apiKey: authProvider.credentials!.apiKey,
                apiSecret: authProvider.credentials!.apiSecret,
              );
              final repository = CoinoneRepository(apiClient: apiClient);

              // Reuse or create WebSocket client
              sharedCoinoneWsClient ??= CoinoneWebSocketClient();

              return previous ??
                  CoinoneTradingProvider(
                    repository: repository,
                    wsClient: sharedCoinoneWsClient!,
                  );
            } else {
              // Disconnect WebSocket when logged out
              sharedCoinoneWsClient?.disconnect();
              sharedCoinoneWsClient = null;
            }
            return null;
          },
        ),

        // Coinone Withdrawal Provider
        ChangeNotifierProxyProvider<AuthProvider, CoinoneWithdrawalProvider?>(
          create: (context) => null,
          update: (context, authProvider, previous) {
            if (authProvider.isAuthenticated &&
                authProvider.credentials != null &&
                authProvider.currentExchange == ExchangeType.coinone) {
              final apiClient = CoinoneApiClient(
                apiKey: authProvider.credentials!.apiKey,
                apiSecret: authProvider.credentials!.apiSecret,
              );
              final repository = CoinoneRepository(apiClient: apiClient);

              final provider = previous ?? CoinoneWithdrawalProvider(repository: repository);

              // Initialize provider
              if (previous == null) {
                provider.initialize();
              }

              return provider;
            }
            return null;
          },
        ),
      ],
      child: MaterialApp(
        title: AppConstants.appName,
        debugShowCheckedModeBanner: false,
        theme: ThemeConstants.appTheme,
        home: const SplashScreen(),
      ),
    );
  }
}

/// Splash screen with automatic navigation
///
/// Responsibility: Check authentication state and navigate accordingly
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkAuthenticationState();
  }

  Future<void> _checkAuthenticationState() async {
    // Show splash for minimum duration
    await Future.delayed(AppConstants.splashScreenDuration);

    if (!mounted) return;

    final authProvider = context.read<AuthProvider>();
    await authProvider.initialize();

    if (!mounted) return;

    // Navigate based on authentication state and exchange type
    if (authProvider.isAuthenticated) {
      // Route to appropriate trading screen based on exchange
      if (authProvider.currentExchange == ExchangeType.coinone) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => const CoinoneTradingScreen(),
          ),
        );
      } else {
        // Default to Bybit
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => const BybitTradingScreen(),
          ),
        );
      }
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => const BybitLoginScreen(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.currency_bitcoin,
              size: 100,
              color: ThemeConstants.primaryColor,
            ),
            SizedBox(height: ThemeConstants.spacingLarge),
            Text(
              AppConstants.appName,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: ThemeConstants.spacingLarge),
            CircularProgressIndicator(
              color: ThemeConstants.primaryColor,
            ),
          ],
        ),
      ),
    );
  }
}
