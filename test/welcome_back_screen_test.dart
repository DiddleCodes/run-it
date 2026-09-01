import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:local_auth/local_auth.dart';
import 'package:run_it/core/routing/app_router.dart';
import 'package:run_it/features/auth/application/auth_controller.dart';
import 'package:run_it/features/auth/domain/auth_models.dart';
import 'package:run_it/features/auth/presentation/welcome_back_screen.dart';

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
    passcodeSet: true,
  ),
);

/// Overrides just the handful of [AuthController] methods
/// [WelcomeBackScreen] calls, rather than exercising real secure storage —
/// lets each test drive passcode/biometric/recovery outcomes
/// deterministically.
class _FakeAuthController extends AuthController {
  bool biometricEnrolled = true;
  bool isFaceId = false;
  bool passcodeShouldSucceed = false;
  bool biometricShouldSucceed = false;
  bool recoverShouldSucceed = true;
  String? storedContact = 'student@campus.edu';
  Duration biometricDelay = Duration.zero;

  int loginWithPasscodeCalls = 0;
  int loginWithBiometricCalls = 0;
  String? lastPasscodeAttempt;
  String? recoveredContact;
  String? recoveredCode;
  String? savedPasscode;

  @override
  AuthSession? build() => null;

  @override
  Future<bool> hasBiometricCredential() async => biometricEnrolled;

  @override
  Future<List<BiometricType>> availableBiometrics() async =>
      biometricEnrolled
      ? [isFaceId ? BiometricType.face : BiometricType.fingerprint]
      : const [];

  @override
  Future<bool> loginWithPasscode(String passcode) async {
    loginWithPasscodeCalls++;
    lastPasscodeAttempt = passcode;
    if (!passcodeShouldSucceed) return false;
    state = _studentSession();
    return true;
  }

  @override
  Future<bool> loginWithBiometric() async {
    loginWithBiometricCalls++;
    if (biometricDelay > Duration.zero) await Future<void>.delayed(biometricDelay);
    if (!biometricShouldSucceed) return false;
    state = _studentSession();
    return true;
  }

  @override
  Future<String?> storedPasscodeContact() async => storedContact;

  @override
  Future<AccountType?> storedPasscodeAccountType() async =>
      storedContact == null ? null : AccountType.student;

  @override
  Future<void> sendOtp(String contact, {required AccountType accountType}) async {}

  @override
  Future<bool> recoverSessionForPasscodeReset({
    required String contact,
    required String code,
  }) async {
    recoveredContact = contact;
    recoveredCode = code;
    if (!recoverShouldSucceed) return false;
    state = _studentSession();
    return true;
  }

  @override
  Future<void> setPasscode(String passcode) async {
    savedPasscode = passcode;
  }

  @override
  Future<bool> isBiometricAvailable() async => true;
}

/// The default flutter_test surface (800x600) is shorter than any real
/// phone and pushes this screen's lower content out of the hit-testable
/// viewport (still no overflow — it's a `SingleChildScrollView` — but taps
/// below the fold fail since nothing scrolls them into view). Pin every
/// test to a realistic phone size instead.
void _setPhoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _tapDigits(WidgetTester tester, String digits) async {
  for (final digit in digits.split('')) {
    await tester.tap(find.text(digit));
    await tester.pump(const Duration(milliseconds: 30));
  }
}

Widget _buildApp(_FakeAuthController fake) {
  final router = GoRouter(
    initialLocation: AppRoutes.login,
    routes: [
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => const WelcomeBackScreen(),
      ),
      GoRoute(
        path: AppRoutes.home,
        builder: (context, state) => const Text('HOME_SCREEN'),
      ),
    ],
  );
  return ProviderScope(
    overrides: [authControllerProvider.overrideWith(() => fake)],
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  testWidgets('auto-submit fires at the 6th digit with no separate login button', (
    tester,
  ) async {
    _setPhoneViewport(tester);
    final fake = _FakeAuthController()..passcodeShouldSucceed = true;
    await tester.pumpWidget(_buildApp(fake));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50)); // biometric probe

    await _tapDigits(tester, '12345');
    expect(fake.loginWithPasscodeCalls, 0);

    await _tapDigits(tester, '6');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(fake.loginWithPasscodeCalls, 1);
    expect(fake.lastPasscodeAttempt, '123456');
    await tester.pumpAndSettle();
    expect(find.text('HOME_SCREEN'), findsOneWidget);
  });

  testWidgets('an incorrect passcode clears entry and shows the inline error message', (
    tester,
  ) async {
    _setPhoneViewport(tester);
    final fake = _FakeAuthController()..passcodeShouldSucceed = false;
    await tester.pumpWidget(_buildApp(fake));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await _tapDigits(tester, '111111');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500)); // shake animation

    expect(find.text('Incorrect passcode. Try again.'), findsOneWidget);
    // Digits reset — no stray filled dots left over from the failed try.
    expect(fake.loginWithPasscodeCalls, 1);

    // Entry still works after a failure — not a dead end.
    fake.passcodeShouldSucceed = true;
    await _tapDigits(tester, '222222');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(fake.loginWithPasscodeCalls, 2);
    await tester.pumpAndSettle();
    expect(find.text('HOME_SCREEN'), findsOneWidget);
  });

  testWidgets(
    'the biometric keypad shortcut triggers the same auth path as the dedicated "Sign in with Biometrics" button',
    (tester) async {
      _setPhoneViewport(tester);
      final fake = _FakeAuthController()..biometricShouldSucceed = true;
      await tester.pumpWidget(_buildApp(fake));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50)); // biometric probe

      expect(find.text('Sign in with Biometrics'), findsOneWidget);
      // Two distinct biometric entry points: the keypad shortcut and the
      // dedicated button below the "OR" divider.
      expect(find.byIcon(Icons.fingerprint_rounded), findsNWidgets(2));
      expect(
        find.bySemanticsLabel('Sign in using device biometrics'),
        findsWidgets,
      );

      // Tap the keypad's fingerprint shortcut (bottom-left slot).
      await tester.tap(find.byIcon(Icons.fingerprint_rounded).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(fake.loginWithBiometricCalls, 1);
      await tester.pumpAndSettle();
      expect(find.text('HOME_SCREEN'), findsOneWidget);
    },
  );

  testWidgets(
    'the dedicated biometric button drives the same loginWithBiometric call and shows an authenticating state',
    (tester) async {
      _setPhoneViewport(tester);
      final fake = _FakeAuthController()
        ..biometricShouldSucceed = true
        ..biometricDelay = const Duration(milliseconds: 200);
      await tester.pumpWidget(_buildApp(fake));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await tester.tap(find.text('Sign in with Biometrics'));
      await tester.pump(); // mid-flight: the 200ms delay hasn't resolved yet.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.pumpAndSettle();
      expect(fake.loginWithBiometricCalls, 1);
      expect(find.text('HOME_SCREEN'), findsOneWidget);
    },
  );

  testWidgets('a failed biometric attempt returns to passcode entry instead of dead-ending', (
    tester,
  ) async {
    _setPhoneViewport(tester);
    final fake = _FakeAuthController()..biometricShouldSucceed = false;
    await tester.pumpWidget(_buildApp(fake));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('Sign in with Biometrics'));
    await tester.pumpAndSettle();

    expect(fake.loginWithBiometricCalls, 1);
    expect(find.text('HOME_SCREEN'), findsNothing);
    // Still on Welcome Back, keypad still usable.
    expect(find.text('Welcome back!'), findsOneWidget);
    fake.passcodeShouldSucceed = true;
    await _tapDigits(tester, '123456');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(fake.loginWithPasscodeCalls, 1);
  });

  testWidgets(
    'Forgot passcode routes through OTP re-verification -> Set Passcode -> back to Welcome Back',
    (tester) async {
      _setPhoneViewport(tester);
      final fake = _FakeAuthController()
        ..storedContact = 'student@campus.edu'
        ..recoverShouldSucceed = true;
      await tester.pumpWidget(_buildApp(fake));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await tester.tap(find.text('Forgot passcode?'));
      await tester.pumpAndSettle();

      expect(find.text('Enter the code'), findsOneWidget);
      expect(find.text('Sent to student@campus.edu'), findsOneWidget);

      // Enter a 6-digit recovery code — auto-submits.
      final codeField = find.byType(TextField);
      await tester.enterText(codeField, '482913');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700)); // verify + success beat
      await tester.pumpAndSettle();

      expect(fake.recoveredContact, 'student@campus.edu');
      expect(fake.recoveredCode, '482913');

      // Landed on Set Passcode to create a new one.
      expect(find.text('Create a 6-digit passcode'), findsOneWidget);
      await _tapDigits(tester, '135790');
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('Confirm your passcode'), findsOneWidget);
      await _tapDigits(tester, '135790');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      expect(fake.savedPasscode, '135790');
      // Unwound all the way back to Welcome Back, not left on OTP or Set
      // Passcode.
      expect(find.text('Welcome back!'), findsOneWidget);
    },
  );

  testWidgets('Forgot passcode with no stored account shows a message instead of navigating', (
    tester,
  ) async {
    _setPhoneViewport(tester);
    final fake = _FakeAuthController()..storedContact = null;
    await tester.pumpWidget(_buildApp(fake));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('Forgot passcode?'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Enter the code'), findsNothing);
    expect(find.text('Welcome back!'), findsOneWidget);
  });

  testWidgets('no biometric credential enrolled hides both biometric entry points', (
    tester,
  ) async {
    _setPhoneViewport(tester);
    final fake = _FakeAuthController()..biometricEnrolled = false;
    await tester.pumpWidget(_buildApp(fake));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Sign in with Biometrics'), findsNothing);
    expect(find.byIcon(Icons.fingerprint_rounded), findsNothing);
  });
}
