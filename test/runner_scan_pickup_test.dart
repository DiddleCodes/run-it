import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:run_it/core/network/api_exception.dart';
import 'package:run_it/core/network/orders_repository.dart';
import 'package:run_it/core/network/uploads_repository.dart';
import 'package:run_it/core/routing/app_router.dart';
import 'package:run_it/core/widgets/app_notification.dart';
import 'package:run_it/core/widgets/primary_button.dart';
import 'package:run_it/features/auth/application/auth_controller.dart';
import 'package:run_it/features/auth/domain/auth_models.dart';
import 'package:run_it/features/auth/presentation/kyc/camera_capture_step.dart';
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

// Task 21b: DeliveryJob.id is the real backend orderId now (see
// MatchingRepository.listAvailable) — matches _OrderWithIdController's own
// orderId below so RunnerScanScreen's same-device sync convenience
// (_syncOrderTrackingIfSameOrder) actually fires, same as the real case of
// a runner verifying the order they genuinely claimed.
const _orderId = 'order-pickup-1';

DeliveryJob _job() => DeliveryJob(
  id: _orderId,
  eateryName: 'Jollof Palace',
  eateryLocation: 'Student Centre',
  dropoffZone: 'Hostel B, Room 204',
  dropoffLocation: 'Room 204',
  payoutAmount: 800,
  totalAmount: 3000,
  offeredAt: DateTime.now(),
);

/// A runner who has just accepted a job — the *next* scan is the pickup
/// one (Task 11's `verify-pickup`), not delivery.
class _AcceptedRunnerController extends RunnerController {
  @override
  RunnerSession build() => RunnerSession(
    status: const RunnerStatus(
      availability: RunnerAvailability.online,
      activeDeliveryId: _orderId,
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
    orderId: _orderId,
    orderItems: ['1 × Jollof'],
    total: 3000,
    eateryName: 'Jollof Palace',
    deliveryLocationLabel: 'Hostel B',
  );
}

class _VerifyingPickupOrdersRepository extends OrdersRepository {
  const _VerifyingPickupOrdersRepository();
  @override
  Future<void> verifyPickup({
    required String orderId,
    required String code,
    required String handoffPhotoUrl,
    required String token,
  }) async {}
}

class _MismatchedPickupOrdersRepository extends OrdersRepository {
  const _MismatchedPickupOrdersRepository();
  @override
  Future<void> verifyPickup({
    required String orderId,
    required String code,
    required String handoffPhotoUrl,
    required String token,
  }) async {
    throw const ApiException(400, "This isn't the order you accepted.");
  }
}

/// Task 30: stands in for the real presign+PUT upload the handoff-photo
/// capture screen triggers before verify-pickup is ever called.
class _RecordingUploadsRepository extends UploadsRepository {
  _RecordingUploadsRepository();
  String? capturedPurpose;

  @override
  Future<String> uploadImage({
    required List<int> bytes,
    required String purpose,
    required String contentType,
    required String token,
  }) async {
    capturedPurpose = purpose;
    return 'https://cdn.example.com/handoff/test.jpg';
  }
}

void _setPhoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Task 30: entering a pickup code now opens the required handoff-photo
/// capture screen first — this drives through that real step (via
/// `CameraCaptureStep.onCaptured`, same seam `delivery_proof_capture_test.dart`
/// uses; there's no test-environment camera implementation) before the
/// underlying verify-pickup call ever fires.
Future<void> _submitManualPickupCode(WidgetTester tester, String code) async {
  await tester.tap(find.text('Enter code'));
  await tester.pump(const Duration(milliseconds: 300));
  await tester.enterText(find.byType(TextField), code);
  await tester.pump();
  final confirmButton = tester.widget<PrimaryButton>(
    find.widgetWithText(PrimaryButton, 'Confirm'),
  );
  confirmButton.onPressed!();
  await tester.pump(); // sheet pop
  await tester.pump(); // handoff-photo capture screen pushed

  final captureStep = tester.widget<CameraCaptureStep>(
    find.byType(CameraCaptureStep),
  );
  captureStep.onCaptured(Uint8List.fromList([1, 2, 3]));
  await tester.pump(); // upload + capture screen pops
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
            ordersRepositoryProvider.overrideWithValue(const _VerifyingPickupOrdersRepository()),
            uploadsRepositoryProvider.overrideWithValue(_RecordingUploadsRepository()),
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
            ordersRepositoryProvider.overrideWithValue(const _MismatchedPickupOrdersRepository()),
            uploadsRepositoryProvider.overrideWithValue(_RecordingUploadsRepository()),
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
