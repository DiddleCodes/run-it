import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:run_it/core/network/api_client.dart';
import 'package:run_it/core/network/uploads_repository.dart';

/// The backend's presign, then storage's PUT — recording what the app sent.
({UploadsRepository repository, List<http.Request> requests}) _repository(Map<String, Object?> presign) {
  final requests = <http.Request>[];
  final client = MockClient((request) async {
    requests.add(request);
    if (request.url.path == '/uploads/presign') return http.Response(jsonEncode(presign), 201);
    return http.Response('', 200); // the storage PUT
  });
  return (
    repository: UploadsRepository(client: ApiClient(baseUrl: 'https://api.test', httpClient: client), httpClient: client),
    requests: requests,
  );
}

void main() {
  final bytes = List<int>.filled(1234, 7);

  test('a private photo (ID, delivery proof…) returns its private reference — there is no public URL', () async {
    const ref = 'private://runner-kyc-id/runner-1/3f2b8c1e-9a4d-4e5f-8b6a-1c2d3e4f5a6b.jpg';
    final (:repository, :requests) = _repository({
      'uploadUrl': 'https://storage.test/private/runner-kyc-id/x.jpg?X-Amz-Signature=abc',
      'fileUrl': ref,
      'publicUrl': null,
      'expiresInSeconds': 300,
    });

    final result = await repository.uploadImage(bytes: bytes, purpose: 'runner-kyc-id', contentType: 'image/jpeg', token: 't');

    expect(result, ref);
    expect(jsonDecode(requests.first.body), {'purpose': 'runner-kyc-id', 'contentType': 'image/jpeg', 'contentLengthBytes': 1234});
    // Exactly the declared size and type — both are signed into the upload URL.
    final put = requests.last;
    expect(put.method, 'PUT');
    expect(put.bodyBytes.length, 1234);
    expect(put.headers['Content-Type'], startsWith('image/jpeg'));
  });

  test('a menu photo returns its public URL', () async {
    const url = 'https://media.test/menu-item-photo/x.png';
    final (:repository, requests: _) = _repository({'uploadUrl': 'https://storage.test/put', 'fileUrl': url, 'publicUrl': url});
    expect(await repository.uploadImage(bytes: bytes, purpose: 'menu-item-photo', contentType: 'image/png', token: 't'), url);
  });

  test('still works with a backend that only returns publicUrl', () async {
    const url = 'https://media.test/vendor-logo/x.png';
    final (:repository, requests: _) = _repository({'uploadUrl': 'https://storage.test/put', 'publicUrl': url});
    expect(await repository.uploadImage(bytes: bytes, purpose: 'vendor-logo', contentType: 'image/png', token: 't'), url);
  });
}
