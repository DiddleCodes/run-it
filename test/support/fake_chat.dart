import 'dart:async';

import 'package:run_it/features/chat/data/chat_realtime.dart';
import 'package:run_it/features/chat/data/chat_repository.dart';
import 'package:run_it/features/chat/domain/chat_models.dart';

/// Task 78: the order-chat socket, driven by hand from tests.
class FakeChatRealtime implements ChatRealtime {
  final messageEvents = StreamController<ChatMessage>.broadcast();
  final noticeEvents = StreamController<ChatMessage>.broadcast();
  final readEvents = StreamController<ChatReadReceipt>.broadcast();
  final connectedEvents = StreamController<void>.broadcast();
  final joined = <String>{};

  @override
  Stream<ChatMessage> get messages => messageEvents.stream;
  @override
  Stream<ChatMessage> get notices => noticeEvents.stream;
  @override
  Stream<ChatReadReceipt> get reads => readEvents.stream;
  @override
  Stream<void> get connected => connectedEvents.stream;

  @override
  void joinOrder(String orderId) => joined.add(orderId);
  @override
  void leaveOrder(String orderId) => joined.remove(orderId);
}

/// Task 78: the order-chat REST endpoints, in memory.
class FakeChatRepository extends ChatRepository {
  FakeChatRepository({this.myUserId = 'me', this.chat, this.threads = const [], this.notices = const []});

  final String myUserId;

  OrderChat? chat;
  List<ChatThread> threads;
  List<AccountNotice> notices;
  final sent = <String>[];
  var markReadCalls = 0;
  var failSends = false;

  @override
  Future<OrderChat> fetchChat({required String orderId, required String token}) async => chat!;

  @override
  Future<ChatMessage> send({required String orderId, required String body, required String token}) async {
    if (failSends) throw Exception('offline');
    sent.add(body);
    return ChatMessage(id: 'sent-${sent.length}', orderId: orderId, senderUserId: myUserId, body: body, createdAt: DateTime.now());
  }

  @override
  Future<void> markRead({required String orderId, required String token}) async => markReadCalls++;

  @override
  Future<List<ChatThread>> fetchThreads({required String token}) async => threads;

  @override
  Future<List<AccountNotice>> fetchNotices({required String token}) async => notices;
}
