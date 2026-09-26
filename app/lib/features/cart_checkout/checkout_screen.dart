import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/roles.dart';
import '../../data/remote/api_client.dart';
import 'shop_cart_provider.dart';

class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key});

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  final _formKey = GlobalKey<FormState>();
  final _line1Controller = TextEditingController();
  final _line2Controller = TextEditingController();
  final _cityController = TextEditingController();
  final _phoneController = TextEditingController();
  final _windowController = TextEditingController();
  String _paymentMethod = PaymentMethod.cashOnDelivery;
  bool _submitting = false;
  String? _error;

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
            'line1': _line1Controller.text,
            'line2': _line2Controller.text,
            'city': _cityController.text,
            'phone': _phoneController.text,
          },
          'window': _windowController.text,
        },
      );

      ref.read(shopCartProvider.notifier).clear();

      if (_paymentMethod == PaymentMethod.stripe && result.stripeCheckoutUrl != null) {
        await launchUrl(Uri.parse(result.stripeCheckoutUrl!), mode: LaunchMode.externalApplication);
      }

      if (!mounted) return;
      context.go('/orders/${result.order.id}');
    } catch (e) {
      final message = e is ApiException ? e.message : e.toString();
      setState(() => _error = message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(shopCartProvider);
    final total = cart.fold<double>(0, (sum, i) => sum + i.lineTotal);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Delivery address', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            TextFormField(
              controller: _line1Controller,
              decoration: const InputDecoration(labelText: 'Address line 1'),
              validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 8),
            TextFormField(controller: _line2Controller, decoration: const InputDecoration(labelText: 'Address line 2 (optional)')),
            const SizedBox(height: 8),
            TextFormField(
              controller: _cityController,
              decoration: const InputDecoration(labelText: 'City'),
              validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _phoneController,
              decoration: const InputDecoration(labelText: 'Phone'),
              validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 8),
            TextFormField(controller: _windowController, decoration: const InputDecoration(labelText: 'Preferred delivery window (optional)')),
            const SizedBox(height: 24),
            Text('Payment method', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            RadioListTile<String>(
              value: PaymentMethod.stripe,
              groupValue: _paymentMethod,
              onChanged: (v) => setState(() => _paymentMethod = v!),
              title: const Text('Pay by card (Stripe)'),
              subtitle: const Text('Opens a secure checkout page'),
            ),
            RadioListTile<String>(
              value: PaymentMethod.manualReceipt,
              groupValue: _paymentMethod,
              onChanged: (v) => setState(() => _paymentMethod = v!),
              title: const Text('Bank transfer — upload receipt'),
              subtitle: const Text('Pay via bank transfer / JazzCash / EasyPaisa, then upload a screenshot for admin review'),
            ),
            RadioListTile<String>(
              value: PaymentMethod.cashOnDelivery,
              groupValue: _paymentMethod,
              onChanged: (v) => setState(() => _paymentMethod = v!),
              title: const Text('Cash on delivery'),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Total'),
                Text(formatCurrency(total), style: Theme.of(context).textTheme.titleLarge),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _submitting ? null : _placeOrder,
              child: _submitting
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Place order'),
            ),
          ],
        ),
      ),
    );
  }
}
