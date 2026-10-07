import '../../../core/utils/server_time.dart';

/// One row of the notification centre — a stored backend Notification
/// (`GET /notifications`). Chat messages are push-only and never appear.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.createdAt,
    this.orderId,
    this.readAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>?;
    return AppNotification(
      id: json['id'] as String,
      type: json['type'] as String,
      title: json['title'] as String,
      body: json['body'] as String,
      orderId: data?['orderId'] as String?,
      createdAt: parseServerTime(json['createdAt'] as String),
      readAt: parseServerTimeOrNull(json['readAt']),
    );
  }

  final String id;
  final String type;
  final String title;
  final String body;
  final String? orderId;
  final DateTime createdAt;
  final DateTime? readAt;

  bool get isRead => readAt != null;

  AppNotification markedRead(DateTime at) => AppNotification(
    id: id,
    type: type,
    title: title,
    body: body,
    orderId: orderId,
    createdAt: createdAt,
    readAt: readAt ?? at,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'title': title,
    'body': body,
    'data': {'orderId': ?orderId},
    'createdAt': createdAt.toUtc().toIso8601String(),
    'readAt': readAt?.toUtc().toIso8601String(),
  };
}

/// The newest page of notifications plus how many of *all* of them are unread.
class NotificationFeed {
  const NotificationFeed({required this.items, required this.unreadCount});

  factory NotificationFeed.fromJson(Map<String, dynamic> json) => NotificationFeed(
    items: [
      for (final item in json['items'] as List<dynamic>) AppNotification.fromJson(item as Map<String, dynamic>),
    ],
    unreadCount: json['unreadCount'] as int,
  );

  static const empty = NotificationFeed(items: [], unreadCount: 0);

  final List<AppNotification> items;
  final int unreadCount;

  /// [id] read as of [at] — the count only drops if it was unread.
  NotificationFeed markRead(String id, DateTime at) {
    final wasUnread = items.any((n) => n.id == id && !n.isRead);
    return NotificationFeed(
      items: [for (final n in items) n.id == id ? n.markedRead(at) : n],
      unreadCount: wasUnread && unreadCount > 0 ? unreadCount - 1 : unreadCount,
    );
  }

  NotificationFeed markAllRead(DateTime at) =>
      NotificationFeed(items: [for (final n in items) n.markedRead(at)], unreadCount: 0);

  Map<String, dynamic> toJson() => {
    'items': [for (final n in items) n.toJson()],
    'unreadCount': unreadCount,
  };
}
