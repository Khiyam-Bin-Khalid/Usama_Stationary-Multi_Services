import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/cart_item.dart';
import '../../data/models/product.dart';

class PosCart extends Notifier<List<CartItem>> {
  @override
  List<CartItem> build() => [];

  void add(Product product) {
    final index = state.indexWhere((i) => i.product.id == product.id);
    if (index == -1) {
      state = [...state, CartItem(product: product, quantity: 1)];
    } else {
      final item = state[index];
      state = [
        for (var i = 0; i < state.length; i++)
          if (i == index) item.copyWith(quantity: item.quantity + 1) else state[i],
      ];
    }
  }

  void setQuantity(String productId, num quantity) {
    if (quantity <= 0) {
      remove(productId);
      return;
    }
    state = [
      for (final item in state)
        if (item.product.id == productId) item.copyWith(quantity: quantity) else item,
    ];
  }

  void remove(String productId) {
    state = state.where((i) => i.product.id != productId).toList();
  }

  void clear() => state = [];

  double get total => state.fold(0, (sum, i) => sum + i.lineTotal);
}

final posCartProvider = NotifierProvider<PosCart, List<CartItem>>(PosCart.new);
