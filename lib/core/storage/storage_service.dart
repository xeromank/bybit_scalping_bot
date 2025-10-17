/// Abstract interface for secure storage services
///
/// This interface defines the contract for all storage service implementations.
/// Following the Dependency Inversion Principle, high-level modules depend on
/// this abstraction rather than concrete implementations.
///
/// Responsibility: Define the contract for secure data persistence
///
/// Benefits:
/// - Easy to swap storage implementations
/// - Easy to mock for testing
/// - Easy to add encryption layers
abstract class StorageService {
  /// Saves a key-value pair securely
  ///
  /// [key] - The key to identify the value
  /// [value] - The value to store
  ///
  /// Throws an exception if the operation fails
  Future<void> write({
    required String key,
    required String value,
  });

  /// Reads a value by key
  ///
  /// [key] - The key to identify the value
  ///
  /// Returns the stored value or null if not found
  /// Throws an exception if the operation fails
  Future<String?> read({required String key});

  /// Deletes a value by key
  ///
  /// [key] - The key to identify the value
  ///
  /// Throws an exception if the operation fails
  Future<void> delete({required String key});

  /// Checks if a key exists
  ///
  /// [key] - The key to check
  ///
  /// Returns true if the key exists, false otherwise
  Future<bool> containsKey({required String key});

  /// Deletes all stored data
  ///
  /// Throws an exception if the operation fails
  Future<void> deleteAll();
}
