import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:bybit_scalping_bot/providers/auth_provider.dart';
import 'package:bybit_scalping_bot/screens/trading_screen_new.dart';
import 'package:bybit_scalping_bot/screens/coinone_trading_screen.dart';
import 'package:bybit_scalping_bot/widgets/auth/credential_form.dart';
import 'package:bybit_scalping_bot/widgets/common/loading_button.dart';
import 'package:bybit_scalping_bot/constants/theme_constants.dart';
import 'package:bybit_scalping_bot/constants/app_constants.dart';
import 'package:bybit_scalping_bot/core/enums/exchange_type.dart';
import 'package:bybit_scalping_bot/models/exchange_credentials.dart';

/// Login screen using new architecture
///
/// Responsibility: Provide UI for user authentication
///
/// This screen uses the AuthProvider to handle login operations
/// and navigates to the trading screen on successful authentication.
class LoginScreenNew extends StatefulWidget {
  const LoginScreenNew({super.key});

  @override
  State<LoginScreenNew> createState() => _LoginScreenNewState();
}

class _LoginScreenNewState extends State<LoginScreenNew> {
  final _formKey = GlobalKey<FormState>();
  final _apiKeyController = TextEditingController();
  final _apiSecretController = TextEditingController();
  final _labelController = TextEditingController();

  List<ExchangeCredentials> _recentCredentials = [];
  bool _showRecentCredentials = false;

  @override
  void initState() {
    super.initState();
    // Build가 완료된 후에 실행
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSavedCredentials();
      _loadRecentCredentials();
    });
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _apiSecretController.dispose();
    _labelController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedCredentials() async {
    final authProvider = context.read<AuthProvider>();
    await authProvider.initialize();

    if (authProvider.credentials != null && mounted) {
      setState(() {
        _apiKeyController.text = authProvider.credentials!.apiKey;
        _apiSecretController.text = authProvider.credentials!.apiSecret;
      });
    }
  }

  Future<void> _loadRecentCredentials() async {
    final authProvider = context.read<AuthProvider>();
    final credentials = await authProvider.getRecentCredentials(authProvider.currentExchange);

    if (mounted) {
      setState(() {
        _recentCredentials = credentials;
      });
    }
  }

  void _selectCredential(ExchangeCredentials credential) {
    setState(() {
      _apiKeyController.text = credential.apiKey;
      _apiSecretController.text = credential.apiSecret;
      _labelController.text = credential.label ?? '';
      _showRecentCredentials = false;
    });
  }

  Future<void> _deleteCredential(ExchangeCredentials credential) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('인증 정보 삭제'),
        content: Text('${credential.displayLabel}을(를) 삭제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: ThemeConstants.errorColor,
            ),
            child: const Text('삭제'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      // Remove from list
      setState(() {
        _recentCredentials.removeWhere((c) =>
            c.apiKey == credential.apiKey && c.apiSecret == credential.apiSecret);
      });

      // Update storage
      final authProvider = context.read<AuthProvider>();
      // Note: We'll need to add a delete method to CredentialRepository
      await _loadRecentCredentials();
    }
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final authProvider = context.read<AuthProvider>();
    final label = _labelController.text.trim();

    final result = await authProvider.login(
      exchange: authProvider.currentExchange,
      apiKey: _apiKeyController.text.trim(),
      apiSecret: _apiSecretController.text.trim(),
      label: label.isNotEmpty ? label : null,
    );

    if (!mounted) return;

    result.when(
      success: (data) {
        // Navigate to appropriate trading screen based on exchange
        final screen = authProvider.currentExchange == ExchangeType.bybit
            ? const TradingScreenNew() // Bybit 선물 거래
            : const CoinoneTradingScreen(); // Coinone 현물 거래

        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => screen),
        );
      },
      failure: (message, exception) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: ThemeConstants.errorColor,
            duration: const Duration(seconds: 4),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(ThemeConstants.spacingLarge),
            child: Consumer<AuthProvider>(
              builder: (context, authProvider, child) {
                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // App Icon
                    const Icon(
                      Icons.currency_bitcoin,
                      size: 80,
                      color: ThemeConstants.primaryColor,
                    ),
                    const SizedBox(height: ThemeConstants.spacingLarge),

                    // App Title
                    const Text(
                      AppConstants.appName,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: ThemeConstants.spacingSmall),

                    // App Subtitle
                    Text(
                      '선물 스캘핑 자동 매매',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: ThemeConstants.spacingXLarge),

                    // Exchange Selector
                    _buildExchangeSelector(authProvider),
                    const SizedBox(height: ThemeConstants.spacingLarge),

                    // Recent Credentials (if any)
                    if (_recentCredentials.isNotEmpty)
                      _buildRecentCredentialsSection(),
                    if (_recentCredentials.isNotEmpty)
                      const SizedBox(height: ThemeConstants.spacingMedium),

                    // Credential Form
                    CredentialForm(
                      apiKeyController: _apiKeyController,
                      apiSecretController: _apiSecretController,
                      enabled: !authProvider.isLoading,
                      formKey: _formKey,
                    ),
                    const SizedBox(height: ThemeConstants.spacingMedium),

                    // Label input (optional)
                    TextFormField(
                      controller: _labelController,
                      enabled: !authProvider.isLoading,
                      decoration: const InputDecoration(
                        labelText: 'API Key 라벨 (선택)',
                        hintText: '예: 메인 계정, 테스트 등',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.label),
                      ),
                    ),
                    const SizedBox(height: ThemeConstants.spacingLarge),

                    // Login Button
                    LoadingButton(
                      text: '로그인',
                      onPressed: _login,
                      isLoading: authProvider.isLoading,
                      backgroundColor: ThemeConstants.primaryColor,
                    ),
                    const SizedBox(height: ThemeConstants.spacingLarge),

                    // Security Message
                    Container(
                      padding: const EdgeInsets.all(ThemeConstants.spacingSmall),
                      decoration: BoxDecoration(
                        color: Colors.green[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green[200]!),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.lock, color: Colors.green[700], size: 16),
                          const SizedBox(width: ThemeConstants.spacingSmall),
                          Expanded(
                            child: Text(
                              '🔐 이중 암호화 저장 (AES-256 + XOR)\n최근 사용한 API Key는 최대 5개까지 안전하게 보관됩니다.',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.green[800],
                                height: 1.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: ThemeConstants.spacingSmall),
                    Text(
                      '⚠️ API Key는 거래 권한이 필요합니다.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExchangeSelector(AuthProvider authProvider) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildExchangeButton(
              exchange: ExchangeType.bybit,
              label: 'Bybit',
              subtitle: '선물 거래',
              isSelected: authProvider.currentExchange == ExchangeType.bybit,
              onTap: () => authProvider.setCurrentExchange(ExchangeType.bybit),
            ),
          ),
          Container(
            width: 1,
            height: 60,
            color: Colors.grey[300],
          ),
          Expanded(
            child: _buildExchangeButton(
              exchange: ExchangeType.coinone,
              label: 'Coinone',
              subtitle: '현물 거래',
              isSelected: authProvider.currentExchange == ExchangeType.coinone,
              onTap: () => authProvider.setCurrentExchange(ExchangeType.coinone),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExchangeButton({
    required ExchangeType exchange,
    required String label,
    required String subtitle,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: () {
        onTap();
        // Reload recent credentials for new exchange
        _loadRecentCredentials();
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? ThemeConstants.primaryColor.withOpacity(0.1) : null,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: isSelected ? ThemeConstants.primaryColor : Colors.grey[700],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                color: isSelected ? ThemeConstants.primaryColor : Colors.grey[500],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentCredentialsSection() {
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
                  '최근 사용한 API Key',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: Icon(
                    _showRecentCredentials
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                  ),
                  onPressed: () {
                    setState(() {
                      _showRecentCredentials = !_showRecentCredentials;
                    });
                  },
                ),
              ],
            ),
            if (_showRecentCredentials) ...[
              const SizedBox(height: ThemeConstants.spacingSmall),
              ..._recentCredentials.map((credential) =>
                  _buildCredentialItem(credential)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCredentialItem(ExchangeCredentials credential) {
    return InkWell(
      onTap: () => _selectCredential(credential),
      child: Container(
        margin: const EdgeInsets.only(bottom: ThemeConstants.spacingSmall),
        padding: const EdgeInsets.all(ThemeConstants.spacingSmall),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    credential.displayLabel,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    credential.maskedApiKey,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '최근 사용: ${_formatDate(credential.lastUsed)}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              color: ThemeConstants.errorColor,
              onPressed: () => _deleteCredential(credential),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 1) {
      return '방금 전';
    } else if (diff.inHours < 1) {
      return '${diff.inMinutes}분 전';
    } else if (diff.inDays < 1) {
      return '${diff.inHours}시간 전';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}일 전';
    } else {
      return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    }
  }
}
