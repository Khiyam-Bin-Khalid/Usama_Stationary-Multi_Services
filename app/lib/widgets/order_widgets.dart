import 'package:flutter/material.dart';
import '../core/format.dart';
import '../core/roles.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/status_style.dart';
import '../data/models/order.dart';
import '../features/orders/order_status_style.dart';
import 'product_image.dart';

/// One ordered line as shown everywhere an order item appears: the product
/// image the customer selected, name, SKU, quantity × unit price, line total.
class OrderItemTile extends StatelessWidget {
  final OrderItemView item;
  final double imageSize;
  final bool dense;
  const OrderItemTile({super.key, required this.item, this.imageSize = 56, this.dense = false});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: dense ? 6 : 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ProductImage(imageUrl: item.imageUrl, size: imageSize),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                  [if (item.sku != null) 'SKU ${item.sku}', '${item.quantity} × ${formatCurrency(item.unitPrice)}'].join(' · '),
                  style: text.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(formatCurrency(item.lineTotal), style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

/// Subtotal / discount / delivery / tax / grand total block.
class OrderTotals extends StatelessWidget {
  final double subtotal;
  final double discountTotal;
  final double deliveryFee;
  final double taxAmount;
  final double taxRate;
  final double total;
  final String? promotionName;
  const OrderTotals({
    super.key,
    required this.subtotal,
    required this.discountTotal,
    required this.deliveryFee,
    required this.taxAmount,
    this.taxRate = 0,
    required this.total,
    this.promotionName,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _row(context, 'Subtotal', formatCurrency(subtotal)),
        if (discountTotal > 0)
          _row(context, promotionName != null ? 'Discount ($promotionName)' : 'Discount', '- ${formatCurrency(discountTotal)}',
              color: AppColors.success),
        _row(context, 'Delivery charges', deliveryFee > 0 ? formatCurrency(deliveryFee) : 'Free'),
        if (taxAmount > 0) _row(context, taxRate > 0 ? 'Tax (${taxRate.toStringAsFixed(taxRate.truncateToDouble() == taxRate ? 0 : 1)}%)' : 'Tax', formatCurrency(taxAmount)),
        const Divider(height: 20),
        _row(context, 'Grand total', formatCurrency(total), emphasize: true),
      ],
    );
  }

  Widget _row(BuildContext context, String label, String value, {bool emphasize = false, Color? color}) {
    final style = emphasize
        ? Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)
        : Theme.of(context).textTheme.bodyMedium?.copyWith(color: color);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(label, style: style), Text(value, style: style)],
      ),
    );
  }
}

/// Vertical lifecycle timeline: every stage from the order's own history is
/// shown with its timestamp; the remaining stages are shown greyed so the
/// customer can see what comes next.
class OrderTimeline extends StatelessWidget {
  final CustomerOrder order;
  const OrderTimeline({super.key, required this.order});

  @override
  Widget build(BuildContext context) {
    final history = order.statusHistory;
    final reached = <String, OrderStatusEvent>{};
    for (final e in history) {
      reached[e.status] = e; // last occurrence wins (e.g. a re-upload)
    }
    final current = order.status;

    // Upcoming stages depend on the payment method: card/COD orders skip the
    // receipt stages.
    final skipsReceipt = order.paymentMethod != PaymentMethod.manualReceipt;
    final stages = OrderStatus.lifecycle.where((s) {
      if (skipsReceipt && (s == OrderStatus.paymentSubmitted || s == OrderStatus.paymentUnderReview)) {
        return reached.containsKey(s);
      }
      if (s == OrderStatus.paymentApproved && order.paymentMethod == PaymentMethod.cashOnDelivery) return reached.containsKey(s);
      return true;
    }).toList();
    // Non-linear events (rejection / cancellation) are shown where they happened.
    final extra = history.where((e) => e.status == OrderStatus.paymentRejected || e.status == OrderStatus.cancelled).toList();

    final rows = <Widget>[];
    for (final s in stages) {
      final ev = reached[s];
      rows.add(_TimelineRow(
        label: orderStatusLabel(s),
        subtitle: ev != null ? '${formatDateTime(ev.at)}${ev.note != null && ev.note!.isNotEmpty ? '\n${ev.note}' : ''}' : orderStatusHint(s),
        done: ev != null,
        current: s == current,
        tone: orderStatusTone(s),
      ));
    }
    for (final e in extra) {
      rows.add(_TimelineRow(
        label: orderStatusLabel(e.status),
        subtitle: '${formatDateTime(e.at)}${e.note != null && e.note!.isNotEmpty ? '\n${e.note}' : ''}',
        done: true,
        current: e.status == current,
        tone: StatusTone.danger,
      ));
    }
    return Column(children: rows);
  }
}

class _TimelineRow extends StatelessWidget {
  final String label;
  final String subtitle;
  final bool done;
  final bool current;
  final StatusTone tone;
  const _TimelineRow({required this.label, required this.subtitle, required this.done, required this.current, required this.tone});

  @override
  Widget build(BuildContext context) {
    final style = StatusStyle.of(context, tone);
    final dotColor = current ? AppColors.primaryOrange : (done ? style.foreground : AppColors.border);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 24,
            child: Column(
              children: [
                Container(
                  width: 14,
                  height: 14,
                  margin: const EdgeInsets.only(top: 3),
                  decoration: BoxDecoration(
                    color: done || current ? dotColor : Colors.transparent,
                    shape: BoxShape.circle,
                    border: Border.all(color: dotColor, width: 2),
                  ),
                ),
                Expanded(child: Container(width: 2, color: AppColors.border)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                        fontWeight: current || done ? FontWeight.w700 : FontWeight.w500,
                        color: done || current ? AppColors.textPrimary : AppColors.textSecondary,
                      )),
                  Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Order header chip pair (order status + payment status).
class OrderStatusChips extends StatelessWidget {
  final CustomerOrder order;
  const OrderStatusChips({super.key, required this.order});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        StatusBadge(label: orderStatusLabel(order.status), tone: orderStatusTone(order.status)),
        StatusBadge(label: paymentStatusLabel(order.paymentStatus), tone: paymentStatusTone(order.paymentStatus)),
      ],
    );
  }
}

/// Small horizontal strip of item thumbnails for list rows.
class OrderThumbnails extends StatelessWidget {
  final List<OrderItemView> items;
  final int max;
  const OrderThumbnails({super.key, required this.items, this.max = 3});

  @override
  Widget build(BuildContext context) {
    final shown = items.take(max).toList();
    final more = items.length - shown.length;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final i in shown) Padding(padding: const EdgeInsets.only(right: 4), child: ProductImage(imageUrl: i.imageUrl, size: 40, radius: 6)),
        if (more > 0)
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(6), border: Border.all(color: AppColors.border)),
            child: Text('+$more', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          ),
      ],
    );
  }
}
