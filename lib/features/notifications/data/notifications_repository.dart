import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/app_notification.dart';

final notificationsRepositoryProvider = Provider<NotificationsRepository>(
  (ref) => const NotificationsRepository(),
);

/// The backend's notification feed (NotificationsController).
class NotificationsRepository {
  const NotificationsRepository({this.client = const ApiClient()});

  final ApiClient client;

  /// Newest first.
  Future<NotificationFeed> list({required String token, int limit = 50}) async =>
      NotificationFeed.fromJson(await client.get('/notifications?limit=$limit', token: token) as Map<String, dynamic>);

  Future<void> markRead({required String id, required String token}) =>
      client.post('/notifications/${Uri.encodeComponent(id)}/read', token: token);

  Future<void> markAllRead({required String token}) => client.post('/notifications/read-all', token: token);
}
