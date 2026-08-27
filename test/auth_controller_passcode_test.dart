import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:run_it/features/auth/application/auth_controller.dart';
import 'package:run_it/features/auth/domain/auth_models.dart';

class _FakeAuthController extends AuthController {
  _FakeAuthController(this._session);
  final AuthSession _session;
  @override
  AuthSession? build() => _session;
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // flutter_secure_storage talks to native code over this channel; nothing
  // implements it in the plain flutter_test harness, so stand in with a
  // tiny in-memory map behind the same method names/arguments the plugin's
  // MethodChannelFlutterSecureStorage actually sends.
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final store = <String, String>{};

  setUp(() {
    store.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          final args = call.arguments as Map;
          switch (call.method) {
            case 'write':
              store[args['key'] as String] = args['value'] as String;
              return null;
            case 'read':
              return store[args['key'] as String];
            case 'delete':
              store.remove(args['key'] as String);
              return null;
            case 'deleteAll':
              store.clear();
              return null;
            case 'containsKey':
              return store.containsKey(args['key'] as String);
            default:
              return null;
          }
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'setPasscode hashes and stores the code, and flips passcodeSet',
    () async {
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith(
            () => _FakeAuthController(_studentSession()),
          ),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(authControllerProvider.notifier);

      expect(container.read(authControllerProvider)!.user.passcodeSet, isFalse);
      await controller.setPasscode('123456');

      expect(container.read(authControllerProvider)!.user.passcodeSet, isTrue);
      expect(await controller.hasStoredPasscode(), isTrue);
      // Never stored as plaintext — only a hash.
      expect(store.values.any((v) => v == '123456'), isFalse);
    },
  );

  test('loginWithPasscode: matching code signs back in, mismatched code fails safely', () async {
    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(
          () => _FakeAuthController(_studentSession()),
        ),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(authControllerProvider.notifier);
    await controller.setPasscode('482913');

    // A later app launch starts logged out even though the passcode
    // remains stored on-device — mirrors how the login screen is reached.
    controller.logout();
    expect(container.read(authControllerProvider), isNull);

    expect(await controller.loginWithPasscode('000000'), isFalse);
    expect(container.read(authControllerProvider), isNull);

    expect(await controller.loginWithPasscode('482913'), isTrue);
    expect(container.read(authControllerProvider)!.user.id, 'student-1');
  });

  test(
    'loginWithPasscode fails when no passcode was ever set on this device',
    () async {
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith(
            () => _FakeAuthController(_studentSession()),
          ),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(authControllerProvider.notifier);

      expect(await controller.loginWithPasscode('123456'), isFalse);
    },
  );

  test('biometric setup naturally reports unavailable with no platform channel registered', () async {
    // No local_auth platform implementation exists in this harness, so
    // isBiometricAvailable()'s catch-and-return-false path fires — the
    // exact condition SetPasscodeScreen uses to skip straight to Home
    // instead of routing to the optional biometric-setup screen.
    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(
          () => _FakeAuthController(_studentSession()),
        ),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(authControllerProvider.notifier);

    expect(await controller.isBiometricAvailable(), isFalse);
  });
}
