import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Single light theme built strictly from AppColors (the spec palette is a
/// white-background system, so there is no dark variant).
class AppTheme {
  AppTheme._();

  static bool _active(Set<WidgetState> s) => s.contains(WidgetState.pressed) || s.contains(WidgetState.hovered);

  static ThemeData get light {
    final colorScheme = ColorScheme(
      brightness: Brightness.light,
      primary: AppColors.primaryOrange,
      onPrimary: Colors.white,
      primaryContainer: AppColors.tint(AppColors.primaryOrange),
      onPrimaryContainer: AppColors.primaryDark,
      secondary: AppColors.primaryDark,
      onSecondary: Colors.white,
      error: AppColors.accentRed,
      onError: Colors.white,
      errorContainer: AppColors.tint(AppColors.accentRed),
      onErrorContainer: AppColors.accentRed,
      surface: AppColors.background,
      onSurface: AppColors.textPrimary,
      surfaceContainerHighest: AppColors.surface,
      surfaceContainerHigh: AppColors.surface,
      surfaceContainer: AppColors.surface,
      surfaceContainerLow: AppColors.surface,
      onSurfaceVariant: AppColors.textSecondary,
      outline: AppColors.border,
      outlineVariant: AppColors.border,
      tertiary: AppColors.success,
      onTertiary: Colors.white,
    );

    final base = ThemeData(useMaterial3: true, brightness: Brightness.light, colorScheme: colorScheme);
    final text = base.textTheme.apply(bodyColor: AppColors.textPrimary, displayColor: AppColors.textPrimary);

    // Primary buttons: orange, primaryDark on hover/press, disabled = border fill + secondary text.
    final primaryButtonStyle = ButtonStyle(
      backgroundColor: WidgetStateProperty.resolveWith((s) {
        if (s.contains(WidgetState.disabled)) return AppColors.border;
        return _active(s) ? AppColors.primaryDark : AppColors.primaryOrange;
      }),
      foregroundColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.disabled) ? AppColors.textSecondary : Colors.white,
      ),
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      elevation: const WidgetStatePropertyAll(0),
      padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 20, vertical: 14)),
      textStyle: const WidgetStatePropertyAll(TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
      shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
    );

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.background,
      canvasColor: AppColors.background,
      dividerColor: AppColors.border,
      textTheme: text.copyWith(
        bodySmall: text.bodySmall?.copyWith(color: AppColors.textSecondary),
        labelSmall: text.labelSmall?.copyWith(color: AppColors.textSecondary),
        labelMedium: text.labelMedium?.copyWith(color: AppColors.textSecondary),
        titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        headlineSmall: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
      ),
      iconTheme: const IconThemeData(color: AppColors.textPrimary),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        shape: Border(bottom: BorderSide(color: AppColors.border)),
        titleTextStyle: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: AppColors.border)),
      ),
      dialogTheme: const DialogThemeData(backgroundColor: AppColors.background, surfaceTintColor: Colors.transparent),
      bottomSheetTheme: const BottomSheetThemeData(backgroundColor: AppColors.background, surfaceTintColor: Colors.transparent),
      drawerTheme: const DrawerThemeData(backgroundColor: AppColors.surface, surfaceTintColor: Colors.transparent),
      dividerTheme: const DividerThemeData(color: AppColors.border, thickness: 1, space: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        labelStyle: const TextStyle(color: AppColors.textSecondary),
        hintStyle: const TextStyle(color: AppColors.textSecondary),
        helperStyle: const TextStyle(color: AppColors.textSecondary),
        errorStyle: const TextStyle(color: AppColors.accentRed),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.primaryDark, width: 1.5)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.accentRed)),
        focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.accentRed, width: 1.5)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(style: primaryButtonStyle),
      filledButtonTheme: FilledButtonThemeData(style: primaryButtonStyle),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          side: const BorderSide(color: AppColors.border),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith((s) {
            if (s.contains(WidgetState.disabled)) return AppColors.textSecondary;
            return _active(s) ? AppColors.primaryDark : AppColors.primaryOrange;
          }),
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          textStyle: const WidgetStatePropertyAll(TextStyle(fontWeight: FontWeight.w600)),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.primaryOrange,
        foregroundColor: Colors.white,
        elevation: 0,
        extendedTextStyle: TextStyle(fontWeight: FontWeight.w700),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surface,
        selectedColor: AppColors.primaryOrange,
        side: const BorderSide(color: AppColors.border),
        showCheckmark: false,
        labelStyle: TextStyle(
          fontWeight: FontWeight.w600,
          color: WidgetStateColor.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : AppColors.textPrimary),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? AppColors.primaryOrange : AppColors.surface,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? Colors.white : AppColors.textPrimary,
          ),
          side: const WidgetStatePropertyAll(BorderSide(color: AppColors.border)),
          textStyle: const WidgetStatePropertyAll(TextStyle(fontWeight: FontWeight.w600)),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.tint(AppColors.primaryOrange),
        selectedIconTheme: const IconThemeData(color: AppColors.primaryOrange),
        selectedLabelTextStyle: const TextStyle(color: AppColors.primaryOrange, fontWeight: FontWeight.w700, fontSize: 12),
        unselectedIconTheme: const IconThemeData(color: AppColors.textSecondary),
        unselectedLabelTextStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
      ),
      navigationDrawerTheme: NavigationDrawerThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: AppColors.tint(AppColors.primaryOrange),
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(color: s.contains(WidgetState.selected) ? AppColors.primaryOrange : AppColors.textSecondary),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => TextStyle(
            color: s.contains(WidgetState.selected) ? AppColors.primaryOrange : AppColors.textPrimary,
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: AppColors.textSecondary,
        textColor: AppColors.textPrimary,
        subtitleTextStyle: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        selectedColor: AppColors.primaryOrange,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : AppColors.textSecondary),
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AppColors.primaryOrange : AppColors.border),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AppColors.primaryOrange : Colors.transparent),
        side: const BorderSide(color: AppColors.border, width: 1.5),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AppColors.primaryOrange : AppColors.textSecondary),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.primaryOrange, linearTrackColor: AppColors.border),
      badgeTheme: const BadgeThemeData(backgroundColor: AppColors.accentRed, textColor: Colors.white),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: AppColors.textPrimary,
        contentTextStyle: TextStyle(color: Colors.white),
        behavior: SnackBarBehavior.floating,
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: AppColors.primaryOrange,
        unselectedLabelColor: AppColors.textSecondary,
        indicatorColor: AppColors.primaryOrange,
      ),
      dataTableTheme: const DataTableThemeData(
        headingTextStyle: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600, fontSize: 12),
        dataTextStyle: TextStyle(color: AppColors.textPrimary, fontSize: 13),
        dividerThickness: 1,
      ),
      popupMenuTheme: const PopupMenuThemeData(color: AppColors.background, surfaceTintColor: Colors.transparent),
    );
  }
}
