import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/routing/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_notification.dart';
import '../../auth/application/auth_controller.dart';
import '../../chat/application/chat_controllers.dart';
import '../../chat/domain/chat_models.dart';

/// Same rotation of tints/glyphs the Jobs screen's vendor badges use —
/// duplicated (not imported) since both are file-private, but it keeps
/// order-thread tiles visually consistent with their job cards.
const _vendorTileBadges = [
  (AppColors.accentRose, AppColors.primaryMaroon, Icons.restaurant_rounded),
  (AppColors.goldTint, AppColors.gold, Icons.local_cafe_rounded),
  (AppColors.successBackground, AppColors.success, Icons.eco_rounded),
  (Color(0xFFE4E9F7), Color(0xFF3B5BA8), Icons.icecream_rounded),
];

(Color, Color, IconData) _vendorTileFor(String name) =>
    _vendorTileBadges[name.hashCode.abs() % _vendorTileBadges.length];

/// Task 78: the tabs map onto real data like this —
/// - All / Orders: one thread per order this runner has been assigned
///   (active and past), from `GET /messages/threads`. Every thread is an
///   order thread now, so the two show the same list.
/// - Support: there is no support chat backend, so this is an honest
///   pointer to the support email rather than a fake conversation.
/// - Updates: the runner's real notifications (`GET /notifications`).
enum _MessagesTab { all, orders, support, updates }

class RunnerMessagesScreen extends ConsumerStatefulWidget {
  const RunnerMessagesScreen({super.key});

  @override
  ConsumerState<RunnerMessagesScreen> createState() => _RunnerMessagesScreenState();
}

class _RunnerMessagesScreenState extends ConsumerState<RunnerMessagesScreen> {
  _MessagesTab _tab = _MessagesTab.all;

  Widget _list<T>(AsyncValue<List<T>> value, Widget Function(T item) row, {required VoidCallback onRetry}) {
    return switch (value) {
      AsyncData(:final value) when value.isEmpty => const _EmptyMessages(),
      AsyncData(:final value) => RefreshIndicator(
        onRefresh: () async => onRetry(),
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(AppSpacing.ml, 12, AppSpacing.ml, 24),
          itemCount: value.length,
          separatorBuilder: (_, _) => const Divider(height: 1, color: AppColors.borderSubtle, indent: 62),
          itemBuilder: (context, index) => row(value[index]),
        ),
      ),
      AsyncError() => _LoadError(onRetry: onRetry),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }

  @override
  Widget build(BuildContext context) {
    final myUserId = ref.watch(authControllerProvider.select((s) => s?.user.id));

    return Scaffold(
      backgroundColor: AppColors.backgroundCream,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.ml, 6, AppSpacing.ml, 0),
              child: _MessagesHeader(
                onSearchTap: () => ref
                    .read(appNotificationProvider.notifier)
                    .info('Search is coming soon.'),
                onMoreTap: () => ref
                    .read(appNotificationProvider.notifier)
                    .info('More options are coming soon.'),
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.ml),
              child: _SegmentedTabs(
                value: _tab,
                onChanged: (tab) => setState(() => _tab = tab),
              ),
            ),
            Expanded(
              child: switch (_tab) {
                _MessagesTab.all || _MessagesTab.orders => _list<ChatThread>(
                  ref.watch(chatThreadsProvider),
                  (thread) => _ThreadRow(
                    thread: thread,
                    myUserId: myUserId,
                    onTap: () => context.push(AppRoutes.orderChat, extra: thread.orderId),
                  ),
                  onRetry: () => ref.invalidate(chatThreadsProvider),
                ),
                _MessagesTab.support => const _SupportPointer(),
                _MessagesTab.updates => _list<AccountNotice>(
                  ref.watch(accountNoticesProvider),
                  (notice) => _NoticeRow(notice: notice),
                  onRetry: () => ref.invalidate(accountNoticesProvider),
                ),
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _MessagesHeader extends StatelessWidget {
  const _MessagesHeader({required this.onSearchTap, required this.onMoreTap});
  final VoidCallback onSearchTap;
  final VoidCallback onMoreTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(width: 42),
        Expanded(
          child: Center(
            child: Text(
              'Messages',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: AppColors.inkText,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        _HeaderIconButton(icon: CupertinoIcons.search, onTap: onSearchTap),
        const SizedBox(width: 8),
        _HeaderIconButton(icon: CupertinoIcons.ellipsis_circle, onTap: onMoreTap),
      ],
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(icon, color: AppColors.inkText, size: 22),
      ),
    );
  }
}

class _SegmentedTabs extends StatelessWidget {
  const _SegmentedTabs({required this.value, required this.onChanged});
  final _MessagesTab value;
  final ValueChanged<_MessagesTab> onChanged;

  static const _labels = {
    _MessagesTab.all: 'All',
    _MessagesTab.orders: 'Orders',
    _MessagesTab.support: 'Support',
    _MessagesTab.updates: 'Updates',
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.borderSubtle.withValues(alpha: .5),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        children: [
          for (final tab in _MessagesTab.values)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(tab),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    color: value == tab ? AppColors.surfaceCard : null,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    boxShadow: value == tab
                        ? [
                            BoxShadow(
                              color: AppColors.maroonShadow,
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  child: Center(
                    child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 200),
                      style: Theme.of(context).textTheme.labelMedium!.copyWith(
                        color: value == tab ? AppColors.primaryMaroon : AppColors.mutedText,
                        fontWeight: value == tab ? FontWeight.w700 : FontWeight.w500,
                      ),
                      child: Text(_labels[tab]!),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _NoticeRow extends StatelessWidget {
  const _NoticeRow({required this.notice});
  final AccountNotice notice;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: AppColors.goldTint, shape: BoxShape.circle),
            child: const Icon(CupertinoIcons.bell_fill, color: AppColors.gold, size: 20),
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
                        notice.title,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: AppColors.inkText,
                          fontWeight: notice.unread ? FontWeight.w800 : FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      _relativeTime(notice.createdAt),
                      style: Theme.of(
                        context,
                      ).textTheme.labelSmall?.copyWith(color: AppColors.mutedText),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  notice.body,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: AppColors.mutedText),
                ),
              ],
            ),
          ),
          if (notice.unread) ...[
            const SizedBox(width: 8),
            Container(
              width: 9,
              height: 9,
              decoration: const BoxDecoration(color: AppColors.primaryMaroon, shape: BoxShape.circle),
            ),
          ],
        ],
      ),
    );
  }
}

class _ThreadRow extends StatelessWidget {
  const _ThreadRow({required this.thread, required this.myUserId, required this.onTap});
  final ChatThread thread;
  final String? myUserId;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final last = thread.lastMessage;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
              Builder(
                builder: (context) {
                  final (bg, fg, icon) = _vendorTileFor(thread.vendorName);
                  return Container(
                    width: 46,
                    height: 46,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: bg,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Icon(icon, size: 20, color: fg),
                  );
                },
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
                          thread.otherPartyName,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: AppColors.inkText,
                            fontWeight: thread.unread ? FontWeight.w800 : FontWeight.w600,
                          ),
                        ),
                      ),
                      ...[
                        const SizedBox(width: 6),
                        Text(
                          thread.reference,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: AppColors.mutedText),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    last == null ? 'No messages yet' : '${last.senderUserId == myUserId ? 'You: ' : ''}${last.body}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: thread.unread ? AppColors.inkText : AppColors.mutedText,
                      fontWeight: thread.unread ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (last != null)
                  Text(
                    _relativeTime(last.createdAt),
                    style: Theme.of(
                      context,
                    ).textTheme.labelSmall?.copyWith(color: AppColors.mutedText),
                  ),
                const SizedBox(height: 6),
                if (thread.unreadCount > 0)
                  Container(
                    constraints: const BoxConstraints(minWidth: 18),
                    height: 18,
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.primaryMaroon,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Text(
                      '${thread.unreadCount}',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.onMaroon,
                        fontWeight: FontWeight.w700,
                        height: 1,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _relativeTime(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 60) return '${diff.inMinutes}m';
  if (diff.inHours < 24) return '${diff.inHours}h';
  return DateFormat('MMM d').format(time);
}

class _EmptyMessages extends StatelessWidget {
  const _EmptyMessages();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 68,
              height: 68,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: AppColors.accentRose,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.chat_bubble_outline_rounded,
                color: AppColors.primaryMaroon,
                size: 28,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No messages yet',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(color: AppColors.inkText),
            ),
            const SizedBox(height: 6),
            Text(
              'Conversations about your deliveries will show up here.',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppColors.mutedText),
            ),
          ],
        ),
      ),
    );
  }
}

class _SupportPointer extends StatelessWidget {
  const _SupportPointer();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 68,
              height: 68,
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: AppColors.primaryMaroon, shape: BoxShape.circle),
              child: const Icon(CupertinoIcons.shield_fill, color: AppColors.onMaroon, size: 26),
            ),
            const SizedBox(height: 16),
            Text(
              'RUN-It Support',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(color: AppColors.inkText),
            ),
            const SizedBox(height: 6),
            Text(
              'In-app support chat isn’t available yet. Email support@run-it.app and we’ll get back to you.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.mutedText),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Couldn’t load your messages.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.mutedText),
        ),
        TextButton(onPressed: onRetry, child: const Text('Try again')),
      ],
    ),
  );
}
