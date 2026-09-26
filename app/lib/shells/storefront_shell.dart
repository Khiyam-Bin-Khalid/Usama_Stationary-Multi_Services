import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/providers.dart';
import '../features/cart_checkout/shop_cart_provider.dart';

class StorefrontShell extends ConsumerWidget {
  final Widget child;
  const StorefrontShell({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).matchedLocation;
    final cartCount = ref.watch(shopCartProvider).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Usama Book Depot'),
        actions: [
          TextButton.icon(
            onPressed: () => context.go('/shop'),
            icon: const Icon(Icons.storefront_outlined),
            label: const Text('Shop'),
            style: TextButton.styleFrom(
              foregroundColor: location.startsWith('/shop') ? Theme.of(context).colorScheme.primary : null,
            ),
          ),
          TextButton.icon(
            onPressed: () => context.go('/orders'),
            icon: const Icon(Icons.receipt_long_outlined),
            label: const Text('My Orders'),
            style: TextButton.styleFrom(
              foregroundColor: location.startsWith('/orders') ? Theme.of(context).colorScheme.primary : null,
            ),
          ),
          IconButton(
            onPressed: () => context.go('/cart'),
            icon: Badge(
              label: Text('$cartCount'),
              isLabelVisible: cartCount > 0,
              child: const Icon(Icons.shopping_cart_outlined),
            ),
          ),
          IconButton(icon: const Icon(Icons.logout), onPressed: () => ref.read(authStateProvider.notifier).logout()),
          const SizedBox(width: 8),
        ],
      ),
      body: child,
    );
  }
}
