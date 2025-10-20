import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:bybit_scalping_bot/providers/auth_provider.dart';
import 'package:bybit_scalping_bot/core/enums/exchange_type.dart';
import 'package:bybit_scalping_bot/core/result/result.dart';
import 'package:bybit_scalping_bot/screens/bybit_trading_screen.dart';
import 'package:bybit_scalping_bot/utils/logger.dart';

/// Bybit Login Screen
///
/// Simple login screen for Bybit API credentials
class BybitLoginScreen extends StatefulWidget {
  const BybitLoginScreen({super.key});

  @override
  State<BybitLoginScreen> createState() => _BybitLoginScreenState();
}

class _BybitLoginScreenState extends State<BybitLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _apiKeyController = TextEditingController();
  final _apiSecretController = TextEditingController();

  bool _isLoading = false;
  bool _obscureSecret = true;

  @override
  void dispose() {
    _apiKeyController.dispose();
    _apiSecretController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final authProvider = context.read<AuthProvider>();
      final result = await authProvider.login(
        apiKey: _apiKeyController.text.trim(),
        apiSecret: _apiSecretController.text.trim(),
        exchange: ExchangeType.bybit,
      );

      if (!mounted) return;

      switch (result) {
        case Success(:final data):
          if (data) {
            Logger.success('Bybit 로그인 성공');

            // Navigate to trading screen
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (context) => const BybitTradingScreen(),
              ),
            );
          } else {
            _showError('로그인 실패. API 키를 확인해주세요.');
          }
        case Failure(:final message):
          _showError('로그인 실패: $message');
      }
    } catch (e) {
      Logger.error('Login error: $e');
      if (mounted) {
        _showError('로그인 중 오류가 발생했습니다: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E1E),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Logo
                  const Icon(
                    Icons.currency_bitcoin,
                    size: 80,
                    color: Colors.amber,
                  ),
                  const SizedBox(height: 16),

                  // Title
                  const Text(
                    'Bybit 선물 거래',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'API 키로 로그인하세요',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.grey[400],
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 48),

                  // API Key Input
                  TextFormField(
                    controller: _apiKeyController,
                    enabled: !_isLoading,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'API Key',
                      labelStyle: TextStyle(color: Colors.grey[400]),
                      hintText: 'Bybit API 키를 입력하세요',
                      hintStyle: TextStyle(color: Colors.grey[600]),
                      filled: true,
                      fillColor: const Color(0xFF2D2D2D),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      prefixIcon: const Icon(Icons.key, color: Colors.blue),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'API Key를 입력해주세요';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // API Secret Input
                  TextFormField(
                    controller: _apiSecretController,
                    enabled: !_isLoading,
                    obscureText: _obscureSecret,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'API Secret',
                      labelStyle: TextStyle(color: Colors.grey[400]),
                      hintText: 'Bybit API Secret을 입력하세요',
                      hintStyle: TextStyle(color: Colors.grey[600]),
                      filled: true,
                      fillColor: const Color(0xFF2D2D2D),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      prefixIcon: const Icon(Icons.lock, color: Colors.orange),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureSecret ? Icons.visibility : Icons.visibility_off,
                          color: Colors.grey[400],
                        ),
                        onPressed: () {
                          setState(() {
                            _obscureSecret = !_obscureSecret;
                          });
                        },
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'API Secret을 입력해주세요';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 32),

                  // Login Button
                  SizedBox(
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _handleLogin,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        disabledBackgroundColor: Colors.grey[700],
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              '로그인',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 24),

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
                              'API 키 권한',
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
                          '• 선물 거래 권한 필요\n'
                          '• 포지션 조회 권한 필요\n'
                          '• 계좌 정보 조회 권한 필요\n'
                          '• 개발 중에는 Testnet 사용 권장',
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
          ),
        ),
      ),
    );
  }
}
