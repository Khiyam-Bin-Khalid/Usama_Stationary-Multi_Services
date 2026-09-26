import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Paints the brand background behind every route:
///   light: linear-gradient(135deg, #fdfcfb 0%, #e2d1c3 100%)
///   dark:  same direction, espresso -> cocoa.
///
/// Mounted once via `MaterialApp.router(builder: ...)`; every Scaffold has a
/// transparent background (see AppTheme) so the gradient shows through.
/// CSS `135deg` runs top-left -> bottom-right, which is what
/// `Alignment.topLeft` -> `Alignment.bottomRight` gives here.
class AppBackground extends StatelessWidget {
  final Widget child;
  const AppBackground({super.key, required this.child});

  static LinearGradient gradientFor(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      stops: const [0.0, 1.0],
      colors: isDark
          ? const [AppColors.darkGradientStart, AppColors.darkGradientEnd]
          : const [AppColors.lightGradientStart, AppColors.lightGradientEnd],
    );
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return DecoratedBox(
      decoration: BoxDecoration(gradient: gradientFor(brightness)),
      child: child,
    );
  }
}
