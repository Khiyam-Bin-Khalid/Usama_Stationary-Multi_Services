import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/local/app_database.dart';
import '../data/models/user.dart';
import '../data/remote/api_client.dart';
import '../data/remote/auth_api.dart';
import '../data/remote/order_api.dart';
import '../data/remote/payment_api.dart';
import '../data/remote/product_api.dart';
import '../data/remote/promotion_api.dart';
import '../data/remote/report_api.dart';
import '../data/remote/sale_api.dart';
import '../data/remote/sync_api.dart';
import '../data/remote/token_storage.dart';
import '../data/remote/user_api.dart';
import '../data/repositories/auth_repository.dart';
import '../data/repositories/pos_repository.dart';
import '../data/repositories/sync_service.dart';

/// True on every target except web — see connection_web.dart for why web
/// doesn't get a local SQLite cache.
final localDbAvailableProvider = Provider<bool>((ref) => !kIsWeb);

final tokenStorageProvider = Provider((ref) => TokenStorage());
final apiClientProvider = Provider((ref) => ApiClient(ref.watch(tokenStorageProvider)));

final authApiProvider = Provider((ref) => AuthApi(ref.watch(apiClientProvider)));
final productApiProvider = Provider((ref) => ProductApi(ref.watch(apiClientProvider)));
final saleApiProvider = Provider((ref) => SaleApi(ref.watch(apiClientProvider)));
final syncApiProvider = Provider((ref) => SyncApi(ref.watch(apiClientProvider)));
final reportApiProvider = Provider((ref) => ReportApi(ref.watch(apiClientProvider)));
final promotionApiProvider = Provider((ref) => PromotionApi(ref.watch(apiClientProvider)));
final orderApiProvider = Provider((ref) => OrderApi(ref.watch(apiClientProvider)));
final paymentApiProvider = Provider((ref) => PaymentApi(ref.watch(apiClientProvider)));
final userApiProvider = Provider((ref) => UserApi(ref.watch(apiClientProvider)));

final authRepositoryProvider =
    Provider((ref) => AuthRepository(authApi: ref.watch(authApiProvider), tokenStorage: ref.watch(tokenStorageProvider)));

/// Null on web — see localDbAvailableProvider.
final appDatabaseProvider = Provider<AppDatabase?>((ref) {
  if (kIsWeb) return null;
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final posRepositoryProvider =
    Provider((ref) => PosRepository(db: ref.watch(appDatabaseProvider), saleApi: ref.watch(saleApiProvider)));

final syncServiceProvider = Provider<SyncService?>((ref) {
  final db = ref.watch(appDatabaseProvider);
  if (db == null) return null;
  final service = SyncService(
    db: db,
    productApi: ref.watch(productApiProvider),
    promotionApi: ref.watch(promotionApiProvider),
    syncApi: ref.watch(syncApiProvider),
  );
  service.start();
  ref.onDispose(service.dispose);
  return service;
});

/// Current authenticated user, resolved once at startup and updated by
/// login/logout. AsyncValue.loading() while we check for a stored token.
class AuthState extends AsyncNotifier<AppUser?> {
  @override
  Future<AppUser?> build() => ref.watch(authRepositoryProvider).currentUser();

  Future<void> login(String email, String password) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => ref.read(authRepositoryProvider).login(email, password));
  }

  Future<void> registerCustomer({required String name, required String email, required String password, String? phone}) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => ref.read(authRepositoryProvider).registerCustomer(name: name, email: email, password: password, phone: phone),
    );
  }

  Future<void> logout() async {
    await ref.read(authRepositoryProvider).logout();
    state = const AsyncValue.data(null);
  }
}

final authStateProvider = AsyncNotifierProvider<AuthState, AppUser?>(AuthState.new);
