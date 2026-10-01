import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:run_it/core/notifications/push_notifications.dart';
import 'package:run_it/core/routing/app_router.dart';
import 'package:run_it/core/widgets/app_notification.dart';
import 'package:run_it/features/auth/application/auth_controller.dart';
import 'package:run_it/features/auth/domain/auth_models.dart';

class _FakeAuthController extends AuthController {
  @override
  AuthSession? build() => null;

  void signIn(AuthSession session) => state = session;

  @override
  Future<void> logout({bool expired = false}) async {
    this.expired = expired;
    state = null;
  }
}

class _FakeClient implements PushMessagingClient {
  String? token = 'fcm-token-1';
  var permissionRequests = 0;
  var deletedTokens = 0;
  final refresh = StreamController<String>.broadcast();
  final foreground = StreamController<PushMessage>.broadcast();
  final opened = StreamController<PushMessage>.broadcast();

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return true;
  }

  @override
  Future<String?> getToken() async => token;

  @override
  Future<void> deleteToken() async {
    deletedTokens++;
    token = null;
  }

  @override
  Stream<String> get onTokenRefresh => refresh.stream;
  @override
  Stream<PushMessage> get onForegroundMessage => foreground.stream;
  @override
  Stream<PushMessage> get onOpenedFromNotification => opened.stream;
  @override
  Future<PushMessage?> getInitialMessage() async => null;
}

class _FakeDeviceTokens extends DeviceTokenRepository {
  final registered = <(String token, String platform, String accessToken)>[];
  final removed = <(String token, String accessToken)>[];

  @override
  Future<void> register({required String token, required String platform, required String accessToken}) async =>
      registered.add((token, platform, accessToken));

  @override
  Future<void> remove({required String token, required String accessToken}) async => removed.add((token, accessToken));
}

AuthSession _session(String userId, {String accessToken = 'access-1'}) => AuthSession(
  accessToken: accessToken,
  refreshToken: 'refresh',
  expiresAt: DateTime.now().add(const Duration(minutes: 5)),
  user: UserProfile(id: userId, name: 'Ayanfe O.', contact: 'a@ui.edu.ng', accountType: AccountType.student),
);

void main() {
  late _FakeClient client;
  late _FakeDeviceTokens deviceTokens;
  late ProviderContainer container;
  late _FakeAuthController auth;

  setUp(() {
    client = _FakeClient();
    deviceTokens = _FakeDeviceTokens();
    container = ProviderContainer(
      overrides: [
        pushMessagingClientProvider.overrideWithValue(client),
        deviceTokenRepositoryProvider.overrideWithValue(deviceTokens),
        authControllerProvider.overrideWith(_FakeAuthController.new),
      ],
    );
    addTearDown(container.dispose);
    container.read(pushNotificationsProvider);
    auth = container.read(authControllerProvider.notifier) as _FakeAuthController;
  });

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('nothing is registered while signed out', () async {
    await settle();
    expect(deviceTokens.registered, isEmpty);
    expect(client.permissionRequests, 0);
  });

  test('signing in asks for permission and registers this device with the backend', () async {
    auth.signIn(_session('student-1'));
    await settle();

    expect(client.permissionRequests, 1);
    expect(deviceTokens.registered, [('fcm-token-1', 'android', 'access-1')]);
  });

  test('a refreshed access token for the same user does not re-register', () async {
    auth.signIn(_session('student-1'));
    await settle();
    auth.signIn(_session('student-1', accessToken: 'access-2'));
    await settle();

    expect(deviceTokens.registered, hasLength(1));
  });

  test('a rotated FCM token is re-registered for the signed-in user', () async {
    auth.signIn(_session('student-1'));
    await settle();
    client.refresh.add('fcm-token-2');
    await settle();

    expect(deviceTokens.registered.last, ('fcm-token-2', 'android', 'access-1'));
  });

  test('explicit sign-out removes the token from the backend and deletes it at Firebase', () async {
    auth.signIn(_session('student-1'));
    await settle();
    await auth.logout();
    await settle();

    expect(deviceTokens.removed, [('fcm-token-1', 'access-1')]);
    expect(client.deletedTokens, 1);
  });

  test('a session that merely expired keeps the device registered', () async {
    auth.signIn(_session('student-1'));
    await settle();
    await auth.logout(expired: true);
    await settle();

    expect(deviceTokens.removed, isEmpty);
    expect(client.deletedTokens, 0);
  });

  test('a push that arrives while the app is open shows as an in-app banner', () async {
    client.foreground.add(
      const PushMessage(title: 'Order accepted', body: 'Tantalizers has accepted your order.', data: {'orderId': 'o1'}),
    );
    await settle();

    final banners = container.read(appNotificationProvider);
    expect(banners.single.message, 'Order accepted — Tantalizers has accepted your order.');
  });

  group('where a tapped notification goes', () {
    test("a restaurant's new order opens its orders list", () {
      expect(
        pushDestination(const PushMessage(data: {'type': 'order_placed', 'orderId': 'o1'}), trackedOrderId: null),
        AppRoutes.restaurantOrders,
      );
    });

    test('an update to the order being tracked opens live tracking', () {
      expect(
        pushDestination(const PushMessage(data: {'type': 'order_picked_up', 'orderId': 'o1'}), trackedOrderId: 'o1'),
        AppRoutes.orderTracking,
      );
    });

    test("any other order's update opens that order's detail", () {
      expect(
        pushDestination(const PushMessage(data: {'type': 'order_declined', 'orderId': 'o2'}), trackedOrderId: 'o1'),
        AppRoutes.orderDetail,
      );
    });

    test('an account notice just opens the app', () {
      expect(pushDestination(const PushMessage(data: {'type': 'account_suspended'}), trackedOrderId: null), isNull);
    });

    test("a runner's claim confirmation opens the delivery screen for the job in progress", () {
      expect(
        pushDestination(
          const PushMessage(data: {'type': 'runner_claim_confirmed', 'orderId': 'o1'}),
          trackedOrderId: null,
          activeDeliveryOrderId: 'o1',
        ),
        AppRoutes.runnerDelivery,
      );
    });

    test('a claim confirmation for a job not in progress here (e.g. after a restart) opens the jobs list', () {
      expect(
        pushDestination(
          const PushMessage(data: {'type': 'runner_claim_confirmed', 'orderId': 'o1'}),
          trackedOrderId: null,
          activeDeliveryOrderId: null,
        ),
        AppRoutes.runnerJobs,
      );
    });

    test("the student's 'runner assigned' opens live tracking for the tracked order, else its detail", () {
      const assigned = PushMessage(data: {'type': 'runner_assigned', 'orderId': 'o1'});
      expect(pushDestination(assigned, trackedOrderId: 'o1'), AppRoutes.orderTracking);
      expect(pushDestination(assigned, trackedOrderId: null), AppRoutes.orderDetail);
    });
  });

  test("'Runner assigned' arriving while the app is open shows as a banner", () async {
    client.foreground.add(
      const PushMessage(
        title: 'Runner assigned',
        body: 'Test R. is picking up your order from Golden Crust Bakery.',
        data: {'type': 'runner_assigned', 'orderId': 'o1'},
      ),
    );
    await settle();

    expect(
      container.read(appNotificationProvider).single.message,
      'Runner assigned — Test R. is picking up your order from Golden Crust Bakery.',
    );
  });
}
