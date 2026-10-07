import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/cache/cached_fetch.dart';
import '../../../core/cache/cached_sources.dart';
import '../../../core/cache/local_cache.dart';
import '../../auth/application/auth_controller.dart';
import '../data/notifications_repository.dart';
import '../domain/app_notification.dart';

/// The student's notification centre — cached like the other student
/// screens (saved copy first, "Last updated" while offline).
class NotificationsController extends AsyncNotifier<NotificationFeed> {
  @override
  Future<NotificationFeed> build() async {
    final session = ref.watch(authControllerProvider);
    if (session == null) return NotificationFeed.empty;
    ref.watch(notificationsRepositoryProvider);
    return cachedFetch<NotificationFeed>(ref, notificationsSource(ref, session));
  }

  /// Pull-to-refresh, or a push arriving: always asks the network.
  Future<void> refresh() async {
    final session = ref.read(authControllerProvider);
    if (session != null) ref.read(cacheSessionProvider).forceNetwork(CacheKeys.notifications(session.user.id));
    ref.invalidateSelf();
    await future;
  }

  /// Shown as read straight away; the backend catches up. If that call
  /// fails the next refresh shows the truth again.
  Future<void> markRead(String id) async {
    final session = ref.read(authControllerProvider);
    final feed = state.valueOrNull;
    if (session == null || feed == null) return;
    final target = feed.items.where((n) => n.id == id).firstOrNull;
    if (target == null || target.isRead) return;
    _show(session.user.id, feed.markRead(id, DateTime.now()));
    try {
      await ref.read(notificationsRepositoryProvider).markRead(id: id, token: session.accessToken);
    } catch (error) {
      debugPrint('Notifications: marking $id read failed — $error');
    }
  }

  Future<void> markAllRead() async {
    final session = ref.read(authControllerProvider);
    final feed = state.valueOrNull;
    if (session == null || feed == null || feed.unreadCount == 0) return;
    _show(session.user.id, feed.markAllRead(DateTime.now()));
    try {
      await ref.read(notificationsRepositoryProvider).markAllRead(token: session.accessToken);
    } catch (error) {
      debugPrint('Notifications: marking all read failed — $error');
    }
  }

  /// Updates the screen and the saved copy together, so reopening offline
  /// doesn't bring read items back as unread.
  void _show(String userId, NotificationFeed feed) {
    state = AsyncData(feed);
    unawaited(ref.read(localCacheProvider).write(CacheKeys.notifications(userId), feed.toJson()));
  }
}

final notificationsProvider = AsyncNotifierProvider<NotificationsController, NotificationFeed>(
  NotificationsController.new,
);

/// The bell's badge: 0 until the feed has loaded (never a guess).
final unreadNotificationCountProvider = Provider<int>(
  (ref) => ref.watch(notificationsProvider.select((feed) => feed.valueOrNull?.unreadCount ?? 0)),
);
