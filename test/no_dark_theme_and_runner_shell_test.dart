import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:run_it/core/network/matching_repository.dart';
import 'package:run_it/core/routing/app_router.dart';
import 'package:run_it/features/auth/application/auth_controller.dart';
import 'package:run_it/features/auth/domain/auth_models.dart';
import 'package:run_it/features/auth/presentation/kyc/kyc_status_screen.dart';
import 'package:run_it/features/runner/domain/runner_models.dart';
import 'package:run_it/features/runner/presentation/runner_jobs_screen.dart';
import 'package:run_it/features/runner/presentation/runner_screens.dart';

class _FakeAuthController extends AuthController {
  _FakeAuthController(this._session);
  final AuthSession _session;
  @override
  AuthSession? build() => _session;
}

/// RunnerHomeScreen/RunnerJobsScreen both mount `availableJobsProvider`
/// (Task 21b), which otherwise hits the real `GET /matching/available` —
/// keeps these theme/nav tests network-free.
class _FakeMatchingRepository extends MatchingRepository {
  const _FakeMatchingRepository();
  @override
  Future<List<DeliveryJob>> listAvailable({required String token}) async => const [];
}

AuthSession _verifiedRunnerSession() => AuthSession(
  accessToken: 'a',
  refreshToken: 'r',
  expiresAt: DateTime.now().add(const Duration(minutes: 5)),
  user: const UserProfile(
    id: 'runner-1',
    name: 'Test Runner',
    contact: '+2348000000000',
    accountType: AccountType.runner,
    campusId: 'ui',
    kycStatus: KycStatus.verified,
    runnerType: RunnerType.studentRunner,
  ),
);

void main() {
  group('runner screens never resolve to a dark theme', () {
    testWidgets(
      'the KYC Verified screen for a runner renders with the light theme',
      (tester) async {
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
                () => _FakeAuthController(_verifiedRunnerSession()),
              ),
            ],
            child: MaterialApp.router(routerConfig: router),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        final context = tester.element(find.byType(KycStatusScreen));
        expect(Theme.of(context).brightness, Brightness.light);
      },
    );

    testWidgets('the runner dashboard renders with the light theme', (
      tester,
    ) async {
      final router = GoRouter(
        initialLocation: AppRoutes.runnerHome,
        routes: [
          GoRoute(
            path: AppRoutes.runnerHome,
            builder: (context, state) =>
                const RunnerShell(child: RunnerHomeScreen()),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authControllerProvider.overrideWith(
              () => _FakeAuthController(_verifiedRunnerSession()),
            ),
            matchingRepositoryProvider.overrideWithValue(const _FakeMatchingRepository()),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final context = tester.element(find.byType(RunnerHomeScreen));
      expect(Theme.of(context).brightness, Brightness.light);
    });
  });

  group('RunnerShell mounts the persistent bottom nav', () {
    testWidgets('all 5 tabs render, with Home active on the dashboard', (
      tester,
    ) async {
      final router = GoRouter(
        initialLocation: AppRoutes.runnerHome,
        routes: [
          GoRoute(
            path: AppRoutes.runnerHome,
            builder: (context, state) =>
                const RunnerShell(child: RunnerHomeScreen()),
          ),
          GoRoute(
            path: AppRoutes.runnerJobs,
            builder: (context, state) =>
                const RunnerShell(child: RunnerJobsScreen()),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authControllerProvider.overrideWith(
              () => _FakeAuthController(_verifiedRunnerSession()),
            ),
            matchingRepositoryProvider.overrideWithValue(const _FakeMatchingRepository()),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Jobs'), findsOneWidget);
      expect(find.text('Messages'), findsOneWidget);
      expect(find.text('Profile'), findsOneWidget);
      expect(find.text('Scan'), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.viewfinder), findsOneWidget);
      // Home is the active tab on the dashboard route.
      expect(find.byIcon(CupertinoIcons.house_fill), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.house), findsNothing);

      await tester.tap(find.text('Jobs'));
      await tester.pumpAndSettle();

      expect(find.byType(RunnerJobsScreen), findsOneWidget);
      expect(find.byType(RunnerHomeScreen), findsNothing);
      // Switching tabs flips which icon is filled vs. outlined.
      expect(find.byIcon(CupertinoIcons.bag_fill), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.house_fill), findsNothing);
    });
  });
}
