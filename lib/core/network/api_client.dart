import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'api_exception.dart';

/// Thin JSON wrapper over `package:http` — the app's first *real* network
/// boundary (every other repository so far — [AuthRepository],
/// `WalletBalanceController` — is still deliberately client-mocked; see
/// their own doc comments). [ApiException] is thrown for a non-2xx
/// response; a connectivity failure (no route to the backend, timeout)
/// throws whatever `package:http` itself throws and is left to bubble up,
/// so callers can tell "the backend rejected this" apart from "couldn't
/// reach the backend" instead of collapsing both into one generic error.
///
/// Task 10 performance audit: every request now has a bounded
/// [requestTimeout], and `GET`s retry with exponential backoff on a
/// transport-level failure (timeout, no route — relevant given unreliable
/// campus wifi). `POST`s are deliberately **not** auto-retried here: unlike
/// most of this backend's endpoints (Task 9b hardened wallet/escrow
/// idempotency specifically), not every POST is proven idempotent against a
/// blind client-side retry (e.g. `/wallet/fund/initialize` mints a fresh
/// reference every call), and a network layer is the wrong place to guess
/// per-endpoint safety. A POST that times out surfaces a clear error and
/// leaves retrying to the user's own action (tapping the button again),
/// consistent with "no optimistic UI for wallet/payment state."
class ApiClient {
  /// [httpClient] defaults to `null` rather than `http.Client()` so this
  /// stays a `const` constructor (every repository builds one as a field
  /// initializer, e.g. `final _repository = const PayoutRepository();`) —
  /// falls back to the top-level `http.get`/`http.post` functions, and only
  /// tests that need to inject an `http.testing.MockClient` pass one in.
  const ApiClient({this.baseUrl = apiBaseUrl, this.httpClient});

  final String baseUrl;
  final http.Client? httpClient;

  static const requestTimeout = Duration(seconds: 12);
  static const _maxAttempts = 3;
  static const _initialBackoff = Duration(milliseconds: 400);

  Map<String, String> _headers(String? token) => {
    'Content-Type': 'application/json',
    if (token != null) 'Authorization': 'Bearer $token',
  };

  Future<dynamic> get(String path, {String? token}) {
    final uri = Uri.parse('$baseUrl$path');
    return _withRetry(() async {
      final client = httpClient;
      final response = client != null
          ? await client.get(uri, headers: _headers(token)).timeout(requestTimeout)
          : await http.get(uri, headers: _headers(token)).timeout(requestTimeout);
      return _decode(response);
    });
  }

  Future<dynamic> post(
    String path, {
    Map<String, dynamic>? body,
    String? token,
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    final encodedBody = body == null ? null : jsonEncode(body);
    final client = httpClient;
    final response = client != null
        ? await client.post(uri, headers: _headers(token), body: encodedBody).timeout(requestTimeout)
        : await http.post(uri, headers: _headers(token), body: encodedBody).timeout(requestTimeout);
    return _decode(response);
  }

  // Same no-auto-retry reasoning as post() — a PATCH/DELETE isn't proven
  // safe to blind-retry across this backend's endpoints in general.
  Future<dynamic> patch(
    String path, {
    Map<String, dynamic>? body,
    String? token,
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    final encodedBody = body == null ? null : jsonEncode(body);
    final client = httpClient;
    final response = client != null
        ? await client.patch(uri, headers: _headers(token), body: encodedBody).timeout(requestTimeout)
        : await http.patch(uri, headers: _headers(token), body: encodedBody).timeout(requestTimeout);
    return _decode(response);
  }

  Future<dynamic> delete(String path, {String? token}) async {
    final uri = Uri.parse('$baseUrl$path');
    final client = httpClient;
    final response = client != null
        ? await client.delete(uri, headers: _headers(token)).timeout(requestTimeout)
        : await http.delete(uri, headers: _headers(token)).timeout(requestTimeout);
    return _decode(response);
  }

  /// Retries only a transport-level failure (timeout, socket/client
  /// exception — "couldn't reach the backend at all"). A decoded
  /// [ApiException] is a real answer from the backend and is never
  /// retried — retrying a definitive 4xx/5xx would just get the same
  /// answer again.
  Future<dynamic> _withRetry(Future<dynamic> Function() attempt) async {
    var backoff = _initialBackoff;
    for (var attemptNumber = 1; ; attemptNumber++) {
      try {
        return await attempt();
      } on ApiException {
        rethrow;
      } catch (_) {
        if (attemptNumber >= _maxAttempts) rethrow;
        await Future<void>.delayed(backoff);
        backoff *= 2;
      }
    }
  }

  /// Task 17: set once, at app startup, so every `ApiClient` instance —
  /// including each repository's own default `const ApiClient()` — reacts
  /// to a backend-confirmed-invalid session (expired or suspended; the
  /// response never distinguishes which) the same way, without every
  /// repository needing its own Riverpod-provided client just for this one
  /// cross-cutting concern. A 401 here always means the *session* is bad —
  /// a per-resource authorization failure (e.g. "not a party to this
  /// order") is a 403 precisely so it's never mistaken for this.
  static void Function()? onUnauthorized;

  dynamic _decode(http.Response response) {
    final decoded = response.body.isEmpty ? null : jsonDecode(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return decoded;
    }
    if (response.statusCode == 401) onUnauthorized?.call();
    throw ApiException(response.statusCode, _extractMessage(decoded));
  }

  String _extractMessage(dynamic decoded) {
    if (decoded is! Map<String, dynamic>) {
      return 'Something went wrong. Please try again.';
    }
    final message = decoded['message'];
    if (message is String) return message;
    if (message is List && message.isNotEmpty) return message.first.toString();
    return 'Something went wrong. Please try again.';
  }
}
