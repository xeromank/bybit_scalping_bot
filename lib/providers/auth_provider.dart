import 'package:flutter/foundation.dart';
import 'package:bybit_scalping_bot/core/result/result.dart';
import 'package:bybit_scalping_bot/models/credentials.dart';
import 'package:bybit_scalping_bot/models/exchange_credentials.dart';
import 'package:bybit_scalping_bot/core/enums/exchange_type.dart';
import 'package:bybit_scalping_bot/repositories/credential_repository.dart';
import 'package:bybit_scalping_bot/repositories/bybit_repository.dart';
import 'package:bybit_scalping_bot/repositories/coinone_repository.dart';
import 'package:bybit_scalping_bot/services/coinone/coinone_api_client.dart';

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
/// - Multi-exchange support (Bybit, Coinone)
class AuthProvider extends ChangeNotifier {
  final CredentialRepository _credentialRepository;
  final BybitRepository Function(Credentials) _createBybitRepository;

  // State
  Credentials? _credentials;
  ExchangeType _currentExchange = ExchangeType.bybit; // Default to Bybit
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
  ExchangeType get currentExchange => _currentExchange;
  bool get isAuthenticated => _isAuthenticated;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  /// Initializes authentication state by checking stored credentials
  ///
  /// Tries to load credentials for the default exchange (Bybit first, then Coinone)
  Future<void> initialize() async {
    _setLoading(true);

    // Try Bybit first (backward compatibility)
    final bybitResult = await _credentialRepository.getExchangeCredentials(ExchangeType.bybit);

    if (bybitResult case Success(:final data) when data != null) {
      _currentExchange = ExchangeType.bybit;
      _credentials = Credentials(apiKey: data.apiKey, apiSecret: data.apiSecret);
      _isAuthenticated = true;
      _errorMessage = null;
      _setLoading(false);
      return;
    }

    // Try Coinone
    final coinoneResult = await _credentialRepository.getExchangeCredentials(ExchangeType.coinone);

    if (coinoneResult case Success(:final data) when data != null) {
      _currentExchange = ExchangeType.coinone;
      _credentials = Credentials(apiKey: data.apiKey, apiSecret: data.apiSecret);
      _isAuthenticated = true;
      _errorMessage = null;
      _setLoading(false);
      return;
    }

    // No credentials found
    _isAuthenticated = false;
    _setLoading(false);
  }

  /// Logs in with provided credentials for specific exchange
  ///
  /// Validates credentials by testing API connection
  Future<Result<bool>> login({
    required ExchangeType exchange,
    required String apiKey,
    required String apiSecret,
    String? label,
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

      // Test API connection based on exchange type
      if (exchange == ExchangeType.bybit) {
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
      } else if (exchange == ExchangeType.coinone) {
        // Test Coinone connection
        final apiClient = CoinoneApiClient(
          apiKey: credentials.apiKey,
          apiSecret: credentials.apiSecret,
        );
        final repository = CoinoneRepository(apiClient: apiClient);

        // Verify API key by fetching wallet balance
        final balanceResult = await repository.getWalletBalance();

        if (balanceResult.isFailure) {
          _errorMessage = balanceResult.errorOrNull ?? 'Coinone API authentication failed';
          _setLoading(false);
          return Failure(_errorMessage!);
        }
      }

      // Save credentials for the exchange
      if (kDebugMode) {
        print('🔐 AuthProvider: ${exchange.displayName} 자격증명 저장 시도...');
      }

      final saveResult = await _credentialRepository.saveExchangeCredentials(
        exchange,
        credentials.apiKey,
        credentials.apiSecret,
        label: label,
      );

      if (saveResult.isFailure) {
        _errorMessage = saveResult.errorOrNull ?? 'Failed to save credentials';
        _setLoading(false);
        if (kDebugMode) {
          print('❌ AuthProvider: 자격증명 저장 실패 - $_errorMessage');
        }
        return Failure(_errorMessage!);
      }

      if (kDebugMode) {
        print('✅ AuthProvider: ${exchange.displayName} 자격증명 저장 성공');
      }

      // Update state
      _currentExchange = exchange;
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

  /// Get recent credentials for specific exchange
  Future<List<ExchangeCredentials>> getRecentCredentials(ExchangeType exchange) async {
    final result = await _credentialRepository.getRecentCredentials(exchange);
    return result.when(
      success: (credentials) => credentials,
      failure: (_, __) => [],
    );
  }

  /// Set current exchange (for UI selection)
  void setCurrentExchange(ExchangeType exchange) {
    _currentExchange = exchange;
    notifyListeners();
  }

  /// Logs out and clears stored credentials for current exchange
  Future<Result<bool>> logout() async {
    _setLoading(true);

    try {
      final result = await _credentialRepository.deleteExchangeCredentials(_currentExchange);

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
