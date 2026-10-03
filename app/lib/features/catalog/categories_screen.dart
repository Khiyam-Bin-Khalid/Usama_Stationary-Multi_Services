import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/responsive.dart';
import '../../core/roles.dart';
import '../../core/theme/app_colors.dart';
import 'catalog_screen.dart';

const _categoryIcons = {
  ProductCategory.stationery: Icons.edit_note_outlined,
  ProductCategory.grocery: Icons.local_grocery_store_outlined,
  ProductCategory.garment: Icons.checkroom_outlined,
  ProductCategory.printing: Icons.print_outlined,
  ProductCategory.sports: Icons.sports_soccer_outlined,
};

/// Category tiles with live product counts; tapping opens the products page
/// filtered to that category.
class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final products = ref.watch(catalogProductsProvider).valueOrNull ?? const [];
    final columns = context.isPhone ? 2 : (context.isTablet ? 3 : 5);
    return SingleChildScrollView(
      child: ResponsiveContainer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Categories', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 16),
            GridView.count(
              crossAxisCount: columns,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.3,
              children: [
                for (final c in ProductCategory.all)
                  Card(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => context.go('/shop/products?category=$c'),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(_categoryIcons[c] ?? Icons.category_outlined, size: 36, color: AppColors.primaryOrange),
                            const SizedBox(height: 10),
                            Text(ProductCategory.label(c), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700)),
                            Text('${products.where((p) => p.category == c).length} products', style: Theme.of(context).textTheme.bodySmall),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
