import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_notification.dart';
import '../../auth/application/auth_controller.dart';
import '../application/chat_controllers.dart';
import '../domain/chat_models.dart';

/// Task 78: an order's chat — the runner's former demo chat screen (same
/// layout: bubbles, time stamps, composer), now on real data and shared by
/// both sides: the student (from live tracking / My Orders) and the runner
/// (from the active delivery / Messages tab).
class OrderChatScreen extends ConsumerStatefulWidget {
  const OrderChatScreen({super.key, required this.orderId});
  final String orderId;

  @override
  ConsumerState<OrderChatScreen> createState() => _OrderChatScreenState();
}

class _OrderChatScreenState extends ConsumerState<OrderChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  late final StateController<String?> _openChat;
  var _sending = false;

  @override
  void initState() {
    super.initState();
    _openChat = ref.read(openChatOrderIdProvider.notifier);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _openChat.state = widget.orderId;
      ref.read(orderChatProvider(widget.orderId).notifier).markRead();
    });
  }

  @override
  void dispose() {
    if (_openChat.state == widget.orderId) _openChat.state = null;
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToEnd() {
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

  Future<void> _send() async {
    final text = _controller.text;
    if (text.trim().isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await ref.read(orderChatProvider(widget.orderId).notifier).send(text);
      _controller.clear();
    } catch (_) {
      // Keep what they typed so they can simply try again.
      ref.read(appNotificationProvider.notifier).error('Message not sent. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final chat = ref.watch(orderChatProvider(widget.orderId));
    final me = ref.watch(authControllerProvider.select((s) => s?.user.id));
    ref.listen(orderChatProvider(widget.orderId), (previous, next) {
      if ((next.valueOrNull?.messages.length ?? 0) != (previous?.valueOrNull?.messages.length ?? 0)) _scrollToEnd();
    });
    final data = chat.valueOrNull;

    return Scaffold(
      backgroundColor: AppColors.backgroundCream,
      appBar: AppBar(
        title: Text(data?.otherPartyName ?? 'Chat'),
        bottom: data == null
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(20),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    'Order ${orderReference(widget.orderId)} · ${data.vendorName}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.mutedText),
                  ),
                ),
              ),
      ),
      body: SafeArea(
        child: switch (chat) {
          AsyncError() when data == null => _ChatError(
            onRetry: () => ref.invalidate(orderChatProvider(widget.orderId)),
          ),
          _ when data == null => const Center(child: CircularProgressIndicator()),
          _ => Column(
            children: [
              Expanded(
                child: data.messages.isEmpty
                    ? Center(
                        child: Text(
                          data.canSend ? 'Say hello.' : 'No messages on this order.',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.mutedText),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                        itemCount: data.messages.length,
                        itemBuilder: (context, index) {
                          final message = data.messages[index];
                          return _MessageBubble(message: message, mine: message.senderUserId == me);
                        },
                      ),
              ),
              if (data.canSend)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          textInputAction: TextInputAction.send,
                          maxLength: 1000,
                          buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
                          onSubmitted: (_) => _send(),
                          decoration: const InputDecoration(hintText: 'Message'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: _sending ? null : _send,
                        customBorder: const CircleBorder(),
                        child: Container(
                          width: 46,
                          height: 46,
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(color: AppColors.primaryMaroon, shape: BoxShape.circle),
                          child: Icon(
                            Icons.arrow_upward_rounded,
                            color: AppColors.onMaroon.withValues(alpha: _sending ? .5 : 1),
                            size: 20,
                            semanticLabel: 'Send',
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Text(
                    'This order is finished, so its chat is closed.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.mutedText),
                  ),
                ),
            ],
          ),
        },
      ),
    );
  }
}

class _ChatError extends StatelessWidget {
  const _ChatError({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Couldn’t load this chat.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.mutedText),
          ),
          const SizedBox(height: 12),
          TextButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    ),
  );
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.mine});
  final ChatMessage message;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final meta = DateFormat('h:mm a').format(message.createdAt);
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
              message.body,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: mine ? AppColors.onMaroon : AppColors.inkText,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              // Read receipts on your own messages only.
              mine && message.readAt != null ? '$meta · Seen' : meta,
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
