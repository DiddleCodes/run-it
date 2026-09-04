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

// Mirrors AuthController's own private storage keys — there's no public
// accessor, so a test that needs to directly manipulate what's persisted
// (e.g. to simulate real elapsed time past a token's expiry) has to use
// the same literal key names the real code writes to.
const _refreshTokenStorageKey = 'runit_session_refresh_token_v1';
const _expiryStorageKey = 'runit_session_expiry_v1';

/// Stubs only the network boundary — everything above it (passcode
/// hashing, secure-storage reads/writes, refresh-vs-logout routing) is the
/// real [AuthController] logic under test. `/auth/refresh` and
/// `/auth/logout` default to a canned success (Task 34); pass
/// [refreshResponder]/[logoutResponder] to override per test (e.g. to
/// simulate a rejected/revoked refresh token). [requestLog], if given,
/// records every request made so a test can assert on what was actually
/// sent (path, body).
class _FakeAuthController extends AuthController {
  _FakeAuthController(
    this._session, {
    this.refreshResponder,
    this.logoutResponder,
    this.requestLog,
  });
  final AuthSession _session;
  final Future<http.Response> Function(http.Request)? refreshResponder;
  final Future<http.Response> Function(http.Request)? logoutResponder;
  final List<http.Request>? requestLog;

  @override
  AuthSession? build() {
    repository = AuthRepository(
      client: ApiClient(
        httpClient: MockClient((request) async {
          requestLog?.add(request);
          if (request.url.path == '/auth/refresh') {
            return refreshResponder != null
                ? await refreshResponder!(request)
                : http.Response(
                    jsonEncode({
                      'accessToken': 'refreshed-access-token',
                      'refreshToken': 'refreshed-refresh-token',
                    }),
                    200,
                  );
          }
          if (request.url.path == '/auth/logout') {
            return logoutResponder != null
                ? await logoutResponder!(request)
                : http.Response(jsonEncode({'message': 'Logged out.'}), 200);
          }
          return http.Response(jsonEncode({'accessToken': 'mock-dev-token'}), 200);
        }),
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

  group('handleUnauthorized (Task 17 + Task 34 silent refresh)', () {
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
      'Task 34: a successful silent refresh preserves the session — no logout, no notification, '
      'and the new tokens are what get persisted',
      () async {
        final requestLog = <http.Request>[];
        final container = ProviderContainer(
          overrides: [
            authControllerProvider.overrideWith(
              () => _FakeAuthController(_studentSession(), requestLog: requestLog),
            ),
          ],
        );
        addTearDown(container.dispose);
        final controller = container.read(authControllerProvider.notifier);

        await controller.handleUnauthorized();

        // Session survives, silently — with the rotated tokens, not the
        // original ones.
        final session = container.read(authControllerProvider);
        expect(session, isNotNull);
        expect(session!.accessToken, 'refreshed-access-token');
        expect(session.refreshToken, 'refreshed-refresh-token');
        expect(container.read(appNotificationProvider), isEmpty);
        expect(store[_refreshTokenStorageKey], 'refreshed-refresh-token');

        // Really called the real refresh endpoint with the original
        // refresh token — not a re-derived or dev-only shortcut.
        final refreshCall = requestLog.singleWhere((r) => r.url.path == '/auth/refresh');
        expect(jsonDecode(refreshCall.body)['refreshToken'], 'test-refresh');
      },
    );

    test(
      'a rejected refresh (expired/revoked/suspended) falls through to the old hard-logout '
      'behavior: clears the live session, shows a clear message, and — unlike a plain expired '
      'logout — clears the persisted session too, so a later passcode unlock cannot '
      'silently resume the same rejected token',
      () async {
        final container = ProviderContainer(
          overrides: [
            authControllerProvider.overrideWith(
              () => _FakeAuthController(
                _studentSession(),
                refreshResponder: (_) async =>
                    http.Response(jsonEncode({'message': 'Your session has expired. Please sign in again.'}), 401),
              ),
            ),
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

    test(
      'two concurrent 401s share a single real refresh call, not two independent ones racing '
      'against the same not-yet-rotated token',
      () async {
        final requestLog = <http.Request>[];
        final container = ProviderContainer(
          overrides: [
            authControllerProvider.overrideWith(
              () => _FakeAuthController(_studentSession(), requestLog: requestLog),
            ),
          ],
        );
        addTearDown(container.dispose);
        final controller = container.read(authControllerProvider.notifier);

        await Future.wait([
          controller.handleUnauthorized(),
          controller.handleUnauthorized(),
        ]);

        expect(container.read(authControllerProvider), isNotNull);
        expect(requestLog.where((r) => r.url.path == '/auth/refresh'), hasLength(1));
      },
    );
  });

  group('logout (Task 34: server-side revocation)', () {
    test('an explicit logout revokes the refresh token server-side, not just locally', () async {
      final requestLog = <http.Request>[];
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith(
            () => _FakeAuthController(_studentSession(), requestLog: requestLog),
          ),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(authControllerProvider.notifier);

      await controller.logout();

      final logoutCall = requestLog.singleWhere((r) => r.url.path == '/auth/logout');
      expect(jsonDecode(logoutCall.body)['refreshToken'], 'test-refresh');
      expect(container.read(authControllerProvider), isNull);
    });

    test('a network failure during the revoke call never blocks signing out of this device', () async {
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith(
            () => _FakeAuthController(
              _studentSession(),
              logoutResponder: (_) async => throw Exception('offline'),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(authControllerProvider.notifier);

      await controller.logout();

      expect(container.read(authControllerProvider), isNull);
      expect(await controller.hasStoredPasscode(), isFalse);
    });

    test('an expired (not explicit) logout never calls the revoke endpoint', () async {
      final requestLog = <http.Request>[];
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith(
            () => _FakeAuthController(_studentSession(), requestLog: requestLog),
          ),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(authControllerProvider.notifier);

      await controller.logout(expired: true);

      expect(requestLog.where((r) => r.url.path == '/auth/logout'), isEmpty);
    });
  });

  group('_loadPersistedSession silent refresh (Task 34)', () {
    test(
      'loginWithPasscode resumes via a real refresh call when the persisted access token has '
      'time-expired but the stored refresh token is still accepted',
      () async {
        final requestLog = <http.Request>[];
        final container = ProviderContainer(
          overrides: [
            authControllerProvider.overrideWith(
              () => _FakeAuthController(_studentSession(), requestLog: requestLog),
            ),
          ],
        );
        addTearDown(container.dispose);
        final controller = container.read(authControllerProvider.notifier);
        await controller.setPasscode('482913');
        // Simulate real elapsed time: the persisted access token is now
        // past its (short-lived, 1h in production) expiry.
        store[_expiryStorageKey] = DateTime.now().subtract(const Duration(hours: 2)).toIso8601String();
        await controller.logout(expired: true);

        expect(await controller.loginWithPasscode('482913'), isTrue);

        final session = container.read(authControllerProvider);
        expect(session!.accessToken, 'refreshed-access-token');
        expect(requestLog.where((r) => r.url.path == '/auth/refresh'), hasLength(1));
      },
    );

    test(
      'loginWithPasscode requires a real re-authentication when the persisted refresh token '
      'itself is rejected (expired/revoked/suspended)',
      () async {
        final container = ProviderContainer(
          overrides: [
            authControllerProvider.overrideWith(
              () => _FakeAuthController(
                _studentSession(),
                refreshResponder: (_) async =>
                    http.Response(jsonEncode({'message': 'Your session has expired. Please sign in again.'}), 401),
              ),
            ),
          ],
        );
        addTearDown(container.dispose);
        final controller = container.read(authControllerProvider.notifier);
        await controller.setPasscode('482913');
        store[_expiryStorageKey] = DateTime.now().subtract(const Duration(hours: 2)).toIso8601String();
        await controller.logout(expired: true);

        await expectLater(
          controller.loginWithPasscode('482913'),
          throwsA(isA<SessionRecoveryRequiredException>()),
        );
      },
    );
  });
}
