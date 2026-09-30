import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/chat_models.dart';

/// Task 78: the order-chat REST endpoints (backend ChatModule). Sending goes
/// through here, not the socket, so a message is stored before anyone sees
/// it — the socket only carries what's already saved.
class ChatRepository {
  const ChatRepository({this.client = const ApiClient()});

  final ApiClient client;

  Future<OrderChat> fetchChat({required String orderId, required String token}) async =>
      OrderChat.fromJson(await client.get('/orders/$orderId/messages', token: token) as Map<String, dynamic>);

  Future<ChatMessage> send({required String orderId, required String body, required String token}) async =>
      ChatMessage.fromJson(
        await client.post('/orders/$orderId/messages', body: {'body': body}, token: token) as Map<String, dynamic>,
      );

  Future<void> markRead({required String orderId, required String token}) =>
      client.postIdempotent('/orders/$orderId/messages/read', token: token);

  Future<List<ChatThread>> fetchThreads({required String token}) async => [
    for (final t in await client.get('/messages/threads', token: token) as List<dynamic>)
      ChatThread.fromJson(t as Map<String, dynamic>),
  ];

  Future<List<AccountNotice>> fetchNotices({required String token}) async {
    final json = await client.get('/notifications?limit=50', token: token) as Map<String, dynamic>;
    return [for (final n in json['items'] as List<dynamic>) AccountNotice.fromJson(n as Map<String, dynamic>)];
  }
}

final chatRepositoryProvider = Provider<ChatRepository>((ref) => const ChatRepository());
