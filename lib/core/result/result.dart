/// Result type for type-safe error handling without exceptions
///
/// Represents the result of an operation that can either succeed or fail.
/// This pattern follows the Railway-Oriented Programming paradigm and provides
/// a clean way to handle errors without try-catch blocks.
///
/// Example:
/// ```dart
/// Future<Result<User>> fetchUser() async {
///   try {
///     final user = await api.getUser();
///     return Success(user);
///   } catch (e) {
///     return Failure('Failed to fetch user', e);
///   }
/// }
///
/// // Usage
/// final result = await fetchUser();
/// switch (result) {
///   case Success(:final data):
///     print('User: ${data.name}');
///   case Failure(:final message):
///     print('Error: $message');
/// }
/// ```
sealed class Result<T> {
  const Result();

  /// Returns true if this result is a success
  bool get isSuccess => this is Success<T>;

  /// Returns true if this result is a failure
  bool get isFailure => this is Failure<T>;

  /// Returns the data if success, otherwise null
  T? get dataOrNull => this is Success<T> ? (this as Success<T>).data : null;

  /// Returns the error message if failure, otherwise null
  String? get errorOrNull =>
      this is Failure<T> ? (this as Failure<T>).message : null;

  /// Maps the success value to another type
  Result<R> map<R>(R Function(T data) transform) {
    return switch (this) {
      Success(:final data) => Success(transform(data)),
      Failure(:final message, :final exception) =>
        Failure(message, exception),
    };
  }

  /// Executes a callback based on the result type
  R when<R>({
    required R Function(T data) success,
    required R Function(String message, Exception? exception) failure,
  }) {
    return switch (this) {
      Success(:final data) => success(data),
      Failure(:final message, :final exception) => failure(message, exception),
    };
  }
}

/// Represents a successful result containing data
class Success<T> extends Result<T> {
  final T data;

  const Success(this.data);

  @override
  String toString() => 'Success(data: $data)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Success<T> &&
          runtimeType == other.runtimeType &&
          data == other.data;

  @override
  int get hashCode => data.hashCode;
}

/// Represents a failed result containing an error message
class Failure<T> extends Result<T> {
  final String message;
  final Exception? exception;

  const Failure(this.message, [this.exception]);

  @override
  String toString() =>
      'Failure(message: $message${exception != null ? ', exception: $exception' : ''})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Failure<T> &&
          runtimeType == other.runtimeType &&
          message == other.message &&
          exception == other.exception;

  @override
  int get hashCode => message.hashCode ^ exception.hashCode;
}
