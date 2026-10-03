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
import '../../data/models/promotion.dart';
import '../../widgets/product_image.dart';
import '../cart_checkout/shop_cart_provider.dart';

final catalogProductsProvider =
    FutureProvider.autoDispose<List<Product>>((ref) => ref.watch(productApiProvider).list(isAvailableOnline: true, sellableOnly: true));
final activePromotionsProvider = FutureProvider.autoDispose<List<Promotion>>((ref) => ref.watch(promotionApiProvider).active());

bool productOnDeal(Product p, List<Promotion> promos) =>
    promos.any((promo) => promo.categories.isEmpty || promo.categories.contains(p.category));

/// Storefront home / products page. [showHero] renders the welcome banner +
/// promotions strip (home); the Products page is the same grid with the
/// category / search controls only. [dealsOnly] limits to promoted items.
class CatalogScreen extends ConsumerStatefulWidget {
  final bool showHero;
  final String? initialCategory;
  final bool dealsOnly;
  const CatalogScreen({super.key, this.showHero = true, this.initialCategory, this.dealsOnly = false});

  @override
  ConsumerState<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends ConsumerState<CatalogScreen> {
  String? _category;
  String _search = '';
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _category = widget.initialCategory;
  }

  @override
  void didUpdateWidget(covariant CatalogScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialCategory != widget.initialCategory) _category = widget.initialCategory;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(catalogProductsProvider);
    final promotionsAsync = ref.watch(activePromotionsProvider);
    final gutter = context.gutter;

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(catalogProductsProvider);
        ref.invalidate(activePromotionsProvider);
      },
      child: CustomScrollView(
        slivers: [
          if (widget.showHero)
            SliverResponsivePadding(
              sliver: SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.only(top: 16), child: _Hero(onShop: () => context.go('/shop/products')))),
            ),
          promotionsAsync.maybeWhen(
            data: (promotions) => promotions.isEmpty || !(widget.showHero || widget.dealsOnly)
                ? const SliverToBoxAdapter(child: SizedBox.shrink())
                : SliverResponsivePadding(sliver: SliverToBoxAdapter(child: _PromotionsBanner(promotions: promotions))),
            orElse: () => const SliverToBoxAdapter(child: SizedBox.shrink()),
          ),
          SliverResponsivePadding(
            sliver: SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: 16, bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.dealsOnly ? 'Deals' : (widget.showHero ? 'Shop by category' : 'Products'),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Search products by name or SKU',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _search.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.close),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _search = '');
                                },
                              ),
                      ),
                      onChanged: (v) => setState(() => _search = v.trim().toLowerCase()),
                    ),
                    const SizedBox(height: 10),
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
            ),
          ),
          productsAsync.when(
            loading: () => const SliverFillRemaining(child: Center(child: CircularProgressIndicator())),
            error: (e, _) => SliverFillRemaining(child: Center(child: Text('Could not load products: $e'))),
            data: (products) {
              final promos = promotionsAsync.valueOrNull ?? const <Promotion>[];
              final filtered = products.where((p) {
                if (!p.isSellable) return false;
                if (_category != null && p.category != _category) return false;
                if (widget.dealsOnly && !productOnDeal(p, promos)) return false;
                if (_search.isNotEmpty && !p.name.toLowerCase().contains(_search) && !p.sku.toLowerCase().contains(_search)) return false;
                return true;
              }).toList();
              if (filtered.isEmpty) {
                return const SliverFillRemaining(hasScrollBody: false, child: Padding(padding: EdgeInsets.all(32), child: Center(child: Text('No products found'))));
              }
              return SliverResponsivePadding(
                sliver: SliverPadding(
                  padding: EdgeInsets.only(top: 8, bottom: gutter + 16),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: context.productGridColumns,
                      mainAxisExtent: context.isPhone ? 300 : 330,
                      crossAxisSpacing: context.isPhone ? 12 : 16,
                      mainAxisSpacing: context.isPhone ? 12 : 16,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, i) => StorefrontProductCard(product: filtered[i], onDeal: productOnDeal(filtered[i], promos)),
                      childCount: filtered.length,
                    ),
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

class _Hero extends StatelessWidget {
  final VoidCallback onShop;
  const _Hero({required this.onShop});

  @override
  Widget build(BuildContext context) {
    final phone = context.isPhone;
    return Container(
      padding: EdgeInsets.all(phone ? 20 : 32),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(colors: [AppColors.primaryOrange, AppColors.primaryDark]),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Usama Book Depot',
                    style: TextStyle(color: Colors.white, fontSize: phone ? 22 : 30, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                const Text(
                  'Stationery, grocery, sporting goods and printing services — delivered to your door.',
                  style: TextStyle(color: Colors.white, fontSize: 14),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppColors.primaryDark),
                  onPressed: onShop,
                  child: const Text('Shop all products'),
                ),
              ],
            ),
          ),
          if (!phone) const Icon(Icons.storefront_outlined, size: 96, color: Colors.white70),
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
      height: 80,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 12),
        scrollDirection: Axis.horizontal,
        itemCount: promotions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final promo = promotions[i];
          return InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => context.go('/shop/deals'),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(color: AppColors.tint(AppColors.accentRed), borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.accentRed)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(promo.name, style: const TextStyle(color: AppColors.accentRed, fontWeight: FontWeight.bold)),
                  Text(
                    '${promo.discountLabel}${promo.categories.isEmpty ? ' · all products' : ' · ${promo.categories.map(ProductCategory.label).join(', ')}'}',
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Product card: image, category, name, SKU, price, stock, add-to-cart.
class StorefrontProductCard extends ConsumerWidget {
  final Product product;
  final bool onDeal;
  const StorefrontProductCard({super.key, required this.product, this.onDeal = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final outOfStock = product.isOutOfStock;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.go('/shop/product/${product.id}'),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  AspectRatio(aspectRatio: 1.3, child: ProductImage(imageUrl: product.imageUrl, width: double.infinity)),
                  if (onDeal) const Positioned(top: 6, left: 6, child: StatusBadge(label: 'Deal', tone: StatusTone.danger, solid: true)),
                  if (product.isLowStock)
                    Positioned(top: 6, right: 6, child: StatusBadge(label: 'Only ${product.currentStock} left', tone: StatusTone.danger)),
                ],
              ),
              const SizedBox(height: 8),
              Text(ProductCategory.label(product.category), style: Theme.of(context).textTheme.labelSmall),
              const SizedBox(height: 2),
              Expanded(
                child: Text(product.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              ),
              Text('SKU ${product.sku}', style: Theme.of(context).textTheme.labelSmall),
              const SizedBox(height: 4),
              Text(formatCurrency(product.price), style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              if (outOfStock)
                const StatusBadge(label: 'Out of stock', tone: StatusTone.danger)
              else
                SizedBox(
                  width: double.infinity,
                  height: 40,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12)),
                    onPressed: () {
                      ref.read(shopCartProvider.notifier).add(product);
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text('${product.name} added to cart'),
                        duration: const Duration(seconds: 2),
                        action: SnackBarAction(label: 'View cart', textColor: AppColors.primaryOrange, onPressed: () => context.go('/cart')),
                      ));
                    },
                    icon: const Icon(Icons.add_shopping_cart_outlined, size: 18),
                    label: const Text('Add to cart'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
