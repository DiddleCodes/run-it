import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_io_client/socket_io_client.dart' as socket_io;

import '../../features/runner/domain/runner_models.dart';
import 'api_client.dart';
import 'api_config.dart';

final matchingRepositoryProvider = Provider<MatchingRepository>(
  (ref) => const MatchingRepository(),
);

/// Task 21b: `GET /matching/available` — backs the Jobs screen's
/// initial/reconnect list. See `MatchingService.listAvailable`'s own doc
/// comment backend-side for why this exists alongside the broadcast socket
/// rather than relying on it alone (rebroadcast is one-shot, not a
/// heartbeat).
class MatchingRepository {
  const MatchingRepository({this.client = const ApiClient()});
  final ApiClient client;

  Future<List<DeliveryJob>> listAvailable({required String token}) async {
    final decoded = await client.get('/matching/available', token: token) as List<dynamic>;
    return decoded
        .cast<Map<String, dynamic>>()
        .map(
          (json) => DeliveryJob(
            id: json['orderId'] as String,
            eateryName: json['vendorName'] as String,
            // No per-vendor address exists backend-side (Vendor has no
            // location field at all) — every job's pickup leg reads the
            // same generic campus-eatery-cluster line the old preview data
            // also used, since that was never real per-vendor data either.
            eateryLocation: 'Student Centre, Main Walk',
            dropoffZone: (json['deliveryLocationLabel'] as String?) ?? 'Delivery address on file',
            dropoffLocation: (json['deliveryLocationLabel'] as String?) ?? 'Delivery address on file',
            payoutAmount: json['payoutAmount'] as int,
            totalAmount: json['totalAmount'] as int,
            offeredAt: DateTime.parse(json['createdAt'] as String),
          ),
        )
        .toList();
  }
}

enum DispatchConnectionStatus { disconnected, connecting, connected }

/// Task 21b: the live `runner-dispatch` channel (Socket.IO, not raw
/// WebSocket — see `RunnerDispatchGateway`'s own doc comment backend-side).
/// Deliberately thin: a `new_job_available` event only ever triggers a
/// caller-supplied callback (a full re-fetch of `/matching/available`, not
/// an attempt to incrementally merge the broadcast's bare
/// `{orderId, vendorId}` payload — it doesn't carry enough to build a full
/// [DeliveryJob] card) — see [RunnerDispatchClient.connect].
class RunnerDispatchClient {
  socket_io.Socket? _socket;

  final _statusController = StreamController<DispatchConnectionStatus>.broadcast();
  Stream<DispatchConnectionStatus> get statusStream => _statusController.stream;
  DispatchConnectionStatus _status = DispatchConnectionStatus.disconnected;
  DispatchConnectionStatus get status => _status;

  void _setStatus(DispatchConnectionStatus next) {
    _status = next;
    // Guards against a disposal-order race: an independent provider's own
    // onDispose (e.g. AvailableJobsController's) may call disconnect()
    // after this client's own dispose() already closed the controller —
    // container-wide teardown order between sibling providers isn't
    // guaranteed.
    if (!_statusController.isClosed) _statusController.add(next);
  }

  /// [onNewJob] fires for every `new_job_available` broadcast/re-broadcast
  /// — callers should treat it as "go re-fetch the list", not as carrying
  /// the job itself.
  void connect({required String token, required void Function() onNewJob}) {
    disconnect();
    _setStatus(DispatchConnectionStatus.connecting);
    final socket = socket_io.io(
      '$apiBaseUrl/runner-dispatch',
      socket_io.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': token})
          .disableAutoConnect()
          .build(),
    );
    socket
      ..onConnect((_) => _setStatus(DispatchConnectionStatus.connected))
      ..onDisconnect((_) => _setStatus(DispatchConnectionStatus.disconnected))
      ..onConnectError((_) => _setStatus(DispatchConnectionStatus.disconnected))
      ..onError((_) => _setStatus(DispatchConnectionStatus.disconnected))
      ..on('new_job_available', (_) => onNewJob())
      ..connect();
    _socket = socket;
  }

  void disconnect() {
    _socket?.dispose();
    _socket = null;
    _setStatus(DispatchConnectionStatus.disconnected);
  }

  void dispose() {
    disconnect();
    _statusController.close();
  }
}

final runnerDispatchClientProvider = Provider<RunnerDispatchClient>((ref) {
  final client = RunnerDispatchClient();
  ref.onDispose(client.dispose);
  return client;
});
