import '../models/user.dart';
import '../remote/auth_api.dart';
import '../remote/token_storage.dart';

class AuthRepository {
  final AuthApi authApi;
  final TokenStorage tokenStorage;

  AuthRepository({required this.authApi, required this.tokenStorage});

  Future<AppUser> login(String email, String password) async {
    final result = await authApi.login(email, password);
    await tokenStorage.save(accessToken: result.accessToken, refreshToken: result.refreshToken, role: result.user.role);
    return result.user;
  }

  Future<AppUser> registerCustomer({required String name, required String email, required String password, String? phone}) async {
    final result = await authApi.registerCustomer(name: name, email: email, password: password, phone: phone);
    await tokenStorage.save(accessToken: result.accessToken, refreshToken: result.refreshToken, role: result.user.role);
    return result.user;
  }

  Future<AppUser?> currentUser() async {
    final token = await tokenStorage.accessToken;
    if (token == null) return null;
    try {
      return await authApi.me();
    } catch (_) {
      return null;
    }
  }

  Future<void> logout() => tokenStorage.clear();
}
