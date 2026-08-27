import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:run_it/core/routing/app_router.dart';
import 'package:run_it/core/widgets/segmented_progress_bar.dart';
import 'package:run_it/features/auth/application/auth_controller.dart';
import 'package:run_it/features/auth/domain/auth_models.dart';
import 'package:run_it/features/auth/presentation/kyc/kyc_capture_screen.dart';
import 'package:run_it/features/auth/presentation/kyc/kyc_status_screen.dart';

class _FakeAuthController extends AuthController {
  _FakeAuthController(this._session);
  final AuthSession _session;
  @override
  AuthSession? build() => _session;
}

AuthSession _rejectedRiderSession() => AuthSession(
  accessToken: 'a',
  refreshToken: 'r',
  expiresAt: DateTime.now().add(const Duration(minutes: 5)),
  user: const UserProfile(
    id: 'runner-1',
    name: 'Test Runner',
    contact: '+2348000000000',
    accountType: AccountType.runner,
    campusId: 'ui',
    kycStatus: KycStatus.rejected,
    kycRejectionReason:
        'ID photo was blurry — please retake in better lighting.',
    // Persisted from their original submission — this is exactly what
    // lets Resubmit reconstruct the right (5-step) capture flow instead
    // of falling back to the shorter one.
    runnerType: RunnerType.independentRider,
  ),
);

void main() {
  testWidgets(
    'rejected state shows the real reason and Resubmit restores the runner-type-specific capture flow',
    (tester) async {
      final router = GoRouter(
        initialLocation: AppRoutes.kycStatus,
        routes: [
          GoRoute(
            path: AppRoutes.kycStatus,
            builder: (context, state) => const KycStatusScreen(),
          ),
          GoRoute(
            path: AppRoutes.kycCapture,
            builder: (context, state) => const KycCaptureScreen(),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authControllerProvider.overrideWith(
              () => _FakeAuthController(_rejectedRiderSession()),
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pump();

      // The specific backend-provided reason, not a generic label.
      expect(
        find.text('ID photo was blurry — please retake in better lighting.'),
        findsOneWidget,
      );
      expect(find.text('Resubmit'), findsOneWidget);
      expect(find.text('Contact support'), findsOneWidget);

      await tester.tap(find.text('Resubmit'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(KycCaptureScreen), findsOneWidget);
      // Independent Rider is a 5-step flow (ID, Selfie, Vehicle Photo,
      // Vehicle Details, Almost There) — if the resubmit path lost the
      // runner type, this would silently fall back to 3.
      final bar = tester.widget<SegmentedProgressBar>(
        find.byType(SegmentedProgressBar),
      );
      expect(bar.stepCount, 5);
    },
  );

  testWidgets('Contact support shows a message instead of doing nothing', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: AppRoutes.kycStatus,
      routes: [
        GoRoute(
          path: AppRoutes.kycStatus,
          builder: (context, state) => const KycStatusScreen(),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(
            () => _FakeAuthController(_rejectedRiderSession()),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('Contact support'));
    await tester.pump();

    expect(find.byType(SnackBar), findsOneWidget);

    // Let the SnackBar's own auto-dismiss timer and any setup timers from
    // the card's entrance animation resolve before the test ends — an
    // unresolved Timer at teardown fails the test even though it has no
    // bearing on the behavior under test.
    await tester.pump(const Duration(seconds: 5));
  });

  group('the rejected -> resubmit -> pending loop', () {
    test('submitKyc moves a rejected account back to pending and clears the reason', () {
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith(
            () => _FakeAuthController(_rejectedRiderSession()),
          ),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(authControllerProvider.notifier);

      expect(
        container.read(authControllerProvider)!.user.kycStatus,
        KycStatus.rejected,
      );

      controller.submitKyc(runnerType: RunnerType.independentRider);

      final user = container.read(authControllerProvider)!.user;
      expect(user.kycStatus, KycStatus.pending);
      expect(user.kycRejectionReason, isNull);
      expect(user.runnerType, RunnerType.independentRider);
    });
  });
}
