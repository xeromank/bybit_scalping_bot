import 'package:flutter/material.dart';
import 'package:bybit_scalping_bot/screens/login_screen.dart';
import 'package:bybit_scalping_bot/screens/trading_screen.dart';
import 'package:bybit_scalping_bot/services/secure_storage_service.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bybit Scalping Bot',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.orange),
        useMaterial3: true,
      ),
      home: const SplashScreen(),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final _secureStorage = SecureStorageService();

  @override
  void initState() {
    super.initState();
    _checkCredentials();
  }

  Future<void> _checkCredentials() async {
    await Future.delayed(const Duration(seconds: 1));

    final credentials = await _secureStorage.getCredentials();

    if (mounted) {
      if (credentials != null) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => TradingScreen(
              apiKey: credentials['apiKey']!,
              apiSecret: credentials['apiSecret']!,
            ),
          ),
        );
      } else {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => const LoginScreen(),
          ),
        );
      }
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
              color: Colors.orange,
            ),
            SizedBox(height: 24),
            Text(
              'Bybit Scalping Bot',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 24),
            CircularProgressIndicator(
              color: Colors.orange,
            ),
          ],
        ),
      ),
    );
  }
}
