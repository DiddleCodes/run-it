import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:run_it/core/network/ratings_repository.dart';
import 'package:run_it/features/auth/application/auth_controller.dart';
import 'package:run_it/features/auth/domain/auth_models.dart';
import 'package:run_it/features/runner/presentation/runner_profile_screen.dart';

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
  ),
);

class _FakeRatingsRepository extends RatingsRepository {
  const _FakeRatingsRepository(this.summary);
  final RunnerRatingSummary? summary;
  @override
  Future<RunnerRatingSummary> fetchRunnerRatingSummary(String runnerId) async {
    if (summary == null) throw StateError('unreachable in this test');
    return summary!;
  }
}

Widget _harness(RatingsRepository repo) => ProviderScope(
  overrides: [
    authControllerProvider.overrideWith(() => _FakeAuthController(_runnerSession())),
    ratingsRepositoryProvider.overrideWithValue(repo),
  ],
  child: const MaterialApp(home: RunnerProfileScreen()),
);

void main() {
  group('Runner Profile — real rating-summary fetch (Task 14 Part D)', () {
    testWidgets('shows the real average once GET /runners/:id/rating-summary resolves', (tester) async {
      await tester.pumpWidget(
        _harness(const _FakeRatingsRepository(RunnerRatingSummary(runnerId: 'runner-1', averageRating: 4.7, ratingCount: 23))),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Shown in both the profile hero row and the Rating stat card.
      expect(find.text('4.7'), findsNWidgets(2));
    });

    testWidgets('shows a dash rather than a fabricated number before any rating exists', (tester) async {
      await tester.pumpWidget(
        _harness(const _FakeRatingsRepository(RunnerRatingSummary(runnerId: 'runner-1', averageRating: 0, ratingCount: 0))),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('—'), findsWidgets);
      expect(find.text('0.0'), findsNothing);
    });
  });
}
