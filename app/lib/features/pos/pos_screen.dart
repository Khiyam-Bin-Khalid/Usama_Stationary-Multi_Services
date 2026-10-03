import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/format.dart';
import '../../core/theme/app_colors.dart';
import '../../core/roles.dart';
import '../../core/theme/status_style.dart';
import '../../data/models/cart_item.dart';
import '../../data/models/product.dart';
import '../../data/models/sale.dart';
import '../../data/remote/api_client.dart';
import '../../data/repositories/pos_repository.dart';
import '../../core/providers.dart';
import '../../widgets/product_image.dart';
import 'pos_products_provider.dart';
import 'pos_cart_provider.dart';

/// Sales section: "Daily Sale" (today's sold-out products, read-only —
/// staff see only their own, Admin/Super Admin see everyone's) and
/// "New Sale" (the POS quick-sell flow — recording a sale here deducts
/// inventory stock immediately, spec §4.1).
class PosScreen extends StatelessWidget {
  const PosScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const Material(
            color: AppColors.surface,
            child: TabBar(
              tabs: [
                Tab(text: 'Daily Sale'),
                Tab(text: 'New Sale'),
              ],
            ),
          ),
          const Expanded(
            child: TabBarView(children: [_DailySaleTab(), _NewSaleTab()]),
          ),
        ],
      ),
    );
  }
}

/// Today's sales — tries the live API first; falls back to the local
/// [LocalSalesCache] when the device is offline so the tab never goes blank.
final _todaySalesProvider = FutureProvider.autoDispose<List<Sale>>((ref) async {
  final now = DateTime.now();
  final startOfDay = DateTime(now.year, now.month, now.day);
  try {
    return await ref.watch(saleApiProvider).listSales(from: startOfDay, to: now);
  } on ApiException catch (e) {
    if (!e.isNetworkError) rethrow;
    // Offline — serve from the local cache seeded by PosRepository.
    final db = ref.read(appDatabaseProvider);
    if (db == null) rethrow;
    return db.localSalesInRange(startOfDay, now);
  }
});

/// Flattened per-product view of today's sales — "which products sold out
/// today", not just invoice totals — so staff/admin can see it at a glance.
class _DailySaleTab extends ConsumerWidget {
  const _DailySaleTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final salesAsync = ref.watch(_todaySalesProvider);
    final role =
        ref.watch(authStateProvider).valueOrNull?.role ?? UserRole.staff;
    final showCashier = role != UserRole.staff;

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(_todaySalesProvider),
      child: salesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            Center(child: Text('Could not load today\'s sales: $e')),
        data: (sales) {
          final rows = <(Sale, SaleLineItem)>[
            for (final sale in sales)
              for (final item in sale.items) (sale, item),
          ]..sort((a, b) => b.$1.createdAt.compareTo(a.$1.createdAt));

          final totalRevenue = sales.fold<double>(0, (sum, s) => sum + s.total);
          final totalItems = rows.fold<double>(
            0,
            (sum, r) => sum + r.$2.quantity,
          );

          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Row(
                children: [
                  Expanded(
                    child: _SummaryCard(
                      label: 'Revenue today',
                      value: formatCurrency(totalRevenue),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _SummaryCard(
                      label: 'Items sold today',
                      value: totalItems.toStringAsFixed(
                        totalItems == totalItems.roundToDouble() ? 0 : 2,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (rows.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 40),
                  child: Center(child: Text('No products sold yet today')),
                )
              else
                Card(
                  child: Column(
                    children: [
                      for (final (sale, item) in rows) ...[
                        ListTile(
                          leading: ProductImage(imageUrl: item.imageUrl, size: 40),
                          title: Text(
                            item.name,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            '${ProductCategory.label(item.category)} · ${item.quantity.toStringAsFixed(item.quantity == item.quantity.roundToDouble() ? 0 : 2)} × ${formatCurrency(item.unitPrice)}'
                            '${showCashier && sale.cashierName != null ? '\nSold by ${sale.cashierName}' : ''}',
                          ),
                          isThreeLine: showCashier && sale.cashierName != null,
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                formatCurrency(item.lineTotal),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                formatTime(sale.createdAt),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1),
                      ],
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String label;
  final String value;
  const _SummaryCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 6),
            Text(value, style: Theme.of(context).textTheme.titleLarge),
          ],
        ),
      ),
    );
  }
}

class _NewSaleTab extends ConsumerStatefulWidget {
  const _NewSaleTab();

  @override
  ConsumerState<_NewSaleTab> createState() => _NewSaleTabState();
}

class _NewSaleTabState extends ConsumerState<_NewSaleTab> {
  String? _category;
  String _search = '';
  bool _checkingOut = false;

  Future<void> _checkout(String paymentMethod) async {
    final cart = ref.read(posCartProvider);
    if (cart.isEmpty) return;
    setState(() => _checkingOut = true);
    try {
      final cashierName = ref.read(authStateProvider).valueOrNull?.name;
      final result = await ref
          .read(posRepositoryProvider)
          .recordSale(
            items: cart,
            paymentMethod: paymentMethod,
            cashierName: cashierName,
          );
      ref.read(posCartProvider.notifier).clear();
      if (!mounted) return;
      ref.invalidate(currentShiftProvider);
      ref.invalidate(_todaySalesProvider);
      final online = result.outcome == SaleRecordOutcome.syncedOnline;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            online
                ? 'Sale recorded'
                : 'Offline — sale saved locally and will sync automatically',
          ),
          backgroundColor: online ? AppColors.success : AppColors.primaryOrange,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not record sale: $e'),
          backgroundColor: AppColors.accentRed,
        ),
      );
    } finally {
      if (mounted) setState(() => _checkingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(posProductsStreamProvider);
    final cart = ref.watch(posCartProvider);
    final isWide = MediaQuery.of(context).size.width >= 900;
    final shiftOpen = ref.watch(currentShiftProvider).valueOrNull != null;

    final productPane = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!shiftOpen)
          Container(
            color: AppColors.tint(AppColors.primaryOrange),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                const Icon(
                  Icons.schedule_outlined,
                  size: 16,
                  color: AppColors.primaryDark,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'No shift open — open one so sales are tied to your cash drawer.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.primaryDark,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => context.go('/shift'),
                  child: const Text('Open shift'),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              TextField(
                decoration: const InputDecoration(
                  hintText: 'Search products...',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (v) => setState(() => _search = v.toLowerCase()),
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    ChoiceChip(
                      label: const Text('All'),
                      selected: _category == null,
                      onSelected: (_) => setState(() => _category = null),
                    ),
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
                if (!p.isSellable)
                  return false; // spec §4.1: out-of-stock hidden from quick-sell
                if (_category != null && p.category != _category) return false;
                if (_search.isNotEmpty &&
                    !p.name.toLowerCase().contains(_search))
                  return false;
                return true;
              }).toList();

              if (filtered.isEmpty)
                return const Center(child: Text('No products found'));

              return GridView.builder(
                padding: const EdgeInsets.all(12),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 220,
                  mainAxisExtent: 148,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount: filtered.length,
                itemBuilder: (context, i) => _ProductTile(
                  product: filtered[i],
                  onTap: () =>
                      ref.read(posCartProvider.notifier).add(filtered[i]),
                ),
              );
            },
          ),
        ),
      ],
    );

    final cartPane = _CartPanel(
      cart: cart,
      checkingOut: _checkingOut,
      onCheckout: _checkout,
    );

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
    final outOfStock = product.isOutOfStock;
    return Card(
      child: InkWell(
        onTap: outOfStock ? null : onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ProductImage(imageUrl: product.imageUrl, size: 44),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        Text(product.sku, style: Theme.of(context).textTheme.labelSmall),
                      ],
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Text(
                formatCurrency(product.price),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              if (product.isMadeToOrder)
                const StatusBadge(label: 'Made to order', tone: StatusTone.info)
              else if (outOfStock)
                const StatusBadge(
                  label: 'Out of stock',
                  tone: StatusTone.danger,
                )
              else if (product.isLowStock)
                StatusBadge(
                  label: 'Only ${product.currentStock} left',
                  tone: StatusTone.danger,
                )
              else
                Text(
                  '${product.currentStock} in stock',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CartPanel extends ConsumerStatefulWidget {
  final List<CartItem> cart;
  final bool checkingOut;
  final void Function(String paymentMethod) onCheckout;
  const _CartPanel({
    required this.cart,
    required this.checkingOut,
    required this.onCheckout,
  });

  @override
  ConsumerState<_CartPanel> createState() => _CartPanelState();
}

class _CartPanelState extends ConsumerState<_CartPanel> {
  String _paymentMethod = 'cash';

  @override
  Widget build(BuildContext context) {
    final cart = widget.cart;
    final checkingOut = widget.checkingOut;
    final notifier = ref.read(posCartProvider.notifier);
    final total = cart.fold<double>(0, (sum, i) => sum + i.lineTotal);

    return Container(
      color: AppColors.surface,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(
                  Icons.shopping_cart_outlined,
                  color: cart.isEmpty
                      ? AppColors.textSecondary
                      : AppColors.primaryOrange,
                ),
                const SizedBox(width: 8),
                Text(
                  'Cart (${cart.length})',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                if (cart.isNotEmpty)
                  TextButton(
                    onPressed: notifier.clear,
                    child: const Text('Clear'),
                  ),
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
                        leading: ProductImage(imageUrl: item.product.imageUrl, size: 40),
                        title: Text(
                          item.product.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text('${item.product.sku} · ${formatCurrency(item.product.price)}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline),
                              onPressed: () => notifier.setQuantity(
                                item.product.id,
                                item.quantity - 1,
                              ),
                            ),
                            Text('${item.quantity}'),
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline),
                              onPressed: () => notifier.setQuantity(
                                item.product.id,
                                item.quantity + 1,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.close,
                                color: AppColors.accentRed,
                                size: 18,
                              ),
                              tooltip: 'Remove',
                              onPressed: () => notifier.remove(item.product.id),
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
                    Text(
                      formatCurrency(total),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'cash',
                      label: Text('Cash'),
                      icon: Icon(Icons.payments_outlined),
                    ),
                    ButtonSegment(
                      value: 'card',
                      label: Text('Card'),
                      icon: Icon(Icons.credit_card_outlined),
                    ),
                  ],
                  selected: {_paymentMethod},
                  onSelectionChanged: (s) =>
                      setState(() => _paymentMethod = s.first),
                ),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  onPressed: cart.isEmpty || checkingOut
                      ? null
                      : () => widget.onCheckout(_paymentMethod),
                  icon: checkingOut
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check_circle_outline),
                  label: Text(
                    checkingOut
                        ? 'Recording…'
                        : 'Complete Sale · ${formatCurrency(total)}',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
