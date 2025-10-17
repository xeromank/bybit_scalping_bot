import 'package:flutter/material.dart';
import 'package:bybit_scalping_bot/constants/theme_constants.dart';
import 'package:bybit_scalping_bot/constants/app_constants.dart';

/// Widget for API credential input form
///
/// Responsibility: Provide a form for entering API credentials
///
/// This widget provides a reusable form for API key and secret input
/// with validation and visibility toggle.
class CredentialForm extends StatefulWidget {
  final TextEditingController apiKeyController;
  final TextEditingController apiSecretController;
  final bool enabled;
  final GlobalKey<FormState>? formKey;

  const CredentialForm({
    super.key,
    required this.apiKeyController,
    required this.apiSecretController,
    this.enabled = true,
    this.formKey,
  });

  @override
  State<CredentialForm> createState() => _CredentialFormState();
}

class _CredentialFormState extends State<CredentialForm> {
  bool _obscureSecret = true;

  @override
  Widget build(BuildContext context) {
    return Form(
      key: widget.formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // API Key Field
          TextFormField(
            controller: widget.apiKeyController,
            decoration: ThemeConstants.inputDecoration(
              labelText: 'API Key',
              prefixIcon: Icons.key,
            ),
            enabled: widget.enabled,
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return AppConstants.errorApiKeyRequired;
              }
              return null;
            },
          ),
          const SizedBox(height: ThemeConstants.spacingMedium),

          // API Secret Field
          TextFormField(
            controller: widget.apiSecretController,
            obscureText: _obscureSecret,
            decoration: ThemeConstants.inputDecoration(
              labelText: 'API Secret',
              prefixIcon: Icons.lock,
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureSecret ? Icons.visibility : Icons.visibility_off,
                ),
                onPressed: widget.enabled
                    ? () {
                        setState(() {
                          _obscureSecret = !_obscureSecret;
                        });
                      }
                    : null,
              ),
            ),
            enabled: widget.enabled,
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return AppConstants.errorApiSecretRequired;
              }
              return null;
            },
          ),
        ],
      ),
    );
  }
}
