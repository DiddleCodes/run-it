import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:run_it/core/network/api_exception.dart';
import 'package:run_it/core/network/orders_repository.dart';
import 'package:run_it/core/network/uploads_repository.dart';
import 'package:run_it/core/widgets/app_notification.dart';
import 'package:run_it/features/auth/application/auth_controller.dart';
import 'package:run_it/features/auth/domain/auth_models.dart';
import 'package:run_it/features/auth/presentation/kyc/camera_capture_step.dart';
import 'package:run_it/features/ordering/presentation/report_problem_screen.dart';

/// Task 30: the real student-facing "report a problem" screen — exercises
/// the reason field, the optional photo (captured via the same
/// `CameraCaptureStep.onCaptured` seam `delivery_proof_capture_test.dart`
/// uses), and the real upload-then-submit call.
class _FakeAuthController extends AuthController {
  _FakeAuthController(this._session);
  final AuthSession _session;
  @override
  AuthSession? build() => _session;
}

AuthSession _studentSession() => AuthSession(
  accessToken: 'student-token',
  refreshToken: 'student-token',
  expiresAt: DateTime.now().add(const Duration(minutes: 5)),
  user: const UserProfile(
    id: 'student-1',
    name: 'Ada Student',
    contact: 'ada@student.ui.edu.ng',
    accountType: AccountType.student,
    campusId: 'ui',
  ),
);

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
    return 'https://cdn.example.com/dispute-report/test.jpg';
  }
}

class _RecordingOrdersRepository extends OrdersRepository {
  _RecordingOrdersRepository();
  String? capturedOrderId;
  String? capturedReason;
  String? capturedPhotoUrl;

  @override
  Future<void> reportProblem({
    required String orderId,
    required String reason,
    String? photoUrl,
    required String token,
  }) async {
    capturedOrderId = orderId;
    capturedReason = reason;
    capturedPhotoUrl = photoUrl;
  }
}

class _FailingOrdersRepository extends OrdersRepository {
  const _FailingOrdersRepository();
  @override
  Future<void> reportProblem({
    required String orderId,
    required String reason,
    String? photoUrl,
    required String token,
  }) async {
    throw const ApiException(409, 'A dispute already exists for this order');
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
                MaterialPageRoute(builder: (_) => ReportProblemScreen(orderId: orderId)),
              ),
              child: const Text('Open report screen'),
            ),
          ),
        ),
      ),
      builder: (context, child) => AppNotificationHost(child: child ?? const SizedBox.shrink()),
    ),
  );
}

/// A real, valid 1x1 PNG (not arbitrary bytes) — the screen renders a real
/// `Image.memory` thumbnail once a photo is added, which needs real
/// decodable image data even in a widget test.
final _tinyValidPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);

void main() {
  testWidgets(
    'submitting a reason with no photo calls the real endpoint with photoUrl omitted, then closes',
    (tester) async {
      final orders = _RecordingOrdersRepository();

      await tester.pumpWidget(
        _harness(
          orderId: 'order-report-1',
          overrides: [
            authControllerProvider.overrideWith(() => _FakeAuthController(_studentSession())),
            ordersRepositoryProvider.overrideWithValue(orders),
          ],
        ),
      );
      await tester.tap(find.text('Open report screen'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'My order arrived cold.');
      await tester.tap(find.text('Submit report'));
      await tester.pumpAndSettle();

      expect(orders.capturedOrderId, 'order-report-1');
      expect(orders.capturedReason, 'My order arrived cold.');
      expect(orders.capturedPhotoUrl, isNull);
      expect(find.text("We've received your report and will follow up."), findsOneWidget);
      expect(find.byType(ReportProblemScreen), findsNothing);
    },
  );

  testWidgets(
    'a blank reason blocks submission with a real validation message',
    (tester) async {
      final orders = _RecordingOrdersRepository();

      await tester.pumpWidget(
        _harness(
          orderId: 'order-report-2',
          overrides: [
            authControllerProvider.overrideWith(() => _FakeAuthController(_studentSession())),
            ordersRepositoryProvider.overrideWithValue(orders),
          ],
        ),
      );
      await tester.tap(find.text('Open report screen'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Submit report'));
      await tester.pump();

      expect(find.text('Tell us what went wrong.'), findsOneWidget);
      expect(orders.capturedOrderId, isNull);
    },
  );

  testWidgets(
    'adding a photo uploads it with the real dispute-report purpose and sends the resulting URL',
    (tester) async {
      final uploads = _RecordingUploadsRepository();
      final orders = _RecordingOrdersRepository();

      await tester.pumpWidget(
        _harness(
          orderId: 'order-report-3',
          overrides: [
            authControllerProvider.overrideWith(() => _FakeAuthController(_studentSession())),
            uploadsRepositoryProvider.overrideWithValue(uploads),
            ordersRepositoryProvider.overrideWithValue(orders),
          ],
        ),
      );
      await tester.tap(find.text('Open report screen'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Missing an item.');
      await tester.tap(find.text('Add a photo (optional)'));
      await tester.pumpAndSettle();

      final captureStep = tester.widget<CameraCaptureStep>(find.byType(CameraCaptureStep));
      captureStep.onCaptured(Uint8List.fromList(_tinyValidPng));
      await tester.pumpAndSettle();

      expect(find.text('Remove photo'), findsOneWidget);

      await tester.tap(find.text('Submit report'));
      await tester.pumpAndSettle();

      expect(uploads.capturedPurpose, 'dispute-report');
      expect(orders.capturedPhotoUrl, 'https://cdn.example.com/dispute-report/test.jpg');
    },
  );

  testWidgets(
    'a real backend rejection (e.g. a dispute already exists) shows its own message and keeps the screen open',
    (tester) async {
      await tester.pumpWidget(
        _harness(
          orderId: 'order-report-4',
          overrides: [
            authControllerProvider.overrideWith(() => _FakeAuthController(_studentSession())),
            ordersRepositoryProvider.overrideWithValue(const _FailingOrdersRepository()),
          ],
        ),
      );
      await tester.tap(find.text('Open report screen'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Second report attempt.');
      await tester.tap(find.text('Submit report'));
      await tester.pumpAndSettle();

      expect(find.text('A dispute already exists for this order'), findsOneWidget);
      expect(find.byType(ReportProblemScreen), findsOneWidget);
    },
  );
}
