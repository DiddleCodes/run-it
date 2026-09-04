import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:run_it/core/network/escrow_repository.dart';
import 'package:run_it/core/network/matching_repository.dart';
import 'package:run_it/features/auth/application/auth_controller.dart';
import 'package:run_it/features/auth/domain/auth_models.dart';
import 'package:run_it/features/runner/application/runner_controller.dart';
import 'package:run_it/features/runner/domain/runner_models.dart';

class _FakeAuthController extends AuthController {
  _FakeAuthController(this._session);
  final AuthSession _session;
  @override
  AuthSession? build() => _session;
}

/// Task 21b: `acceptJob` now calls this instead of a local timer/preview
/// flow — [result] drives the outcome, [claimed] records every orderId
/// actually attempted so a test can assert exactly what was sent.
class _FakeEscrowRepository extends EscrowRepository {
  _FakeEscrowRepository({this.result = ClaimResult.claimed, this.throwError = false});
  final ClaimResult result;
  final bool throwError;
  final List<String> claimed = [];

  @override
  Future<ClaimResult> claim({required String orderId, required String token}) async {
    claimed.add(orderId);
    if (throwError) throw Exception('network down');
    return result;
  }
}

class _FakeMatchingRepository extends MatchingRepository {
  const _FakeMatchingRepository();
  @override
  Future<List<DeliveryJob>> listAvailable({required String token}) async => const [];
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

DeliveryJob _job({String id = 'order-1'}) => DeliveryJob(
  id: id,
  eateryName: 'Tantalizers',
  eateryLocation: 'Student Centre, Main Walk',
  dropoffZone: 'Queen Elizabeth II Hall',
  dropoffLocation: 'Queen Elizabeth II Hall',
  payoutAmount: 850,
  totalAmount: 4500,
  offeredAt: DateTime.now(),
);

void main() {
  test('runner delivery state machine only permits forward transitions', () async {
    final escrow = _FakeEscrowRepository();
    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(() => _FakeAuthController(_sessionForCampus('ui'))),
        escrowRepositoryProvider.overrideWithValue(escrow),
        matchingRepositoryProvider.overrideWithValue(const _FakeMatchingRepository()),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(runnerControllerProvider.notifier);

    expect(controller.confirmPickup(), isFalse);
    await controller.toggleAvailability();

    final result = await controller.acceptJob(_job());
    expect(result, AcceptOfferResult.accepted);
    expect(escrow.claimed, ['order-1']);
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
    'a lost claim race (409) reports alreadyClaimed and never sets an active delivery',
    () async {
      final escrow = _FakeEscrowRepository(result: ClaimResult.alreadyClaimed);
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith(() => _FakeAuthController(_sessionForCampus('ui'))),
          escrowRepositoryProvider.overrideWithValue(escrow),
          matchingRepositoryProvider.overrideWithValue(const _FakeMatchingRepository()),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(runnerControllerProvider.notifier);
      await controller.toggleAvailability();

      final result = await controller.acceptJob(_job());

      expect(result, AcceptOfferResult.alreadyClaimed);
      expect(container.read(runnerControllerProvider).activeDelivery, isNull);
      // A claim attempt (won or lost) still counts toward the real
      // acceptance-rate denominator — see RunnerSession.offersReceived's
      // own doc comment.
      expect(container.read(runnerControllerProvider).offersReceived, 1);
      expect(container.read(runnerControllerProvider).offersAccepted, 0);
    },
  );

  test('a network failure while claiming reports networkError, not a crash', () async {
    final escrow = _FakeEscrowRepository(throwError: true);
    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(() => _FakeAuthController(_sessionForCampus('ui'))),
        escrowRepositoryProvider.overrideWithValue(escrow),
        matchingRepositoryProvider.overrideWithValue(const _FakeMatchingRepository()),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(runnerControllerProvider.notifier);
    await controller.toggleAvailability();

    final result = await controller.acceptJob(_job());

    expect(result, AcceptOfferResult.networkError);
    expect(container.read(runnerControllerProvider).activeDelivery, isNull);
  });

  group('verified-KYC gating applies to both runner types equally', () {
    for (final runnerType in RunnerType.values) {
      test('a non-Verified ${runnerType.name} cannot go online', () async {
        final container = ProviderContainer(
          overrides: [
            authControllerProvider.overrideWith(
              () => _FakeAuthController(
                _sessionForCampus('ui', kycStatus: KycStatus.pending, runnerType: runnerType),
              ),
            ),
            matchingRepositoryProvider.overrideWithValue(const _FakeMatchingRepository()),
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
      });

      test('a non-Verified ${runnerType.name} cannot claim a job', () async {
        final container = ProviderContainer(
          overrides: [
            authControllerProvider.overrideWith(
              () => _FakeAuthController(
                _sessionForCampus('ui', kycStatus: KycStatus.none, runnerType: runnerType),
              ),
            ),
            escrowRepositoryProvider.overrideWithValue(_FakeEscrowRepository()),
            matchingRepositoryProvider.overrideWithValue(const _FakeMatchingRepository()),
          ],
        );
        addTearDown(container.dispose);
        final controller = container.read(runnerControllerProvider.notifier);

        final result = await controller.acceptJob(_job());

        expect(result, AcceptOfferResult.notVerified);
        expect(container.read(runnerControllerProvider).activeDelivery, isNull);
      });
    }

    test('a Verified runner of either type can go online and claim jobs', () async {
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith(
            () => _FakeAuthController(_sessionForCampus('ui', kycStatus: KycStatus.verified)),
          ),
          escrowRepositoryProvider.overrideWithValue(_FakeEscrowRepository()),
          matchingRepositoryProvider.overrideWithValue(const _FakeMatchingRepository()),
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

  test('offersReceived/offersAccepted track real claim-attempt-vs-won behavior', () async {
    final escrow = _FakeEscrowRepository();
    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(() => _FakeAuthController(_sessionForCampus('ui'))),
        escrowRepositoryProvider.overrideWithValue(escrow),
        matchingRepositoryProvider.overrideWithValue(const _FakeMatchingRepository()),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(runnerControllerProvider.notifier);

    await controller.toggleAvailability();
    expect(container.read(runnerControllerProvider).offersReceived, 0);

    final result = await controller.acceptJob(_job());

    expect(result, AcceptOfferResult.accepted);
    expect(container.read(runnerControllerProvider).offersReceived, 1);
    expect(container.read(runnerControllerProvider).offersAccepted, 1);
  });
}
