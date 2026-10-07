import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:local_auth/local_auth.dart';
import 'package:run_it/core/routing/app_router.dart';
import 'package:run_it/features/auth/application/auth_controller.dart';
import 'package:run_it/features/auth/domain/auth_models.dart';
import 'package:run_it/features/auth/presentation/signup_screen.dart';

/// What the backend says about the account right now (GET /auth/me).
class _Backend {
  _Backend({this.kyc = KycStatus.none, this.vendor = VendorReviewStatus.none});
  KycStatus kyc;
  VendorReviewStatus vendor;
  bool reachable = true;
  int meCalls = 0;
}

/// Every sign-in path, with the device knowing nothing about the account's
/// review status (a fresh install / new phone) — exactly what used to send
/// approved runners back into verification.
class _FakeAuth extends AuthController {
  _FakeAuth(this.backend, this.accountType);

  final _Backend backend;
  final AccountType accountType;

  /// Only the biometric path has a fingerprint enrolled — otherwise Welcome
  /// Back would offer it automatically and the passcode paths would really
  /// be biometric sign-ins.
  bool biometricEnrolled = false;

  UserProfile _deviceCopy({required bool passcodeSet}) => UserProfile(
    id: 'u1',
    name: 'Test',
    contact: 'test@runit.dev',
    accountType: accountType,
    passcodeSet: passcodeSet,
  );

  void _signIn({bool passcodeSet = true}) => state = AuthSession(
    accessToken: 'a',
    refreshToken: 'r',
    expiresAt: DateTime.now().add(const Duration(hours: 1)),
    user: _deviceCopy(passcodeSet: passcodeSet),
  );

  @override
  AuthSession? build() => null;

  @override
  Future<void> sendOtp(String contact, {required AccountType accountType}) async {}

  @override
  Future<void> verifyOtpAndLogin({
    required String contact,
    required String code,
    required String name,
    required AccountType accountType,
    String? classOrGrade,
    String? phone,
  }) async => _signIn(passcodeSet: false); // a new phone: no passcode yet

  @override
  Future<void> setPasscode(String passcode) async {
    final current = state;
    if (current != null) state = current.copyWith(user: current.user.copyWith(passcodeSet: true));
  }

  @override
  Future<bool> isBiometricAvailable() async => false;

  @override
  Future<bool> hasBiometricCredential() async => biometricEnrolled;

  @override
  Future<List<BiometricType>> availableBiometrics() async =>
      biometricEnrolled ? [BiometricType.fingerprint] : const [];

  @override
  Future<bool> loginWithPasscode(String passcode) async {
    _signIn();
    return true;
  }

  @override
  Future<bool> loginWithBiometric() async {
    _signIn();
    return true;
  }

  @override
  Future<String?> storedPasscodeContact() async => 'test@runit.dev';

  @override
  Future<AccountType?> storedPasscodeAccountType() async => accountType;

  @override
  Future<bool> recoverSessionForPasscodeReset({required String contact, required String code}) async {
    _signIn();
    return true;
  }

  @override
  Future<bool> refreshProfile() async {
    backend.meCalls++;
    final current = state;
    if (current == null || !backend.reachable) return false;
    state = current.copyWith(
      user: current.user.copyWith(kycStatus: backend.kyc, vendorStatus: backend.vendor),
    );
    return true;
  }
}

Future<(GoRouter, _Backend)> _start(WidgetTester tester, AccountType type, _Backend backend, {bool biometric = false}) async {
  final container = ProviderContainer(
    overrides: [authControllerProvider.overrideWith(() => _FakeAuth(backend, type)..biometricEnrolled = biometric)],
  );
  addTearDown(container.dispose);
  final router = container.read(appRouterProvider);
  // The destination screens make network calls of their own; they're not
  // what's under test — only where the router lands.
  await tester.pumpWidget(UncontrolledProviderScope(container: container, child: MaterialApp.router(routerConfig: router)));
  await tester.pump(const Duration(seconds: 3)); // past the splash
  return (router, backend);
}

/// Unmounts the destination (stopping its polling) and lets one-shot
/// timers — toasts, the code-resend countdown — run out.
Future<void> _finish(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(minutes: 2));
}

String _at(GoRouter router) => router.routerDelegate.currentConfiguration.uri.path;

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

Future<void> _typeOnPad(WidgetTester tester, String digits) async {
  for (final d in digits.split('')) {
    await tester.tap(find.text(d).last);
    await tester.pump(const Duration(milliseconds: 60));
  }
  await tester.pump(const Duration(milliseconds: 400));
}

/// The four ways in, each ending wherever the router settles.
final _paths = <String, Future<void> Function(WidgetTester, GoRouter, AccountType)>{
  'emailed code': (tester, router, type) async {
    router.go(AppRoutes.otp, extra: SignupArgs(name: 'Test', contact: 'test@runit.dev', accountType: type));
    await _settle(tester);
    await tester.enterText(find.byType(TextField).first, '123456');
    await _settle(tester);
    await _typeOnPad(tester, '111111'); // create passcode
    await _typeOnPad(tester, '111111'); // confirm
    await _settle(tester);
  },
  'passcode': (tester, router, type) async {
    router.go(AppRoutes.login);
    await _settle(tester);
    await _typeOnPad(tester, '111111');
    await _settle(tester);
  },
  'biometric': (tester, router, type) async {
    router.go(AppRoutes.login);
    await _settle(tester);
    await tester.tap(find.bySemanticsLabel(RegExp('fingerprint|Fingerprint|biometric|Biometric')).first);
    await _settle(tester);
  },
  'forgot passcode': (tester, router, type) async {
    router.go(AppRoutes.login);
    await _settle(tester);
    await tester.tap(find.text('Forgot passcode?'));
    await _settle(tester);
    await tester.enterText(find.byType(TextField).first, '123456');
    await _settle(tester);
    await _typeOnPad(tester, '222222');
    await _typeOnPad(tester, '222222');
    await _settle(tester);
  },
};

void main() {
  group('destinationFor — where an account belongs given its real status', () {
    UserProfile user(AccountType type, {KycStatus kyc = KycStatus.none, VendorReviewStatus vendor = VendorReviewStatus.none}) =>
        UserProfile(id: 'u', name: 'n', contact: 'c', accountType: type, kycStatus: kyc, vendorStatus: vendor);

    test('runners', () {
      expect(destinationFor(user(AccountType.runner, kyc: KycStatus.verified)), AppRoutes.runnerHome);
      expect(destinationFor(user(AccountType.runner, kyc: KycStatus.pending)), AppRoutes.kycStatus);
      expect(destinationFor(user(AccountType.runner, kyc: KycStatus.rejected)), AppRoutes.kycStatus);
      expect(destinationFor(user(AccountType.runner)), AppRoutes.runnerType);
    });

    test('restaurants', () {
      expect(destinationFor(user(AccountType.restaurant, vendor: VendorReviewStatus.approved)), AppRoutes.restaurantOrders);
      expect(destinationFor(user(AccountType.restaurant, vendor: VendorReviewStatus.inactive)), AppRoutes.restaurantOrders);
      expect(
        destinationFor(user(AccountType.restaurant, vendor: VendorReviewStatus.pending)),
        AppRoutes.restaurantApplicationStatus,
      );
      expect(
        destinationFor(user(AccountType.restaurant, vendor: VendorReviewStatus.rejected)),
        AppRoutes.restaurantApplicationStatus,
      );
      expect(destinationFor(user(AccountType.restaurant)), AppRoutes.vendorApplication);
    });

    test('students', () {
      expect(destinationFor(user(AccountType.student)), AppRoutes.home);
    });
  });

  const runnerCases = {
    'approved': (KycStatus.verified, AppRoutes.runnerHome),
    'pending': (KycStatus.pending, AppRoutes.kycStatus),
    'unverified': (KycStatus.none, AppRoutes.runnerType),
  };
  const restaurantCases = {
    'approved': (VendorReviewStatus.approved, AppRoutes.restaurantOrders),
    'pending': (VendorReviewStatus.pending, AppRoutes.restaurantApplicationStatus),
    'rejected': (VendorReviewStatus.rejected, AppRoutes.restaurantApplicationStatus),
    'new': (VendorReviewStatus.none, AppRoutes.vendorApplication),
  };

  for (final MapEntry(key: path, value: signIn) in _paths.entries) {
    group('Signing in by $path', () {
      for (final MapEntry(key: label, value: (status, expected)) in runnerCases.entries) {
        testWidgets('an $label runner lands on $expected', (tester) async {
          final (router, backend) = await _start(tester, AccountType.runner, _Backend(kyc: status), biometric: path == 'biometric');
          await signIn(tester, router, AccountType.runner);
          expect(backend.meCalls, greaterThan(0), reason: 'routed on the real status, not the device copy');
          expect(_at(router), expected);
          await _finish(tester);
        });
      }
      for (final MapEntry(key: label, value: (status, expected)) in restaurantCases.entries) {
        testWidgets('a $label restaurant lands on $expected', (tester) async {
          final (router, _) = await _start(tester, AccountType.restaurant, _Backend(vendor: status), biometric: path == 'biometric');
          await signIn(tester, router, AccountType.restaurant);
          expect(_at(router), expected);
          await _finish(tester);
        });
      }
    });
  }

  testWidgets("when the status can't be fetched, nobody is guessed into verification", (tester) async {
    final backend = _Backend(kyc: KycStatus.verified)..reachable = false;
    final (router, _) = await _start(tester, AccountType.runner, backend);
    await _paths['passcode']!(tester, router, AccountType.runner);

    expect(_at(router), AppRoutes.signInGate);
    expect(find.text("Couldn't check your account"), findsOneWidget);

    backend.reachable = true;
    await tester.tap(find.text('Try again'));
    await _settle(tester);
    expect(_at(router), AppRoutes.runnerHome);
    await _finish(tester);
  });
}
