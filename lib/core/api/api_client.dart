/// Abstract interface for API clients
///
/// This interface defines the contract for all API client implementations.
/// Following the Dependency Inversion Principle, high-level modules depend on
/// this abstraction rather than concrete implementations.
///
/// Responsibility: Define the contract for API communication
///
/// Benefits:
/// - Easy to swap implementations (e.g., different exchanges)
/// - Easy to mock for testing
/// - Easy to add new exchanges
abstract class ApiClient {
  /// Base URL for the API
  String get baseUrl;

  /// API key for authentication
  String get apiKey;

  /// Performs a GET request to the specified endpoint
  ///
  /// [endpoint] - The API endpoint path
  /// [params] - Optional query parameters
  ///
  /// Returns a JSON response as a Map
  /// Throws an exception if the request fails
  Future<Map<String, dynamic>> get(
    String endpoint, {
    Map<String, dynamic>? params,
  });

  /// Performs a POST request to the specified endpoint
  ///
  /// [endpoint] - The API endpoint path
  /// [body] - Optional request body
  ///
  /// Returns a JSON response as a Map
  /// Throws an exception if the request fails
  Future<Map<String, dynamic>> post(
    String endpoint, {
    Map<String, dynamic>? body,
  });

  /// Performs a DELETE request to the specified endpoint
  ///
  /// [endpoint] - The API endpoint path
  /// [body] - Optional request body
  ///
  /// Returns a JSON response as a Map
  /// Throws an exception if the request fails
  Future<Map<String, dynamic>> delete(
    String endpoint, {
    Map<String, dynamic>? body,
  });

  /// Performs a PUT request to the specified endpoint
  ///
  /// [endpoint] - The API endpoint path
  /// [body] - Optional request body
  ///
  /// Returns a JSON response as a Map
  /// Throws an exception if the request fails
  Future<Map<String, dynamic>> put(
    String endpoint, {
    Map<String, dynamic>? body,
  });
}
