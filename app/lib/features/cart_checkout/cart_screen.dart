import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/format.dart';
import '../../core/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/cart_item.dart';
import '../../widgets/product_image.dart';
import 'shop_cart_provider.dart';

/// Cart: every line shows the selected product image, name, SKU, unit price,
/// quantity controls, line total and a remove button (consolidated spec).
class CartScreen extends ConsumerWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(shopCartProvider);
    final notifier = ref.read(shopCartProvider.notifier);
    final subtotal = cart.fold<double>(0, (sum, i) => sum + i.lineTotal);
    final count = cart.fold<int>(0, (sum, i) => sum + i.quantity.toInt());

    if (cart.isEmpty) {
      return ResponsiveContainer(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.shopping_cart_outlined, size: 56, color: AppColors.textSecondary),
              const SizedBox(height: 12),
              Text('Your cart is empty', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 16),
              FilledButton(onPressed: () => context.go('/shop'), child: const Text('Browse products')),
            ],
          ),
        ),
      );
    }

    final list = Column(
      children: [
        for (final item in cart) ...[
          _CartLine(item: item, onQuantity: (q) => notifier.setQuantity(item.product.id, q), onRemove: () => notifier.remove(item.product.id)),
          const Divider(),
        ],
      ],
    );

    final summary = Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Order summary', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [Text('Items ($count)'), Text(formatCurrency(subtotal))],
            ),
            const SizedBox(height: 4),
            Text('Discounts, delivery charges and tax are shown at checkout.', style: Theme.of(context).textTheme.bodySmall),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Subtotal', style: TextStyle(fontWeight: FontWeight.w600)),
                Text(formatCurrency(subtotal), style: Theme.of(context).textTheme.titleLarge),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => context.go('/checkout'),
              icon: const Icon(Icons.lock_outline, size: 18),
              label: const Text('Proceed to checkout'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: () => context.go('/shop'), child: const Text('Continue shopping')),
          ],
        ),
      ),
    );

    return SingleChildScrollView(
      child: ResponsiveContainer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Your cart', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 16),
            if (context.isDesktop)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: list),
                  const SizedBox(width: 24),
                  SizedBox(width: 340, child: summary),
                ],
              )
            else ...[
              list,
              const SizedBox(height: 16),
              summary,
            ],
          ],
        ),
      ),
    );
  }
}

class _CartLine extends StatelessWidget {
  final CartItem item;
  final void Function(num) onQuantity;
  final VoidCallback onRemove;
  const _CartLine({required this.item, required this.onQuantity, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final p = item.product;
    final phone = context.isPhone;
    final maxQty = p.isMadeToOrder ? 999 : p.currentStock;
    final qtyControls = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Decrease',
          icon: const Icon(Icons.remove_circle_outline),
          onPressed: () => onQuantity(item.quantity - 1),
        ),
        Text('${item.quantity}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        IconButton(
          tooltip: 'Increase',
          icon: const Icon(Icons.add_circle_outline),
          onPressed: item.quantity >= maxQty ? null : () => onQuantity(item.quantity + 1),
        ),
      ],
    );
    final remove = TextButton.icon(
      onPressed: onRemove,
      icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.accentRed),
      label: const Text('Remove', style: TextStyle(color: AppColors.accentRed)),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ProductImage(imageUrl: p.imageUrl, size: phone ? 72 : 96),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15), maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text('SKU ${p.sku}', style: Theme.of(context).textTheme.bodySmall),
                Text('Unit price ${formatCurrency(p.price)}', style: Theme.of(context).textTheme.bodySmall),
                if (!p.isMadeToOrder && item.quantity >= p.currentStock)
                  Text('Only ${p.currentStock} available', style: const TextStyle(color: AppColors.accentRed, fontSize: 12)),
                const SizedBox(height: 6),
                if (phone)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      qtyControls,
                      Text(formatCurrency(item.lineTotal), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    ],
                  ),
                if (phone) Align(alignment: Alignment.centerLeft, child: remove),
              ],
            ),
          ),
          if (!phone) ...[
            qtyControls,
            const SizedBox(width: 16),
            SizedBox(
              width: 110,
              child: Text(formatCurrency(item.lineTotal), textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            ),
            const SizedBox(width: 8),
            IconButton(tooltip: 'Remove', icon: const Icon(Icons.delete_outline, color: AppColors.accentRed), onPressed: onRemove),
          ],
        ],
      ),
    );
  }
}
