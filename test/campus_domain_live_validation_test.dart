import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:run_it/core/network/campus_repository.dart';
import 'package:run_it/features/auth/domain/auth_models.dart';
import 'package:run_it/features/auth/presentation/signup_screen.dart';

/// Stands in for the real `GET /campuses/check-email` call — same
/// "subclass the repository, override the network method" convention as
/// every other repository fake in this suite.
class _FakeCampusRepository extends CampusRepository {
  _FakeCampusRepository(this._respond);
  final Future<CampusEmailCheck> Function(String email) _respond;

  int callCount = 0;

  @override
  Future<CampusEmailCheck> checkEmail(String email) {
    callCount++;
    return _respond(email);
  }
}

Widget _wrap(CampusRepository repository) => ProviderScope(
  overrides: [campusRepositoryProvider.overrideWithValue(repository)],
  child: const MaterialApp(home: SignupScreen(accountType: AccountType.student)),
);

Finder _emailField() => find.byType(TextField).at(1);

void main() {
  group('Task 27: real-time campus-domain feedback on the student signup email field', () {
    testWidgets('shows a green check for a recognized campus domain', (tester) async {
      final repo = _FakeCampusRepository(
        (email) async => const CampusEmailCheck(valid: true, campusName: 'University of Ibadan'),
      );
      await tester.pumpWidget(_wrap(repo));

      await tester.enterText(_emailField(), 'ada@student.ui.edu.ng');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      expect(repo.callCount, 1);
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    });

    testWidgets(
      "shows red with the backend's real rejection message for an unrecognized domain",
      (tester) async {
        const message =
            'We don\'t recognize "gmail.com" as a registered campus email domain. '
            'RUN-It is currently only available to students at supported schools.';
        final repo = _FakeCampusRepository(
          (email) async => const CampusEmailCheck(valid: false, message: message),
        );
        await tester.pumpWidget(_wrap(repo));

        await tester.enterText(_emailField(), 'ada@gmail.com');
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump();

        expect(repo.callCount, 1);
        expect(find.text(message), findsOneWidget);
        expect(find.byIcon(Icons.check_circle_rounded), findsNothing);
      },
    );

    testWidgets(
      'never calls the domain check, and never shows red, while the address is still syntactically incomplete',
      (tester) async {
        final repo = _FakeCampusRepository(
          (email) async => const CampusEmailCheck(valid: true, campusName: 'x'),
        );
        await tester.pumpWidget(_wrap(repo));

        // No real TLD yet ("u" is only one letter) — the shape check
        // itself withholds calling the (real, network-backed) domain
        // check at all.
        await tester.enterText(_emailField(), 'ada@student.u');
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump();

        expect(repo.callCount, 0);
        expect(find.text('Enter a valid school email address.'), findsOneWidget);
      },
    );

    testWidgets('shows a checking indicator while the request is in flight, not a premature red or green', (
      tester,
    ) async {
      final completer = Completer<CampusEmailCheck>();
      final repo = _FakeCampusRepository((email) => completer.future);
      await tester.pumpWidget(_wrap(repo));

      await tester.enterText(_emailField(), 'ada@student.ui.edu.ng');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_rounded), findsNothing);
      expect(find.textContaining("don't recognize"), findsNothing);

      completer.complete(const CampusEmailCheck(valid: true, campusName: 'University of Ibadan'));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    });

    testWidgets('a superseded request (user kept typing) never overwrites the latest state', (tester) async {
      final firstCompleter = Completer<CampusEmailCheck>();
      var call = 0;
      final repo = _FakeCampusRepository((email) {
        call++;
        // The second, current request resolves invalid (a spoofed
        // subdomain, realistically) — the first, now-stale request will
        // later resolve valid, and must not be allowed to overwrite this.
        return call == 1
            ? firstCompleter.future
            : Future.value(const CampusEmailCheck(valid: false, message: 'Not recognized.'));
      });
      await tester.pumpWidget(_wrap(repo));

      await tester.enterText(_emailField(), 'ada@student.ui.edu.ng');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(repo.callCount, 1);

      // Edits again before the first request resolves.
      await tester.enterText(_emailField(), 'ada@student.ui.edu.ng.evil.com');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(repo.callCount, 2);
      expect(find.text('Not recognized.'), findsOneWidget);

      // The first (now-stale) request finally resolves as valid — it must
      // not flip the field green out from under the newer, already-
      // resolved-invalid second request.
      firstCompleter.complete(const CampusEmailCheck(valid: true, campusName: 'University of Ibadan'));
      await tester.pump();

      expect(find.byIcon(Icons.check_circle_rounded), findsNothing);
      expect(find.text('Not recognized.'), findsOneWidget);
    });
  });
}
