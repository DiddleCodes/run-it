import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:run_it/core/network/api_exception.dart';
import 'package:run_it/core/network/demo_identity_service.dart';
import 'package:run_it/core/network/orders_repository.dart';
import 'package:run_it/core/routing/app_router.dart';
import 'package:run_it/core/widgets/app_notification.dart';
import 'package:run_it/features/auth/application/auth_controller.dart';
import 'package:run_it/features/auth/domain/auth_models.dart';
import 'package:run_it/features/ordering/application/order_tracking_controller.dart';
import 'package:run_it/features/ordering/domain/ordering_models.dart';
import 'package:run_it/features/runner/application/runner_controller.dart';
import 'package:run_it/features/runner/domain/runner_models.dart';
import 'package:run_it/features/runner/presentation/runner_scan_screen.dart';

class _FakeAuthController extends AuthController {
  _FakeAuthController(this._session);
  final AuthSession _session;
  @override
  AuthSession? build() => _session;
}

AuthSession _runnerSession() => AuthSession(
  accessToken: 'a',
  refreshToken: 'r',
  expiresAt: DateTime.now().add(const Duration(minutes: 5)),
  user: const UserProfile(
    id: 'runner-1',
    name: 'Ada Runner',
    contact: '+2348000000000',
    accountType: AccountType.runner,
    campusId: 'ui',
    kycStatus: KycStatus.verified,
    runnerType: RunnerType.studentRunner,
  ),
);

DeliveryJob _job() => DeliveryJob(
  id: 'job-1',
  campusId: 'ui',
  eateryName: 'Jollof Palace',
  eateryLocation: 'Student Centre',
  dropoffZone: 'Hostel B, Room 204',
  dropoffLocation: 'Room 204',
  payoutAmount: 800,
  estimatedDistanceMeters: 500,
  offeredAt: DateTime.now(),
  expiresAt: DateTime.now().add(const Duration(seconds: 20)),
);

/// A runner who has just accepted a job — the *next* scan is the pickup
/// one (Task 11's `verify-pickup`), not delivery.
class _AcceptedRunnerController extends RunnerController {
  @override
  RunnerSession build() => RunnerSession(
    status: const RunnerStatus(
      availability: RunnerAvailability.online,
      activeDeliveryId: 'job-1',
    ),
    activeDelivery: ActiveDelivery(
      job: _job(),
      status: DeliveryStage.accepted,
      orderNumber: '#RI-2048',
      orderItems: const ['1 × Jollof'],
    ),
  );
}

class _OrderWithIdController extends OrderTrackingController {
  @override
  OrderTrackingSession build() => const OrderTrackingSession(
    stage: OrderStage.runnerAssigned,
    orderId: 'order-pickup-1',
    orderItems: ['1 × Jollof'],
    total: 3000,
    eateryName: 'Jollof Palace',
    deliveryLocationLabel: 'Hostel B',
  );
}

class _FakeDemoIdentityService extends DemoIdentityService {
  const _FakeDemoIdentityService();
  @override
  Future<String> ensureRunnerUserId() async => 'demo-runner-1';
  @override
  Future<String> mintTokenFor({
    required String userId,
    required String accountType,
  }) async => 'demo-runner-token';
}

class _VerifyingPickupOrdersRepository extends OrdersRepository {
  const _VerifyingPickupOrdersRepository();
  @override
  Future<void> verifyPickup({
    required String orderId,
    required String code,
    required String token,
  }) async {}
}

class _MismatchedPickupOrdersRepository extends OrdersRepository {
  const _MismatchedPickupOrdersRepository();
  @override
  Future<void> verifyPickup({
    required String orderId,
    required String code,
    required String token,
  }) async {
    throw const ApiException(400, "This isn't the order you accepted.");
  }
}

void _setPhoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _submitManualPickupCode(WidgetTester tester, String code) async {
  await tester.tap(find.text('Enter code'));
  await tester.pump(const Duration(milliseconds: 300));
  await tester.enterText(find.byType(TextField), code);
  await tester.pump();
  final confirmButton = tester.widget<FilledButton>(
    find.widgetWithText(FilledButton, 'Confirm'),
  );
  confirmButton.onPressed!();
  await tester.pump(); // sheet pop
  await tester.pump(); // flush the verify-pickup call
}

Widget _harness({required List<Override> overrides}) {
  final router = GoRouter(
    initialLocation: AppRoutes.runnerScan,
    routes: [
      GoRoute(
        path: AppRoutes.runnerScan,
        builder: (_, _) => const RunnerScanScreen(),
      ),
      GoRoute(
        path: AppRoutes.runnerHome,
        builder: (_, _) => const Text('RUNNER_HOME'),
      ),
    ],
  );
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp.router(
      routerConfig: router,
      builder: (context, child) =>
          AppNotificationHost(child: child ?? const SizedBox.shrink()),
    ),
  );
}

void main() {
  testWidgets(
    'a correct pickup code advances the runner and the student tracking session together',
    (tester) async {
      _setPhoneViewport(tester);
      await tester.pumpWidget(
        _harness(
          overrides: [
            authControllerProvider.overrideWith(() => _FakeAuthController(_runnerSession())),
            runnerControllerProvider.overrideWith(() => _AcceptedRunnerController()),
            orderTrackingProvider.overrideWith(() => _OrderWithIdController()),
            demoIdentityServiceProvider.overrideWithValue(const _FakeDemoIdentityService()),
            ordersRepositoryProvider.overrideWithValue(const _VerifyingPickupOrdersRepository()),
          ],
        ),
      );
      await tester.pump();

      expect(find.textContaining('Scanning pickup code'), findsOneWidget);

      final container = ProviderScope.containerOf(tester.element(find.byType(RunnerScanScreen)));
      

      await _submitManualPickupCode(tester, '8678');
      await tester.pump(const Duration(milliseconds: 900)); // success overlay

      expect(
        container.read(runnerControllerProvider).activeDelivery?.status,
        DeliveryStage.pickedUp,
      );
      expect(container.read(orderTrackingProvider).stage, OrderStage.pickedUp);
    },
  );

  testWidgets(
    'a mismatched pickup code shows a clear error and never advances anything',
    (tester) async {
      _setPhoneViewport(tester);
      await tester.pumpWidget(
        _harness(
          overrides: [
            authControllerProvider.overrideWith(() => _FakeAuthController(_runnerSession())),
            runnerControllerProvider.overrideWith(() => _AcceptedRunnerController()),
            orderTrackingProvider.overrideWith(() => _OrderWithIdController()),
            demoIdentityServiceProvider.overrideWithValue(const _FakeDemoIdentityService()),
            ordersRepositoryProvider.overrideWithValue(const _MismatchedPickupOrdersRepository()),
          ],
        ),
      );
      await tester.pump();

      final container = ProviderScope.containerOf(tester.element(find.byType(RunnerScanScreen)));
      

      await _submitManualPickupCode(tester, '0000');
      await tester.pump(); // error overlay + notification appear

      expect(find.text("This isn't the order you accepted."), findsWidgets);
      expect(
        container.read(runnerControllerProvider).activeDelivery?.status,
        DeliveryStage.accepted,
      );
      expect(container.read(orderTrackingProvider).stage, OrderStage.runnerAssigned);

      // The scanner recovers, ready for another attempt.
      await tester.pump(const Duration(milliseconds: 1800));
      expect(find.text('Enter code'), findsOneWidget);
    },
  );
}
