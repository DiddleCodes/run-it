import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/application/auth_controller.dart';
import '../../features/auth/domain/auth_models.dart';
import '../../features/ordering/application/order_tracking_controller.dart';
import '../network/api_client.dart';
import '../routing/app_router.dart';
import '../widgets/app_notification.dart';

/// A push as the app needs it — title/body for the in-app banner, and the
/// backend's string `data` (`type`, `orderId`, ...) for routing a tap.
@immutable
class PushMessage {
  const PushMessage({this.title, this.body, this.data = const {}});

  final String? title;
  final String? body;
  final Map<String, String> data;

  String? get type => data['type'];
  String? get orderId => data['orderId'];
}

/// The slice of firebase_messaging this app uses, behind an interface so
/// the registration/routing logic is testable without a Firebase app.
abstract class PushMessagingClient {
  /// Asks for permission to show notifications (the Android 13+ / iOS
  /// prompt). Returns whether they're allowed.
  Future<bool> requestPermission();
  Future<String?> getToken();
  Future<void> deleteToken();
  Stream<String> get onTokenRefresh;

  /// Pushes that arrive while the app is open — the OS shows nothing for
  /// these, so the app does.
  Stream<PushMessage> get onForegroundMessage;

  /// A notification tapped while the app was in the background.
  Stream<PushMessage> get onOpenedFromNotification;

  /// The notification tapped to launch the app from terminated, if any.
  Future<PushMessage?> getInitialMessage();
}

class FirebasePushMessagingClient implements PushMessagingClient {
  FirebasePushMessagingClient() : _messaging = FirebaseMessaging.instance;

  final FirebaseMessaging _messaging;

  static PushMessage _from(RemoteMessage m) => PushMessage(
    title: m.notification?.title,
    body: m.notification?.body,
    data: {for (final e in m.data.entries) e.key: '${e.value}'},
  );

  @override
  Future<bool> requestPermission() async {
    final settings = await _messaging.requestPermission();
    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  @override
  Future<String?> getToken() => _messaging.getToken();

  @override
  Future<void> deleteToken() => _messaging.deleteToken();

  @override
  Stream<String> get onTokenRefresh => _messaging.onTokenRefresh;

  @override
  Stream<PushMessage> get onForegroundMessage => FirebaseMessaging.onMessage.map(_from);

  @override
  Stream<PushMessage> get onOpenedFromNotification => FirebaseMessaging.onMessageOpenedApp.map(_from);

  @override
  Future<PushMessage?> getInitialMessage() async {
    final m = await _messaging.getInitialMessage();
    return m == null ? null : _from(m);
  }
}

/// `null` where Firebase isn't running (web/desktop, a failed init, tests)
/// — push is then simply off; nothing else in the app depends on it.
final pushMessagingClientProvider = Provider<PushMessagingClient?>(
  (ref) => Firebase.apps.isEmpty ? null : FirebasePushMessagingClient(),
);

/// The backend's device-token endpoints (NotificationsController).
class DeviceTokenRepository {
  const DeviceTokenRepository({this.client = const ApiClient()});

  final ApiClient client;

  Future<void> register({required String token, required String platform, required String accessToken}) =>
      client.post('/notifications/device-tokens', body: {'token': token, 'platform': platform}, token: accessToken);

  Future<void> remove({required String token, required String accessToken}) =>
      client.delete('/notifications/device-tokens/${Uri.encodeComponent(token)}', token: accessToken);
}

final deviceTokenRepositoryProvider = Provider<DeviceTokenRepository>((ref) => const DeviceTokenRepository());

/// Where a tapped notification should take the user, or null to just open
/// the app. A restaurant's new order goes to its orders list; a student's
/// order update goes to live tracking when it's the order being tracked on
/// this device, otherwise to that order's detail.
String? pushDestination(PushMessage message, {required String? trackedOrderId}) {
  final orderId = message.orderId;
  if (message.type == 'order_placed') return AppRoutes.restaurantOrders;
  if (orderId == null) return null;
  return orderId == trackedOrderId ? AppRoutes.orderTracking : AppRoutes.orderDetail;
}

/// Push notifications, end to end on the device:
///
/// - registers this device's FCM token with the backend whenever someone
///   signs in (and again whenever Firebase rotates it), so the backend's
///   NotificationsService can reach them;
/// - on an explicit sign-out, removes the token and deletes it at Firebase,
///   so the next person to use this phone never gets the last one's pushes
///   (a session that merely expired keeps it — same person, same phone);
/// - shows a push that arrives while the app is open as an in-app banner
///   (the OS doesn't), and refreshes live tracking straight away when it's
///   about the tracked order;
/// - opens the relevant screen when a notification is tapped — once the
///   user is past the sign-in screens, if it launched the app.
///
/// Watched once from the app root; does nothing when push is unavailable.
class PushNotificationsController {
  PushNotificationsController(this.ref, this.client) {
    _subscriptions
      ..add(client.onTokenRefresh.listen(_onTokenRefresh))
      ..add(client.onForegroundMessage.listen(_onForegroundMessage))
      ..add(client.onOpenedFromNotification.listen(_onOpened));
    ref.listen<AuthSession?>(authControllerProvider, _onAuthChanged, fireImmediately: true);
    unawaited(client.getInitialMessage().then((m) => m == null ? null : _onOpened(m)));
  }

  final Ref ref;
  final PushMessagingClient client;
  final _subscriptions = <StreamSubscription<Object?>>[];
  PushMessage? _pendingOpen;
  VoidCallback? _routerListener;

  String get _platform => defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';

  void dispose() {
    for (final s in _subscriptions) {
      unawaited(s.cancel());
    }
    _detachRouterListener();
  }

  void _onAuthChanged(AuthSession? previous, AuthSession? next) {
    if (next != null && previous?.user.id != next.user.id) {
      unawaited(_register(next));
    } else if (previous != null && next == null && !ref.read(authControllerProvider.notifier).expired) {
      unawaited(_unregister(previous));
    }
  }

  Future<void> _register(AuthSession session) async {
    try {
      await client.requestPermission();
      final token = await client.getToken();
      if (token == null) return;
      await _send(token, session);
    } catch (error) {
      // Best-effort: no push is never worth blocking or failing sign-in.
      // The next sign-in or token rotation tries again.
      debugPrint('Push: device registration failed — $error');
    }
  }

  Future<void> _onTokenRefresh(String token) async {
    final session = ref.read(authControllerProvider);
    if (session == null) return;
    try {
      await _send(token, session);
    } catch (error) {
      debugPrint('Push: re-registering a rotated token failed — $error');
    }
  }

  Future<void> _send(String token, AuthSession session) async {
    await ref
        .read(deviceTokenRepositoryProvider)
        .register(token: token, platform: _platform, accessToken: session.accessToken);
    debugPrint('Push: registered this device for ${session.user.id}.');
  }

  Future<void> _unregister(AuthSession previous) async {
    try {
      final token = await client.getToken();
      if (token != null) {
        await ref.read(deviceTokenRepositoryProvider).remove(token: token, accessToken: previous.accessToken);
      }
    } catch (error) {
      debugPrint('Push: removing this device from the backend failed — $error');
    }
    // Even if the backend call failed, a deleted token can't be delivered to
    // — the backend prunes it on its next send.
    try {
      await client.deleteToken();
    } catch (error) {
      debugPrint('Push: deleting the Firebase token failed — $error');
    }
  }

  void _onForegroundMessage(PushMessage message) {
    final text = [message.title, message.body].whereType<String>().join(' — ');
    if (text.isNotEmpty) ref.read(appNotificationProvider.notifier).info(text);

    final tracking = ref.read(orderTrackingProvider);
    if (message.orderId != null && message.orderId == tracking.orderId) {
      unawaited(ref.read(orderTrackingProvider.notifier).refreshFromServer());
    }
  }

  void _onOpened(PushMessage message) {
    _pendingOpen = message;
    _tryOpenPending();
    if (_pendingOpen != null) _attachRouterListener();
  }

  /// Splash, onboarding and the sign-in/passcode screens navigate on their
  /// own once they're done; jumping away from under them would be undone
  /// (or strand the user), so a tap that launched the app waits for them.
  static bool _isPreAuthLocation(String path) =>
      path == AppRoutes.splash || path == AppRoutes.onboarding || path.startsWith('/auth') || path.startsWith('/kyc');

  void _tryOpenPending() {
    final message = _pendingOpen;
    if (message == null || ref.read(authControllerProvider) == null) return;
    final router = ref.read(appRouterProvider);
    if (_isPreAuthLocation(router.routerDelegate.currentConfiguration.uri.path)) return;

    _pendingOpen = null;
    _detachRouterListener();
    final trackedOrderId = ref.read(orderTrackingProvider).orderId;
    final destination = pushDestination(message, trackedOrderId: trackedOrderId);
    if (destination == null) return;
    if (destination == AppRoutes.orderDetail) {
      unawaited(router.push(destination, extra: message.orderId));
    } else {
      router.go(destination);
    }
  }

  void _attachRouterListener() {
    if (_routerListener != null) return;
    final delegate = ref.read(appRouterProvider).routerDelegate;
    // Post-frame: the location only settles after the navigation that
    // notified us has been built.
    void listener() => WidgetsBinding.instance.addPostFrameCallback((_) => _tryOpenPending());
    delegate.addListener(listener);
    _routerListener = () => delegate.removeListener(listener);
  }

  void _detachRouterListener() {
    _routerListener?.call();
    _routerListener = null;
  }
}

final pushNotificationsProvider = Provider<PushNotificationsController?>((ref) {
  final client = ref.watch(pushMessagingClientProvider);
  if (client == null) return null;
  final controller = PushNotificationsController(ref, client);
  ref.onDispose(controller.dispose);
  return controller;
});
