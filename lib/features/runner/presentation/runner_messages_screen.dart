import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_notification.dart';

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.text,
    required this.sentAt,
    required this.fromRunner,
  });
  final String id;
  final String text;
  final DateTime sentAt;

  /// true = sent by the signed-in runner; false = the other party.
  final bool fromRunner;
}

class ChatThread {
  const ChatThread({
    required this.id,
    required this.title,
    required this.isSupport,
    this.orderReference,
    this.messages = const [],
    this.unreadCount = 0,
  });
  final String id;
  final String title;
  final bool isSupport;
  final String? orderReference;
  final List<ChatMessage> messages;

  /// A real count, not just a bool — the reference mockup's order-thread
  /// rows show a numbered badge, not a plain dot.
  final int unreadCount;

  bool get unread => unreadCount > 0;

  ChatMessage? get lastMessage => messages.isEmpty ? null : messages.last;

  ChatThread copyWith({List<ChatMessage>? messages, int? unreadCount}) => ChatThread(
    id: id,
    title: title,
    isSupport: isSupport,
    orderReference: orderReference,
    messages: messages ?? this.messages,
    unreadCount: unreadCount ?? this.unreadCount,
  );
}

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

/// There's no messaging backend yet — this is a self-contained, locally
/// held demo dataset (support thread + a couple of order-scoped threads)
/// so the screen is genuinely tappable/functional rather than a static
/// mockup, same spirit as the rest of the app's in-memory demo data.
class ChatThreadsController extends Notifier<List<ChatThread>> {
  @override
  List<ChatThread> build() {
    final now = DateTime.now();
    return [
      ChatThread(
        id: 'support',
        title: 'RUN-It Support',
        isSupport: true,
        messages: [
          ChatMessage(
            id: 's1',
            text: "Hi! We're here if you ever run into an issue on a delivery.",
            sentAt: now.subtract(const Duration(days: 2)),
            fromRunner: false,
          ),
        ],
      ),
      ChatThread(
        id: 'order-2041',
        title: 'Tantalizers',
        orderReference: '#RI-2041',
        isSupport: false,
        unreadCount: 2,
        messages: [
          ChatMessage(
            id: 'o1',
            text: "I'm outside the hall, which entrance?",
            sentAt: now.subtract(const Duration(minutes: 40)),
            fromRunner: false,
          ),
        ],
      ),
      ChatThread(
        id: 'order-2038',
        title: 'Chicken Republic',
        orderReference: '#RI-2038',
        isSupport: false,
        messages: [
          ChatMessage(
            id: 'o2',
            text: 'Thanks for the quick delivery!',
            sentAt: now.subtract(const Duration(days: 1, hours: 3)),
            fromRunner: false,
          ),
          ChatMessage(
            id: 'o3',
            text: 'Anytime — safe one!',
            sentAt: now.subtract(const Duration(days: 1, hours: 3)),
            fromRunner: true,
          ),
        ],
      ),
    ];
  }

  void markRead(String threadId) {
    state = [
      for (final t in state)
        if (t.id == threadId) t.copyWith(unreadCount: 0) else t,
    ];
  }

  void sendMessage(String threadId, String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final message = ChatMessage(
      id: 'm-${DateTime.now().microsecondsSinceEpoch}',
      text: trimmed,
      sentAt: DateTime.now(),
      fromRunner: true,
    );
    state = [
      for (final t in state)
        if (t.id == threadId) t.copyWith(messages: [...t.messages, message]) else t,
    ];
  }
}

final chatThreadsProvider =
    NotifierProvider<ChatThreadsController, List<ChatThread>>(
      ChatThreadsController.new,
    );

/// One-way system/promo announcements — distinct from [ChatThread]: these
/// aren't conversations, so they get their own segment ("Notifications")
/// rather than being mixed into the order/support chat list.
class SystemNotice {
  const SystemNotice({
    required this.title,
    required this.message,
    required this.sentAt,
    this.unread = false,
  });
  final String title;
  final String message;
  final DateTime sentAt;
  final bool unread;
}

final systemNoticesProvider = Provider<List<SystemNotice>>((ref) {
  final now = DateTime.now();
  return [
    SystemNotice(
      title: 'Peak hours incentive',
      message: 'Earn an extra ₦100 per delivery, 12–2pm today.',
      sentAt: now.subtract(const Duration(hours: 3)),
      unread: true,
    ),
    SystemNotice(
      title: 'Payout sent',
      message: 'Your last payout has been processed.',
      sentAt: now.subtract(const Duration(days: 2)),
    ),
  ];
});

enum _MessagesTab { all, orders, support, updates }

class RunnerMessagesScreen extends ConsumerStatefulWidget {
  const RunnerMessagesScreen({super.key});

  @override
  ConsumerState<RunnerMessagesScreen> createState() => _RunnerMessagesScreenState();
}

class _RunnerMessagesScreenState extends ConsumerState<RunnerMessagesScreen> {
  _MessagesTab _tab = _MessagesTab.all;

  @override
  Widget build(BuildContext context) {
    final threads = ref.watch(chatThreadsProvider);
    // Support always pinned first, everything else in most-recent-first
    // order behind it.
    final support = threads.where((t) => t.isSupport);
    final orders = threads.where((t) => !t.isSupport).toList()
      ..sort((a, b) {
        final aTime = a.lastMessage?.sentAt ?? DateTime(0);
        final bTime = b.lastMessage?.sentAt ?? DateTime(0);
        return bTime.compareTo(aTime);
      });
    final notices = ref.watch(systemNoticesProvider);

    final visibleThreads = switch (_tab) {
      _MessagesTab.all => [...support, ...orders],
      _MessagesTab.orders => orders,
      _MessagesTab.support => support.toList(),
      _MessagesTab.updates => const <ChatThread>[],
    };

    void openThread(ChatThread thread) {
      ref.read(chatThreadsProvider.notifier).markRead(thread.id);
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => _ChatDetailScreen(threadId: thread.id)),
      );
    }

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
              child: _tab == _MessagesTab.updates
                  ? (notices.isEmpty
                        ? const _EmptyMessages()
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(AppSpacing.ml, 12, AppSpacing.ml, 24),
                            itemCount: notices.length,
                            separatorBuilder: (_, _) => const Divider(
                              height: 1,
                              color: AppColors.borderSubtle,
                              indent: 62,
                            ),
                            itemBuilder: (context, index) => _NoticeRow(notice: notices[index]),
                          ))
                  : (visibleThreads.isEmpty
                        ? const _EmptyMessages()
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(AppSpacing.ml, 12, AppSpacing.ml, 24),
                            itemCount: visibleThreads.length,
                            separatorBuilder: (_, _) => const Divider(
                              height: 1,
                              color: AppColors.borderSubtle,
                              indent: 62,
                            ),
                            itemBuilder: (context, index) {
                              final thread = visibleThreads[index];
                              return _ThreadRow(
                                thread: thread,
                                onTap: () => openThread(thread),
                              );
                            },
                          )),
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
  final SystemNotice notice;

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
                      _relativeTime(notice.sentAt),
                      style: Theme.of(
                        context,
                      ).textTheme.labelSmall?.copyWith(color: AppColors.mutedText),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  notice.message,
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
  const _ThreadRow({required this.thread, required this.onTap});
  final ChatThread thread;
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
            if (thread.isSupport)
              // Left circular, unlike the square order-thread tiles below —
              // the reference mockup's pinned Support row already matched
              // this shape, per TASK 4g §4 ("that part already matches").
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.primaryMaroon,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  CupertinoIcons.shield_fill,
                  color: AppColors.onMaroon,
                  size: 20,
                ),
              )
            else
              Builder(
                builder: (context) {
                  final (bg, fg, icon) = _vendorTileFor(thread.title);
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
                          thread.title,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: AppColors.inkText,
                            fontWeight: thread.unread ? FontWeight.w800 : FontWeight.w600,
                          ),
                        ),
                      ),
                      if (thread.orderReference != null) ...[
                        const SizedBox(width: 6),
                        Text(
                          thread.orderReference!,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: AppColors.mutedText),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    last?.text ?? 'No messages yet',
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
                    _relativeTime(last.sentAt),
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

class _ChatDetailScreen extends ConsumerStatefulWidget {
  const _ChatDetailScreen({required this.threadId});
  final String threadId;

  @override
  ConsumerState<_ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends ConsumerState<_ChatDetailScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _send() {
    if (_controller.text.trim().isEmpty) return;
    ref.read(chatThreadsProvider.notifier).sendMessage(widget.threadId, _controller.text);
    _controller.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final thread = ref
        .watch(chatThreadsProvider)
        .firstWhere((t) => t.id == widget.threadId);

    return Scaffold(
      backgroundColor: AppColors.backgroundCream,
      appBar: AppBar(
        title: Text(thread.title),
        bottom: thread.orderReference == null
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(20),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    'Order ${thread.orderReference}',
                    style: Theme.of(context).textTheme.labelSmall
                        ?.copyWith(color: AppColors.mutedText),
                  ),
                ),
              ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: thread.messages.isEmpty
                  ? Center(
                      child: Text(
                        'Say hello.',
                        style: Theme.of(
                          context,
                        ).textTheme.bodyMedium?.copyWith(color: AppColors.mutedText),
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      itemCount: thread.messages.length,
                      itemBuilder: (context, index) =>
                          _MessageBubble(message: thread.messages[index]),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(hintText: 'Message'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: _send,
                    customBorder: const CircleBorder(),
                    child: Container(
                      width: 46,
                      height: 46,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        color: AppColors.primaryMaroon,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.arrow_upward_rounded,
                        color: AppColors.onMaroon,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});
  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final mine = message.fromRunner;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .72),
        decoration: BoxDecoration(
          color: mine ? AppColors.primaryMaroon : AppColors.surfaceCard,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(mine ? 16 : 4),
            bottomRight: Radius.circular(mine ? 4 : 16),
          ),
          border: mine ? null : Border.all(color: AppColors.borderSubtle),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message.text,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: mine ? AppColors.onMaroon : AppColors.inkText,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              DateFormat('h:mm a').format(message.sentAt),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: mine ? AppColors.onMaroon.withValues(alpha: .7) : AppColors.mutedText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
