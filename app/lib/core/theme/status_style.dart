import 'package:flutter/material.dart';
import 'app_colors.dart';

/// success  → paid / delivered / completed / in stock / synced
/// danger   → low stock, out of stock, deal ribbon, rejected, refund (accentRed)
/// warning  → pending / under review / active step (orange)
/// info     → made-to-order, processing (neutral surface, primary text)
/// neutral  → disabled, unpaid, cancelled-ish (neutral surface, secondary text)
enum StatusTone { success, warning, danger, info, neutral }

class StatusStyle {
  final Color background;
  final Color foreground;
  final bool outlined;
  const StatusStyle(this.background, this.foreground, {this.outlined = false});

  static StatusStyle of(BuildContext context, StatusTone tone) {
    switch (tone) {
      case StatusTone.success:
        return StatusStyle(AppColors.tint(AppColors.success), AppColors.success);
      case StatusTone.warning:
        return StatusStyle(AppColors.tint(AppColors.primaryOrange), AppColors.primaryDark);
      case StatusTone.danger:
        return StatusStyle(AppColors.tint(AppColors.accentRed), AppColors.accentRed);
      case StatusTone.info:
        return const StatusStyle(AppColors.surface, AppColors.textPrimary, outlined: true);
      case StatusTone.neutral:
        return const StatusStyle(AppColors.surface, AppColors.textSecondary, outlined: true);
    }
  }
}

/// Small pill badge used for order/payment/job statuses and stock flags.
class StatusBadge extends StatelessWidget {
  final String label;
  final StatusTone tone;
  /// Solid variant (token background, white text) for ribbons like "Deal".
  final bool solid;
  const StatusBadge({super.key, required this.label, required this.tone, this.solid = false});

  @override
  Widget build(BuildContext context) {
    final style = StatusStyle.of(context, tone);
    final bg = solid ? style.foreground : style.background;
    final fg = solid ? Colors.white : style.foreground;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: style.outlined && !solid ? Border.all(color: AppColors.border) : null,
      ),
      child: Text(label, style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w700)),
    );
  }
}

/// Small colored dot, e.g. the "synced with server" indicator.
class StatusDot extends StatelessWidget {
  final Color color;
  final double size;
  const StatusDot({super.key, required this.color, this.size = 8});

  @override
  Widget build(BuildContext context) =>
      Container(width: size, height: size, decoration: BoxDecoration(color: color, shape: BoxShape.circle));
}
