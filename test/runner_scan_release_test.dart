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

/// A runner already at the picked-up stage — the *next* scan is the
/// delivery-confirmation one (Task 11's `verify-delivery`), not the pickup
/// scan.
class _PickedUpRunnerController extends RunnerController {
  @override
  RunnerSession build() => RunnerSession(
    status: const RunnerStatus(
      availability: RunnerAvailability.online,
      activeDeliveryId: 'job-1',
    ),
    activeDelivery: ActiveDelivery(
      job: _job(),
      status: DeliveryStage.pickedUp,
      orderNumber: '#RI-2048',
      orderItems: const ['1 × Jollof'],
    ),
  );
}

class _OrderWithIdController extends OrderTrackingController {
  @override
  OrderTrackingSession build() => const OrderTrackingSession(
    stage: OrderStage.pickedUp,
    orderId: 'order-release-1',
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

class _VerifyingDeliveryOrdersRepository extends OrdersRepository {
  const _VerifyingDeliveryOrdersRepository(this.outcome);
  final DeliveryVerificationResult outcome;
  @override
  Future<DeliveryVerificationResult> verifyDelivery({
    required String orderId,
    required String code,
    required String token,
  }) async => outcome;
}

class _MismatchedDeliveryOrdersRepository extends OrdersRepository {
  const _MismatchedDeliveryOrdersRepository();
  @override
  Future<DeliveryVerificationResult> verifyDelivery({
    required String orderId,
    required String code,
    required String token,
  }) async {
    throw const ApiException(400, "That PIN doesn't match this order.");
  }
}

/// The default flutter_test surface (800x600) is too short for the manual
/// code sheet's Confirm button to land on-screen; pin to a realistic phone
/// size instead.
void _setPhoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Runs the manual-entry sheet through to its Confirm tap and flushes the
/// verify-delivery call, leaving the caller to pump whatever comes next
/// (the success overlay's beat, or the immediate error state) and assert.
Future<void> _submitManualDeliveryCode(WidgetTester tester, String code) async {
  // Not pumpAndSettle: the scan frame's corner/sweep overlay repeats
  // forever by design, so "settle" never arrives.
  await tester.tap(find.text('Enter code'));
  await tester.pump(const Duration(milliseconds: 300)); // sheet slide-in
  await tester.enterText(find.byType(TextField), code);
  await tester.pump();
  // The manual-code sheet's own content isn't inside a Scrollable, so
  // `ensureVisible`/`tap` can't reliably land on the Confirm button once
  // the sheet's height exceeds this test's viewport — invoke its callback
  // directly instead of depending on hit-test geometry.
  final confirmButton = tester.widget<FilledButton>(
    find.widgetWithText(FilledButton, 'Confirm'),
  );
  confirmButton.onPressed!();
  await tester.pump(); // sheet pop
  await tester.pump(); // flush the verify-delivery call
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
    'a correct delivery PIN releases escrow and reports success honestly, reflecting real backend state',
    (tester) async {
      _setPhoneViewport(tester);
      await tester.pumpWidget(
        _harness(
          overrides: [
            authControllerProvider.overrideWith(() => _FakeAuthController(_runnerSession())),
            runnerControllerProvider.overrideWith(() => _PickedUpRunnerController()),
            orderTrackingProvider.overrideWith(() => _OrderWithIdController()),
            demoIdentityServiceProvider.overrideWithValue(const _FakeDemoIdentityService()),
            ordersRepositoryProvider.overrideWithValue(
              const _VerifyingDeliveryOrdersRepository(DeliveryVerificationResult.delivered),
            ),
          ],
        ),
      );
      await tester.pump();

      // Confirms this really is the delivery-confirmation scan, not pickup.
      expect(find.textContaining('Scanning delivery code'), findsOneWidget);

      final container = ProviderScope.containerOf(tester.element(find.byType(RunnerScanScreen)));
      await _submitManualDeliveryCode(tester, '4821');
      await tester.pump(const Duration(milliseconds: 900)); // success-overlay beat
      await tester.pump(const Duration(milliseconds: 400)); // notification

      expect(find.text('Delivery confirmed — payout sent.'), findsOneWidget);
      // Only a fully successful verify-delivery reflects real confirmed
      // backend state — no optimistic UI on order/payment state.
      expect(container.read(orderTrackingProvider).stage, OrderStage.delivered);
    },
  );

  testWidgets(
    'a partial transfer-leg failure reports payout as processing, and never marks the order delivered locally',
    (tester) async {
      _setPhoneViewport(tester);
      await tester.pumpWidget(
        _harness(
          overrides: [
            authControllerProvider.overrideWith(() => _FakeAuthController(_runnerSession())),
            runnerControllerProvider.overrideWith(() => _PickedUpRunnerController()),
            orderTrackingProvider.overrideWith(() => _OrderWithIdController()),
            demoIdentityServiceProvider.overrideWithValue(const _FakeDemoIdentityService()),
            ordersRepositoryProvider.overrideWithValue(
              const _VerifyingDeliveryOrdersRepository(DeliveryVerificationResult.payoutProcessing),
            ),
          ],
        ),
      );
      await tester.pump();

      final container = ProviderScope.containerOf(tester.element(find.byType(RunnerScanScreen)));
      await _submitManualDeliveryCode(tester, '4821');
      await tester.pump(const Duration(milliseconds: 900));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Delivery confirmed — payout processing.'), findsOneWidget);
      expect(find.text('Delivery confirmed — payout sent.'), findsNothing);
      // The PIN matched (the physical handoff is genuinely verified), so
      // the runner's own queue can move on — but the backend never flipped
      // order.status to delivered (the payout leg is still pending), so
      // the student's own tracking session must not show "Delivered" yet.
      expect(container.read(orderTrackingProvider).stage, OrderStage.pickedUp);
    },
  );

  testWidgets(
    'a mismatched PIN shows a clear error, never advances anything, and leaves the scanner ready to retry',
    (tester) async {
      _setPhoneViewport(tester);
      final runnerController = _PickedUpRunnerController();
      await tester.pumpWidget(
        _harness(
          overrides: [
            authControllerProvider.overrideWith(() => _FakeAuthController(_runnerSession())),
            runnerControllerProvider.overrideWith(() => runnerController),
            orderTrackingProvider.overrideWith(() => _OrderWithIdController()),
            demoIdentityServiceProvider.overrideWithValue(const _FakeDemoIdentityService()),
            ordersRepositoryProvider.overrideWithValue(
              const _MismatchedDeliveryOrdersRepository(),
            ),
          ],
        ),
      );
      await tester.pump();

      final container = ProviderScope.containerOf(tester.element(find.byType(RunnerScanScreen)));
      await _submitManualDeliveryCode(tester, '0000');
      await tester.pump(); // error overlay + notification appear

      // The backend's own rejection message reaches the runner unchanged —
      // shown both as the on-screen error overlay and the toast, so at
      // least one match is expected (not necessarily exactly one).
      expect(find.text("That PIN doesn't match this order."), findsWidgets);
      // No optimistic UI: neither side of the bridge advances on a
      // rejected verification.
      expect(runnerController.state.activeDelivery?.status, DeliveryStage.pickedUp);
      expect(container.read(orderTrackingProvider).stage, OrderStage.pickedUp);

      // The scanner is ready to try again, not stuck.
      await tester.pump(const Duration(milliseconds: 1800)); // error overlay auto-dismiss
      expect(find.text('Enter code'), findsOneWidget);
    },
  );
}
