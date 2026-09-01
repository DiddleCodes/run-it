import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:run_it/core/network/vendors_repository.dart';
import 'package:run_it/features/auth/application/auth_controller.dart';
import 'package:run_it/features/auth/domain/auth_models.dart';
import 'package:run_it/features/runner/application/runner_controller.dart';
import 'package:run_it/features/runner/domain/runner_models.dart';
import 'package:run_it/features/vendor/domain/vendor_dashboard_models.dart';

class _FakeAuthController extends AuthController {
  _FakeAuthController(this._session);
  final AuthSession _session;
  @override
  AuthSession? build() => _session;
}

/// In-memory stand-in for the real, network-backed `VendorsRepository` —
/// every test that goes online (`toggleAvailability`) exercises
/// `RunnerController._scheduleOffer`, which now fetches from
/// `campusEateriesProvider` (real `GET /vendors`, Task 14) instead of the
/// old `MockOrderingRepository`. [vendors] defaults to one active vendor so
/// existing offer-flow tests keep receiving an offer; the "no active
/// vendors" test overrides it with an empty list instead.
class _FakeVendorsRepository extends VendorsRepository {
  const _FakeVendorsRepository([this.vendors = const [_defaultVendor]]);
  final List<MyVendorProfile> vendors;

  static const _defaultVendor = MyVendorProfile(id: 'tantalizers', businessName: 'Tantalizers', category: 'Meals');

  @override
  Future<VendorsPage> listVendors({String? category, String? search, int page = 1, int limit = 20}) async {
    return VendorsPage(items: vendors, total: vendors.length, page: page, limit: limit);
  }
}

AuthSession _sessionForCampus(
  String campusId, {
  KycStatus kycStatus = KycStatus.verified,
  RunnerType runnerType = RunnerType.studentRunner,
}) => AuthSession(
  accessToken: 'test-access',
  refreshToken: 'test-refresh',
  expiresAt: DateTime.now().add(const Duration(minutes: 5)),
  user: UserProfile(
    id: 'runner-1',
    name: 'Test Runner',
    contact: '+2348000000000',
    accountType: AccountType.runner,
    campusId: campusId,
    kycStatus: kycStatus,
    runnerType: runnerType,
  ),
);

void main() {
  test('runner delivery state machine only permits forward transitions', () {
    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(
          () => _FakeAuthController(_sessionForCampus('ui')),
        ),
        vendorsRepositoryProvider.overrideWithValue(const _FakeVendorsRepository()),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(runnerControllerProvider.notifier);

    expect(controller.confirmPickup(), isFalse);
    controller.toggleAvailability();
    controller.simulateOfferNow();
    expect(container.read(runnerControllerProvider).offer, isNotNull);

    controller.acceptOffer();
    expect(
      container.read(runnerControllerProvider).activeDelivery!.status,
      DeliveryStage.accepted,
    );
    expect(controller.confirmDropoff(), isFalse);

    expect(controller.confirmPickup(), isTrue);
    expect(controller.confirmDropoff(), isTrue);
    expect(
      container.read(runnerControllerProvider).activeDelivery!.status,
      DeliveryStage.delivered,
    );
    expect(container.read(runnerControllerProvider).earnings, hasLength(1));
  });

  test(
    // Task 14: the backend has no per-campus vendor assignment, so there's
    // no longer a "this campus has no vendors" case to scope to — the only
    // remaining "no jobs" condition is genuinely zero active vendors
    // anywhere.
    'a runner never receives an offer when there are no active vendors at all',
    () async {
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith(
            () => _FakeAuthController(_sessionForCampus('ui')),
          ),
          vendorsRepositoryProvider.overrideWithValue(const _FakeVendorsRepository([])),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(runnerControllerProvider.notifier);

      controller.toggleAvailability();
      // Lets the repository-scoped lookup (a delayed Future, not a Timer)
      // resolve before asserting.
      await Future.delayed(const Duration(milliseconds: 400));

      final session = container.read(runnerControllerProvider);
      expect(session.noJobsInZone, isTrue);
      expect(session.offer, isNull);
    },
  );

  test(
    'acceptOffer rejects an offer tied to a different campus than the runner',
    () {
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith(
            () => _FakeAuthController(_sessionForCampus('ui')),
          ),
          vendorsRepositoryProvider.overrideWithValue(const _FakeVendorsRepository()),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(runnerControllerProvider.notifier);
      controller.toggleAvailability();

      final crossCampusJob = DeliveryJob(
        id: 'job-cross-campus',
        campusId: 'oau', // the runner above belongs to 'ui', not 'oau'
        eateryName: 'Some Other Campus Spot',
        eateryLocation: 'Elsewhere',
        dropoffZone: 'Elsewhere Hall',
        dropoffLocation: 'Room 1',
        payoutAmount: 500,
        estimatedDistanceMeters: 300,
        offeredAt: DateTime.now(),
        expiresAt: DateTime.now().add(const Duration(seconds: 20)),
      );
      controller.debugInjectOffer(crossCampusJob);

      controller.acceptOffer();

      expect(container.read(runnerControllerProvider).activeDelivery, isNull);
    },
  );

  group('verified-KYC gating applies to both runner types equally', () {
    for (final runnerType in RunnerType.values) {
      test(
        'a non-Verified ${runnerType.name} cannot go online',
        () async {
          final container = ProviderContainer(
            overrides: [
              authControllerProvider.overrideWith(
                () => _FakeAuthController(
                  _sessionForCampus(
                    'ui',
                    kycStatus: KycStatus.pending,
                    runnerType: runnerType,
                  ),
                ),
              ),
            ],
          );
          addTearDown(container.dispose);
          final controller = container.read(runnerControllerProvider.notifier);

          final result = await controller.toggleAvailability();

          expect(result, GoOnlineResult.notVerified);
          expect(
            container.read(runnerControllerProvider).status.availability,
            RunnerAvailability.offline,
          );
        },
      );

      test(
        'a non-Verified ${runnerType.name} cannot accept a job',
        () async {
          final container = ProviderContainer(
            overrides: [
              authControllerProvider.overrideWith(
                () => _FakeAuthController(
                  _sessionForCampus(
                    'ui',
                    kycStatus: KycStatus.none,
                    runnerType: runnerType,
                  ),
                ),
              ),
            ],
          );
          addTearDown(container.dispose);
          final controller = container.read(runnerControllerProvider.notifier);

          final job = DeliveryJob(
            id: 'job-1',
            campusId: 'ui',
            eateryName: 'Tantalizers',
            eateryLocation: 'Student Centre',
            dropoffZone: 'Hall',
            dropoffLocation: 'Room 1',
            payoutAmount: 500,
            estimatedDistanceMeters: 300,
            offeredAt: DateTime.now(),
            expiresAt: DateTime.now().add(const Duration(seconds: 20)),
          );
          final result = await controller.acceptJob(job);

          expect(result, AcceptOfferResult.notVerified);
          expect(container.read(runnerControllerProvider).activeDelivery, isNull);
        },
      );
    }

    test('a Verified runner of either type can go online and accept jobs', () async {
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith(
            () => _FakeAuthController(
              _sessionForCampus('ui', kycStatus: KycStatus.verified),
            ),
          ),
          vendorsRepositoryProvider.overrideWithValue(const _FakeVendorsRepository()),
        ],
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
  });

  test('offersReceived/offersAccepted track real accept-vs-decline behavior', () async {
    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(
          () => _FakeAuthController(_sessionForCampus('ui')),
        ),
        vendorsRepositoryProvider.overrideWithValue(const _FakeVendorsRepository()),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(runnerControllerProvider.notifier);

    await controller.toggleAvailability();
    controller.simulateOfferNow();
    expect(container.read(runnerControllerProvider).offersReceived, 1);
    expect(container.read(runnerControllerProvider).offersAccepted, 0);

    await controller.acceptOffer();
    expect(container.read(runnerControllerProvider).offersAccepted, 1);
  });
}
