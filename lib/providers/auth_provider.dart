import 'package:flutter/foundation.dart';
import 'package:bybit_scalping_bot/core/result/result.dart';
import 'package:bybit_scalping_bot/models/credentials.dart';
import 'package:bybit_scalping_bot/repositories/credential_repository.dart';
import 'package:bybit_scalping_bot/repositories/bybit_repository.dart';

/// Provider for authentication state and operations
///
/// Responsibility: Manage authentication state and business logic
///
/// This provider follows the MVVM pattern, acting as the ViewModel layer.
/// It manages authentication state, handles login/logout operations, and
/// provides reactive state updates to the UI.
///
/// Benefits:
/// - Centralized authentication logic
/// - Reactive UI updates through ChangeNotifier
/// - Separation of concerns from UI layer
class AuthProvider extends ChangeNotifier {
  final CredentialRepository _credentialRepository;
  final BybitRepository Function(Credentials) _createBybitRepository;

  // State
  Credentials? _credentials;
  bool _isAuthenticated = false;
  bool _isLoading = false;
  String? _errorMessage;

  AuthProvider({
    required CredentialRepository credentialRepository,
    required BybitRepository Function(Credentials) createBybitRepository,
  })  : _credentialRepository = credentialRepository,
        _createBybitRepository = createBybitRepository;

  // Getters
  Credentials? get credentials => _credentials;
  bool get isAuthenticated => _isAuthenticated;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  /// Initializes authentication state by checking stored credentials
  Future<void> initialize() async {
    _setLoading(true);

    final result = await _credentialRepository.getCredentials();

    result.when(
      success: (credentials) {
        if (credentials != null) {
          _credentials = credentials;
          _isAuthenticated = true;
          _errorMessage = null;
        }
      },
      failure: (message, exception) {
        _errorMessage = message;
        _isAuthenticated = false;
      },
    );

    _setLoading(false);
  }

  /// Logs in with provided credentials
  ///
  /// Validates credentials by testing API connection
  Future<Result<bool>> login({
    required String apiKey,
    required String apiSecret,
  }) async {
    _setLoading(true);
    _errorMessage = null;

    try {
      final credentials = Credentials(
        apiKey: apiKey.trim(),
        apiSecret: apiSecret.trim(),
      );

      if (!credentials.isValid) {
        _errorMessage = 'Invalid credentials';
        _setLoading(false);
        return const Failure('Invalid credentials: API key and secret are required');
      }

      // Test API connection
      final repository = _createBybitRepository(credentials);
      final connectionResult = await repository.testConnection();

      if (connectionResult.isFailure) {
        _errorMessage = connectionResult.errorOrNull ?? 'Connection failed';
        _setLoading(false);
        return Failure(_errorMessage!);
      }

      // Verify API key by fetching wallet balance
      final balanceResult = await repository.getWalletBalance();

      if (balanceResult.isFailure) {
        _errorMessage = balanceResult.errorOrNull ?? 'API authentication failed';
        _setLoading(false);
        return Failure(_errorMessage!);
      }

      // Save credentials
      final saveResult =
          await _credentialRepository.saveCredentials(credentials);

      if (saveResult.isFailure) {
        _errorMessage = saveResult.errorOrNull ?? 'Failed to save credentials';
        _setLoading(false);
        return Failure(_errorMessage!);
      }

      // Update state
      _credentials = credentials;
      _isAuthenticated = true;
      _errorMessage = null;
      _setLoading(false);

      return const Success(true);
    } catch (e) {
      _errorMessage = e.toString();
      _setLoading(false);
      return Failure('Login failed: ${e.toString()}');
    }
  }

  /// Logs out and clears stored credentials
  Future<Result<bool>> logout() async {
    _setLoading(true);

    try {
      final result = await _credentialRepository.deleteCredentials();

      if (result.isSuccess) {
        _credentials = null;
        _isAuthenticated = false;
        _errorMessage = null;
        _setLoading(false);
        return const Success(true);
      } else {
        _errorMessage = result.errorOrNull ?? 'Logout failed';
        _setLoading(false);
        return Failure(_errorMessage!);
      }
    } catch (e) {
      _errorMessage = e.toString();
      _setLoading(false);
      return Failure('Logout failed: ${e.toString()}');
    }
  }

  /// Clears error message
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  /// Sets loading state
  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }
}
