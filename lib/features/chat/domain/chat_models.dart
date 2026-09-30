import 'package:flutter/foundation.dart';

/// Task 78: one message in an order's student <-> runner chat.
@immutable
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.orderId,
    required this.senderUserId,
    required this.body,
    required this.createdAt,
    this.readAt,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    id: json['id'] as String,
    orderId: json['orderId'] as String,
    senderUserId: json['senderUserId'] as String,
    body: json['body'] as String,
    // The backend sends UTC; everything the user sees is local time.
    createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
    readAt: json['readAt'] == null ? null : DateTime.parse(json['readAt'] as String).toLocal(),
  );

  final String id;
  final String orderId;
  final String senderUserId;
  final String body;
  final DateTime createdAt;
  final DateTime? readAt;

  ChatMessage copyWith({DateTime? readAt}) => ChatMessage(
    id: id,
    orderId: orderId,
    senderUserId: senderUserId,
    body: body,
    createdAt: createdAt,
    readAt: readAt ?? this.readAt,
  );
}

/// `#78523600` — the last 8 characters: app-placed order ids are
/// `order-<micros>`, so the first 8 would be `ORDER-17…` on every order.
String orderReference(String orderId) =>
    '#${orderId.substring((orderId.length - 8).clamp(0, orderId.length)).toUpperCase()}';

/// One order's chat, as `GET /orders/:id/messages` returns it.
@immutable
class OrderChat {
  const OrderChat({
    required this.orderId,
    required this.canSend,
    required this.vendorName,
    required this.otherPartyName,
    required this.messages,
  });

  factory OrderChat.fromJson(Map<String, dynamic> json) => OrderChat(
    orderId: json['orderId'] as String,
    canSend: json['canSend'] == true,
    vendorName: json['vendorName'] as String,
    otherPartyName: json['otherPartyName'] as String,
    messages: [
      for (final m in json['messages'] as List<dynamic>) ChatMessage.fromJson(m as Map<String, dynamic>),
    ],
  );

  final String orderId;

  /// False once the order is delivered or cancelled — the history stays
  /// readable, but nothing more can be sent.
  final bool canSend;
  final String vendorName;

  /// The runner's name for the student, the student's for the runner.
  final String otherPartyName;
  final List<ChatMessage> messages;

  OrderChat copyWith({List<ChatMessage>? messages}) => OrderChat(
    orderId: orderId,
    canSend: canSend,
    vendorName: vendorName,
    otherPartyName: otherPartyName,
    messages: messages ?? this.messages,
  );
}

/// A row in the runner's Messages tab — one per order they've been
/// assigned, from `GET /messages/threads`.
@immutable
class ChatThread {
  const ChatThread({
    required this.orderId,
    required this.canSend,
    required this.vendorName,
    required this.otherPartyName,
    required this.unreadCount,
    required this.lastActivityAt,
    this.lastMessage,
  });

  factory ChatThread.fromJson(Map<String, dynamic> json) => ChatThread(
    orderId: json['orderId'] as String,
    canSend: json['canSend'] == true,
    vendorName: json['vendorName'] as String,
    otherPartyName: json['otherPartyName'] as String,
    unreadCount: (json['unreadCount'] as num?)?.toInt() ?? 0,
    lastActivityAt: DateTime.parse(json['lastActivityAt'] as String).toLocal(),
    lastMessage: json['lastMessage'] == null
        ? null
        : ChatMessage.fromJson(json['lastMessage'] as Map<String, dynamic>),
  );

  final String orderId;
  final bool canSend;
  final String vendorName;
  final String otherPartyName;
  final int unreadCount;
  final DateTime lastActivityAt;
  final ChatMessage? lastMessage;

  bool get unread => unreadCount > 0;
  String get reference => orderReference(orderId);
}

/// An entry in the Updates segment — a real notification from
/// `GET /notifications` (order updates, account notices).
@immutable
class AccountNotice {
  const AccountNotice({required this.title, required this.body, required this.createdAt, required this.unread});

  factory AccountNotice.fromJson(Map<String, dynamic> json) => AccountNotice(
    title: json['title'] as String,
    body: json['body'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
    unread: json['readAt'] == null,
  );

  final String title;
  final String body;
  final DateTime createdAt;
  final bool unread;
}
