import 'api_client.dart';
import 'guarded.dart';

class AuditApi {
  final ApiClient client;
  AuditApi(this.client);

  /// Superadmin only. Each entry: {_id, action, actor:{name,email,role},
  /// actorRole, entityType, entityId, before, after, details, createdAt}.
  Future<List<Map<String, dynamic>>> list({String? action, int page = 1, int limit = 100}) => guarded(() async {
        final res = await client.dio.get('/audit-logs', queryParameters: {
          if (action != null && action.isNotEmpty) 'action': action,
          'page': page,
          'limit': limit,
        });
        return List<Map<String, dynamic>>.from(res.data['logs']);
      });
}
