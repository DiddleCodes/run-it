import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:run_it/core/routing/app_router.dart';
import 'package:run_it/features/auth/application/auth_controller.dart';
import 'package:run_it/features/auth/domain/auth_models.dart';
import 'package:run_it/features/auth/presentation/set_passcode_screen.dart';

class _FakeAuthController extends AuthController {
  _FakeAuthController(this._session);
  final AuthSession _session;
  String? lastPasscode;

  @override
  AuthSession? build() => _session;

  @override
  Future<void> setPasscode(String passcode) async {
    lastPasscode = passcode;
  }

  @override
  Future<bool> isBiometricAvailable() async => false;
}

AuthSession _studentSession() => AuthSession(
  accessToken: 'test-access',
  refreshToken: 'test-refresh',
  expiresAt: DateTime.now().add(const Duration(minutes: 5)),
  user: const UserProfile(
    id: 'student-1',
    name: 'Test Student',
    contact: 'student@campus.edu',
    accountType: AccountType.student,
    campusId: 'ui',
  ),
);

Future<void> _tapDigits(WidgetTester tester, String digits) async {
  for (final digit in digits.split('')) {
    await tester.tap(find.text(digit));
    await tester.pump(const Duration(milliseconds: 30));
  }
}

void main() {
  testWidgets(
    'a confirm-step mismatch shows an error and resets without saving; a match saves and navigates on',
    (tester) async {
      final fake = _FakeAuthController(_studentSession());
      final router = GoRouter(
        initialLocation: AppRoutes.setPasscode,
        routes: [
          GoRoute(
            path: AppRoutes.setPasscode,
            builder: (context, state) => const SetPasscodeScreen(),
          ),
          GoRoute(
            path: AppRoutes.home,
            builder: (context, state) => const Text('HOME_SCREEN'),
          ),
          GoRoute(
            path: AppRoutes.biometricSetup,
            builder: (context, state) => const Text('BIOMETRIC_SCREEN'),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [authControllerProvider.overrideWith(() => fake)],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pump();

      expect(find.text('Create a 6-digit passcode'), findsOneWidget);

      // Enter phase — six digits.
      await _tapDigits(tester, '123456');
      await tester.pump(
        const Duration(milliseconds: 250),
      ); // enter -> confirm transition

      expect(find.text('Confirm your passcode'), findsOneWidget);

      // Confirm phase — deliberately mismatched.
      await _tapDigits(tester, '654321');
      await tester.pump(const Duration(milliseconds: 500)); // shake + reset

      expect(find.text("Those don't match — try again."), findsOneWidget);
      expect(fake.lastPasscode, isNull);
      // Still on the confirm step, not bounced back to re-entering the
      // first passcode.
      expect(find.text('Confirm your passcode'), findsOneWidget);

      // Confirm phase — matching this time.
      await _tapDigits(tester, '123456');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      expect(fake.lastPasscode, '123456');
      expect(find.text('HOME_SCREEN'), findsOneWidget);
    },
  );
}
