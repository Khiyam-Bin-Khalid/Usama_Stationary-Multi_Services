import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/responsive.dart';
import '../../core/roles.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/status_style.dart';
import '../../data/models/product.dart';
import '../../widgets/product_image.dart';
import '../cart_checkout/shop_cart_provider.dart';
import 'catalog_screen.dart';

final _productProvider = FutureProvider.autoDispose.family<Product, String>((ref, id) => ref.watch(productApiProvider).get(id));

/// Product page: large image, name, SKU, category, price, stock status,
/// description and a quantity selector before adding to the cart.
class ProductDetailScreen extends ConsumerStatefulWidget {
  final String productId;
  const ProductDetailScreen({super.key, required this.productId});

  @override
  ConsumerState<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends ConsumerState<ProductDetailScreen> {
  int _quantity = 1;

  @override
  Widget build(BuildContext context) {
    final productAsync = ref.watch(_productProvider(widget.productId));
    final promos = ref.watch(activePromotionsProvider).valueOrNull ?? const [];

    return productAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Could not load product: $e')),
      data: (product) {
        final inCart = ref.watch(shopCartProvider).where((i) => i.product.id == product.id).fold<num>(0, (s, i) => s + i.quantity);
        final maxQty = product.isMadeToOrder ? 999 : product.currentStock - inCart.toInt();
        final canBuy = product.isSellable && product.isAvailableOnline && maxQty > 0;
        final onDeal = productOnDeal(product, promos);

        final image = AspectRatio(aspectRatio: 1.2, child: ProductImage(imageUrl: product.imageUrl, width: double.infinity, radius: 16));
        final info = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                StatusBadge(label: ProductCategory.label(product.category), tone: StatusTone.info),
                if (onDeal) const StatusBadge(label: 'Deal', tone: StatusTone.danger, solid: true),
                if (product.isMadeToOrder)
                  const StatusBadge(label: 'Made to order', tone: StatusTone.info)
                else if (product.isOutOfStock)
                  const StatusBadge(label: 'Out of stock', tone: StatusTone.danger)
                else if (product.isLowStock)
                  StatusBadge(label: 'Only ${product.currentStock} left', tone: StatusTone.danger)
                else
                  const StatusBadge(label: 'In stock', tone: StatusTone.success),
              ],
            ),
            const SizedBox(height: 12),
            Text(product.name, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text('SKU ${product.sku}${product.barcode != null ? ' · Barcode ${product.barcode}' : ''}', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            Text(formatCurrency(product.price), style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: AppColors.primaryDark)),
            Text('per ${product.unit}', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            if (product.description != null && product.description!.isNotEmpty) ...[
              Text('Description', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(product.description!),
              const SizedBox(height: 16),
            ],
            if (canBuy) ...[
              Row(
                children: [
                  const Text('Quantity', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(width: 12),
                  IconButton(icon: const Icon(Icons.remove_circle_outline), onPressed: _quantity > 1 ? () => setState(() => _quantity--) : null),
                  Text('$_quantity', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  IconButton(icon: const Icon(Icons.add_circle_outline), onPressed: _quantity < maxQty ? () => setState(() => _quantity++) : null),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    final notifier = ref.read(shopCartProvider.notifier);
                    notifier.add(product);
                    if (_quantity > 1) notifier.setQuantity(product.id, inCart + _quantity);
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text('$_quantity × ${product.name} added to cart'),
                      action: SnackBarAction(label: 'View cart', textColor: AppColors.primaryOrange, onPressed: () => context.go('/cart')),
                    ));
                  },
                  icon: const Icon(Icons.add_shopping_cart_outlined),
                  label: const Text('Add to cart'),
                ),
              ),
            ] else
              const Text('This product is currently unavailable for online ordering.', style: TextStyle(color: AppColors.accentRed)),
          ],
        );

        return SingleChildScrollView(
          child: ResponsiveContainer(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextButton.icon(onPressed: () => context.go('/shop/products'), icon: const Icon(Icons.arrow_back, size: 18), label: const Text('All products')),
                const SizedBox(height: 8),
                if (context.isPhone) ...[image, const SizedBox(height: 16), info] else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 5, child: image),
                      const SizedBox(width: 32),
                      Expanded(flex: 6, child: info),
                    ],
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
