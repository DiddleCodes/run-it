import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:run_it/core/network/orders_repository.dart';
import 'package:run_it/core/routing/app_router.dart';
import 'package:run_it/core/widgets/app_notification.dart';
import 'package:run_it/core/widgets/primary_button.dart';
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

const _orderId = 'order-pod-1';

DeliveryJob _podJob() => DeliveryJob(
  id: _orderId,
  eateryName: 'Jollof Palace',
  eateryLocation: 'Student Centre',
  dropoffZone: 'Hostel B, Room 204',
  dropoffLocation: 'Room 204',
  payoutAmount: 800,
  totalAmount: 3000, // naira — ₦3,000, so ₦300,000 kobo
  isPayOnDelivery: true,
  offeredAt: DateTime.now(),
);

class _PickedUpPodRunnerController extends RunnerController {
  @override
  RunnerSession build() => RunnerSession(
    status: const RunnerStatus(availability: RunnerAvailability.online, activeDeliveryId: _orderId),
    activeDelivery: ActiveDelivery(
      job: _podJob(),
      status: DeliveryStage.pickedUp,
      orderNumber: '#RI-3001',
      orderItems: const ['1 × Jollof'],
    ),
  );
}

class _OrderWithIdController extends OrderTrackingController {
  @override
  OrderTrackingSession build() => const OrderTrackingSession(
    stage: OrderStage.pickedUp,
    orderId: _orderId,
    orderItems: ['1 × Jollof'],
    total: 3000,
    eateryName: 'Jollof Palace',
    deliveryLocationLabel: 'Hostel B',
  );
}

/// Records the exact `amountCollectedKobo` `verify-delivery` was called
/// with — `null` means the call never happened at all.
class _RecordingOrdersRepository extends OrdersRepository {
  int? capturedAmountCollectedKobo;
  bool called = false;

  @override
  Future<DeliveryVerificationResult> verifyDelivery({
    required String orderId,
    required String code,
    required String token,
    int? amountCollectedKobo,
  }) async {
    called = true;
    capturedAmountCollectedKobo = amountCollectedKobo;
    return DeliveryVerificationResult.delivered;
  }
}

void _setPhoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _harness({required List<Override> overrides}) {
  final router = GoRouter(
    initialLocation: AppRoutes.runnerScan,
    routes: [
      GoRoute(path: AppRoutes.runnerScan, builder: (_, _) => const RunnerScanScreen()),
      GoRoute(path: AppRoutes.runnerHome, builder: (_, _) => const Text('RUNNER_HOME')),
    ],
  );
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp.router(
      routerConfig: router,
      builder: (context, child) => AppNotificationHost(child: child ?? const SizedBox.shrink()),
    ),
  );
}

/// Opens the manual-code sheet and confirms it, same helper shape
/// `runner_scan_release_test.dart` uses — leaves the caller to pump
/// whatever comes next (the cash-collection screen, for a Pay on Delivery
/// job).
Future<void> _submitManualDeliveryCode(WidgetTester tester, String code) async {
  await tester.tap(find.text('Enter code'));
  await tester.pump(const Duration(milliseconds: 300));
  await tester.enterText(find.byType(TextField).first, code);
  await tester.pump();
  final confirmButton = tester.widget<PrimaryButton>(find.widgetWithText(PrimaryButton, 'Confirm'));
  confirmButton.onPressed!();
  await tester.pump(); // sheet pop
  await tester.pump(); // cash-collection screen push
}

void main() {
  testWidgets(
    'Task 47: a Pay on Delivery order requires cash collection before verify-delivery is ever called, and reports the exact amount collected',
    (tester) async {
      _setPhoneViewport(tester);
      final orders = _RecordingOrdersRepository();
      await tester.pumpWidget(
        _harness(
          overrides: [
            authControllerProvider.overrideWith(() => _FakeAuthController(_runnerSession())),
            runnerControllerProvider.overrideWith(() => _PickedUpPodRunnerController()),
            orderTrackingProvider.overrideWith(() => _OrderWithIdController()),
            ordersRepositoryProvider.overrideWithValue(orders),
          ],
        ),
      );
      await tester.pump();

      await _submitManualDeliveryCode(tester, '4821');

      // The cash-collection screen is up, and verify-delivery has NOT been
      // called yet — a runner can't skip straight past cash confirmation.
      expect(find.text('Collect payment'), findsOneWidget);
      expect(orders.called, isFalse);

      await tester.tap(find.textContaining('mark as paid'));
      await tester.pump(); // cash-collection screen pop
      await tester.pump(const Duration(milliseconds: 900)); // success-overlay beat
      await tester.pump(const Duration(milliseconds: 400)); // notification

      expect(orders.called, isTrue);
      // 3000 naira -> 300,000 kobo, the exact order total, since "mark as
      // paid" (not "I collected a different amount") was tapped.
      expect(orders.capturedAmountCollectedKobo, 300000);
      expect(find.text('Delivery confirmed — payout sent.'), findsOneWidget);
    },
  );

  testWidgets(
    'reporting a different collected amount sends that real figure, not the order total',
    (tester) async {
      _setPhoneViewport(tester);
      final orders = _RecordingOrdersRepository();
      await tester.pumpWidget(
        _harness(
          overrides: [
            authControllerProvider.overrideWith(() => _FakeAuthController(_runnerSession())),
            runnerControllerProvider.overrideWith(() => _PickedUpPodRunnerController()),
            orderTrackingProvider.overrideWith(() => _OrderWithIdController()),
            ordersRepositoryProvider.overrideWithValue(orders),
          ],
        ),
      );
      await tester.pump();

      await _submitManualDeliveryCode(tester, '4821');
      expect(find.text('Collect payment'), findsOneWidget);

      await tester.tap(find.text("I collected a different amount"));
      await tester.pump();
      await tester.enterText(find.byType(TextField).last, '2000');
      await tester.pump();
      await tester.tap(find.text('Confirm amount'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 900));
      await tester.pump(const Duration(milliseconds: 400));

      expect(orders.called, isTrue);
      expect(orders.capturedAmountCollectedKobo, 200000); // ₦2,000, not ₦3,000
    },
  );

  testWidgets(
    'backing out of cash collection never calls verify-delivery and leaves the scanner ready to retry',
    (tester) async {
      _setPhoneViewport(tester);
      final orders = _RecordingOrdersRepository();
      await tester.pumpWidget(
        _harness(
          overrides: [
            authControllerProvider.overrideWith(() => _FakeAuthController(_runnerSession())),
            runnerControllerProvider.overrideWith(() => _PickedUpPodRunnerController()),
            orderTrackingProvider.overrideWith(() => _OrderWithIdController()),
            ordersRepositoryProvider.overrideWithValue(orders),
          ],
        ),
      );
      await tester.pump();

      await _submitManualDeliveryCode(tester, '4821');
      expect(find.text('Collect payment'), findsOneWidget);

      await tester.pageBack();
      await tester.pump();
      await tester.pump();

      expect(orders.called, isFalse);
      expect(find.text('Collect payment'), findsNothing);
    },
  );
}
