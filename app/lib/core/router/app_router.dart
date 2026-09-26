import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers.dart';
import '../roles.dart';
import '../../features/auth/login_screen.dart';
import '../../features/auth/register_screen.dart';
import '../../shells/pos_admin_shell.dart';
import '../../shells/storefront_shell.dart';
import '../../features/pos/pos_screen.dart';
import '../../features/inventory/inventory_screen.dart';
import '../../features/reports/reports_screen.dart';
import '../../features/admin/staff_management_screen.dart';
import '../../features/admin/promotions_admin_screen.dart';
import '../../features/admin/payment_review_screen.dart';
import '../../features/admin/orders_admin_screen.dart';
import '../../features/catalog/catalog_screen.dart';
import '../../features/cart_checkout/cart_screen.dart';
import '../../features/cart_checkout/checkout_screen.dart';
import '../../features/orders/my_orders_screen.dart';
import '../../features/orders/order_detail_screen.dart';

const _posHome = '/pos';
const _shopHome = '/shop';

final goRouterProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authStateProvider);

  return GoRouter(
    initialLocation: '/login',
    redirect: (context, state) {
      final loggingIn = state.matchedLocation == '/login' || state.matchedLocation == '/register';

      if (authState.isLoading) return null;
      final user = authState.valueOrNull;

      if (user == null) return loggingIn ? null : '/login';
      if (loggingIn) return UserRole.isPosAdminShell(user.role) ? _posHome : _shopHome;

      final wantsPosArea = state.matchedLocation.startsWith('/pos') ||
          state.matchedLocation.startsWith('/inventory') ||
          state.matchedLocation.startsWith('/reports') ||
          state.matchedLocation.startsWith('/admin');
      final wantsShopArea = state.matchedLocation.startsWith('/shop') ||
          state.matchedLocation.startsWith('/cart') ||
          state.matchedLocation.startsWith('/checkout') ||
          state.matchedLocation.startsWith('/orders');

      if (UserRole.isPosAdminShell(user.role) && wantsShopArea) return _posHome;
      if (!UserRole.isPosAdminShell(user.role) && wantsPosArea) return _shopHome;
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(path: '/register', builder: (context, state) => const RegisterScreen()),

      ShellRoute(
        builder: (context, state, child) => PosAdminShell(child: child),
        routes: [
          GoRoute(path: '/pos', builder: (context, state) => const PosScreen()),
          GoRoute(path: '/inventory', builder: (context, state) => const InventoryScreen()),
          GoRoute(path: '/reports', builder: (context, state) => const ReportsScreen()),
          GoRoute(path: '/admin/staff', builder: (context, state) => const StaffManagementScreen()),
          GoRoute(path: '/admin/promotions', builder: (context, state) => const PromotionsAdminScreen()),
          GoRoute(path: '/admin/payments', builder: (context, state) => const PaymentReviewScreen()),
          GoRoute(path: '/admin/orders', builder: (context, state) => const OrdersAdminScreen()),
        ],
      ),

      ShellRoute(
        builder: (context, state, child) => StorefrontShell(child: child),
        routes: [
          GoRoute(path: '/shop', builder: (context, state) => const CatalogScreen()),
          GoRoute(path: '/cart', builder: (context, state) => const CartScreen()),
          GoRoute(path: '/checkout', builder: (context, state) => const CheckoutScreen()),
          GoRoute(path: '/orders', builder: (context, state) => const MyOrdersScreen()),
          GoRoute(path: '/orders/:id', builder: (context, state) => OrderDetailScreen(orderId: state.pathParameters['id']!)),
        ],
      ),
    ],
  );
});
