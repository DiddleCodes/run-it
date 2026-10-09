import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'api_client.dart';

final uploadsRepositoryProvider = Provider<UploadsRepository>(
  (ref) => const UploadsRepository(),
);

/// The presign-then-PUT-then-register pattern Task 9's backend expects: ask
/// this app's own backend for a one-time upload URL, PUT the raw bytes
/// straight to storage (never through this app's own backend), then hand
/// the returned `fileUrl` to whichever endpoint records it. Menu photos and
/// logos get a public URL; ID, selfie, delivery, handoff and dispute photos
/// go to a private bucket and get a `private://` reference instead, which
/// only the backend can turn into a (short-lived) viewable link.
class UploadsRepository {
  const UploadsRepository({this.client = const ApiClient(), this.httpClient});

  final ApiClient client;

  /// Only ever overridden by a test — production callers always PUT
  /// through a real `http.Client()`, created fresh per upload since this
  /// class has no long-lived state of its own.
  final http.Client? httpClient;

  /// Returns what to hand to whichever endpoint registers this upload: a
  /// public URL, or a private reference.
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
    final fileUrl = (presign['fileUrl'] ?? presign['publicUrl']) as String;

    final putClient = httpClient ?? http.Client();
    final response = await putClient
        // Size and type are signed into the URL: send exactly what was declared.
        .put(Uri.parse(uploadUrl), headers: {'Content-Type': contentType}, body: bytes)
        .timeout(ApiClient.requestTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Upload failed (HTTP ${response.statusCode})');
    }
    return fileUrl;
  }
}
