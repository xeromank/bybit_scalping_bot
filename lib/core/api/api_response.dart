/// Generic API response wrapper for Bybit API
///
/// This class represents the standard response structure from Bybit API.
/// All Bybit API endpoints return responses in this format.
///
/// Responsibility: Provide a type-safe wrapper for API responses
class ApiResponse<T> {
  final int retCode;
  final String retMsg;
  final T? result;
  final Map<String, dynamic>? retExtInfo;
  final int? time;

  const ApiResponse({
    required this.retCode,
    required this.retMsg,
    this.result,
    this.retExtInfo,
    this.time,
  });

  /// Returns true if the API call was successful
  bool get isSuccess => retCode == 0;

  /// Returns true if the API call failed
  bool get isFailure => !isSuccess;

  /// Creates an ApiResponse from JSON
  factory ApiResponse.fromJson(
    Map<String, dynamic> json,
    T Function(dynamic)? fromJsonT,
  ) {
    return ApiResponse<T>(
      retCode: json['retCode'] as int,
      retMsg: json['retMsg'] as String,
      result: fromJsonT != null && json['result'] != null
          ? fromJsonT(json['result'])
          : json['result'] as T?,
      retExtInfo: json['retExtInfo'] as Map<String, dynamic>?,
      time: json['time'] as int?,
    );
  }

  /// Converts ApiResponse to JSON
  Map<String, dynamic> toJson(dynamic Function(T)? toJsonT) {
    return {
      'retCode': retCode,
      'retMsg': retMsg,
      'result': toJsonT != null && result != null ? toJsonT(result as T) : result,
      if (retExtInfo != null) 'retExtInfo': retExtInfo,
      if (time != null) 'time': time,
    };
  }

  @override
  String toString() =>
      'ApiResponse(retCode: $retCode, retMsg: $retMsg, result: $result)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ApiResponse<T> &&
          runtimeType == other.runtimeType &&
          retCode == other.retCode &&
          retMsg == other.retMsg &&
          result == other.result;

  @override
  int get hashCode => retCode.hashCode ^ retMsg.hashCode ^ result.hashCode;
}
