import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:bybit_scalping_bot/providers/auth_provider.dart';
import 'package:bybit_scalping_bot/screens/trading_screen_new.dart';
import 'package:bybit_scalping_bot/widgets/auth/credential_form.dart';
import 'package:bybit_scalping_bot/widgets/common/loading_button.dart';
import 'package:bybit_scalping_bot/constants/theme_constants.dart';
import 'package:bybit_scalping_bot/constants/app_constants.dart';

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

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _apiSecretController.dispose();
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

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final authProvider = context.read<AuthProvider>();

    final result = await authProvider.login(
      apiKey: _apiKeyController.text.trim(),
      apiSecret: _apiSecretController.text.trim(),
    );

    if (!mounted) return;

    result.when(
      success: (data) {
        // Navigate to trading screen
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => const TradingScreenNew(),
          ),
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

                    // Credential Form
                    CredentialForm(
                      apiKeyController: _apiKeyController,
                      apiSecretController: _apiSecretController,
                      enabled: !authProvider.isLoading,
                      formKey: _formKey,
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

                    // Warning Message
                    Text(
                      '⚠️ API Key는 선물 거래 권한이 필요하며,\n안전하게 암호화되어 저장됩니다.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
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
}
