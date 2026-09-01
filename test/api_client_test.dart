import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:run_it/core/network/api_client.dart';
import 'package:run_it/core/network/api_exception.dart';

void main() {
  group('ApiClient.get — retry-with-backoff on transport failure', () {
    test('retries a timeout/connection failure and succeeds once the backend responds', () async {
      var attempts = 0;
      final client = MockClient((request) async {
        attempts++;
        if (attempts < 3) {
          throw const SocketException('connection reset');
        }
        return http.Response(jsonEncode({'ok': true}), 200);
      });
      final api = ApiClient(httpClient: client);

      final result = await api.get('/ping');

      expect(result, {'ok': true});
      expect(attempts, 3);
    });

    test('gives up after the maximum attempts and surfaces the real error', () async {
      final client = MockClient((request) async => throw const SocketException('unreachable'));
      final api = ApiClient(httpClient: client);

      await expectLater(api.get('/ping'), throwsA(isA<SocketException>()));
    });

    test('never retries a real backend answer (4xx), even a single attempt', () async {
      var attempts = 0;
      final client = MockClient((request) async {
        attempts++;
        return http.Response(jsonEncode({'message': 'Not found'}), 404);
      });
      final api = ApiClient(httpClient: client);

      await expectLater(api.get('/missing'), throwsA(isA<ApiException>()));
      expect(attempts, 1);
    });
  });

  group('ApiClient.post — no auto-retry', () {
    test('a single transport failure is surfaced immediately, not retried', () async {
      var attempts = 0;
      final client = MockClient((request) async {
        attempts++;
        throw const SocketException('connection reset');
      });
      final api = ApiClient(httpClient: client);

      await expectLater(api.post('/orders'), throwsA(isA<SocketException>()));
      expect(attempts, 1);
    });

    test('a successful POST still returns the decoded body', () async {
      final client = MockClient(
        (request) async => http.Response(jsonEncode({'id': 'abc'}), 201),
      );
      final api = ApiClient(httpClient: client);

      final result = await api.post('/orders', body: {'x': 1});

      expect(result, {'id': 'abc'});
    });
  });

  group('ApiClient.onUnauthorized (Task 17)', () {
    tearDown(() => ApiClient.onUnauthorized = null);

    test('fires exactly once on a 401 response, before the ApiException is thrown', () async {
      var calls = 0;
      ApiClient.onUnauthorized = () => calls++;
      final client = MockClient(
        (request) async => http.Response(
          jsonEncode({'message': 'Your session has expired. Please sign in again.'}),
          401,
        ),
      );
      final api = ApiClient(httpClient: client);

      await expectLater(api.get('/auth/me'), throwsA(isA<ApiException>()));
      expect(calls, 1);
    });

    test('never fires for a 403 — a per-resource authorization failure is not a session failure', () async {
      var calls = 0;
      ApiClient.onUnauthorized = () => calls++;
      final client = MockClient(
        (request) async => http.Response(jsonEncode({'message': 'Forbidden'}), 403),
      );
      final api = ApiClient(httpClient: client);

      await expectLater(api.get('/orders/x/escrow/release'), throwsA(isA<ApiException>()));
      expect(calls, 0);
    });

    test('never fires for an unrelated 4xx (e.g. 404)', () async {
      var calls = 0;
      ApiClient.onUnauthorized = () => calls++;
      final client = MockClient((request) async => http.Response(jsonEncode({'message': 'Not found'}), 404));
      final api = ApiClient(httpClient: client);

      await expectLater(api.get('/missing'), throwsA(isA<ApiException>()));
      expect(calls, 0);
    });
  });
}

/// A minimal stand-in for dart:io's SocketException — the real class isn't
/// available on every platform target this test suite runs against, and
/// all ApiClient cares about is "some transport-level throwable, not an
/// ApiException".
class SocketException implements Exception {
  const SocketException(this.message);
  final String message;
  @override
  String toString() => 'SocketException: $message';
}
