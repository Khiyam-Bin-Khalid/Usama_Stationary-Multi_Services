import 'package:flutter/material.dart';
import 'app_colors.dart';

enum StatusTone { success, warning, danger, info, neutral }

class StatusStyle {
  final Color background;
  final Color foreground;
  const StatusStyle(this.background, this.foreground);

  /// Looks up the accessible (background, foreground) pair for a status
  /// tone in the current brightness — used for low-stock badges, payment
  /// status chips, and order status chips throughout both shells.
  static StatusStyle of(BuildContext context, StatusTone tone) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    switch (tone) {
      case StatusTone.success:
        return isDark
            ? const StatusStyle(AppColors.successBgDark, AppColors.successFgDark)
            : const StatusStyle(AppColors.successBgLight, AppColors.successFgLight);
      case StatusTone.warning:
        return isDark
            ? const StatusStyle(AppColors.warningBgDark, AppColors.warningFgDark)
            : const StatusStyle(AppColors.warningBgLight, AppColors.warningFgLight);
      case StatusTone.danger:
        return isDark
            ? const StatusStyle(AppColors.dangerBgDark, AppColors.dangerFgDark)
            : const StatusStyle(AppColors.dangerBgLight, AppColors.dangerFgLight);
      case StatusTone.info:
        return isDark
            ? const StatusStyle(AppColors.infoBgDark, AppColors.infoFgDark)
            : const StatusStyle(AppColors.infoBgLight, AppColors.infoFgLight);
      case StatusTone.neutral:
        return isDark
            ? const StatusStyle(AppColors.neutralBgDark, AppColors.neutralFgDark)
            : const StatusStyle(AppColors.neutralBgLight, AppColors.neutralFgLight);
    }
  }
}

/// Small pill badge used for order/payment/job statuses and low-stock flags.
class StatusBadge extends StatelessWidget {
  final String label;
  final StatusTone tone;
  const StatusBadge({super.key, required this.label, required this.tone});

  @override
  Widget build(BuildContext context) {
    final style = StatusStyle.of(context, tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: style.background, borderRadius: BorderRadius.circular(999)),
      child: Text(
        label,
        style: TextStyle(color: style.foreground, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}
