import 'api_client.dart';
import 'guarded.dart';
import '../models/user.dart';

class AuthResult {
  final AppUser user;
  final String accessToken;
  final String refreshToken;
  const AuthResult({required this.user, required this.accessToken, required this.refreshToken});
}

class AuthApi {
  final ApiClient client;
  AuthApi(this.client);

  Future<AuthResult> login(String email, String password) => guarded(() async {
        final res = await client.dio.post('/auth/login', data: {'email': email, 'password': password});
        return AuthResult(
          user: AppUser.fromJson(res.data['user']),
          accessToken: res.data['accessToken'],
          refreshToken: res.data['refreshToken'],
        );
      });

  Future<AuthResult> registerCustomer({required String name, required String email, required String password, String? phone}) =>
      guarded(() async {
        final res = await client.dio.post('/auth/register-customer', data: {
          'name': name,
          'email': email,
          'password': password,
          if (phone != null && phone.isNotEmpty) 'phone': phone,
        });
        return AuthResult(
          user: AppUser.fromJson(res.data['user']),
          accessToken: res.data['accessToken'],
          refreshToken: res.data['refreshToken'],
        );
      });

  Future<AppUser> me() => guarded(() async {
        final res = await client.dio.get('/auth/me');
        return AppUser.fromJson(res.data['user']);
      });

  Future<AppUser> createStaffAccount({
    required String name,
    required String email,
    required String password,
    required String role,
    String? phone,
    String? branch,
  }) =>
      guarded(() async {
        final res = await client.dio.post('/auth/staff', data: {
          'name': name,
          'email': email,
          'password': password,
          'role': role,
          if (phone != null) 'phone': phone,
          if (branch != null) 'branch': branch,
        });
        return AppUser.fromJson(res.data['user']);
      });
}
