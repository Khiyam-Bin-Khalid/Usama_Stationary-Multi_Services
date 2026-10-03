// The cart must show, for every line, the selected product's image slot,
// name, SKU, unit price, quantity controls, line total and a remove action
// (consolidated spec).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:usama_book_depot/core/theme/app_theme.dart';
import 'package:usama_book_depot/data/models/product.dart';
import 'package:usama_book_depot/features/cart_checkout/cart_screen.dart';
import 'package:usama_book_depot/features/cart_checkout/shop_cart_provider.dart';

const _pen = Product(
  id: 'p1',
  name: 'Ballpoint Pen (Box of 10)',
  sku: 'STN-00002',
  barcode: '8901234567906',
  category: 'stationery',
  unit: 'box',
  price: 300,
  costPrice: 200,
  currentStock: 5,
  reorderThreshold: 2,
  isMadeToOrder: false,
  isAvailableOnline: true,
  isActive: true,
);

void main() {
  testWidgets('cart line shows image, name, SKU, price, quantity, total and remove', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(shopCartProvider.notifier).add(_pen);
    container.read(shopCartProvider.notifier).setQuantity(_pen.id, 2);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: AppTheme.light, home: const Scaffold(body: CartScreen())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ballpoint Pen (Box of 10)'), findsOneWidget);
    expect(find.text('SKU STN-00002'), findsOneWidget);
    expect(find.textContaining('Unit price'), findsOneWidget);
    expect(find.text('2'), findsOneWidget); // quantity
    expect(find.text('Rs. 600'), findsWidgets); // line total (and subtotal)
    expect(find.byIcon(Icons.inventory_2_outlined), findsOneWidget); // image slot (no photo → placeholder)
    expect(find.byIcon(Icons.add_circle_outline), findsOneWidget);
    expect(find.byIcon(Icons.remove_circle_outline), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);

    // + increases quantity, remove empties the cart.
    await tester.tap(find.byIcon(Icons.add_circle_outline));
    await tester.pumpAndSettle();
    expect(container.read(shopCartProvider).first.quantity, 3);

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    expect(container.read(shopCartProvider), isEmpty);
    expect(find.text('Your cart is empty'), findsOneWidget);
  });
}
