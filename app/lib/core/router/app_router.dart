import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers.dart';
import '../roles.dart';
import '../../features/auth/login_screen.dart';
import '../../features/auth/register_screen.dart';
import '../../shells/pos_admin_shell.dart';
import '../../shells/storefront_shell.dart';
import '../../features/dashboard/dashboard_screen.dart';
import '../../features/pos/pos_screen.dart';
import '../../features/inventory/inventory_screen.dart';
import '../../features/inventory/discrepancies_screen.dart';
import '../../features/inventory/stock_movements_screen.dart';
import '../../features/reports/reports_screen.dart';
import '../../features/shift/shift_screen.dart';
import '../../features/notifications/notifications_screen.dart';
import '../../features/admin/staff_management_screen.dart';
import '../../features/admin/promotions_admin_screen.dart';
import '../../features/admin/payment_review_screen.dart';
import '../../features/admin/orders_admin_screen.dart';
import '../../features/admin/admin_order_detail_screen.dart';
import '../../features/admin/audit_log_screen.dart';
import '../../features/catalog/catalog_screen.dart';
import '../../features/catalog/product_detail_screen.dart';
import '../../features/catalog/categories_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/cart_checkout/cart_screen.dart';
import '../../features/cart_checkout/checkout_screen.dart';
import '../../features/orders/my_orders_screen.dart';
import '../../features/orders/order_detail_screen.dart';

/// Spec §1: every staff role lands on its own dashboard after login.
const _posHome = '/dashboard';
const _shopHome = '/shop';

const _posAreaPrefixes = ['/dashboard', '/pos', '/inventory', '/reports', '/shift', '/notifications', '/admin', '/settings'];
const _shopAreaPrefixes = ['/shop', '/cart', '/checkout', '/orders', '/profile'];

final goRouterProvider = Provider<GoRouter>((ref) {
  // One stable router: auth changes re-run `redirect` through the listenable
  // instead of rebuilding the router (which dropped the post-login redirect).
  final refresh = ValueNotifier<int>(0);
  ref.listen(authStateProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/login',
    refreshListenable: refresh,
    redirect: (context, state) {
      final authState = ref.read(authStateProvider);
      final location = state.matchedLocation;
      final loggingIn = location == '/login' || location == '/register';

      if (authState.isLoading) return null;
      final user = authState.valueOrNull;

      if (user == null) return loggingIn ? null : '/login';
      final isStaffRole = UserRole.isPosAdminShell(user.role);
      if (loggingIn) return isStaffRole ? _posHome : _shopHome;

      final wantsPosArea = _posAreaPrefixes.any(location.startsWith);
      final wantsShopArea = _shopAreaPrefixes.any(location.startsWith);

      if (isStaffRole && wantsShopArea) return _posHome;
      if (!isStaffRole && wantsPosArea) return _shopHome;
      // Spec §2: a role may only open the screens its permission row allows
      // (e.g. staff → /admin/*, admin → /admin/staff or /admin/audit-log).
      if (isStaffRole && wantsPosArea && !Permissions.canAccessPath(user.role, location)) return _posHome;
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(path: '/register', builder: (context, state) => const RegisterScreen()),

      ShellRoute(
        builder: (context, state, child) => PosAdminShell(child: child),
        routes: [
          GoRoute(path: '/dashboard', builder: (context, state) => const DashboardScreen()),
          GoRoute(path: '/pos', builder: (context, state) => const PosScreen()),
          GoRoute(path: '/inventory', builder: (context, state) => const InventoryScreen()),
          GoRoute(path: '/inventory/low-stock', builder: (context, state) => const InventoryScreen(initialFilter: 'low')),
          GoRoute(
            path: '/inventory/movements',
            builder: (context, state) => StockMovementsScreen(productId: state.uri.queryParameters['product']),
          ),
          GoRoute(path: '/inventory/discrepancies', builder: (context, state) => const DiscrepanciesScreen()),
          GoRoute(path: '/reports', builder: (context, state) => const ReportsScreen()),
          GoRoute(path: '/shift', builder: (context, state) => const ShiftScreen()),
          GoRoute(path: '/notifications', builder: (context, state) => const NotificationsScreen()),
          GoRoute(
            path: '/admin/orders',
            builder: (context, state) => OrdersAdminScreen(initialQueue: state.uri.queryParameters['queue']),
          ),
          GoRoute(path: '/admin/orders/:id', builder: (context, state) => AdminOrderDetailScreen(orderId: state.pathParameters['id']!)),
          GoRoute(
            path: '/admin/delivery',
            builder: (context, state) => OrdersAdminScreen(
              initialQueue: state.uri.queryParameters['queue'] ?? 'processing',
              title: 'Processing & delivery',
            ),
          ),
          GoRoute(path: '/admin/payments', builder: (context, state) => const PaymentReviewScreen()),
          GoRoute(path: '/settings', builder: (context, state) => const ProfileScreen()),
          GoRoute(path: '/admin/promotions', builder: (context, state) => const PromotionsAdminScreen()),
          GoRoute(path: '/admin/staff', builder: (context, state) => const StaffManagementScreen()),
          GoRoute(path: '/admin/audit-log', builder: (context, state) => const AuditLogScreen()),
        ],
      ),

      ShellRoute(
        builder: (context, state, child) => StorefrontShell(child: child),
        routes: [
          GoRoute(path: '/shop', builder: (context, state) => const CatalogScreen()),
          GoRoute(
            path: '/shop/products',
            builder: (context, state) => CatalogScreen(showHero: false, initialCategory: state.uri.queryParameters['category']),
          ),
          GoRoute(path: '/shop/categories', builder: (context, state) => const CategoriesScreen()),
          GoRoute(path: '/shop/deals', builder: (context, state) => const CatalogScreen(showHero: false, dealsOnly: true)),
          GoRoute(path: '/shop/product/:id', builder: (context, state) => ProductDetailScreen(productId: state.pathParameters['id']!)),
          GoRoute(path: '/profile', builder: (context, state) => const ProfileScreen()),
          GoRoute(path: '/cart', builder: (context, state) => const CartScreen()),
          GoRoute(path: '/checkout', builder: (context, state) => const CheckoutScreen()),
          GoRoute(path: '/orders', builder: (context, state) => const MyOrdersScreen()),
          GoRoute(path: '/orders/:id', builder: (context, state) => OrderDetailScreen(orderId: state.pathParameters['id']!)),
        ],
      ),
    ],
  );
});
