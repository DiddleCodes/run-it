import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:run_it/core/network/campus_repository.dart';
import 'package:run_it/core/routing/app_router.dart';
import 'package:run_it/features/auth/application/auth_controller.dart';
import 'package:run_it/features/auth/data/auth_repository.dart';
import 'package:run_it/features/auth/domain/auth_models.dart';
import 'package:run_it/features/auth/presentation/signup_screen.dart';

/// Task 28: stands in for the real `POST /auth/otp/request` — records what
/// `SignupScreen._continue()` actually sends for a runner, so these tests
/// can assert on the real contact/accountType pair without a live server.
class _RecordingAuthRepository extends AuthRepository {
  _RecordingAuthRepository();
  String? lastContact;
  AccountType? lastAccountType;

  @override
  Future<void> sendOtp(String contact, {required AccountType accountType}) async {
    lastContact = contact;
    lastAccountType = accountType;
  }
}

class _FakeAuthController extends AuthController {
  _FakeAuthController(this._repository);
  final AuthRepository _repository;
  @override
  AuthSession? build() {
    repository = _repository;
    return null;
  }
}

/// Fails the test if ever called — the real assertion that runner signup
/// never triggers a campus/domain check (Task 26 enforcement is
/// students-only; Task 28 must not accidentally extend it to runners just
/// because a runner's contact is an email now too).
class _FailIfCalledCampusRepository extends CampusRepository {
  const _FailIfCalledCampusRepository();

  @override
  Future<CampusEmailCheck> checkEmail(String email) async {
    fail('Runner signup must never call the campus domain check — Task 26 enforcement is students-only.');
  }
}

Widget _wrap(_RecordingAuthRepository authRepo) {
  final router = GoRouter(
    initialLocation: AppRoutes.accountType,
    routes: [
      GoRoute(
        path: AppRoutes.accountType,
        builder: (_, _) =>
            const SignupScreen(accountType: AccountType.runner),
      ),
      GoRoute(path: AppRoutes.otp, builder: (_, _) => const Text('OTP_SCREEN')),
    ],
  );
  return ProviderScope(
    overrides: [
      authControllerProvider.overrideWith(() => _FakeAuthController(authRepo)),
      campusRepositoryProvider.overrideWithValue(const _FailIfCalledCampusRepository()),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  group('Task 28: runner signup collects a real email (OTP contact) alongside phone', () {
    testWidgets('shows both an email field and a phone field for a runner', (tester) async {
      final authRepo = _RecordingAuthRepository();
      await tester.pumpWidget(_wrap(authRepo));
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Email address'), findsOneWidget);
      expect(find.text('Phone number'), findsOneWidget);
      // Never the student-specific, campus-flavored copy.
      expect(find.text('School email address'), findsNothing);
    });

    testWidgets(
      'Continue sends the OTP to the email (not the phone), and submits with runner accountType',
      (tester) async {
        final authRepo = _RecordingAuthRepository();
        await tester.pumpWidget(_wrap(authRepo));
        await tester.pump();

        await tester.enterText(find.byType(TextField).at(0), 'Femi Runner');
        await tester.enterText(find.byType(TextField).at(1), 'femi.runner@gmail.com');
        await tester.enterText(find.byType(TextField).at(2), '8012345678');
        await tester.tap(_agreeToTermsCheckbox);
        await tester.pump();
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();

        expect(authRepo.lastContact, 'femi.runner@gmail.com');
        expect(authRepo.lastAccountType, AccountType.runner);
        expect(find.text('OTP_SCREEN'), findsOneWidget);
      },
    );

    testWidgets('a malformed runner email blocks Continue with a real validation error', (tester) async {
      final authRepo = _RecordingAuthRepository();
      await tester.pumpWidget(_wrap(authRepo));
      await tester.pump();

      await tester.enterText(find.byType(TextField).at(0), 'Femi Runner');
      await tester.enterText(find.byType(TextField).at(1), 'not-an-email');
      await tester.enterText(find.byType(TextField).at(2), '8012345678');
      await tester.tap(_agreeToTermsCheckbox);
      await tester.pump();
      await tester.tap(find.text('Continue'));
      await tester.pump();

      expect(find.text('Enter a valid email address.'), findsOneWidget);
      expect(authRepo.lastContact, isNull);
    });
  });
}

/// The "I agree to the Terms and Privacy Policy" row's tappable
/// GestureDetector — found via its checkbox's checkmark icon (the row's
/// own text is split across several inline spans, so it can't be found by
/// a single Text match) rather than an ambiguous "first GestureDetector"
/// guess, since this screen has several (back button, this checkbox, the
/// Terms/Privacy Policy links, the "Log in" link).
final Finder _agreeToTermsCheckbox = find.ancestor(
  of: find.byIcon(Icons.check_rounded),
  matching: find.byType(GestureDetector),
).first;
