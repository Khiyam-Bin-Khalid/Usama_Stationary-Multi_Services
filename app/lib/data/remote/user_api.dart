import 'api_client.dart';
import 'guarded.dart';
import '../models/user.dart';

class UserApi {
  final ApiClient client;
  UserApi(this.client);

  Future<List<AppUser>> list({String? role}) => guarded(() async {
        final res = await client.dio.get('/users', queryParameters: {if (role != null) 'role': role});
        return (res.data['users'] as List).map((e) => AppUser.fromJson(e)).toList();
      });

  Future<AppUser> update(String id, Map<String, dynamic> payload) => guarded(() async {
        final res = await client.dio.patch('/users/$id', data: payload);
        return AppUser.fromJson(res.data['user']);
      });

  Future<AppUser> changeRole(String id, String role) => guarded(() async {
        final res = await client.dio.patch('/users/$id/role', data: {'role': role});
        return AppUser.fromJson(res.data['user']);
      });

  Future<void> delete(String id) => guarded(() => client.dio.delete('/users/$id'));
}
