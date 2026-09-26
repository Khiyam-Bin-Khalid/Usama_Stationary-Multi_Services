import 'product.dart';

/// Shared cart line used by both the POS shell and the storefront shell.
class CartItem {
  final Product product;
  final num quantity;

  const CartItem({required this.product, required this.quantity});

  double get lineTotal => product.price * quantity;

  CartItem copyWith({num? quantity}) => CartItem(product: product, quantity: quantity ?? this.quantity);
}
