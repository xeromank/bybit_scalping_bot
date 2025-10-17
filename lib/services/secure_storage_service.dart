import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:bybit_scalping_bot/core/storage/storage_service.dart';

/// Secure storage service implementation using FlutterSecureStorage
///
/// Responsibility: Implement secure data persistence with encryption
///
/// This class implements the StorageService interface and provides
/// secure storage using platform-specific secure storage mechanisms
/// (Keychain on iOS, KeyStore on Android) with additional XOR encryption.
///
/// Features:
/// - Platform-specific secure storage
/// - Additional XOR encryption layer
/// - Automatic encryption key management
class SecureStorageService implements StorageService {
  static const String _apiKeyKey = 'bybit_api_key';
  static const String _apiSecretKey = 'bybit_api_secret';
  static const String _encryptionKey = 'bybit_encryption_key_v1';

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock,
    ),
  );

  // 간단한 XOR 암호화 (추가 보안)
  String _encrypt(String value, String key) {
    final valueBytes = utf8.encode(value);
    final keyBytes = utf8.encode(key);
    final encrypted = <int>[];

    for (int i = 0; i < valueBytes.length; i++) {
      encrypted.add(valueBytes[i] ^ keyBytes[i % keyBytes.length]);
    }

    return base64.encode(encrypted);
  }

  // XOR 복호화
  String _decrypt(String encryptedValue, String key) {
    final encryptedBytes = base64.decode(encryptedValue);
    final keyBytes = utf8.encode(key);
    final decrypted = <int>[];

    for (int i = 0; i < encryptedBytes.length; i++) {
      decrypted.add(encryptedBytes[i] ^ keyBytes[i % keyBytes.length]);
    }

    return utf8.decode(decrypted);
  }

  // 암호화 키 생성 또는 가져오기
  Future<String> _getOrCreateEncryptionKey() async {
    String? key = await _secureStorage.read(key: _encryptionKey);

    if (key == null) {
      // 새 암호화 키 생성
      final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final bytes = utf8.encode(timestamp);
      final hash = sha256.convert(bytes);
      key = hash.toString();
      await _secureStorage.write(key: _encryptionKey, value: key);
    }

    return key;
  }

  // API Key 저장
  Future<void> saveApiKey(String apiKey) async {
    final encryptionKey = await _getOrCreateEncryptionKey();
    final encrypted = _encrypt(apiKey, encryptionKey);
    await _secureStorage.write(key: _apiKeyKey, value: encrypted);
  }

  // API Secret 저장
  Future<void> saveApiSecret(String apiSecret) async {
    final encryptionKey = await _getOrCreateEncryptionKey();
    final encrypted = _encrypt(apiSecret, encryptionKey);
    await _secureStorage.write(key: _apiSecretKey, value: encrypted);
  }

  // API Key와 Secret 함께 저장
  Future<void> saveCredentials({
    required String apiKey,
    required String apiSecret,
  }) async {
    await saveApiKey(apiKey);
    await saveApiSecret(apiSecret);
  }

  // API Key 가져오기
  Future<String?> getApiKey() async {
    final encrypted = await _secureStorage.read(key: _apiKeyKey);
    if (encrypted == null) return null;

    final encryptionKey = await _getOrCreateEncryptionKey();
    return _decrypt(encrypted, encryptionKey);
  }

  // API Secret 가져오기
  Future<String?> getApiSecret() async {
    final encrypted = await _secureStorage.read(key: _apiSecretKey);
    if (encrypted == null) return null;

    final encryptionKey = await _getOrCreateEncryptionKey();
    return _decrypt(encrypted, encryptionKey);
  }

  // API Key와 Secret 함께 가져오기
  Future<Map<String, String>?> getCredentials() async {
    final apiKey = await getApiKey();
    final apiSecret = await getApiSecret();

    if (apiKey == null || apiSecret == null) {
      return null;
    }

    return {
      'apiKey': apiKey,
      'apiSecret': apiSecret,
    };
  }

  // 저장된 인증 정보가 있는지 확인
  Future<bool> hasCredentials() async {
    final apiKey = await _secureStorage.read(key: _apiKeyKey);
    final apiSecret = await _secureStorage.read(key: _apiSecretKey);
    return apiKey != null && apiSecret != null;
  }

  // 인증 정보 삭제
  Future<void> deleteCredentials() async {
    await _secureStorage.delete(key: _apiKeyKey);
    await _secureStorage.delete(key: _apiSecretKey);
  }

  // 모든 데이터 삭제
  @override
  Future<void> deleteAll() async {
    await _secureStorage.deleteAll();
  }

  // StorageService 인터페이스 구현
  @override
  Future<void> write({required String key, required String value}) async {
    final encryptionKey = await _getOrCreateEncryptionKey();
    final encrypted = _encrypt(value, encryptionKey);
    await _secureStorage.write(key: key, value: encrypted);
  }

  @override
  Future<String?> read({required String key}) async {
    final encrypted = await _secureStorage.read(key: key);
    if (encrypted == null) return null;

    final encryptionKey = await _getOrCreateEncryptionKey();
    return _decrypt(encrypted, encryptionKey);
  }

  @override
  Future<void> delete({required String key}) async {
    await _secureStorage.delete(key: key);
  }

  @override
  Future<bool> containsKey({required String key}) async {
    final value = await _secureStorage.read(key: key);
    return value != null;
  }
}
