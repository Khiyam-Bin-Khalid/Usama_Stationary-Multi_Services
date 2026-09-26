import 'package:flutter/material.dart';

/// Explicit color tokens (not ColorScheme.fromSeed) so every text/background
/// pairing can be checked against WCAG AA (>=4.5:1 body text, >=3:1 large
/// text/icons/borders) instead of trusting a generated harmony.
///
/// The whole palette is derived from the brand page background gradient
///   linear-gradient(135deg, #fdfcfb 0%, #e2d1c3 100%)
/// i.e. warm cream -> warm tan. Text colors are deep warm browns picked so
/// they pass AA against the *darkest* point of the gradient (#e2d1c3), which
/// means they also pass everywhere lighter along it.
///
/// Verified ratios (light): onBackground on #e2d1c3 10.97:1, onSurfaceVariant
/// on #e2d1c3 5.98:1, white on primary 7.41:1, primary as text on #e2d1c3
/// 4.99:1, outline on #e2d1c3 3.6:1, error on #e2d1c3 6.14:1.
class AppColors {
  AppColors._();

  // ---- Light theme (gradient: cream -> tan) ----
  static const lightGradientStart = Color(0xFFFDFCFB);
  static const lightGradientEnd = Color(0xFFE2D1C3);

  static const lightPrimary = Color(0xFF7A4A26); // white text on this: 7.4:1
  static const lightOnPrimary = Color(0xFFFFFFFF);
  static const lightBackground = lightGradientEnd; // fallback if gradient can't paint
  static const lightOnBackground = Color(0xFF2B1D14); // ≥10.9:1 across gradient
  static const lightSurface = Color(0xFFFBF8F4); // cards, app bar, nav rail
  static const lightOnSurface = Color(0xFF2B1D14); // 15.4:1
  static const lightSurfaceVariant = Color(0xFFEFE3D7); // inputs, chips
  static const lightOnSurfaceVariant = Color(0xFF5A4636); // 7.0:1 on variant, 6.0:1 on gradient end
  static const lightOutline = Color(0xFF7A6858); // 3.6:1 on gradient end (UI min 3:1)

  // ---- Dark theme (same hue family, inverted: espresso -> cocoa) ----
  static const darkGradientStart = Color(0xFF1E1712);
  static const darkGradientEnd = Color(0xFF33271E);

  static const darkPrimary = Color(0xFFE2C4A8); // tan; dark brown text on it: 9.9:1
  static const darkOnPrimary = Color(0xFF2B1D14);
  static const darkBackground = darkGradientEnd;
  static const darkOnBackground = Color(0xFFF3EBE3); // ≥12.3:1 across gradient
  static const darkSurface = Color(0xFF2A211A);
  static const darkOnSurface = Color(0xFFF3EBE3); // 13.4:1
  static const darkSurfaceVariant = Color(0xFF3B2F26);
  static const darkOnSurfaceVariant = Color(0xFFD3C4B5); // 7.6:1 on variant
  static const darkOutline = Color(0xFF9C8A7A); // 4.4:1 on gradient end

  // Shared status chip pairs (background, foreground) — each pair chosen for
  // contrast against ITSELF, so it stays legible regardless of page theme.
  static const successBgLight = Color(0xFFDCFCE7);
  static const successFgLight = Color(0xFF14532D);
  static const successBgDark = Color(0xFF14532D);
  static const successFgDark = Color(0xFF86EFAC);

  static const warningBgLight = Color(0xFFFEF3C7);
  static const warningFgLight = Color(0xFF92400E);
  static const warningBgDark = Color(0xFF78350F);
  static const warningFgDark = Color(0xFFFCD34D);

  static const dangerBgLight = Color(0xFFFDE2E1);
  static const dangerFgLight = Color(0xFF8C1D18);
  static const dangerBgDark = Color(0xFF5C1A16);
  static const dangerFgDark = Color(0xFFF2B8B5);

  static const infoBgLight = Color(0xFFDCEBFF);
  static const infoFgLight = Color(0xFF0B3C82);
  static const infoBgDark = Color(0xFF0B3C82);
  static const infoFgDark = Color(0xFFAFCBFF);

  static const neutralBgLight = Color(0xFFEFE3D7);
  static const neutralFgLight = Color(0xFF5A4636);
  static const neutralBgDark = Color(0xFF3B2F26);
  static const neutralFgDark = Color(0xFFD3C4B5);
}
