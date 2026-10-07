import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/cache/cached_data_note.dart';
import '../../../core/cache/cached_fetch.dart';
import '../../../core/notifications/push_notifications.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../auth/application/auth_controller.dart';
import '../../ordering/application/order_tracking_controller.dart';
import '../application/notifications_controller.dart';
import '../domain/app_notification.dart';

/// The student's notification centre, from the Home bell: every stored
/// notification newest first, unread ones marked, and a tap opens the same
/// screen the push would have.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feed = ref.watch(notificationsProvider);
    final userId = ref.watch(authControllerProvider.select((session) => session?.user.id));
    final unread = feed.valueOrNull?.unreadCount ?? 0;

    return Scaffold(
      backgroundColor: AppColors.backgroundCream,
      appBar: AppBar(
        title: const Text('Notifications'),
        backgroundColor: AppColors.backgroundCream,
        elevation: 0,
        actions: [
          if (unread > 0)
            TextButton(
              onPressed: () => ref.read(notificationsProvider.notifier).markAllRead(),
              child: const Text('Mark all read'),
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CachedDataNote(
              cacheKey: userId == null ? null : CacheKeys.notifications(userId),
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, 8),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => ref.read(notificationsProvider.notifier).refresh(),
                child: feed.when(
                  skipLoadingOnRefresh: true,
                  skipLoadingOnReload: true,
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (_, _) => _Message(
                    icon: CupertinoIcons.wifi_exclamationmark,
                    title: "Couldn't load your notifications",
                    subtitle: 'Pull down to try again.',
                  ),
                  data: (feed) => feed.items.isEmpty
                      ? const _Message(
                          icon: CupertinoIcons.bell,
                          title: 'No notifications yet',
                          subtitle: 'Updates about your orders will show up here.',
                        )
                      : ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
                          itemCount: feed.items.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 10),
                          itemBuilder: (context, i) => _NotificationTile(
                            notification: feed.items[i],
                            onTap: () => _open(context, ref, feed.items[i]),
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _open(BuildContext context, WidgetRef ref, AppNotification notification) {
    ref.read(notificationsProvider.notifier).markRead(notification.id);
    openPushDestination(
      GoRouter.of(context),
      PushMessage(
        title: notification.title,
        body: notification.body,
        data: {'type': notification.type, 'orderId': ?notification.orderId},
      ),
      trackedOrderId: ref.read(orderTrackingProvider).orderId,
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.notification, required this.onTap});

  final AppNotification notification;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final unread = !notification.isRead;
    final textTheme = Theme.of(context).textTheme;
    return Semantics(
      label: unread ? 'Unread' : null,
      child: Material(
        color: unread ? AppColors.surfaceCard : AppColors.surfaceCard.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(color: AppColors.accentRose, shape: BoxShape.circle),
                  child: Icon(_iconFor(notification.type), color: AppColors.primaryMaroon, size: 19),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              notification.title,
                              style: textTheme.titleSmall?.copyWith(
                                color: AppColors.inkText,
                                fontWeight: unread ? FontWeight.w700 : FontWeight.w500,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            describeNotificationTime(notification.createdAt),
                            style: textTheme.labelSmall?.copyWith(color: AppColors.mutedText),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        notification.body,
                        style: textTheme.bodyMedium?.copyWith(
                          color: unread ? AppColors.inkText : AppColors.mutedText,
                        ),
                      ),
                    ],
                  ),
                ),
                if (unread) ...[
                  const SizedBox(width: 8),
                  Container(
                    key: const ValueKey('unread-dot'),
                    margin: const EdgeInsets.only(top: 6),
                    width: 9,
                    height: 9,
                    decoration: const BoxDecoration(color: AppColors.primaryMaroon, shape: BoxShape.circle),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  static IconData _iconFor(String type) => switch (type) {
    'order_accepted' => CupertinoIcons.flame,
    'runner_assigned' => CupertinoIcons.person_crop_circle_badge_checkmark,
    'order_picked_up' => CupertinoIcons.cube_box,
    'order_delivered' => CupertinoIcons.checkmark_seal,
    'order_declined' || 'order_cancelled' => CupertinoIcons.xmark_circle,
    'account_suspended' || 'account_reinstated' => CupertinoIcons.shield,
    _ => CupertinoIcons.bell,
  };
}

/// "just now", "12m ago", "3h ago", then "Sep 30".
String describeNotificationTime(DateTime at, {DateTime? now}) {
  final diff = (now ?? DateTime.now()).difference(at);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return DateFormat('MMM d').format(at);
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.title, required this.subtitle});
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    // Scrollable so pull-to-refresh still works on an empty or failed list.
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(32),
      children: [
        const SizedBox(height: 60),
        Center(
          child: Container(
            width: 68,
            height: 68,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: AppColors.accentRose, shape: BoxShape.circle),
            child: Icon(icon, color: AppColors.primaryMaroon, size: 30),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(color: AppColors.inkText),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.mutedText),
        ),
      ],
    );
  }
}
