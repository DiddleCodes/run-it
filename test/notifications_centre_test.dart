import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:run_it/core/cache/local_cache.dart';
import 'package:run_it/core/routing/app_router.dart';
import 'package:run_it/features/auth/application/auth_controller.dart';
import 'package:run_it/features/auth/domain/auth_models.dart';
import 'package:run_it/features/notifications/application/notifications_controller.dart';
import 'package:run_it/features/notifications/data/notifications_repository.dart';
import 'package:run_it/features/notifications/domain/app_notification.dart';
import 'package:run_it/features/notifications/presentation/notifications_screen.dart';

class _FakeAuthController extends AuthController {
  @override
  AuthSession? build() => AuthSession(
    accessToken: 'a',
    refreshToken: 'r',
    expiresAt: DateTime.now().add(const Duration(minutes: 5)),
    user: const UserProfile(
      id: 'student-1',
      name: 'Ayanfe O.',
      contact: 'a@student.ui.edu.ng',
      accountType: AccountType.student,
      campusId: 'ui',
    ),
  );
}

Map<String, dynamic> _row(String id, String title, String body, {String? orderId, bool read = false, int minutesAgo = 0}) => {
  'id': id,
  'type': 'order_accepted',
  'title': title,
  'body': body,
  'data': {'orderId': ?orderId},
  'createdAt': DateTime.now().toUtc().subtract(Duration(minutes: minutesAgo)).toIso8601String(),
  'readAt': read ? DateTime.now().toUtc().toIso8601String() : null,
};

/// The backend's feed, in memory: newest first, and it really records reads.
class _FakeRepository extends NotificationsRepository {
  _FakeRepository(this.rows);

  final List<Map<String, dynamic>> rows;
  bool online = true;
  final markedRead = <String>[];
  var markedAllRead = 0;

  @override
  Future<NotificationFeed> list({required String token, int limit = 50}) async {
    if (!online) throw const SocketException('offline');
    return NotificationFeed.fromJson({
      'items': rows,
      'unreadCount': rows.where((r) => r['readAt'] == null).length,
    });
  }

  @override
  Future<void> markRead({required String id, required String token}) async {
    markedRead.add(id);
    for (final r in rows) {
      if (r['id'] == id) r['readAt'] = DateTime.now().toUtc().toIso8601String();
    }
  }

  @override
  Future<void> markAllRead({required String token}) async {
    markedAllRead++;
    for (final r in rows) {
      r['readAt'] ??= DateTime.now().toUtc().toIso8601String();
    }
  }
}

_FakeRepository _threeNotifications() => _FakeRepository([
  _row('n3', 'Runner assigned', 'Test R. is picking up your order from Golden Crust Bakery.', orderId: 'order-3', minutesAgo: 1),
  _row(
    'n2',
    'Order declined',
    'Spice Garden declined your order — "Out of stock". Your ₦2,500.00 has been refunded to your Bridgit wallet.',
    orderId: 'order-2',
    minutesAgo: 30,
  ),
  _row('n1', 'Order delivered', 'Your order has been delivered. Enjoy!', orderId: 'order-1', read: true, minutesAgo: 120),
]);

Future<ProviderContainer> _pumpCentre(WidgetTester tester, _FakeRepository repository, {LocalCache? cache}) async {
  String? opened;
  final router = GoRouter(
    initialLocation: AppRoutes.notifications,
    routes: [
      GoRoute(path: AppRoutes.notifications, builder: (_, _) => const NotificationsScreen()),
      GoRoute(
        path: AppRoutes.orderDetail,
        builder: (_, state) {
          opened = state.extra as String?;
          return Scaffold(body: Text('Order detail for $opened'));
        },
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(_FakeAuthController.new),
        notificationsRepositoryProvider.overrideWithValue(repository),
        localCacheProvider.overrideWithValue(cache ?? MemoryLocalCache()),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(NotificationsScreen)));
}

void main() {
  group('NotificationFeed', () {
    final feed = NotificationFeed.fromJson({
      'items': _threeNotifications().rows,
      'unreadCount': 2,
    });

    test('marking an unread one read drops the count by one; marking it again changes nothing', () {
      final once = feed.markRead('n3', DateTime.now());
      expect(once.unreadCount, 1);
      expect(once.items.first.isRead, isTrue);
      expect(once.markRead('n3', DateTime.now()).unreadCount, 1);
    });

    test('marking an already-read one never lowers the count', () {
      expect(feed.markRead('n1', DateTime.now()).unreadCount, 2);
    });

    test('mark all read', () {
      final all = feed.markAllRead(DateTime.now());
      expect(all.unreadCount, 0);
      expect(all.items.every((n) => n.isRead), isTrue);
    });

    test('survives a round trip through the saved copy', () {
      final back = NotificationFeed.fromJson(feed.toJson());
      expect(back.unreadCount, 2);
      expect(back.items.map((n) => n.id), ['n3', 'n2', 'n1']);
      expect(back.items[1].orderId, 'order-2');
      expect(back.items.last.isRead, isTrue);
    });
  });

  group('Notification centre', () {
    testWidgets('lists newest first, unread ones marked, with real formatted amounts', (tester) async {
      await _pumpCentre(tester, _threeNotifications());

      final titles = ['Runner assigned', 'Order declined', 'Order delivered'];
      final ys = [for (final t in titles) tester.getTopLeft(find.text(t)).dy];
      expect(ys, orderedEquals([...ys]..sort()));
      expect(find.byKey(const ValueKey('unread-dot')), findsNWidgets(2));
      expect(find.textContaining('₦2,500.00'), findsOneWidget);
      expect(find.text('Mark all read'), findsOneWidget);
    });

    testWidgets('tapping one marks it read (once) and opens the screen its push would', (tester) async {
      final repository = _threeNotifications();
      final container = await _pumpCentre(tester, repository);

      await tester.tap(find.text('Order declined'));
      await tester.pumpAndSettle();

      expect(repository.markedRead, ['n2']);
      expect(find.text('Order detail for order-2'), findsOneWidget);
      expect(container.read(unreadNotificationCountProvider), 1);
    });

    testWidgets('tapping an already-read one does not call the backend again', (tester) async {
      final repository = _threeNotifications();
      await _pumpCentre(tester, repository);

      await tester.tap(find.text('Order delivered'));
      await tester.pumpAndSettle();

      expect(repository.markedRead, isEmpty);
    });

    testWidgets('"Mark all read" clears every dot and the count', (tester) async {
      final repository = _threeNotifications();
      final container = await _pumpCentre(tester, repository);

      await tester.tap(find.text('Mark all read'));
      await tester.pumpAndSettle();

      expect(repository.markedAllRead, 1);
      expect(find.byKey(const ValueKey('unread-dot')), findsNothing);
      expect(find.text('Mark all read'), findsNothing);
      expect(container.read(unreadNotificationCountProvider), 0);
    });

    testWidgets('an empty feed says so', (tester) async {
      await _pumpCentre(tester, _FakeRepository([]));

      expect(find.text('No notifications yet'), findsOneWidget);
      expect(find.text('Mark all read'), findsNothing);
    });

    testWidgets('offline, a returning student sees the saved list marked "Last updated" — reads stick', (tester) async {
      final cache = MemoryLocalCache();
      final repository = _threeNotifications();
      await _pumpCentre(tester, repository, cache: cache);
      await tester.tap(find.text('Mark all read'));
      await tester.pumpAndSettle();

      // A new run of the app, with no connection.
      await tester.pumpWidget(const SizedBox());
      repository.online = false;
      await _pumpCentre(tester, repository, cache: cache);

      expect(find.text('Runner assigned'), findsOneWidget);
      expect(find.textContaining('Last updated'), findsOneWidget);
      expect(find.byKey(const ValueKey('unread-dot')), findsNothing);
    });
  });

  test('times read as "just now", minutes, hours, then a date', () {
    final now = DateTime(2026, 10, 7, 12);
    expect(describeNotificationTime(now, now: now), 'just now');
    expect(describeNotificationTime(now.subtract(const Duration(minutes: 12)), now: now), '12m ago');
    expect(describeNotificationTime(now.subtract(const Duration(hours: 3)), now: now), '3h ago');
    expect(describeNotificationTime(DateTime(2026, 9, 30, 8), now: now), 'Sep 30');
  });
}
