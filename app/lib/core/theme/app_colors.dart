import 'package:flutter/material.dart';

/// Brand palette — exact tokens from the design spec. Do not derive or tweak
/// these; every screen picks from this list via AppTheme / StatusStyle.
///
/// Usage map (see app_theme.dart for where each is applied):
///  primaryOrange  primary action buttons, selected tab/nav item, login button,
///                 selected role tile, active step, primary-action icons
///  primaryDark    hover (web) + pressed state of primary buttons, focused input border
///  accentRed      low-stock / out-of-stock / deal ribbons, delete buttons,
///                 errors + invalid field borders, notification badge, refund tag
///  success        paid / delivered / completed tags, synced indicator, success toasts
///  background     base background for all screens + dialogs
///  surface        cards, table rows, sidebar/nav panel, input fills
///  textPrimary    product names, prices, headings, table data, body text
///  textSecondary  timestamps, placeholders, helper text, secondary labels, disabled text
///  border         input outlines, dividers, card outlines, table cell borders
class AppColors {
  AppColors._();

  static const Color primaryOrange = Color(0xFFFF6A00); // CTA / primary action
  static const Color primaryDark = Color(0xFFE65E00); // hover/pressed state
  static const Color accentRed = Color(0xFFFF4D4D); // deals / low-stock / urgency
  static const Color success = Color(0xFF16A34A); // paid / delivered
  static const Color background = Color(0xFFFFFFFF);
  static const Color surface = Color(0xFFF7F7F7); // cards
  static const Color textPrimary = Color(0xFF1A1A1A);
  static const Color textSecondary = Color(0xFF6B6B6B);
  static const Color border = Color(0xFFE5E5E5);

  /// Soft fill for badges/indicators: the token at 12% over the white
  /// background, so the badge text can be the token itself.
  static Color tint(Color token) => Color.alphaBlend(token.withValues(alpha: 0.12), background);
}
