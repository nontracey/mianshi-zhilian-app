import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiResponse<T> {
  final int statusCode;
  final T? data;
  final String? error;

  const ApiResponse({required this.statusCode, this.data, this.error});

  bool get isSuccess => statusCode >= 200 && statusCode < 300;
  bool get hasSuccessField => data is Map<String, dynamic> && (data as Map<String, dynamic>)['success'] == true;

  static ApiResponse<Map<String, dynamic>> fromJson(http.Response response) {
    try {
      final body = json.decode(response.body);
      if (body is Map<String, dynamic>) {
        return ApiResponse(statusCode: response.statusCode, data: body);
      }
      return ApiResponse(
        statusCode: response.statusCode,
        error: 'Unexpected JSON type: ${body.runtimeType}',
      );
    } catch (e) {
      return ApiResponse(
        statusCode: response.statusCode,
        error: 'Invalid JSON: $e',
      );
    }
  }

  T requireData() {
    if (data == null) throw ApiResponseException('No data: $error', statusCode);
    return data!;
  }
}

class ApiResponseException implements Exception {
  final String message;
  final int statusCode;

  ApiResponseException(this.message, this.statusCode);

  @override
  String toString() => 'ApiResponseException($statusCode): $message';
}
