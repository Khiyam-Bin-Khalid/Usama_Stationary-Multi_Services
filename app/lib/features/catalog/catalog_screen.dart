import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/roles.dart';
import '../../core/theme/status_style.dart';
import '../../data/models/product.dart';
import '../../data/models/promotion.dart';
import '../cart_checkout/shop_cart_provider.dart';

final _catalogProductsProvider =
    FutureProvider.autoDispose<List<Product>>((ref) => ref.watch(productApiProvider).list(isAvailableOnline: true));
final _activePromotionsProvider = FutureProvider.autoDispose<List<Promotion>>((ref) => ref.watch(promotionApiProvider).active());

class CatalogScreen extends ConsumerStatefulWidget {
  const CatalogScreen({super.key});

  @override
  ConsumerState<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends ConsumerState<CatalogScreen> {
  String? _category;

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(_catalogProductsProvider);
    final promotionsAsync = ref.watch(_activePromotionsProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(_catalogProductsProvider);
        ref.invalidate(_activePromotionsProvider);
      },
      child: CustomScrollView(
        slivers: [
          promotionsAsync.maybeWhen(
            data: (promotions) => promotions.isEmpty
                ? const SliverToBoxAdapter(child: SizedBox.shrink())
                : SliverToBoxAdapter(child: _PromotionsBanner(promotions: promotions)),
            orElse: () => const SliverToBoxAdapter(child: SizedBox.shrink()),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: SingleChildScrollView(
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
            ),
          ),
          productsAsync.when(
            loading: () => const SliverFillRemaining(child: Center(child: CircularProgressIndicator())),
            error: (e, _) => SliverFillRemaining(child: Center(child: Text('Could not load products: $e'))),
            data: (products) {
              final filtered = _category == null ? products : products.where((p) => p.category == _category).toList();
              if (filtered.isEmpty) return const SliverFillRemaining(child: Center(child: Text('No products found')));
              return SliverPadding(
                padding: const EdgeInsets.all(12),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 240,
                    mainAxisExtent: 220,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => _StorefrontProductCard(product: filtered[i]),
                    childCount: filtered.length,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _PromotionsBanner extends StatelessWidget {
  final List<Promotion> promotions;
  const _PromotionsBanner({required this.promotions});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 72,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        scrollDirection: Axis.horizontal,
        itemCount: promotions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final promo = promotions[i];
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                Theme.of(context).colorScheme.primary,
                Theme.of(context).colorScheme.primary.withValues(alpha: 0.75),
              ]),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(promo.name,
                    style: TextStyle(color: Theme.of(context).colorScheme.onPrimary, fontWeight: FontWeight.bold)),
                Text(promo.discountLabel, style: TextStyle(color: Theme.of(context).colorScheme.onPrimary, fontSize: 12)),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _StorefrontProductCard extends ConsumerWidget {
  final Product product;
  const _StorefrontProductCard({required this.product});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final outOfStock = !product.isMadeToOrder && product.currentStock <= 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(ProductCategory.label(product.category), style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: 4),
            Expanded(child: Text(product.name, maxLines: 3, overflow: TextOverflow.ellipsis)),
            const SizedBox(height: 8),
            Text(formatCurrency(product.price), style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (outOfStock)
              const StatusBadge(label: 'Out of stock', tone: StatusTone.danger)
            else
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    ref.read(shopCartProvider.notifier).add(product);
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${product.name} added to cart'), duration: const Duration(seconds: 1)));
                  },
                  child: const Text('Add to cart'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
