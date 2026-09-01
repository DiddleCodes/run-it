import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:run_it/core/network/ratings_repository.dart';
import 'package:run_it/features/auth/application/auth_controller.dart';
import 'package:run_it/features/auth/domain/auth_models.dart';
import 'package:run_it/features/payout/application/payout_controller.dart';
import 'package:run_it/features/payout/domain/payout_models.dart';
import 'package:run_it/features/runner/presentation/runner_profile_screen.dart';

/// Task 14: Runner Profile now fetches its real rating aggregate — this
/// file only cares about the Payouts row, so a fixed, network-free stub
/// keeps it that way.
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

/// Fixes the Payouts row's state directly rather than letting
/// [PayoutController.load] run for real — this file is testing what the
/// row *displays* for a given controller state, not the network path
/// (see `payout_account_form_test.dart` for that).
class _FakePayoutController extends PayoutController {
  _FakePayoutController(this._initial);
  final PayoutAccount? _initial;

  @override
  PayoutAccount? build() => _initial;

  @override
  Future<void> load() async {}
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
  group('Runner Profile — Payouts row', () {
    testWidgets('reads "Not set" when no payout account has been saved yet', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authControllerProvider.overrideWith(() => _FakeAuthController(_runnerSession())),
            payoutControllerProvider.overrideWith(() => _FakePayoutController(null)),
            ratingsRepositoryProvider.overrideWithValue(const _FakeRatingsRepository()),
          ],
          child: const MaterialApp(home: RunnerProfileScreen()),
        ),
      );
      await tester.pump();

      expect(find.text('Payouts'), findsOneWidget);
      expect(find.text('Not set'), findsOneWidget);
    });

    testWidgets('reflects a saved account as a masked number and bank name', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authControllerProvider.overrideWith(() => _FakeAuthController(_runnerSession())),
            payoutControllerProvider.overrideWith(
              () => _FakePayoutController(
                const PayoutAccount(
                  bankCode: '058',
                  bankName: 'GTBank',
                  accountNumber: '0123454417',
                  accountName: 'Ada Runner',
                ),
              ),
            ),
            ratingsRepositoryProvider.overrideWithValue(const _FakeRatingsRepository()),
          ],
          child: const MaterialApp(home: RunnerProfileScreen()),
        ),
      );
      await tester.pump();

      expect(find.text('Payouts'), findsOneWidget);
      expect(find.text('Not set'), findsNothing);
      expect(find.text('•••• 4417 — GTBank'), findsOneWidget);
    });
  });
}
