import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/providers.dart';
import '../core/responsive.dart';
import '../core/theme/app_colors.dart';
import '../features/cart_checkout/shop_cart_provider.dart';

class _NavItem {
  final String path;
  final IconData icon;
  final IconData activeIcon;
  final String label;
  const _NavItem(this.path, this.icon, this.activeIcon, this.label);
}

const _navItems = [
  _NavItem('/shop', Icons.home_outlined, Icons.home, 'Home'),
  _NavItem('/shop/products', Icons.grid_view_outlined, Icons.grid_view, 'Products'),
  _NavItem('/shop/categories', Icons.category_outlined, Icons.category, 'Categories'),
  _NavItem('/shop/deals', Icons.local_offer_outlined, Icons.local_offer, 'Deals'),
  _NavItem('/cart', Icons.shopping_cart_outlined, Icons.shopping_cart, 'Cart'),
  _NavItem('/orders', Icons.receipt_long_outlined, Icons.receipt_long, 'Orders'),
  _NavItem('/profile', Icons.person_outline, Icons.person, 'Profile'),
];

/// Customer storefront shell. Desktop/tablet: top bar with text navigation
/// inside the responsive max-width container. Phone: compact app bar with
/// cart badge + bottom navigation. Body content is laid out by each page
/// with [ResponsiveContainer] (16 / 24 / 32 px gutters).
class StorefrontShell extends ConsumerWidget {
  final Widget child;
  const StorefrontShell({super.key, required this.child});

  int _selectedIndex(String location) {
    var best = 0;
    var bestLen = -1;
    for (var i = 0; i < _navItems.length; i++) {
      final p = _navItems[i].path;
      final matches = location == p || location.startsWith('$p/') || (p == '/shop/products' && location.startsWith('/shop/product/'));
      if (matches && p.length > bestLen) {
        best = i;
        bestLen = p.length;
      }
    }
    if (location.startsWith('/checkout')) return 4;
    return best;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).matchedLocation;
    final cart = ref.watch(shopCartProvider);
    final cartCount = cart.fold<int>(0, (s, i) => s + i.quantity.toInt());
    final selected = _selectedIndex(location);
    final phone = context.isPhone;
    final user = ref.watch(authStateProvider).valueOrNull;

    final cartButton = IconButton(
      tooltip: 'Cart',
      onPressed: () => context.go('/cart'),
      icon: Badge(
        label: Text('$cartCount'),
        isLabelVisible: cartCount > 0,
        child: Icon(selected == 4 ? Icons.shopping_cart : Icons.shopping_cart_outlined),
      ),
    );

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        toolbarHeight: phone ? 56 : 64,
        title: ResponsiveContainer(
          withVerticalPadding: false,
          child: Row(
            children: [
              InkWell(
                onTap: () => context.go('/shop'),
                child: Row(
                  children: [
                    const Icon(Icons.storefront_outlined, color: AppColors.primaryOrange),
                    const SizedBox(width: 8),
                    Text('Usama Book Depot', style: Theme.of(context).appBarTheme.titleTextStyle),
                  ],
                ),
              ),
              const Spacer(),
              if (!phone)
                for (var i = 0; i < _navItems.length; i++)
                  if (_navItems[i].path != '/cart' && _navItems[i].path != '/profile')
                    _TopLink(item: _navItems[i], selected: i == selected, onTap: () => context.go(_navItems[i].path)),
              if (!phone) const SizedBox(width: 8),
              cartButton,
              if (!phone)
                IconButton(
                  tooltip: user?.name ?? 'Profile',
                  onPressed: () => context.go('/profile'),
                  icon: Icon(selected == 6 ? Icons.person : Icons.person_outline),
                ),
            ],
          ),
        ),
      ),
      body: child,
      bottomNavigationBar: phone
          ? NavigationBar(
              selectedIndex: selected.clamp(0, _navItems.length - 1),
              onDestinationSelected: (i) => context.go(_navItems[i].path),
              labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
              height: 64,
              destinations: [
                for (final item in _navItems)
                  NavigationDestination(
                    icon: item.path == '/cart'
                        ? Badge(label: Text('$cartCount'), isLabelVisible: cartCount > 0, child: Icon(item.icon))
                        : Icon(item.icon),
                    selectedIcon: Icon(item.activeIcon),
                    label: item.label,
                  ),
              ],
            )
          : null,
    );
  }
}

class _TopLink extends StatelessWidget {
  final _NavItem item;
  final bool selected;
  final VoidCallback onTap;
  const _TopLink({required this.item, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: selected ? AppColors.primaryOrange : AppColors.textPrimary,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      child: Text(item.label, style: TextStyle(fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
    );
  }
}
