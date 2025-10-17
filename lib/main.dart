import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:bybit_scalping_bot/services/bybit_api_client.dart';
import 'package:bybit_scalping_bot/services/bybit_websocket_client.dart';
import 'package:bybit_scalping_bot/services/bybit_public_websocket_client.dart';
import 'package:bybit_scalping_bot/services/secure_storage_service.dart';
import 'package:bybit_scalping_bot/repositories/bybit_repository.dart';
import 'package:bybit_scalping_bot/repositories/credential_repository.dart';
import 'package:bybit_scalping_bot/providers/auth_provider.dart';
import 'package:bybit_scalping_bot/providers/balance_provider.dart';
import 'package:bybit_scalping_bot/providers/trading_provider.dart';
import 'package:bybit_scalping_bot/screens/login_screen_new.dart';
import 'package:bybit_scalping_bot/screens/trading_screen_new.dart';
import 'package:bybit_scalping_bot/constants/theme_constants.dart';
import 'package:bybit_scalping_bot/constants/app_constants.dart';

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

    return MultiProvider(
      providers: [
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

        // Balance Provider (depends on auth state)
        ChangeNotifierProxyProvider<AuthProvider, BalanceProvider?>(
          create: (context) => null,
          update: (context, authProvider, previous) {
            if (authProvider.isAuthenticated &&
                authProvider.credentials != null) {
              final apiClient = BybitApiClient(
                apiKey: authProvider.credentials!.apiKey,
                apiSecret: authProvider.credentials!.apiSecret,
              );
              final repository = BybitRepository(apiClient: apiClient);

              // Create WebSocket client for real-time position updates
              final wsClient = BybitWebSocketClient(
                apiKey: authProvider.credentials!.apiKey,
                apiSecret: authProvider.credentials!.apiSecret,
                isTestnet: false,
              );

              // Create public WebSocket client for real-time ticker/kline data
              final publicWsClient = BybitPublicWebSocketClient(
                isTestnet: false,
              );

              final provider = BalanceProvider(
                repository: repository,
                wsClient: wsClient,
                publicWsClient: publicWsClient,
              );

              // Connect both WebSocket clients asynchronously
              Future.wait([
                wsClient.connect(),
                publicWsClient.connect(),
              ]).then((_) {
                // WebSocket connected, fetch balance again to subscribe to positions
                provider.fetchBalance();
              }).catchError((error) {
                // Handle connection error silently - will fallback to API
                print('WebSocket connection failed: $error');
              });

              return provider;
            }
            return null;
          },
        ),

        // Trading Provider (depends on auth state)
        ChangeNotifierProxyProvider<AuthProvider, TradingProvider?>(
          create: (context) => null,
          update: (context, authProvider, previous) {
            if (authProvider.isAuthenticated &&
                authProvider.credentials != null) {
              final apiClient = BybitApiClient(
                apiKey: authProvider.credentials!.apiKey,
                apiSecret: authProvider.credentials!.apiSecret,
              );
              final repository = BybitRepository(apiClient: apiClient);

              // Create public WebSocket client for real-time kline data
              final publicWsClient = BybitPublicWebSocketClient(
                isTestnet: false,
              );

              final tradingProvider = TradingProvider(
                repository: repository,
                publicWsClient: publicWsClient,
              );

              // Connect public WebSocket and initialize
              publicWsClient.connect().then((_) {
                // WebSocket connected, subscribe to default symbol
                tradingProvider.initialize();
              }).catchError((error) {
                print('Public WebSocket connection failed for TradingProvider: $error');
              });

              return tradingProvider;
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

    // Navigate based on authentication state
    if (authProvider.isAuthenticated) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => const TradingScreenNew(),
        ),
      );
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => const LoginScreenNew(),
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
