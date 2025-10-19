import 'dart:convert';
import 'package:bybit_scalping_bot/core/result/result.dart';
import 'package:bybit_scalping_bot/models/credentials.dart';
import 'package:bybit_scalping_bot/models/exchange_credentials.dart';
import 'package:bybit_scalping_bot/core/enums/exchange_type.dart';
import 'package:bybit_scalping_bot/services/secure_storage_service.dart';

/// Repository for managing API credentials
///
/// Responsibility: Abstract credential storage and retrieval
///
/// This repository provides a clean abstraction over the secure storage service,
/// handling credential persistence and retrieval.
///
/// Benefits:
/// - Separates storage logic from business logic
/// - Type-safe error handling with Result type
/// - Easy to mock for testing
class CredentialRepository {
  final SecureStorageService _storageService;

  CredentialRepository({required SecureStorageService storageService})
      : _storageService = storageService;

  /// Saves API credentials securely
  ///
  /// Returns [Result<bool>] - Success(true) or Failure
  Future<Result<bool>> saveCredentials(Credentials credentials) async {
    try {
      if (!credentials.isValid) {
        return const Failure('Invalid credentials: API key and secret are required');
      }

      await _storageService.saveCredentials(
        apiKey: credentials.apiKey,
        apiSecret: credentials.apiSecret,
      );

      return const Success(true);
    } catch (e) {
      return Failure(
        'Failed to save credentials',
        Exception(e.toString()),
      );
    }
  }

  /// Retrieves stored API credentials
  ///
  /// Returns [Result<Credentials?>] - Success with credentials (or null if not found) or Failure
  Future<Result<Credentials?>> getCredentials() async {
    try {
      final data = await _storageService.getCredentials();

      if (data == null) {
        return const Success(null);
      }

      final credentials = Credentials(
        apiKey: data['apiKey']!,
        apiSecret: data['apiSecret']!,
      );

      return Success(credentials);
    } catch (e) {
      return Failure(
        'Failed to retrieve credentials',
        Exception(e.toString()),
      );
    }
  }

  /// Checks if credentials are stored
  ///
  /// Returns [Result<bool>] - Success(true/false) or Failure
  Future<Result<bool>> hasCredentials() async {
    try {
      final hasCredentials = await _storageService.hasCredentials();
      return Success(hasCredentials);
    } catch (e) {
      return Failure(
        'Failed to check credentials',
        Exception(e.toString()),
      );
    }
  }

  /// Deletes stored credentials
  ///
  /// Returns [Result<bool>] - Success(true) or Failure
  Future<Result<bool>> deleteCredentials() async {
    try {
      await _storageService.deleteCredentials();
      return const Success(true);
    } catch (e) {
      return Failure(
        'Failed to delete credentials',
        Exception(e.toString()),
      );
    }
  }

  /// Clears all stored data
  ///
  /// Returns [Result<bool>] - Success(true) or Failure
  Future<Result<bool>> clearAll() async {
    try {
      await _storageService.deleteAll();
      return const Success(true);
    } catch (e) {
      return Failure(
        'Failed to clear all data',
        Exception(e.toString()),
      );
    }
  }

  // ============================================================================
  // Multi-Exchange Support (New)
  // ============================================================================

  /// Save credentials for specific exchange
  Future<Result<bool>> saveExchangeCredentials(
    ExchangeType exchange,
    String apiKey,
    String apiSecret, {
    String? label,
  }) async {
    try {
      final storageKey = '${exchange.identifier}_credentials';

      await _storageService.write(
        key: storageKey,
        value: json.encode({
          'apiKey': apiKey,
          'apiSecret': apiSecret,
        }),
      );

      // Update recent credentials list
      await _addToRecentCredentials(
        ExchangeCredentials(
          exchangeType: exchange,
          apiKey: apiKey,
          apiSecret: apiSecret,
          lastUsed: DateTime.now(),
          label: label,
        ),
      );

      return const Success(true);
    } catch (e) {
      return Failure(
        'Failed to save ${exchange.displayName} credentials',
        Exception(e.toString()),
      );
    }
  }

  /// Get credentials for specific exchange
  Future<Result<ExchangeCredentials?>> getExchangeCredentials(
    ExchangeType exchange,
  ) async {
    try {
      final storageKey = '${exchange.identifier}_credentials';
      final data = await _storageService.read(key: storageKey);

      if (data == null) {
        return const Success(null);
      }

      final decoded = json.decode(data) as Map<String, dynamic>;

      return Success(ExchangeCredentials(
        exchangeType: exchange,
        apiKey: decoded['apiKey'] as String,
        apiSecret: decoded['apiSecret'] as String,
        lastUsed: DateTime.now(),
      ));
    } catch (e) {
      return Failure(
        'Failed to retrieve ${exchange.displayName} credentials',
        Exception(e.toString()),
      );
    }
  }

  /// Get recent credentials for specific exchange (max 5)
  Future<Result<List<ExchangeCredentials>>> getRecentCredentials(
    ExchangeType exchange,
  ) async {
    try {
      final storageKey = '${exchange.identifier}_recent';
      final data = await _storageService.read(key: storageKey);

      if (data == null) {
        return const Success([]);
      }

      final decoded = json.decode(data) as List<dynamic>;
      final credentials = decoded
          .map((e) => ExchangeCredentials.fromJson(e as Map<String, dynamic>))
          .toList();

      // Sort by lastUsed descending
      credentials.sort((a, b) => b.lastUsed.compareTo(a.lastUsed));

      return Success(credentials);
    } catch (e) {
      return Failure(
        'Failed to retrieve recent ${exchange.displayName} credentials',
        Exception(e.toString()),
      );
    }
  }

  /// Add to recent credentials list (keeps max 5)
  Future<void> _addToRecentCredentials(ExchangeCredentials credentials) async {
    final storageKey = '${credentials.exchangeType.identifier}_recent';

    // Get existing list
    final existingData = await _storageService.read(key: storageKey);
    List<ExchangeCredentials> recentList = [];

    if (existingData != null) {
      final decoded = json.decode(existingData) as List<dynamic>;
      recentList = decoded
          .map((e) => ExchangeCredentials.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    // Remove if already exists (to avoid duplicates)
    recentList.removeWhere((c) =>
      c.apiKey == credentials.apiKey &&
      c.apiSecret == credentials.apiSecret
    );

    // Add new credentials at the beginning
    recentList.insert(0, credentials.copyWith(lastUsed: DateTime.now()));

    // Keep only 5 most recent
    if (recentList.length > 5) {
      recentList = recentList.sublist(0, 5);
    }

    // Save back
    await _storageService.write(
      key: storageKey,
      value: json.encode(recentList.map((e) => e.toJson()).toList()),
    );
  }

  /// Delete credentials for specific exchange
  Future<Result<bool>> deleteExchangeCredentials(ExchangeType exchange) async {
    try {
      final storageKey = '${exchange.identifier}_credentials';
      await _storageService.delete(key: storageKey);
      return const Success(true);
    } catch (e) {
      return Failure(
        'Failed to delete ${exchange.displayName} credentials',
        Exception(e.toString()),
      );
    }
  }

  /// Check if exchange has stored credentials
  Future<Result<bool>> hasExchangeCredentials(ExchangeType exchange) async {
    try {
      final storageKey = '${exchange.identifier}_credentials';
      final data = await _storageService.read(key: storageKey);
      return Success(data != null);
    } catch (e) {
      return Failure(
        'Failed to check ${exchange.displayName} credentials',
        Exception(e.toString()),
      );
    }
  }
}
