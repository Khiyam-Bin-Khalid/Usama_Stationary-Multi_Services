import 'package:flutter/material.dart';

/// Responsive layout helpers for the customer storefront (and reused by the
/// admin shell where it helps).
///
/// Breakpoints: < 600 phone · 600–1023 tablet · >= 1024 desktop.
/// Horizontal gutter: 16px on phone, 24px on tablet, 32px on desktop, with
/// content capped at [maxContentWidth] and centred on wide screens. These
/// are the initial guideline values from the spec and are meant to be tuned
/// in one place.
class Breakpoints {
  Breakpoints._();
  static const double tablet = 600;
  static const double desktop = 1024;
  static const double maxContentWidth = 1200;
}

enum ScreenSize { phone, tablet, desktop }

extension ResponsiveContext on BuildContext {
  double get screenWidth => MediaQuery.sizeOf(this).width;

  ScreenSize get screenSize {
    final w = screenWidth;
    if (w >= Breakpoints.desktop) return ScreenSize.desktop;
    if (w >= Breakpoints.tablet) return ScreenSize.tablet;
    return ScreenSize.phone;
  }

  bool get isPhone => screenSize == ScreenSize.phone;
  bool get isTablet => screenSize == ScreenSize.tablet;
  bool get isDesktop => screenSize == ScreenSize.desktop;

  /// Side gutter for page content.
  double get gutter {
    switch (screenSize) {
      case ScreenSize.phone:
        return 16;
      case ScreenSize.tablet:
        return 24;
      case ScreenSize.desktop:
        return 32;
    }
  }

  EdgeInsets get pagePadding => EdgeInsets.symmetric(horizontal: gutter, vertical: 16);

  /// Number of product-grid columns for the current width.
  int get productGridColumns {
    final w = screenWidth;
    if (w >= 1400) return 5;
    if (w >= Breakpoints.desktop) return 4;
    if (w >= 800) return 3;
    return 2;
  }
}

/// Centres [child] in a max-width column with the responsive side gutter.
/// Use it for every storefront page so margins stay consistent.
class ResponsiveContainer extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  final EdgeInsets? padding;
  final bool withVerticalPadding;

  const ResponsiveContainer({
    super.key,
    required this.child,
    this.maxWidth = Breakpoints.maxContentWidth,
    this.padding,
    this.withVerticalPadding = true,
  });

  @override
  Widget build(BuildContext context) {
    final gutter = context.gutter;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: padding ?? EdgeInsets.symmetric(horizontal: gutter, vertical: withVerticalPadding ? 16 : 0),
          child: child,
        ),
      ),
    );
  }
}

/// Sliver variant for CustomScrollView pages.
class SliverResponsivePadding extends StatelessWidget {
  final Widget sliver;
  final double maxWidth;
  const SliverResponsivePadding({super.key, required this.sliver, this.maxWidth = Breakpoints.maxContentWidth});

  @override
  Widget build(BuildContext context) {
    final width = context.screenWidth;
    final gutter = context.gutter;
    final extra = width > maxWidth + gutter * 2 ? (width - maxWidth) / 2 : gutter;
    return SliverPadding(padding: EdgeInsets.symmetric(horizontal: extra), sliver: sliver);
  }
}
