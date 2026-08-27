import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:run_it/core/widgets/segmented_progress_bar.dart';
import 'package:run_it/features/auth/application/auth_controller.dart';
import 'package:run_it/features/auth/application/kyc_flow_controller.dart';
import 'package:run_it/features/auth/domain/auth_models.dart';
import 'package:run_it/features/auth/presentation/kyc/kyc_capture_screen.dart';

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
    name: 'Test Runner',
    contact: '+2348000000000',
    accountType: AccountType.runner,
    campusId: 'ui',
  ),
);

Future<int> _pumpAndReadStepCount(
  WidgetTester tester,
  RunnerType runnerType,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(
          () => _FakeAuthController(_runnerSession()),
        ),
      ],
      child: const MaterialApp(home: KycCaptureScreen()),
    ),
  );
  // Seed the runner type the same way RunnerTypeScreen does, then rebuild.
  final container = ProviderScope.containerOf(
    tester.element(find.byType(KycCaptureScreen)),
  );
  container.read(kycFlowProvider.notifier).setRunnerType(runnerType);
  await tester.pump();

  final bar = tester.widget<SegmentedProgressBar>(
    find.byType(SegmentedProgressBar),
  );
  return bar.stepCount;
}

void main() {
  testWidgets(
    'the progress indicator step count matches kycStepsFor for a student runner (3 steps)',
    (tester) async {
      final stepCount = await _pumpAndReadStepCount(
        tester,
        RunnerType.studentRunner,
      );
      final expected = kycStepsFor(
        true,
        const KycCapture(runnerType: RunnerType.studentRunner),
      ).length;

      expect(stepCount, expected);
      expect(stepCount, 3);
    },
  );

  testWidgets(
    'the progress indicator step count matches kycStepsFor for an independent rider (5 steps)',
    (tester) async {
      final stepCount = await _pumpAndReadStepCount(
        tester,
        RunnerType.independentRider,
      );
      final expected = kycStepsFor(
        true,
        const KycCapture(runnerType: RunnerType.independentRider),
      ).length;

      expect(stepCount, expected);
      expect(stepCount, 5);
    },
  );
}
