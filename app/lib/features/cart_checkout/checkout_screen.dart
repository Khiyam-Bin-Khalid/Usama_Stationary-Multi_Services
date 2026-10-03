import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/responsive.dart';
import '../../core/roles.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/cart_item.dart';
import '../../data/models/order.dart';
import '../../widgets/order_widgets.dart';
import 'shop_cart_provider.dart';

/// Checkout: the complete order summary (images, names, SKUs, quantities,
/// unit prices, item totals, subtotal, discount, delivery, tax, grand total)
/// comes from POST /orders/quote so the customer confirms exactly what will
/// be stored on the order; then delivery details + payment method.
final _quoteProvider = FutureProvider.autoDispose.family<OrderQuote, String>((ref, key) {
  final cart = ref.watch(shopCartProvider);
  return ref.watch(orderApiProvider).quote(items: cart.map((i) => {'product': i.product.id, 'quantity': i.quantity}).toList());
});

String _cartKey(List<CartItem> cart) => cart.map((i) => '${i.product.id}:${i.quantity}').join('|');

class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key});

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _line1Controller = TextEditingController();
  final _line2Controller = TextEditingController();
  final _cityController = TextEditingController();
  final _phoneController = TextEditingController();
  final _windowController = TextEditingController();
  String _paymentMethod = PaymentMethod.cashOnDelivery;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final user = ref.read(authStateProvider).valueOrNull;
    _nameController.text = user?.name ?? '';
    _phoneController.text = user?.phone ?? '';
  }

  @override
  void dispose() {
    for (final c in [_nameController, _line1Controller, _line2Controller, _cityController, _phoneController, _windowController]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _placeOrder() async {
    if (!_formKey.currentState!.validate()) return;
    final cart = ref.read(shopCartProvider);
    if (cart.isEmpty) return;

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final result = await ref.read(orderApiProvider).placeOrder(
        items: cart.map((i) => {'product': i.product.id, 'quantity': i.quantity}).toList(),
        paymentMethod: _paymentMethod,
        delivery: {
          'isHomeDelivery': true,
          'address': {
            'line1': _line1Controller.text.trim(),
            'line2': _line2Controller.text.trim(),
            'city': _cityController.text.trim(),
            'phone': _phoneController.text.trim(),
          },
          'window': _windowController.text.trim(),
        },
      );

      ref.read(shopCartProvider.notifier).clear();

      if (_paymentMethod == PaymentMethod.stripe && result.stripeCheckoutUrl != null) {
        await launchUrl(Uri.parse(result.stripeCheckoutUrl!), mode: LaunchMode.externalApplication);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Order ${result.order.orderNumber} placed')));
      context.go('/orders/${result.order.id}');
    } catch (e) {
      final message = e.toString();
      setState(() => _error = message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(shopCartProvider);
    if (cart.isEmpty) {
      return ResponsiveContainer(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Your cart is empty.'),
              const SizedBox(height: 12),
              FilledButton(onPressed: () => context.go('/shop'), child: const Text('Browse products')),
            ],
          ),
        ),
      );
    }
    final quoteAsync = ref.watch(_quoteProvider(_cartKey(cart)));

    final summary = Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Order summary', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text('Please check the products below before confirming.', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            quoteAsync.when(
              loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
              error: (e, _) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text('Could not price the cart: $e', style: const TextStyle(color: AppColors.accentRed)),
              ),
              data: (quote) => Column(
                children: [
                  for (final item in quote.items) OrderItemTile(item: item, imageSize: 56),
                  const Divider(),
                  OrderTotals(
                    subtotal: quote.subtotal,
                    discountTotal: quote.discountTotal,
                    deliveryFee: quote.deliveryFee,
                    taxAmount: quote.taxAmount,
                    taxRate: quote.taxRate,
                    total: quote.total,
                    promotionName: quote.promotionName,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    final form = Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Delivery information', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          TextFormField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Recipient name'),
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _line1Controller,
            decoration: const InputDecoration(labelText: 'Address line 1'),
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
          ),
          const SizedBox(height: 10),
          TextFormField(controller: _line2Controller, decoration: const InputDecoration(labelText: 'Address line 2 (optional)')),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _cityController,
                  decoration: const InputDecoration(labelText: 'City'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Phone'),
                  validator: (v) => (v == null || v.trim().length < 7) ? 'Enter a valid phone' : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextFormField(controller: _windowController, decoration: const InputDecoration(labelText: 'Preferred delivery time (optional)')),
          const SizedBox(height: 24),
          Text('Payment method', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _PaymentOption(
            value: PaymentMethod.cashOnDelivery,
            group: _paymentMethod,
            title: 'Cash on delivery',
            subtitle: 'Pay the courier when your order arrives',
            icon: Icons.payments_outlined,
            onChanged: (v) => setState(() => _paymentMethod = v),
          ),
          _PaymentOption(
            value: PaymentMethod.manualReceipt,
            group: _paymentMethod,
            title: 'Bank transfer / JazzCash / EasyPaisa',
            subtitle: 'Pay online, then upload the receipt. An admin verifies it before the order is confirmed.',
            icon: Icons.receipt_long_outlined,
            onChanged: (v) => setState(() => _paymentMethod = v),
          ),
          _PaymentOption(
            value: PaymentMethod.stripe,
            group: _paymentMethod,
            title: 'Pay by card',
            subtitle: 'Opens a secure card checkout page',
            icon: Icons.credit_card_outlined,
            onChanged: (v) => setState(() => _paymentMethod = v),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: AppColors.accentRed)),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _submitting || quoteAsync.hasError ? null : _placeOrder,
            child: _submitting
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(quoteAsync.hasValue ? 'Confirm order · ${formatCurrency(quoteAsync.value!.total)}' : 'Confirm order'),
          ),
          const SizedBox(height: 8),
          TextButton(onPressed: () => context.go('/cart'), child: const Text('Back to cart')),
        ],
      ),
    );

    return SingleChildScrollView(
      child: ResponsiveContainer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Checkout', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 16),
            if (context.isDesktop)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: form),
                  const SizedBox(width: 24),
                  Expanded(flex: 2, child: summary),
                ],
              )
            else ...[
              summary,
              const SizedBox(height: 20),
              form,
            ],
          ],
        ),
      ),
    );
  }
}

class _PaymentOption extends StatelessWidget {
  final String value;
  final String group;
  final String title;
  final String subtitle;
  final IconData icon;
  final ValueChanged<String> onChanged;
  const _PaymentOption({
    required this.value,
    required this.group,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final selected = value == group;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? AppColors.tint(AppColors.primaryOrange) : AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => onChanged(value),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: selected ? AppColors.primaryOrange : AppColors.border, width: selected ? 1.5 : 1),
            ),
            child: Row(
              children: [
                Icon(icon, color: selected ? AppColors.primaryOrange : AppColors.textSecondary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                Icon(
                  selected ? Icons.radio_button_checked : Icons.radio_button_off,
                  color: selected ? AppColors.primaryOrange : AppColors.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
