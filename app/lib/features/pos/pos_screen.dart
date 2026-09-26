import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/format.dart';
import '../../core/roles.dart';
import '../../core/theme/status_style.dart';
import '../../data/models/cart_item.dart';
import '../../data/models/product.dart';
import '../../data/repositories/pos_repository.dart';
import '../../core/providers.dart';
import 'pos_products_provider.dart';
import 'pos_cart_provider.dart';

class PosScreen extends ConsumerStatefulWidget {
  const PosScreen({super.key});

  @override
  ConsumerState<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends ConsumerState<PosScreen> {
  String? _category;
  String _search = '';
  bool _checkingOut = false;

  Future<void> _checkout(String paymentMethod) async {
    final cart = ref.read(posCartProvider);
    if (cart.isEmpty) return;
    setState(() => _checkingOut = true);
    try {
      final result = await ref.read(posRepositoryProvider).recordSale(items: cart, paymentMethod: paymentMethod);
      ref.read(posCartProvider.notifier).clear();
      if (!mounted) return;
      final message = result.outcome == SaleRecordOutcome.syncedOnline
          ? 'Sale recorded'
          : 'Offline — sale saved locally and will sync automatically';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not record sale: $e')));
    } finally {
      if (mounted) setState(() => _checkingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(posProductsStreamProvider);
    final cart = ref.watch(posCartProvider);
    final isWide = MediaQuery.of(context).size.width >= 900;

    final productPane = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              TextField(
                decoration: const InputDecoration(hintText: 'Search products...', prefixIcon: Icon(Icons.search)),
                onChanged: (v) => setState(() => _search = v.toLowerCase()),
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    ChoiceChip(label: const Text('All'), selected: _category == null, onSelected: (_) => setState(() => _category = null)),
                    const SizedBox(width: 6),
                    for (final c in ProductCategory.all) ...[
                      ChoiceChip(
                        label: Text(ProductCategory.label(c)),
                        selected: _category == c,
                        onSelected: (_) => setState(() => _category = c),
                      ),
                      const SizedBox(width: 6),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: productsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Could not load products: $e')),
            data: (products) {
              final filtered = products.where((p) {
                if (!p.isActive) return false;
                if (_category != null && p.category != _category) return false;
                if (_search.isNotEmpty && !p.name.toLowerCase().contains(_search)) return false;
                return true;
              }).toList();

              if (filtered.isEmpty) return const Center(child: Text('No products found'));

              return GridView.builder(
                padding: const EdgeInsets.all(12),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 220,
                  mainAxisExtent: 130,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount: filtered.length,
                itemBuilder: (context, i) => _ProductTile(product: filtered[i], onTap: () => ref.read(posCartProvider.notifier).add(filtered[i])),
              );
            },
          ),
        ),
      ],
    );

    final cartPane = _CartPanel(cart: cart, checkingOut: _checkingOut, onCheckout: _checkout);

    if (isWide) {
      return Row(
        children: [
          Expanded(flex: 3, child: productPane),
          const VerticalDivider(width: 1),
          SizedBox(width: 360, child: cartPane),
        ],
      );
    }

    return Column(
      children: [
        Expanded(child: productPane),
        SizedBox(height: 280, child: cartPane),
      ],
    );
  }
}

class _ProductTile extends StatelessWidget {
  final Product product;
  final VoidCallback onTap;
  const _ProductTile({required this.product, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final outOfStock = !product.isMadeToOrder && product.currentStock <= 0;
    return Card(
      child: InkWell(
        onTap: outOfStock ? null : onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(product.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleSmall),
              const Spacer(),
              Text(formatCurrency(product.price), style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              if (product.isMadeToOrder)
                const StatusBadge(label: 'Made to order', tone: StatusTone.info)
              else if (outOfStock)
                const StatusBadge(label: 'Out of stock', tone: StatusTone.danger)
              else if (product.isLowStock)
                StatusBadge(label: '${product.currentStock} left', tone: StatusTone.warning)
              else
                Text('${product.currentStock} in stock', style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

class _CartPanel extends ConsumerWidget {
  final List<CartItem> cart;
  final bool checkingOut;
  final void Function(String paymentMethod) onCheckout;
  const _CartPanel({required this.cart, required this.checkingOut, required this.onCheckout});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(posCartProvider.notifier);
    final total = cart.fold<double>(0, (sum, i) => sum + i.lineTotal);

    return Container(
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Text('Cart', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                if (cart.isNotEmpty) TextButton(onPressed: notifier.clear, child: const Text('Clear')),
              ],
            ),
          ),
          Expanded(
            child: cart.isEmpty
                ? const Center(child: Text('No items yet'))
                : ListView.builder(
                    itemCount: cart.length,
                    itemBuilder: (context, i) {
                      final item = cart[i];
                      return ListTile(
                        title: Text(item.product.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(formatCurrency(item.product.price)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline),
                              onPressed: () => notifier.setQuantity(item.product.id, item.quantity - 1),
                            ),
                            Text('${item.quantity}'),
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline),
                              onPressed: () => notifier.setQuantity(item.product.id, item.quantity + 1),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total'),
                    Text(formatCurrency(total), style: Theme.of(context).textTheme.titleLarge),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: cart.isEmpty || checkingOut ? null : () => onCheckout('cash'),
                        child: const Text('Cash'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: cart.isEmpty || checkingOut ? null : () => onCheckout('card'),
                        child: checkingOut
                            ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Card'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
