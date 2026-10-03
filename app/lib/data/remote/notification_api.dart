import 'api_client.dart';
import 'guarded.dart';
import '../models/notification.dart';

class NotificationApi {
  final ApiClient client;
  NotificationApi(this.client);

  Future<List<AppNotification>> list({bool unreadOnly = false}) => guarded(() async {
        final res = await client.dio.get('/notifications', queryParameters: {'unreadOnly': unreadOnly, 'limit': 100});
        return (res.data['notifications'] as List).map((e) => AppNotification.fromJson(e)).toList();
      });

  Future<int> unreadCount() => guarded(() async {
        final res = await client.dio.get('/notifications/unread-count');
        return (res.data['unread'] as num).toInt();
      });

  Future<void> markRead(String id) => guarded(() => client.dio.patch('/notifications/$id/read'));

  Future<void> markAllRead() => guarded(() => client.dio.post('/notifications/read-all'));
}
