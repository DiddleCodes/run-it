import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/campus_repository.dart';
import '../../../core/network/escrow_repository.dart';
import '../../../core/network/matching_repository.dart';

export '../../../core/network/matching_repository.dart' show DispatchConnectionStatus;
import '../../auth/application/auth_controller.dart';
import '../../auth/domain/auth_models.dart';
import '../data/location_repository.dart';
import '../domain/runner_models.dart';

/// Result of a "go online" attempt — distinct from a plain bool so the UI
/// can show the right message for *why* it was blocked.
enum GoOnlineResult {
  success,
  hasActiveDelivery,
  notVerified,
  outsideCampusBoundary,
  locationUnavailable,
}

/// Result of a claim attempt. [blocked] covers the pre-existing
/// defense-in-depth guards (already delivering) — none of which the UI has
/// ever surfaced feedback for; [alreadyClaimed] is the broadcast model's
/// normal, expected "someone else won the race" outcome (backend's `409
/// ORDER_ALREADY_CLAIMED`), never shown as a generic error;
/// [networkError] covers everything else (couldn't reach the backend, or
/// it rejected the claim for some other reason).
enum AcceptOfferResult {
  accepted,
  blocked,
  notVerified,
  outsideCampusBoundary,
  locationUnavailable,
  alreadyClaimed,
  networkError,
}

enum _GeofenceCheck { inside, outside, locationUnavailable }

class RunnerSession {
  const RunnerSession({
    required this.status,
    this.activeDelivery,
    this.earnings = const [],
    this.offersReceived = 0,
    this.offersAccepted = 0,
  });
  final RunnerStatus status;
  final ActiveDelivery? activeDelivery;
  final List<EarningsRecord> earnings;

  /// Task 21b: real claim-attempt/claim-won counts — how many times this
  /// runner has tried to claim a broadcast job this session, and how many
  /// of those actually won the race. See
  /// [RunnerController.acceptJob]/[RunnerProfileScreen]'s own doc comment
  /// for the acceptance-rate stat this backs.
  final int offersReceived;
  final int offersAccepted;

  RunnerSession copyWith({
    RunnerStatus? status,
    ActiveDelivery? activeDelivery,
    bool clearActiveDelivery = false,
    List<EarningsRecord>? earnings,
    int? offersReceived,
    int? offersAccepted,
  }) => RunnerSession(
    status: status ?? this.status,
    activeDelivery: clearActiveDelivery
        ? null
        : activeDelivery ?? this.activeDelivery,
    earnings: earnings ?? this.earnings,
    offersReceived: offersReceived ?? this.offersReceived,
    offersAccepted: offersAccepted ?? this.offersAccepted,
  );
}

class RunnerController extends Notifier<RunnerSession> {
  @override
  RunnerSession build() {
    return const RunnerSession(
      status: RunnerStatus(availability: RunnerAvailability.offline),
    );
  }

  /// Independent Riders (and only Independent Riders — Student Runners are
  /// already tied to campus by their verified student email, and may
  /// reasonably start a delivery leaving/entering campus edges) must be
  /// physically on campus to go online. That check only ever runs — and
  /// only ever `await`s anything — on the "going online" transition for
  /// that one account type; every other caller (going offline, students,
  /// student runners, and every pre-existing test) flips synchronously,
  /// exactly as before this check existed.
  ///
  /// The verified-KYC check just above it, by contrast, applies to going
  /// online for BOTH runner types equally — "Verified" is an identity gate
  /// (ID + selfie match, + vehicle proof for Independent Riders), not a
  /// geofencing concern, so it isn't scoped to one runner type.
  Future<GoOnlineResult> toggleAvailability() async {
    if (state.activeDelivery != null) return GoOnlineResult.hasActiveDelivery;
    final goingOnline = state.status.availability != RunnerAvailability.online;
    final user = ref.read(authControllerProvider)?.user;

    if (goingOnline && user?.kycStatus != KycStatus.verified) {
      return GoOnlineResult.notVerified;
    }

    if (goingOnline && user?.runnerType == RunnerType.independentRider) {
      switch (await _checkCampusBoundary(user!)) {
        case _GeofenceCheck.outside:
          return GoOnlineResult.outsideCampusBoundary;
        case _GeofenceCheck.locationUnavailable:
          return GoOnlineResult.locationUnavailable;
        case _GeofenceCheck.inside:
          break;
      }
    }

    final next = goingOnline
        ? RunnerAvailability.online
        : RunnerAvailability.offline;
    state = state.copyWith(
      status: RunnerStatus(
        availability: next,
        isVerifiedRunner: state.status.isVerifiedRunner,
      ),
    );
    // availableJobsProvider watches state.status.availability itself
    // (connects/disconnects the runner-dispatch socket and
    // fetches/clears the list accordingly) — nothing to kick off here.
    return GoOnlineResult.success;
  }

  /// `await`s the device location only for an Independent Rider — callers
  /// are expected to check `runnerType` before calling this, same reason
  /// as the guard in [toggleAvailability].
  /// Task 26: the real backend `Campus` model carries no lat/lng (out of
  /// that task's scope — see its report), so this still leans on the old
  /// local `kCampusGeofenceReference` table, matched by name against
  /// whatever the backend says this user's campus actually is. A campus
  /// with no local geofence entry (any school beyond the four seeded ones,
  /// or one this user hasn't been assigned yet) fails open rather than
  /// permanently blocking every Independent Rider there from ever going
  /// online over a data gap that isn't their fault.
  Future<_GeofenceCheck> _checkCampusBoundary(UserProfile user) async {
    final point = await ref.read(locationRepositoryProvider).currentPosition();
    if (point == null) return _GeofenceCheck.locationUnavailable;
    // Awaits the real fetch directly (rather than reading
    // campusNameProvider's possibly-still-loading cached value) — this is
    // a one-shot check, not a widget rebuilding as data arrives, so it
    // needs the resolved answer, not whatever's in the cache the instant
    // this happens to run.
    String? campusName;
    if (user.campusId != null) {
      final campuses = await ref.read(campusesProvider.future);
      for (final campus in campuses) {
        if (campus.id == user.campusId) {
          campusName = campus.name;
          break;
        }
      }
    }
    Campus? geofence;
    for (final candidate in kCampusGeofenceReference) {
      if (candidate.name == campusName) {
        geofence = candidate;
        break;
      }
    }
    if (geofence == null) return _GeofenceCheck.inside;
    return geofence.contains(point)
        ? _GeofenceCheck.inside
        : _GeofenceCheck.outside;
  }

  /// Task 21b: claims a real broadcast job (`POST
  /// /orders/:orderId/escrow/claim`) — first-to-claim-wins, so
  /// [AcceptOfferResult.alreadyClaimed] is a normal outcome, not an error.
  /// Same KYC/geofence guards [toggleAvailability] applies to going online.
  Future<AcceptOfferResult> acceptJob(DeliveryJob job) async {
    if (state.activeDelivery != null) return AcceptOfferResult.blocked;
    final session = ref.read(authControllerProvider);
    final user = session?.user;
    if (session == null || user == null) return AcceptOfferResult.blocked;

    if (user.kycStatus != KycStatus.verified) {
      return AcceptOfferResult.notVerified;
    }

    if (user.runnerType == RunnerType.independentRider) {
      switch (await _checkCampusBoundary(user)) {
        case _GeofenceCheck.outside:
          return AcceptOfferResult.outsideCampusBoundary;
        case _GeofenceCheck.locationUnavailable:
          return AcceptOfferResult.locationUnavailable;
        case _GeofenceCheck.inside:
          break;
      }
    }

    state = state.copyWith(offersReceived: state.offersReceived + 1);

    final ClaimResult result;
    try {
      result = await ref
          .read(escrowRepositoryProvider)
          .claim(orderId: job.id, token: session.accessToken);
    } catch (_) {
      return AcceptOfferResult.networkError;
    }

    if (result == ClaimResult.alreadyClaimed) {
      ref.read(availableJobsProvider.notifier).removeJob(job.id);
      return AcceptOfferResult.alreadyClaimed;
    }

    state = state.copyWith(
      offersAccepted: state.offersAccepted + 1,
      status: RunnerStatus(
        availability: RunnerAvailability.online,
        activeDeliveryId: job.id,
        isVerifiedRunner: state.status.isVerifiedRunner,
      ),
      activeDelivery: ActiveDelivery(
        job: job,
        status: DeliveryStage.accepted,
        orderNumber: '#RI-2048',
        orderItems: const ['1 × Signature jollof', '1 × Chilled malt'],
      ),
    );
    ref.read(availableJobsProvider.notifier).removeJob(job.id);
    return AcceptOfferResult.accepted;
  }

  bool confirmPickup() {
    final active = state.activeDelivery;
    if (active == null || active.status != DeliveryStage.accepted) return false;
    state = state.copyWith(
      activeDelivery: active.copyWith(status: DeliveryStage.pickedUp),
    );
    return true;
  }

  bool confirmDropoff() {
    final active = state.activeDelivery;
    if (active == null || active.status != DeliveryStage.pickedUp) return false;
    final delivered = active.copyWith(status: DeliveryStage.delivered);
    state = state.copyWith(
      activeDelivery: delivered,
      earnings: [
        EarningsRecord(
          deliveryId: delivered.job.id,
          amount: delivered.job.payoutAmount,
          completedAt: DateTime.now(),
          eateryName: delivered.job.eateryName,
          dropoffZone: delivered.job.dropoffZone,
        ),
        ...state.earnings,
      ],
    );
    return true;
  }

  void finishDeliveredDelivery() {
    final active = state.activeDelivery;
    if (active?.status != DeliveryStage.delivered) return;
    state = state.copyWith(
      clearActiveDelivery: true,
      status: RunnerStatus(
        availability: RunnerAvailability.online,
        isVerifiedRunner: state.status.isVerifiedRunner,
      ),
    );
  }
}

final runnerControllerProvider =
    NotifierProvider<RunnerController, RunnerSession>(RunnerController.new);

/// Task 21b: the Jobs screen's Available list — real, backend-driven.
/// Fetching (`GET /matching/available`) is allowed any time this runner is
/// authenticated, same as before — Jobs has always been read-only
/// browsable regardless of online/KYC status (TASK 4g §1). Only the live
/// `runner-dispatch` socket, which is what makes a *new* job appear in
/// real time, is gated by [RunnerAvailability.online]: going offline
/// disconnects it immediately, so this runner cannot receive a live
/// broadcast while offline even if a disconnect raced with an incoming
/// event — the backend's broadcast has no notion of "available" at all
/// (see `RunnerDispatchGateway`'s own doc comment), so this gating is
/// entirely client-side by construction, not a shortcut.
class AvailableJobsController extends AsyncNotifier<List<DeliveryJob>> {
  // Captured directly, not re-read from the provider in _teardown — an
  // onDispose callback firing during whole-container teardown (e.g. widget
  // test cleanup) can't safely `ref.read` a sibling provider that may
  // already be torn down itself; holding the instance sidesteps that.
  RunnerDispatchClient? _connectedClient;

  @override
  Future<List<DeliveryJob>> build() async {
    final availability = ref.watch(
      runnerControllerProvider.select((s) => s.status.availability),
    );
    final token = ref.watch(
      authControllerProvider.select((s) => s?.accessToken),
    );
    ref.onDispose(_teardown);

    if (token == null) {
      _teardown();
      return const [];
    }

    if (availability == RunnerAvailability.online) {
      if (_connectedClient == null) {
        final client = ref.read(runnerDispatchClientProvider);
        client.connect(token: token, onNewJob: _handleNewJob);
        _connectedClient = client;
      }
    } else {
      _teardown();
    }

    return ref.read(matchingRepositoryProvider).listAvailable(token: token);
  }

  /// A `new_job_available` broadcast only ever carries `{orderId,
  /// vendorId}` (see `NewJobBroadcast`/`RunnerDispatchGateway.broadcastNewJob`
  /// backend-side) — not enough to build a full [DeliveryJob] card, so this
  /// re-fetches the whole list rather than trying to merge a partial
  /// payload. `invalidateSelf` re-runs [build] with the socket already
  /// connected, so it's never torn down/reconnected here — only the REST
  /// fetch repeats.
  void _handleNewJob() => ref.invalidateSelf();

  void _teardown() {
    _connectedClient?.disconnect();
    _connectedClient = null;
  }

  /// Called after a lost claim race (409) or a won one — prunes the job
  /// locally immediately, rather than leaving a now-stale "available" job
  /// visible until the next broadcast/refresh happens to remove it.
  void removeJob(String orderId) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(current.where((job) => job.id != orderId).toList());
  }
}

final availableJobsProvider =
    AsyncNotifierProvider<AvailableJobsController, List<DeliveryJob>>(
      AvailableJobsController.new,
    );

/// Task 21b: "a runner shouldn't silently stop receiving jobs if the
/// socket drops without visible indication" — the Jobs screen watches this
/// to show a small non-blocking banner rather than nothing at all. Seeds
/// with the client's current status immediately (`Stream.multi`) rather
/// than starting every listener at `AsyncLoading`, since `connect()` may
/// already have fired status events before this provider gets watched.
final dispatchConnectionStatusProvider = StreamProvider<DispatchConnectionStatus>((ref) {
  final client = ref.watch(runnerDispatchClientProvider);
  return Stream.multi((controller) {
    controller.add(client.status);
    final subscription = client.statusStream.listen(controller.add);
    controller.onCancel = subscription.cancel;
  });
});
