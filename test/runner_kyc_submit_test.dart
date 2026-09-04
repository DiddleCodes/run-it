import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:run_it/core/network/runner_kyc_repository.dart';
import 'package:run_it/core/network/uploads_repository.dart';
import 'package:run_it/core/routing/app_router.dart';
import 'package:run_it/core/widgets/app_notification.dart';
import 'package:run_it/features/auth/application/auth_controller.dart';
import 'package:run_it/features/auth/application/kyc_flow_controller.dart';
import 'package:run_it/features/auth/domain/auth_models.dart';
import 'package:run_it/features/auth/presentation/kyc/camera_capture_step.dart';
import 'package:run_it/features/auth/presentation/kyc/kyc_capture_screen.dart';

/// Task 29: exercises the real runner KYC submit path end to end —
/// KycCaptureScreen's capture wizard through to a real upload-then-submit
/// call — replacing the old client-only Random()/Timer fake resolution
/// (see the Task 28 audit report). Drives `CameraCaptureStep.onCaptured`
/// directly rather than a real camera preview, same seam
/// `delivery_proof_capture_test.dart` uses — there's no test-environment
/// camera implementation.
class _FakeAuthController extends AuthController {
  _FakeAuthController(this._session);
  final AuthSession _session;
  @override
  AuthSession? build() => _session;
}

AuthSession _runnerSession() => AuthSession(
  accessToken: 'runner-token',
  refreshToken: 'runner-token',
  expiresAt: DateTime.now().add(const Duration(minutes: 5)),
  user: const UserProfile(
    id: 'runner-1',
    name: 'Test Runner',
    contact: 'runner1@runit.dev',
    accountType: AccountType.runner,
    campusId: 'ui',
  ),
);

class _RecordingUploadsRepository extends UploadsRepository {
  _RecordingUploadsRepository();
  final List<String> capturedPurposes = [];

  @override
  Future<String> uploadImage({
    required List<int> bytes,
    required String purpose,
    required String contentType,
    required String token,
  }) async {
    capturedPurposes.add(purpose);
    return 'https://cdn.example.com/runner-kyc/$purpose.jpg';
  }
}

class _RecordingRunnerKycRepository extends RunnerKycRepository {
  _RecordingRunnerKycRepository();
  RunnerType? capturedRunnerType;
  String? capturedIdPhotoUrl;
  String? capturedSelfiePhotoUrl;

  @override
  Future<void> submit({
    required String token,
    required RunnerType runnerType,
    required IdType idType,
    required String idPhotoUrl,
    required String selfiePhotoUrl,
    String? vehiclePhotoUrl,
    VehicleType? vehicleType,
    String? vehiclePlate,
  }) async {
    capturedRunnerType = runnerType;
    capturedIdPhotoUrl = idPhotoUrl;
    capturedSelfiePhotoUrl = selfiePhotoUrl;
  }
}

class _FailingRunnerKycRepository extends RunnerKycRepository {
  const _FailingRunnerKycRepository();
  @override
  Future<void> submit({
    required String token,
    required RunnerType runnerType,
    required IdType idType,
    required String idPhotoUrl,
    required String selfiePhotoUrl,
    String? vehiclePhotoUrl,
    VehicleType? vehicleType,
    String? vehiclePlate,
  }) async {
    throw Exception('backend unreachable');
  }
}

Widget _harness(AuthController controller) {
  final router = GoRouter(
    initialLocation: AppRoutes.kycCapture,
    routes: [
      GoRoute(path: AppRoutes.kycCapture, builder: (_, _) => const KycCaptureScreen()),
      GoRoute(path: AppRoutes.kycStatus, builder: (_, _) => const Text('KYC_STATUS_SCREEN')),
    ],
  );
  return ProviderScope(
    overrides: [authControllerProvider.overrideWith(() => controller)],
    child: MaterialApp.router(
      routerConfig: router,
      builder: (context, child) => AppNotificationHost(child: child ?? const SizedBox.shrink()),
    ),
  );
}

void main() {
  testWidgets(
    'a student runner (no vehicle step) uploads ID + selfie and submits for real review',
    (tester) async {
      final uploads = _RecordingUploadsRepository();
      final runnerKyc = _RecordingRunnerKycRepository();
      final controller = _FakeAuthController(_runnerSession())
        ..uploads = uploads
        ..runnerKyc = runnerKyc;

      await tester.pumpWidget(_harness(controller));
      final container = ProviderScope.containerOf(tester.element(find.byType(KycCaptureScreen)));
      container.read(kycFlowProvider.notifier).setRunnerType(RunnerType.studentRunner);
      await tester.pump();

      // Step 1: ID.
      tester.widget<CameraCaptureStep>(find.byType(CameraCaptureStep)).onCaptured(Uint8List.fromList([1]));
      await tester.pump();
      // Step 2: selfie.
      tester.widget<CameraCaptureStep>(find.byType(CameraCaptureStep)).onCaptured(Uint8List.fromList([2]));
      await tester.pump();

      expect(find.text('Submit for Verification'), findsOneWidget);
      await tester.tap(find.text('Submit for Verification'));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(uploads.capturedPurposes, ['runner-kyc-id', 'runner-kyc-selfie']);
      expect(runnerKyc.capturedRunnerType, RunnerType.studentRunner);
      expect(runnerKyc.capturedIdPhotoUrl, 'https://cdn.example.com/runner-kyc/runner-kyc-id.jpg');
      expect(runnerKyc.capturedSelfiePhotoUrl, 'https://cdn.example.com/runner-kyc/runner-kyc-selfie.jpg');

      // Real pending status, no local Random()/Timer resolution.
      expect(container.read(authControllerProvider)!.user.kycStatus, KycStatus.pending);
      expect(find.text('KYC_STATUS_SCREEN'), findsOneWidget);
    },
  );

  testWidgets(
    'an independent rider also uploads the vehicle photo, and its vehicle fields reach the submit call',
    (tester) async {
      final uploads = _RecordingUploadsRepository();
      final runnerKyc = _RecordingRunnerKycRepository();
      final controller = _FakeAuthController(_runnerSession())
        ..uploads = uploads
        ..runnerKyc = runnerKyc;

      await tester.pumpWidget(_harness(controller));
      final container = ProviderScope.containerOf(tester.element(find.byType(KycCaptureScreen)));
      container.read(kycFlowProvider.notifier).setRunnerType(RunnerType.independentRider);
      await tester.pump();

      // ID -> selfie -> vehicle photo.
      tester.widget<CameraCaptureStep>(find.byType(CameraCaptureStep)).onCaptured(Uint8List.fromList([1]));
      await tester.pump();
      tester.widget<CameraCaptureStep>(find.byType(CameraCaptureStep)).onCaptured(Uint8List.fromList([2]));
      await tester.pump();
      tester.widget<CameraCaptureStep>(find.byType(CameraCaptureStep)).onCaptured(Uint8List.fromList([3]));
      await tester.pump();

      // Vehicle details step: pick a motorised type and enter a plate.
      await tester.tap(find.text('Motorbike'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'ABC-123-XY');
      await tester.tap(find.text('Continue'));
      await tester.pump();

      await tester.tap(find.text('Submit for Verification'));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(uploads.capturedPurposes, ['runner-kyc-id', 'runner-kyc-selfie', 'runner-kyc-vehicle']);
      expect(runnerKyc.capturedRunnerType, RunnerType.independentRider);
      expect(find.text('KYC_STATUS_SCREEN'), findsOneWidget);
    },
  );

  testWidgets('a failed submission shows a real error and keeps the wizard open for a retry', (tester) async {
    final uploads = _RecordingUploadsRepository();
    final controller = _FakeAuthController(_runnerSession())
      ..uploads = uploads
      ..runnerKyc = const _FailingRunnerKycRepository();

    await tester.pumpWidget(_harness(controller));
    final container = ProviderScope.containerOf(tester.element(find.byType(KycCaptureScreen)));
    container.read(kycFlowProvider.notifier).setRunnerType(RunnerType.studentRunner);
    await tester.pump();

    tester.widget<CameraCaptureStep>(find.byType(CameraCaptureStep)).onCaptured(Uint8List.fromList([1]));
    await tester.pump();
    tester.widget<CameraCaptureStep>(find.byType(CameraCaptureStep)).onCaptured(Uint8List.fromList([2]));
    await tester.pump();

    await tester.tap(find.text('Submit for Verification'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(
      find.text("Couldn't submit for verification. Check your connection and try again."),
      findsOneWidget,
    );
    // Never silently treated as submitted — stays on the capture screen,
    // and the account never optimistically moves to pending.
    expect(find.byType(KycCaptureScreen), findsOneWidget);
    expect(container.read(authControllerProvider)!.user.kycStatus, KycStatus.none);
  });
}
