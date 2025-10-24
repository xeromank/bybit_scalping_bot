import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:bybit_scalping_bot/providers/auth_provider.dart';
import 'package:bybit_scalping_bot/core/enums/exchange_type.dart';
import 'package:bybit_scalping_bot/core/result/result.dart';
import 'package:bybit_scalping_bot/models/exchange_credentials.dart';
import 'package:bybit_scalping_bot/screens/bybit_trading_screen.dart';
import 'package:bybit_scalping_bot/screens/coinone_trading_screen.dart';
import 'package:bybit_scalping_bot/screens/hyperliquid_traders_screen.dart';
import 'package:bybit_scalping_bot/screens/guest_home_screen.dart';
import 'package:bybit_scalping_bot/utils/logger.dart';
import 'package:bybit_scalping_bot/services/notification_service.dart';

/// Universal Login Screen
///
/// Login screen with exchange selection (Bybit or Coinone) and saved credentials
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
  ExchangeType _selectedExchange = ExchangeType.bybit;

  // Saved credentials
  List<ExchangeCredentials> _savedCredentials = [];
  ExchangeCredentials? _selectedCredential;

  @override
  void initState() {
    super.initState();
    // Load credentials after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSavedCredentials();
      _initializeNotifications();
    });
  }

  /// 알림 서비스 초기화
  Future<void> _initializeNotifications() async {
    final notificationService = NotificationService();
    await notificationService.initialize();
    await notificationService.requestPermissions();
  }

  /// 알림 테스트 버튼 핸들러
  Future<void> _testNotification() async {
    final notificationService = NotificationService();
    await notificationService.showTestNotification();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('테스트 알림이 전송되었습니다!'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _apiSecretController.dispose();
    super.dispose();
  }

  /// Load saved credentials for current exchange
  Future<void> _loadSavedCredentials() async {
    try {
      final authProvider = context.read<AuthProvider>();
      final credentials = await authProvider.getRecentCredentials(_selectedExchange);

      Logger.info('로그인 화면: ${_selectedExchange.displayName}에 저장된 자격증명 ${credentials.length}개 로드됨');

      setState(() {
        _savedCredentials = credentials;
      });
    } catch (e) {
      Logger.error('Error loading saved credentials: $e');
      setState(() {
        _savedCredentials = [];
      });
    }
  }

  /// Select a saved credential
  void _selectCredential(ExchangeCredentials? credential) {
    setState(() {
      _selectedCredential = credential;
      if (credential != null) {
        _apiKeyController.text = credential.apiKey;
        _apiSecretController.text = credential.apiSecret;
      } else {
        _apiKeyController.clear();
        _apiSecretController.clear();
      }
    });
  }

  /// Change exchange and reload credentials
  void _changeExchange(ExchangeType exchange) {
    setState(() {
      _selectedExchange = exchange;
      _selectedCredential = null;
      _apiKeyController.clear();
      _apiSecretController.clear();
    });
    _loadSavedCredentials();
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
        exchange: _selectedExchange,
      );

      if (!mounted) return;

      switch (result) {
        case Success(:final data):
          if (data) {
            final exchangeName = _selectedExchange == ExchangeType.bybit ? 'Bybit' : 'Coinone';
            Logger.success('$exchangeName 로그인 성공 및 자격증명 저장 완료');

            // Reload saved credentials to confirm save
            await _loadSavedCredentials();

            if (!mounted) return;

            // Navigate to appropriate trading screen
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (context) => _selectedExchange == ExchangeType.bybit
                    ? const BybitTradingScreen()
                    : const CoinoneTradingScreen(),
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
                  Text(
                    _selectedExchange == ExchangeType.bybit ? 'Bybit 선물 거래' : 'Coinone 현물 거래',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
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
                  const SizedBox(height: 32),

                  // Exchange Selection
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2D2D2D),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: _isLoading ? null : () {
                              _changeExchange(ExchangeType.bybit);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: _selectedExchange == ExchangeType.bybit
                                    ? Colors.blue
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.trending_up,
                                    color: _selectedExchange == ExchangeType.bybit
                                        ? Colors.white
                                        : Colors.grey[500],
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Bybit (선물)',
                                    style: TextStyle(
                                      color: _selectedExchange == ExchangeType.bybit
                                          ? Colors.white
                                          : Colors.grey[500],
                                      fontWeight: _selectedExchange == ExchangeType.bybit
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: GestureDetector(
                            onTap: _isLoading ? null : () {
                              _changeExchange(ExchangeType.coinone);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: _selectedExchange == ExchangeType.coinone
                                    ? Colors.orange
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.account_balance_wallet,
                                    color: _selectedExchange == ExchangeType.coinone
                                        ? Colors.white
                                        : Colors.grey[500],
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Coinone (현물)',
                                    style: TextStyle(
                                      color: _selectedExchange == ExchangeType.coinone
                                          ? Colors.white
                                          : Colors.grey[500],
                                      fontWeight: _selectedExchange == ExchangeType.coinone
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Saved Credentials Dropdown (Always show)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.history, color: Colors.blue, size: 16),
                            const SizedBox(width: 8),
                            Text(
                              '저장된 계정 선택',
                              style: TextStyle(
                                color: Colors.grey[300],
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (_savedCredentials.isEmpty)
                          Text(
                            '저장된 계정이 없습니다. 로그인하면 자동으로 저장됩니다.',
                            style: TextStyle(
                              color: Colors.grey[500],
                              fontSize: 11,
                            ),
                          )
                        else
                          DropdownButtonFormField<ExchangeCredentials>(
                            initialValue: _selectedCredential,
                            dropdownColor: const Color(0xFF2D2D2D),
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: const Color(0xFF1E1E1E),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            ),
                            hint: Text(
                              '새로운 계정으로 로그인',
                              style: TextStyle(color: Colors.grey[500], fontSize: 13),
                            ),
                            items: [
                              DropdownMenuItem<ExchangeCredentials>(
                                value: null,
                                child: Text(
                                  '새로운 계정',
                                  style: TextStyle(color: Colors.grey[400], fontSize: 13),
                                ),
                              ),
                              ..._savedCredentials.map((cred) {
                                final label = cred.label ?? '계정 ${_savedCredentials.indexOf(cred) + 1}';
                                final maskedKey = cred.apiKey.length > 8
                                    ? '${cred.apiKey.substring(0, 8)}...'
                                    : cred.apiKey;
                                return DropdownMenuItem<ExchangeCredentials>(
                                  value: cred,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        label,
                                        style: TextStyle(color: Colors.grey[300], fontSize: 13),
                                      ),
                                      Text(
                                        maskedKey,
                                        style: TextStyle(color: Colors.grey[600], fontSize: 11),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                            ],
                            onChanged: _isLoading ? null : _selectCredential,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // API Key Input
                  TextFormField(
                    controller: _apiKeyController,
                    enabled: !_isLoading,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'API Key',
                      labelStyle: TextStyle(color: Colors.grey[400]),
                      hintText: _selectedExchange == ExchangeType.bybit
                          ? 'Bybit API 키를 입력하세요'
                          : 'Coinone API 키를 입력하세요',
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
                      hintText: _selectedExchange == ExchangeType.bybit
                          ? 'Bybit API Secret을 입력하세요'
                          : 'Coinone API Secret을 입력하세요',
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
                  const SizedBox(height: 16),

                  // 알림 테스트 버튼
                  SizedBox(
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: _testNotification,
                      icon: const Icon(Icons.notifications_active, color: Colors.orange),
                      label: const Text(
                        '알림 테스트',
                        style: TextStyle(
                          color: Colors.orange,
                          fontSize: 14,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.orange),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // 게스트 모드 버튼 (메인)
                  SizedBox(
                    height: 52,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const GuestHomeScreen(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.remove_red_eye, color: Colors.green, size: 24),
                      label: const Text(
                        '게스트 모드로 둘러보기',
                        style: TextStyle(
                          color: Colors.green,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.green, width: 2),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Hyperliquid 트레이더 추적 버튼
                  SizedBox(
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const HyperliquidTradersScreen(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.track_changes, color: Colors.blue),
                      label: const Text(
                        'Hyperliquid 트레이더 추적',
                        style: TextStyle(
                          color: Colors.blue,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.blue, width: 1.5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Info Box
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: (_selectedExchange == ExchangeType.bybit ? Colors.blue : Colors.orange).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: (_selectedExchange == ExchangeType.bybit ? Colors.blue : Colors.orange).withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              color: _selectedExchange == ExchangeType.bybit ? Colors.blue : Colors.orange,
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
                          _selectedExchange == ExchangeType.bybit
                              ? '• 선물 거래 권한 필요\n'
                                '• 포지션 조회 권한 필요\n'
                                '• 계좌 정보 조회 권한 필요\n'
                                '• 개발 중에는 Testnet 사용 권장'
                              : '• 현물 거래 권한 필요\n'
                                '• 계좌 조회 권한 필요\n'
                                '• 출금 권한 선택적\n'
                                '• 소액으로 테스트 후 운영',
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
