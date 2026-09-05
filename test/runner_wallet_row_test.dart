import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:run_it/core/network/ratings_repository.dart';
import 'package:run_it/core/routing/app_router.dart';
import 'package:run_it/core/widgets/app_nav_shell.dart';
import 'package:run_it/features/auth/application/auth_controller.dart';
import 'package:run_it/features/auth/domain/auth_models.dart';
import 'package:run_it/features/runner/presentation/runner_profile_screen.dart';
import 'package:run_it/features/wallet/data/wallet_repository.dart';
import 'package:run_it/features/wallet/domain/wallet_models.dart';
import 'package:run_it/features/wallet/presentation/wallet_screen.dart';

/// Task 33: runner earnings now land in an in-app wallet balance instead of
/// a direct Paystack transfer — this proves the two things the task asked
/// to confirm live rather than trust from Task 32's report: (1) a runner
/// can actually reach WalletScreen from their own shell/navigation, and
/// (2) once there, it renders their real balance with zero
/// runner-vs-student special-casing, since WalletBalanceController is keyed
/// only on the signed-in session's user id.
class _FakeRatingsRepository extends RatingsRepository {
  const _FakeRatingsRepository();
  @override
  Future<RunnerRatingSummary> fetchRunnerRatingSummary(String runnerId) async =>
      RunnerRatingSummary(runnerId: runnerId, averageRating: 4.8, ratingCount: 12);
}

class _FakeAuthController extends AuthController {
  _FakeAuthController(this._session);
  final AuthSession _session;
  @override
  AuthSession? build() => _session;
}

/// A runner whose delivery earnings have already credited their wallet to
/// ₦3,500 — stands in for a real GET /wallet/:userId/balance +
/// /transactions response, same as `_SavedPayoutAccountController` etc. do
/// for the withdraw-flow tests in student_shell_screens_test.dart.
class _CreditedRunnerWalletRepository extends WalletRepository {
  const _CreditedRunnerWalletRepository();

  @override
  Future<int> getBalance({required String userId, required String token}) async => 3_500;

  @override
  Future<List<WalletTransaction>> getTransactions({
    required String userId,
    required String token,
  }) async => [
    WalletTransaction(
      id: 'wt-runner-1',
      title: 'Delivery earnings',
      subtitle: 'Order payout',
      amount: 3_500,
      kind: WalletTransactionKind.credit,
      occurredAt: DateTime(2026, 9, 3),
      status: 'success',
    ),
  ];
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
  ),
);

void main() {
  group('Runner Profile — Wallet row (Task 33)', () {
    testWidgets('shows a Wallet row and navigates to WalletScreen showing the real credited balance', (
      tester,
    ) async {
      // Task 48's added honest-framing caption makes this screen taller —
      // the default 800x600 test surface was already tight enough that
      // "Wallet" sat right at the sliver list's cache-extent edge; a
      // realistic phone height (same convention most other screen tests
      // in this suite use) gives it real room instead.
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final router = GoRouter(
        initialLocation: AppRoutes.runnerProfile,
        routes: [
          GoRoute(
            path: AppRoutes.runnerProfile,
            builder: (context, state) => const RunnerShell(child: RunnerProfileScreen()),
          ),
          GoRoute(
            path: AppRoutes.runnerWallet,
            builder: (context, state) => const RunnerShell(child: WalletScreen()),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authControllerProvider.overrideWith(() => _FakeAuthController(_runnerSession())),
            ratingsRepositoryProvider.overrideWithValue(const _FakeRatingsRepository()),
            walletRepositoryProvider.overrideWithValue(const _CreditedRunnerWalletRepository()),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pump();

      expect(find.text('Wallet'), findsOneWidget);
      await tester.ensureVisible(find.text('Wallet'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Wallet'));
      await tester.pumpAndSettle();

      // Landed on the real WalletScreen — same widget StudentShell uses,
      // now rendering a runner's real backend-fetched balance.
      expect(find.text('₦3500'), findsOneWidget);
      await tester.dragUntilVisible(
        find.text('Delivery earnings'),
        find.byType(CustomScrollView),
        const Offset(0, -150),
      );
      expect(find.text('Delivery earnings'), findsOneWidget);
    });
  });
}
