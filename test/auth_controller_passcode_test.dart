import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:run_it/core/network/api_client.dart';
import 'package:run_it/core/widgets/app_notification.dart';
import 'package:run_it/features/auth/application/auth_controller.dart';
import 'package:run_it/features/auth/data/auth_repository.dart';
import 'package:run_it/features/auth/domain/auth_models.dart';

/// Stubs only the network boundary (`POST /auth/otp/*`) with a canned
/// success response — everything above it (passcode hashing, secure-storage
/// reads/writes) is the real [AuthController] logic under test.
class _FakeAuthController extends AuthController {
  _FakeAuthController(this._session);
  final AuthSession _session;
  @override
  AuthSession? build() {
    repository = AuthRepository(
      client: ApiClient(
        httpClient: MockClient(
          (request) async => http.Response(
            jsonEncode({'accessToken': 'mock-dev-token'}),
            200,
          ),
        ),
      ),
    );
    return _session;
  }
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

AuthSession _sessionFor(AccountType accountType) => AuthSession(
  accessToken: 'test-access',
  refreshToken: 'test-refresh',
  expiresAt: DateTime.now().add(const Duration(minutes: 5)),
  user: UserProfile(
    id: '${accountType.name}-1',
    name: 'Test ${accountType.name}',
    contact: '${accountType.name}@campus.edu',
    accountType: accountType,
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

    // A later app launch starts logged out (session lost, not an explicit
    // sign-out) even though the passcode remains stored on-device —
    // mirrors how the login screen is reached after the demo-short access
    // token expires.
    await controller.logout(expired: true);
    expect(container.read(authControllerProvider), isNull);

    expect(await controller.loginWithPasscode('000000'), isFalse);
    expect(container.read(authControllerProvider), isNull);

    expect(await controller.loginWithPasscode('482913'), isTrue);
    expect(container.read(authControllerProvider)!.user.id, 'student-1');
  });

  test('an explicit logout (not an expiry) clears the stored passcode + biometric credential, for every account type', () async {
    for (final accountType in AccountType.values) {
      store.clear();
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith(
            () => _FakeAuthController(_sessionFor(accountType)),
          ),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(authControllerProvider.notifier);

      await controller.setPasscode('135790');
      // enableBiometric() itself can't succeed in this harness (no
      // local_auth platform implementation — see the "naturally reports
      // unavailable" test below), but the storage-clearing behavior
      // under test doesn't depend on how the credential got there, so
      // seed it directly under the same key the real code writes to.
      store['runit_biometric_user_v1'] = 'stub-biometric-snapshot';

      expect(store, isNotEmpty, reason: 'setup sanity check for $accountType');

      await controller.logout();

      expect(
        container.read(authControllerProvider),
        isNull,
        reason: '$accountType session should be cleared',
      );
      expect(
        await controller.hasStoredPasscode(),
        isFalse,
        reason: '$accountType passcode should be cleared',
      );
      expect(
        await controller.hasBiometricCredential(),
        isFalse,
        reason: '$accountType biometric credential should be cleared',
      );
      expect(
        store,
        isEmpty,
        reason: '$accountType should leave nothing behind in secure storage',
      );
    }
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

  group('handleUnauthorized (Task 17)', () {
    test('is a no-op when already logged out', () async {
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith(() => _FakeAuthController(_studentSession())),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(authControllerProvider.notifier);
      await controller.logout();
      expect(container.read(authControllerProvider), isNull);

      await controller.handleUnauthorized();

      expect(container.read(appNotificationProvider), isEmpty);
    });

    test(
      'clears the live session, shows a clear message, and — unlike a plain expired '
      'logout — clears the persisted session too, so a later passcode unlock cannot '
      'silently resume the same rejected token',
      () async {
        final container = ProviderContainer(
          overrides: [
            authControllerProvider.overrideWith(() => _FakeAuthController(_studentSession())),
          ],
        );
        addTearDown(container.dispose);
        final controller = container.read(authControllerProvider.notifier);
        await controller.setPasscode('482913');

        await controller.handleUnauthorized();

        expect(container.read(authControllerProvider), isNull);
        expect(
          container.read(appNotificationProvider).map((n) => n.message),
          contains('Your session has ended. Please sign in again.'),
        );

        // The passcode credential itself survives (matches a plain expired
        // logout) — but resuming via it now finds no valid persisted
        // session left to resume, unlike the ordinary expired-logout case
        // covered by the test above.
        expect(await controller.hasStoredPasscode(), isTrue);
        await expectLater(
          controller.loginWithPasscode('482913'),
          throwsA(isA<SessionRecoveryRequiredException>()),
        );
      },
    );
  });
}
