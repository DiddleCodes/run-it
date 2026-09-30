import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/app_notification.dart';
import '../../auth/application/auth_controller.dart';
import '../data/chat_realtime.dart';
import '../data/chat_repository.dart';
import '../domain/chat_models.dart';

/// The order whose chat is on screen right now, if any — so a new message
/// in it doesn't also raise a banner, and gets marked read straight away.
final openChatOrderIdProvider = StateProvider<String?>((ref) => null);

String _token(Ref ref) {
  final session = ref.read(authControllerProvider);
  if (session == null) throw StateError('Not signed in');
  return session.accessToken;
}

/// Task 78: one order's chat while it's open — history from REST, new
/// messages live from the order's socket room, sends through REST.
class OrderChatController extends AutoDisposeFamilyAsyncNotifier<OrderChat, String> {
  final _subscriptions = <StreamSubscription<Object?>>[];

  @override
  Future<OrderChat> build(String orderId) async {
    final realtime = ref.watch(chatRealtimeProvider);
    realtime.joinOrder(orderId);
    _subscriptions
      ..add(realtime.messages.where((m) => m.orderId == orderId).listen(_onIncoming))
      ..add(realtime.reads.where((r) => r.orderId == orderId).listen(_onRead))
      ..add(realtime.connected.listen((_) => unawaited(_reload())));
    ref.onDispose(() {
      realtime.leaveOrder(orderId);
      for (final s in _subscriptions) {
        unawaited(s.cancel());
      }
    });

    final chat = await ref.read(chatRepositoryProvider).fetchChat(orderId: orderId, token: _token(ref));
    unawaited(_markReadIfOpen());
    return chat;
  }

  String? get _myId => ref.read(authControllerProvider)?.user.id;

  /// Adds [message] unless it's already there — the sender gets their own
  /// message back both from the POST and from the room broadcast.
  void _merge(ChatMessage message) {
    final chat = state.valueOrNull;
    if (chat == null || chat.messages.any((m) => m.id == message.id)) return;
    state = AsyncData(chat.copyWith(messages: [...chat.messages, message]));
  }

  void _onIncoming(ChatMessage message) {
    _merge(message);
    if (message.senderUserId != _myId) unawaited(_markReadIfOpen());
  }

  void _onRead(ChatReadReceipt receipt) {
    final chat = state.valueOrNull;
    if (chat == null || receipt.readerUserId == _myId) return;
    state = AsyncData(
      chat.copyWith(
        messages: [
          for (final m in chat.messages)
            if (m.senderUserId == _myId && m.readAt == null) m.copyWith(readAt: receipt.readAt) else m,
        ],
      ),
    );
  }

  Future<void> _reload() async {
    try {
      final fresh = await ref.read(chatRepositoryProvider).fetchChat(orderId: arg, token: _token(ref));
      state = AsyncData(fresh);
    } catch (_) {
      // Keep what's on screen; the next reconnect tries again.
    }
  }

  Future<void> _markReadIfOpen() async {
    if (ref.read(openChatOrderIdProvider) != arg) return;
    try {
      await ref.read(chatRepositoryProvider).markRead(orderId: arg, token: _token(ref));
      ref.invalidate(chatThreadsProvider);
    } catch (_) {
      // Unread counts are cosmetic; never interrupt the chat over them.
    }
  }

  /// Throws on failure so the screen can keep the typed text and say so.
  Future<void> send(String text) async {
    final body = text.trim();
    if (body.isEmpty) return;
    final message = await ref.read(chatRepositoryProvider).send(orderId: arg, body: body, token: _token(ref));
    _merge(message);
  }

  /// Called by the screen once it's actually on screen.
  Future<void> markRead() => _markReadIfOpen();
}

final orderChatProvider = AsyncNotifierProvider.autoDispose.family<OrderChatController, OrderChat, String>(
  OrderChatController.new,
);

/// The runner's Messages tab: a thread per assigned order (active and past),
/// kept fresh by every new message and read receipt.
final chatThreadsProvider = FutureProvider.autoDispose<List<ChatThread>>((ref) async {
  final realtime = ref.watch(chatRealtimeProvider);
  final subscriptions = [
    realtime.notices.listen((_) => ref.invalidateSelf()),
    realtime.reads.listen((_) => ref.invalidateSelf()),
  ];
  ref.onDispose(() {
    for (final s in subscriptions) {
      unawaited(s.cancel());
    }
  });
  return ref.read(chatRepositoryProvider).fetchThreads(token: _token(ref));
});

/// The Messages tab's Updates segment: the user's real notifications.
final accountNoticesProvider = FutureProvider.autoDispose<List<AccountNotice>>(
  (ref) => ref.read(chatRepositoryProvider).fetchNotices(token: _token(ref)),
);

/// While the app is open, a message in a chat that isn't on screen shows
/// as an in-app banner (the backend doesn't push then — see
/// SocketChatRealtime). Watched once from the app root.
final chatNoticeBannerProvider = Provider<void>((ref) {
  final realtime = ref.watch(chatRealtimeProvider);
  final subscription = realtime.notices.listen((message) {
    final me = ref.read(authControllerProvider)?.user.id;
    if (message.senderUserId == me || ref.read(openChatOrderIdProvider) == message.orderId) return;
    ref.read(appNotificationProvider.notifier).info('New message: ${message.body}');
  });
  ref.onDispose(subscription.cancel);
});
