import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:run_it/core/network/orders_repository.dart';
import 'package:run_it/core/network/uploads_repository.dart';
import 'package:run_it/core/widgets/app_notification.dart';
import 'package:run_it/features/auth/application/auth_controller.dart';
import 'package:run_it/features/auth/domain/auth_models.dart';
import 'package:run_it/features/auth/presentation/kyc/camera_capture_step.dart';
import 'package:run_it/features/runner/presentation/delivery_proof_capture_screen.dart';

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

/// Records what it was asked to upload rather than hitting the real S3
/// presign flow — the interesting thing to verify here is that the fallback
/// wires the *right* purpose/bytes through, not that presigned-PUT itself
/// works (that's `UploadsRepository`'s own concern, untested here).
class _RecordingUploadsRepository extends UploadsRepository {
  _RecordingUploadsRepository();
  String? capturedPurpose;
  List<int>? capturedBytes;

  @override
  Future<String> uploadImage({
    required List<int> bytes,
    required String purpose,
    required String contentType,
    required String token,
  }) async {
    capturedPurpose = purpose;
    capturedBytes = bytes;
    return 'https://cdn.example.com/delivery-proof/test.jpg';
  }
}

class _RecordingOrdersRepository extends OrdersRepository {
  _RecordingOrdersRepository();
  String? capturedOrderId;
  String? capturedPhotoUrl;

  @override
  Future<void> submitDeliveryProof({
    required String orderId,
    required String photoUrl,
    required String token,
  }) async {
    capturedOrderId = orderId;
    capturedPhotoUrl = photoUrl;
  }
}

class _FailingOrdersRepository extends OrdersRepository {
  const _FailingOrdersRepository();
  @override
  Future<void> submitDeliveryProof({
    required String orderId,
    required String photoUrl,
    required String token,
  }) async {
    throw Exception('backend unreachable');
  }
}

Widget _harness({required List<Override> overrides, required String orderId}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).push<bool>(
                MaterialPageRoute(builder: (_) => DeliveryProofCaptureScreen(orderId: orderId)),
              ),
              child: const Text('Open capture'),
            ),
          ),
        ),
      ),
      builder: (context, child) => AppNotificationHost(child: child ?? const SizedBox.shrink()),
    ),
  );
}

/// The real `camera` plugin has no test-environment implementation, so
/// exercising this all the way through a live preview isn't possible here
/// (no existing test in this codebase does) — invoking `CameraCaptureStep`'s
/// own `onCaptured` callback directly, the same seam KYC's real capture
/// flow eventually calls it through, tests the fallback's actual
/// upload-then-register logic without needing a real camera.
void main() {
  testWidgets(
    'a captured photo is uploaded and registered against the order, then the screen closes',
    (tester) async {
      final uploads = _RecordingUploadsRepository();
      final orders = _RecordingOrdersRepository();

      await tester.pumpWidget(
        _harness(
          orderId: 'order-proof-1',
          overrides: [
            authControllerProvider.overrideWith(() => _FakeAuthController(_runnerSession())),
            uploadsRepositoryProvider.overrideWithValue(uploads),
            ordersRepositoryProvider.overrideWithValue(orders),
          ],
        ),
      );

      await tester.tap(find.text('Open capture'));
      await tester.pumpAndSettle();

      expect(find.byType(DeliveryProofCaptureScreen), findsOneWidget);
      final captureStep = tester.widget<CameraCaptureStep>(find.byType(CameraCaptureStep));
      captureStep.onCaptured(Uint8List.fromList([1, 2, 3]));
      await tester.pumpAndSettle();

      expect(uploads.capturedPurpose, 'delivery-proof');
      expect(uploads.capturedBytes, [1, 2, 3]);
      expect(orders.capturedOrderId, 'order-proof-1');
      expect(orders.capturedPhotoUrl, 'https://cdn.example.com/delivery-proof/test.jpg');
      expect(find.text('Photo submitted — this delivery is flagged for manual review.'), findsOneWidget);
      // Pops back to the caller on success — never leaves the runner stuck
      // on the capture screen once the fallback has done its job.
      expect(find.byType(DeliveryProofCaptureScreen), findsNothing);
    },
  );

  testWidgets(
    'a failed submission shows the real error and keeps the screen open for a retry',
    (tester) async {
      final uploads = _RecordingUploadsRepository();

      await tester.pumpWidget(
        _harness(
          orderId: 'order-proof-2',
          overrides: [
            authControllerProvider.overrideWith(() => _FakeAuthController(_runnerSession())),
            uploadsRepositoryProvider.overrideWithValue(uploads),
            ordersRepositoryProvider.overrideWithValue(const _FailingOrdersRepository()),
          ],
        ),
      );

      await tester.tap(find.text('Open capture'));
      await tester.pumpAndSettle();

      final captureStep = tester.widget<CameraCaptureStep>(find.byType(CameraCaptureStep));
      captureStep.onCaptured(Uint8List.fromList([1, 2, 3]));
      await tester.pumpAndSettle();

      expect(
        find.text("Couldn't submit photo proof. Check your connection and try again."),
        findsOneWidget,
      );
      // Never silently treated as submitted — the screen stays put so the
      // runner can try again.
      expect(find.byType(DeliveryProofCaptureScreen), findsOneWidget);
    },
  );
}
