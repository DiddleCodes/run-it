import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'api_client.dart';

final uploadsRepositoryProvider = Provider<UploadsRepository>(
  (ref) => const UploadsRepository(),
);

/// The presign-then-PUT-then-register pattern Task 9's backend expects: ask
/// this app's own backend for a one-time upload URL, PUT the raw bytes
/// straight to storage (never through this app's own backend), then hand
/// the resulting public URL to whichever endpoint actually wants it
/// recorded — here, `OrdersRepository.submitDeliveryProof`.
class UploadsRepository {
  const UploadsRepository({this.client = const ApiClient(), this.httpClient});

  final ApiClient client;

  /// Only ever overridden by a test — production callers always PUT
  /// through a real `http.Client()`, created fresh per upload since this
  /// class has no long-lived state of its own.
  final http.Client? httpClient;

  /// Returns the public URL to hand to whichever endpoint registers this
  /// upload.
  Future<String> uploadImage({
    required List<int> bytes,
    required String purpose,
    required String contentType,
    required String token,
  }) async {
    final presign =
        await client.post(
              '/uploads/presign',
              token: token,
              body: {
                'purpose': purpose,
                'contentType': contentType,
                'contentLengthBytes': bytes.length,
              },
            )
            as Map<String, dynamic>;

    final uploadUrl = presign['uploadUrl'] as String;
    final publicUrl = presign['publicUrl'] as String;

    final putClient = httpClient ?? http.Client();
    final response = await putClient
        .put(Uri.parse(uploadUrl), headers: {'Content-Type': contentType}, body: bytes)
        .timeout(ApiClient.requestTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Upload failed (HTTP ${response.statusCode})');
    }
    return publicUrl;
  }
}
