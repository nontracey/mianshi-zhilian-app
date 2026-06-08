import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mianshi_zhilian/services/api_response.dart';

void main() {
  group('ApiResponse.fromJson', () {
    test('valid JSON Map response returns ApiResponse with data', () {
      final response = http.Response('{"key": "value"}', 200);
      final apiResponse = ApiResponse.fromJson(response);

      expect(apiResponse.statusCode, 200);
      expect(apiResponse.data, {'key': 'value'});
      expect(apiResponse.error, isNull);
    });

    test('invalid JSON body returns ApiResponse with error', () {
      final response = http.Response('not json', 400);
      final apiResponse = ApiResponse.fromJson(response);

      expect(apiResponse.statusCode, 400);
      expect(apiResponse.data, isNull);
      expect(apiResponse.error, contains('Invalid JSON'));
    });

    test('non-Map JSON (JSON array) returns ApiResponse with error', () {
      final response = http.Response('[1, 2, 3]', 200);
      final apiResponse = ApiResponse.fromJson(response);

      expect(apiResponse.statusCode, 200);
      expect(apiResponse.data, isNull);
      expect(apiResponse.error, contains('Unexpected JSON type'));
    });

    test('empty body returns ApiResponse with error', () {
      final response = http.Response('', 500);
      final apiResponse = ApiResponse.fromJson(response);

      expect(apiResponse.statusCode, 500);
      expect(apiResponse.data, isNull);
      expect(apiResponse.error, contains('Invalid JSON'));
    });
  });

  group('hasSuccessField', () {
    test('with {"success": true} returns true', () {
      final apiResponse = ApiResponse<Map<String, dynamic>>(
        statusCode: 200,
        data: {'success': true},
      );
      expect(apiResponse.hasSuccessField, isTrue);
    });

    test('with {"success": false} returns false', () {
      final apiResponse = ApiResponse<Map<String, dynamic>>(
        statusCode: 200,
        data: {'success': false},
      );
      expect(apiResponse.hasSuccessField, isFalse);
    });

    test('with no success field returns false', () {
      final apiResponse = ApiResponse<Map<String, dynamic>>(
        statusCode: 200,
        data: {'other': 1},
      );
      expect(apiResponse.hasSuccessField, isFalse);
    });

    test('when data is null returns false', () {
      final apiResponse = ApiResponse<Map<String, dynamic>>(
        statusCode: 200,
      );
      expect(apiResponse.hasSuccessField, isFalse);
    });
  });

  group('isSuccess', () {
    test('with status 200 returns true', () {
      final apiResponse = ApiResponse(statusCode: 200);
      expect(apiResponse.isSuccess, isTrue);
    });

    test('with status 404 returns false', () {
      final apiResponse = ApiResponse(statusCode: 404);
      expect(apiResponse.isSuccess, isFalse);
    });

    test('with status 299 returns true (upper boundary)', () {
      final apiResponse = ApiResponse(statusCode: 299);
      expect(apiResponse.isSuccess, isTrue);
    });

    test('with status 300 returns false (lower boundary)', () {
      final apiResponse = ApiResponse(statusCode: 300);
      expect(apiResponse.isSuccess, isFalse);
    });
  });

  group('requireData', () {
    test('when data exists returns data', () {
      final apiResponse = ApiResponse(statusCode: 200, data: 'hello');
      expect(apiResponse.requireData(), 'hello');
    });

    test('when data is null throws ApiResponseException', () {
      final apiResponse = ApiResponse(statusCode: 404, error: 'Not found');
      expect(
        () => apiResponse.requireData(),
        throwsA(isA<ApiResponseException>()),
      );
    });

    test('thrown exception contains status code and error message', () {
      final apiResponse = ApiResponse(statusCode: 500, error: 'Server error');
      try {
        apiResponse.requireData();
        fail('Expected ApiResponseException');
      } on ApiResponseException catch (e) {
        expect(e.statusCode, 500);
        expect(e.message, contains('Server error'));
        expect(e.toString(), contains('ApiResponseException(500)'));
      }
    });
  });
}
