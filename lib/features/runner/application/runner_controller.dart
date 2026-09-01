import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../../auth/domain/auth_models.dart';
import '../../ordering/application/ordering_providers.dart';
import '../../ordering/domain/ordering_models.dart';
import '../data/location_repository.dart';
import '../domain/runner_models.dart';

/// Dropoff halls a synthesized preview job might land on — there's no
/// per-order dropoff backend yet, just like [RunnerController]'s own
/// demo-offer synthesis below.
const _previewDropoffs = [
  ('Queen Elizabeth II Hall', 'Room B12 · Central Campus'),
  ('Tedder Hall', 'Room A4 · North Campus'),
  ('Independence Hall', 'Room C7 · South Campus'),
  ('Kuti Hall', 'Room D2 · Central Campus'),
];

/// Turns one eatery into a browsable job preview with varied (but
/// deterministic per-eatery) payout/distance/dropoff — so the Jobs
/// screen's Available list doesn't read as identical cloned cards.
DeliveryJob previewJobFor(Eatery eatery, String campusId) {
  final seed = Random(eatery.id.hashCode);
  final dropoff = _previewDropoffs[seed.nextInt(_previewDropoffs.length)];
  final now = DateTime.now();
  return DeliveryJob(
    id: 'preview-${eatery.id}',
    campusId: campusId,
    eateryName: eatery.name,
    eateryLocation: 'Student Centre, Main Walk',
    dropoffZone: dropoff.$1,
    dropoffLocation: dropoff.$2,
    payoutAmount: 550 + seed.nextInt(14) * 50,
    estimatedDistanceMeters: 300 + seed.nextInt(9) * 100,
    offeredAt: now,
    expiresAt: now.add(const Duration(minutes: 10)),
  );
}

/// Jobs a runner could browse and choose to accept right now — there's no
/// separate job-listing backend yet, so this reuses the same
/// campus-scoped eatery data [RunnerController]'s single-offer flow
/// already draws from ([campusEateriesProvider]), just previewed as a
/// full list instead of one random pick.
final availableJobsProvider = FutureProvider<List<DeliveryJob>>((ref) async {
  final user = ref.watch(authControllerProvider)?.user;
  if (user == null) return const [];
  final eateries = await ref.watch(campusEateriesProvider.future);
  return [for (final eatery in eateries) previewJobFor(eatery, user.campusId)];
});

/// Result of a "go online" attempt — distinct from a plain bool so the UI
/// can show the right message for *why* it was blocked.
enum GoOnlineResult {
  success,
  hasActiveDelivery,
  notVerified,
  outsideCampusBoundary,
  locationUnavailable,
}

/// Result of an "accept job" attempt. [blocked] covers the pre-existing
/// defense-in-depth guards (no offer, already delivering, offer tied to
/// the wrong campus) — none of which the UI has ever surfaced feedback
/// for; [notVerified]/[outsideCampusBoundary]/[locationUnavailable] are
/// specific, user-facing outcomes.
enum AcceptOfferResult {
  accepted,
  blocked,
  notVerified,
  outsideCampusBoundary,
  locationUnavailable,
}

enum _GeofenceCheck { inside, outside, locationUnavailable }

class RunnerSession {
  const RunnerSession({
    required this.status,
    this.offer,
    this.offerSecondsRemaining = 0,
    this.activeDelivery,
    this.earnings = const [],
    this.noJobsInZone = false,
    this.offersReceived = 0,
    this.offersAccepted = 0,
  });
  final RunnerStatus status;
  final DeliveryJob? offer;
  final int offerSecondsRemaining;
  final ActiveDelivery? activeDelivery;
  final List<EarningsRecord> earnings;

  /// True once we've checked and found zero vendors in the runner's own
  /// campus — distinct from "online and simply waiting for the next job".
  final bool noJobsInZone;

  /// How many system-scheduled offers (the Home dashboard's 20s-countdown
  /// offer, not the Jobs screen's browse-and-pick Available list) this
  /// runner has been shown, and how many of those they actually accepted
  /// — a genuine, session-scoped acceptance signal, not a fabricated
  /// percentage. See [RunnerController.acceptOffer]/[_startOfferCountdown].
  final int offersReceived;
  final int offersAccepted;

  RunnerSession copyWith({
    RunnerStatus? status,
    DeliveryJob? offer,
    bool clearOffer = false,
    int? offerSecondsRemaining,
    ActiveDelivery? activeDelivery,
    bool clearActiveDelivery = false,
    List<EarningsRecord>? earnings,
    bool? noJobsInZone,
    int? offersReceived,
    int? offersAccepted,
  }) => RunnerSession(
    status: status ?? this.status,
    offer: clearOffer ? null : offer ?? this.offer,
    offerSecondsRemaining: offerSecondsRemaining ?? this.offerSecondsRemaining,
    activeDelivery: clearActiveDelivery
        ? null
        : activeDelivery ?? this.activeDelivery,
    earnings: earnings ?? this.earnings,
    noJobsInZone: noJobsInZone ?? this.noJobsInZone,
    offersReceived: offersReceived ?? this.offersReceived,
    offersAccepted: offersAccepted ?? this.offersAccepted,
  );
}

class RunnerController extends Notifier<RunnerSession> {
  Timer? _offerDelay;
  Timer? _countdown;
  final _random = Random();
  var _disposed = false;

  @override
  RunnerSession build() {
    _disposed = false;
    ref.onDispose(() {
      _disposed = true;
      _cancelTimers();
    });
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
    if (next == RunnerAvailability.online) {
      _scheduleOffer();
    } else {
      _cancelTimers();
      state = state.copyWith(
        clearOffer: true,
        offerSecondsRemaining: 0,
        noJobsInZone: false,
      );
    }
    return GoOnlineResult.success;
  }

  /// `await`s the device location only for an Independent Rider — callers
  /// are expected to check `runnerType` before calling this, same reason
  /// as the guard in [toggleAvailability].
  Future<_GeofenceCheck> _checkCampusBoundary(UserProfile user) async {
    final point = await ref.read(locationRepositoryProvider).currentPosition();
    if (point == null) return _GeofenceCheck.locationUnavailable;
    return user.campus.contains(point)
        ? _GeofenceCheck.inside
        : _GeofenceCheck.outside;
  }

  /// Draws a job from every currently active vendor (Task 14: real vendor
  /// data via [campusEateriesProvider], the same list Home's browsing pulls
  /// from) — the backend has no per-vendor campus assignment yet, so there
  /// is no real subset to scope this to. The synthesized job is still
  /// tagged with the runner's OWN campusId below, purely so the existing
  /// cross-campus defense-in-depth in `acceptOffer` keeps working. If there
  /// are no active vendors at all, this resolves to `noJobsInZone` and
  /// never schedules an offer.
  Future<void> _scheduleOffer() async {
    _offerDelay?.cancel();
    if (state.status.availability != RunnerAvailability.online ||
        state.activeDelivery != null ||
        state.offer != null) {
      return;
    }
    final campusId = ref.read(authControllerProvider)?.user.campusId;
    if (campusId == null) return;

    final eateries = await ref.read(campusEateriesProvider.future);
    if (_disposed) return;
    if (state.status.availability != RunnerAvailability.online ||
        state.activeDelivery != null ||
        state.offer != null) {
      return;
    }
    if (eateries.isEmpty) {
      state = state.copyWith(noJobsInZone: true);
      return;
    }
    state = state.copyWith(noJobsInZone: false);
    _offerDelay = Timer(
      Duration(seconds: 3 + _random.nextInt(3)),
      () => _createScopedOffer(campusId, eateries),
    );
  }

  void _createScopedOffer(String campusId, List<Eatery> eateries) {
    if (state.status.availability != RunnerAvailability.online ||
        state.activeDelivery != null) {
      return;
    }
    final eatery = eateries[_random.nextInt(eateries.length)];
    final offeredAt = DateTime.now();
    final job = DeliveryJob(
      id: 'job-${offeredAt.millisecondsSinceEpoch}',
      campusId: campusId,
      eateryName: eatery.name,
      eateryLocation: 'Student Centre, Main Walk',
      dropoffZone: 'Queen Elizabeth II Hall',
      dropoffLocation: 'Room B12 · Central Campus',
      payoutAmount: 850,
      estimatedDistanceMeters: 620,
      offeredAt: offeredAt,
      expiresAt: offeredAt.add(const Duration(seconds: 20)),
    );
    _startOfferCountdown(job);
  }

  void _startOfferCountdown(DeliveryJob job) {
    state = state.copyWith(
      offer: job,
      offerSecondsRemaining: 20,
      offersReceived: state.offersReceived + 1,
    );
    _countdown = Timer.periodic(const Duration(seconds: 1), (_) {
      final remaining = job.expiresAt.difference(DateTime.now()).inSeconds + 1;
      if (remaining <= 0) {
        declineOffer();
      } else {
        state = state.copyWith(offerSecondsRemaining: remaining);
      }
    });
  }

  /// Legacy demo/test bypass — creates a generic offer immediately,
  /// without going through the campus-scoped repository lookup. Kept
  /// separate from the real scheduling path so existing previews/tests
  /// that don't set up an auth session still work.
  void _createOffer() {
    if (state.status.availability != RunnerAvailability.online ||
        state.activeDelivery != null) {
      return;
    }
    final offeredAt = DateTime.now();
    final job = DeliveryJob(
      id: 'job-${offeredAt.millisecondsSinceEpoch}',
      campusId: 'ui',
      eateryName: 'Tantalizers',
      eateryLocation: 'Student Centre, Main Walk',
      dropoffZone: 'Queen Elizabeth II Hall',
      dropoffLocation: 'Room B12 · Central Campus',
      payoutAmount: 850,
      estimatedDistanceMeters: 620,
      offeredAt: offeredAt,
      expiresAt: offeredAt.add(const Duration(seconds: 20)),
    );
    _startOfferCountdown(job);
  }

  /// Allows deterministic previews/tests without bypassing the offer state.
  void simulateOfferNow() => _createOffer();

  /// Test-only: forces a specific offer into state, bypassing scheduling
  /// entirely — used to exercise `acceptOffer()`'s campus guard with an
  /// offer that couldn't be reached through the normal (already
  /// campus-scoped) path.
  void debugInjectOffer(DeliveryJob job) {
    state = state.copyWith(offer: job, offerSecondsRemaining: 20);
  }

  Future<AcceptOfferResult> acceptOffer() async {
    final offer = state.offer;
    if (offer == null) return AcceptOfferResult.blocked;
    final result = await _acceptJob(offer);
    if (result == AcceptOfferResult.accepted) {
      state = state.copyWith(offersAccepted: state.offersAccepted + 1);
    }
    return result;
  }

  /// Accepts a specific job directly — used by the Jobs screen's
  /// Available tab, where a runner browses [availableJobsProvider] and
  /// picks one rather than responding to the single scheduled
  /// [RunnerSession.offer]. Shares every guard [acceptOffer] has
  /// (single-active-delivery, same-campus, Independent Rider geofence).
  Future<AcceptOfferResult> acceptJob(DeliveryJob job) => _acceptJob(job);

  Future<AcceptOfferResult> _acceptJob(DeliveryJob job) async {
    if (state.activeDelivery != null) return AcceptOfferResult.blocked;
    final user = ref.read(authControllerProvider)?.user;
    if (user == null || job.campusId != user.campusId) {
      // Defense in depth: even if a job somehow reached here for the
      // wrong campus, it can't be accepted.
      return AcceptOfferResult.blocked;
    }

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

    _cancelTimers();
    state = state.copyWith(
      clearOffer: true,
      offerSecondsRemaining: 0,
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
    return AcceptOfferResult.accepted;
  }

  void declineOffer() {
    if (state.offer == null) return;
    _cancelTimers();
    state = state.copyWith(clearOffer: true, offerSecondsRemaining: 0);
    _scheduleOffer();
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
    _scheduleOffer();
  }

  void _cancelTimers() {
    _offerDelay?.cancel();
    _countdown?.cancel();
    _offerDelay = null;
    _countdown = null;
  }
}

final runnerControllerProvider =
    NotifierProvider<RunnerController, RunnerSession>(RunnerController.new);
