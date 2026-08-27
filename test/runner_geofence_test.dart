import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:run_it/features/auth/application/auth_controller.dart';
import 'package:run_it/features/auth/domain/auth_models.dart';
import 'package:run_it/features/runner/application/runner_controller.dart';
import 'package:run_it/features/runner/data/location_repository.dart';
import 'package:run_it/features/runner/domain/runner_models.dart';

class _FakeAuthController extends AuthController {
  _FakeAuthController(this._session);
  final AuthSession _session;
  @override
  AuthSession? build() => _session;
}

class _FakeLocationRepository implements LocationRepository {
  const _FakeLocationRepository(this._point);
  final GeoPoint? _point;
  @override
  Future<GeoPoint?> currentPosition() async => _point;
}

final _uiCampus = kCampuses.firstWhere((c) => c.id == 'ui');
final _insideCampus = GeoPoint(
  latitude: _uiCampus.latitude,
  longitude: _uiCampus.longitude,
);
// Roughly 5.5km north — well outside the 900m default campus radius.
final _outsideCampus = GeoPoint(
  latitude: _uiCampus.latitude + 0.05,
  longitude: _uiCampus.longitude,
);

AuthSession _sessionFor({required RunnerType? runnerType}) => AuthSession(
  accessToken: 'test-access',
  refreshToken: 'test-refresh',
  expiresAt: DateTime.now().add(const Duration(minutes: 5)),
  user: UserProfile(
    id: 'runner-1',
    name: 'Test Runner',
    contact: '+2348000000000',
    accountType: AccountType.runner,
    campusId: 'ui',
    kycStatus: KycStatus.verified,
    runnerType: runnerType,
  ),
);

ProviderContainer _containerFor(RunnerType? runnerType, GeoPoint? point) {
  final container = ProviderContainer(
    overrides: [
      authControllerProvider.overrideWith(
        () => _FakeAuthController(_sessionFor(runnerType: runnerType)),
      ),
      locationRepositoryProvider.overrideWithValue(
        _FakeLocationRepository(point),
      ),
    ],
  );
  return container;
}

void main() {
  group('Independent Rider geofence on going online', () {
    test('inside the campus boundary: goes online normally', () async {
      final container = _containerFor(
        RunnerType.independentRider,
        _insideCampus,
      );
      addTearDown(container.dispose);
      final controller = container.read(runnerControllerProvider.notifier);

      final result = await controller.toggleAvailability();

      expect(result, GoOnlineResult.success);
      expect(
        container.read(runnerControllerProvider).status.availability,
        RunnerAvailability.online,
      );
    });

    test('outside the campus boundary: blocked, stays offline', () async {
      final container = _containerFor(
        RunnerType.independentRider,
        _outsideCampus,
      );
      addTearDown(container.dispose);
      final controller = container.read(runnerControllerProvider.notifier);

      final result = await controller.toggleAvailability();

      expect(result, GoOnlineResult.outsideCampusBoundary);
      expect(
        container.read(runnerControllerProvider).status.availability,
        RunnerAvailability.offline,
      );
    });

    test(
      'location unavailable: reported as such, not a silent failure',
      () async {
        final container = _containerFor(RunnerType.independentRider, null);
        addTearDown(container.dispose);
        final controller = container.read(runnerControllerProvider.notifier);

        final result = await controller.toggleAvailability();

        expect(result, GoOnlineResult.locationUnavailable);
        expect(
          container.read(runnerControllerProvider).status.availability,
          RunnerAvailability.offline,
        );
      },
    );
  });

  group('Student Runners are unaffected by the geofence', () {
    test(
      'a student runner goes online even when "outside" the boundary',
      () async {
        final container = _containerFor(
          RunnerType.studentRunner,
          _outsideCampus,
        );
        addTearDown(container.dispose);
        final controller = container.read(runnerControllerProvider.notifier);

        final result = await controller.toggleAvailability();

        expect(result, GoOnlineResult.success);
        expect(
          container.read(runnerControllerProvider).status.availability,
          RunnerAvailability.online,
        );
      },
    );

    test(
      'a runner with no runnerType set (legacy/unset) is also unaffected',
      () async {
        final container = _containerFor(null, null);
        addTearDown(container.dispose);
        final controller = container.read(runnerControllerProvider.notifier);

        final result = await controller.toggleAvailability();

        expect(result, GoOnlineResult.success);
        expect(
          container.read(runnerControllerProvider).status.availability,
          RunnerAvailability.online,
        );
      },
    );
  });

  group('the geofence also gates accepting an offer', () {
    test(
      'an independent rider outside the boundary cannot accept an offer',
      () async {
        final container = _containerFor(
          RunnerType.independentRider,
          _outsideCampus,
        );
        addTearDown(container.dispose);
        final controller = container.read(runnerControllerProvider.notifier);

        final job = DeliveryJob(
          id: 'job-1',
          campusId: 'ui',
          eateryName: 'Test Eatery',
          eateryLocation: 'Somewhere',
          dropoffZone: 'Hall',
          dropoffLocation: 'Room 1',
          payoutAmount: 500,
          estimatedDistanceMeters: 300,
          offeredAt: DateTime.now(),
          expiresAt: DateTime.now().add(const Duration(seconds: 20)),
        );
        controller.debugInjectOffer(job);

        final result = await controller.acceptOffer();

        expect(result, AcceptOfferResult.outsideCampusBoundary);
        expect(container.read(runnerControllerProvider).activeDelivery, isNull);
      },
    );
  });
}
