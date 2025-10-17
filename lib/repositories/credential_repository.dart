import 'package:bybit_scalping_bot/core/result/result.dart';
import 'package:bybit_scalping_bot/models/credentials.dart';
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
}
