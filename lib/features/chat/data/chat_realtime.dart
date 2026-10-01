import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_io_client/socket_io_client.dart' as socket_io;

import '../../../core/network/api_config.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/domain/auth_models.dart';
import '../domain/chat_models.dart';
import '../../../core/utils/server_time.dart';

/// A `messages_read` event: [readerUserId] has seen everything the other
/// party sent in [orderId] up to [readAt].
@immutable
class ChatReadReceipt {
  const ChatReadReceipt({required this.orderId, required this.readerUserId, required this.readAt});
  final String orderId;
  final String readerUserId;
  final DateTime readAt;
}

/// Task 78: the live half of order chat (backend `order-chat` namespace).
/// Behind an interface so the chat controllers are testable without a
/// socket server.
abstract class ChatRealtime {
  /// New messages in orders whose room this device has joined (open chats).
  Stream<ChatMessage> get messages;

  /// Every new message in any of the user's chats, sent or received — for
  /// the in-app banner and the thread list.
  Stream<ChatMessage> get notices;

  Stream<ChatReadReceipt> get reads;

  /// Fires on every (re)connect — a chat that's open should reload then, in
  /// case messages arrived while the socket was down.
  Stream<void> get connected;

  /// Join [orderId]'s room. Kept across reconnects until [leaveOrder].
  void joinOrder(String orderId);
  void leaveOrder(String orderId);
}

/// Connected only while someone is signed in AND the app is in the
/// foreground. That's deliberate, not just thrift: the backend reads "no
/// connected socket" as "app backgrounded or closed" and only then sends a
/// push for a new message — so a foregrounded app gets it live, never twice.
class SocketChatRealtime implements ChatRealtime {
  SocketChatRealtime(this.ref) {
    _lifecycle = AppLifecycleListener(onStateChange: (state) {
      _foreground = state == AppLifecycleState.resumed || state == AppLifecycleState.inactive;
      _sync();
    });
    ref.listen<AuthSession?>(authControllerProvider, (previous, next) {
      // A new access token only matters at the next handshake — but a
      // different user must never inherit the previous one's connection.
      final userChanged = previous?.user.id != next?.user.id;
      if (userChanged) _disconnect();
      _sync();
    }, fireImmediately: true);
  }

  final Ref ref;
  late final AppLifecycleListener _lifecycle;
  bool _foreground = true;
  socket_io.Socket? _socket;
  final _rooms = <String>{};

  final _messages = StreamController<ChatMessage>.broadcast();
  final _notices = StreamController<ChatMessage>.broadcast();
  final _reads = StreamController<ChatReadReceipt>.broadcast();
  final _connected = StreamController<void>.broadcast();

  @override
  Stream<ChatMessage> get messages => _messages.stream;
  @override
  Stream<ChatMessage> get notices => _notices.stream;
  @override
  Stream<ChatReadReceipt> get reads => _reads.stream;
  @override
  Stream<void> get connected => _connected.stream;

  void _sync() {
    final session = ref.read(authControllerProvider);
    if (session == null || !_foreground) {
      _disconnect();
    } else if (_socket == null) {
      _connect(session.accessToken);
    }
  }

  void _connect(String token) {
    final socket = socket_io.io(
      '$apiBaseUrl/order-chat',
      socket_io.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': token})
          .disableAutoConnect()
          .build(),
    );
    socket
      ..on('connected', (_) {
        for (final room in _rooms) {
          socket.emit('join_order', {'orderId': room});
        }
        _connected.add(null);
      })
      ..on('message', (data) => _messages.add(ChatMessage.fromJson(Map<String, dynamic>.from(data as Map))))
      ..on('message_notice', (data) => _notices.add(ChatMessage.fromJson(Map<String, dynamic>.from(data as Map))))
      ..on('messages_read', (data) {
        final json = Map<String, dynamic>.from(data as Map);
        _reads.add(
          ChatReadReceipt(
            orderId: json['orderId'] as String,
            readerUserId: json['readerUserId'] as String,
            readAt: parseServerTime(json['readAt'] as String),
          ),
        );
      })
      // The handshake is refused once the access token has expired; the
      // next foreground/auth change reconnects with the refreshed one.
      ..on('error', (_) => _disconnect())
      ..connect();
    _socket = socket;
  }

  void _disconnect() {
    _socket?.dispose();
    _socket = null;
  }

  @override
  void joinOrder(String orderId) {
    _rooms.add(orderId);
    _socket?.emit('join_order', {'orderId': orderId});
  }

  @override
  void leaveOrder(String orderId) {
    _rooms.remove(orderId);
    _socket?.emit('leave_order', {'orderId': orderId});
  }

  void dispose() {
    _lifecycle.dispose();
    _disconnect();
    for (final c in [_messages, _notices, _reads, _connected]) {
      unawaited(c.close());
    }
  }
}

final chatRealtimeProvider = Provider<ChatRealtime>((ref) {
  final realtime = SocketChatRealtime(ref);
  ref.onDispose(realtime.dispose);
  return realtime;
});
