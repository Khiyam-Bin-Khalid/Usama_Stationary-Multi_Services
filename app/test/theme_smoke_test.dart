// Smoke test for the brand theme: pumps a representative screen and checks
// the exact palette tokens are what the theme hands out.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:usama_book_depot/core/theme/app_colors.dart';
import 'package:usama_book_depot/core/theme/app_theme.dart';
import 'package:usama_book_depot/core/theme/status_style.dart';

void main() {
  testWidgets('brand theme renders with the spec palette', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 640));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          appBar: AppBar(title: const Text('Usama Book Depot')),
          body: Column(
            children: [
              ElevatedButton(onPressed: () {}, child: const Text('Complete Sale')),
              const TextField(decoration: InputDecoration(labelText: 'Email')),
              const Wrap(children: [
                StatusBadge(label: 'Paid', tone: StatusTone.success),
                StatusBadge(label: 'Only 3 left', tone: StatusTone.danger),
                StatusBadge(label: 'Deal', tone: StatusTone.danger, solid: true),
              ]),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final theme = Theme.of(tester.element(find.text('Complete Sale')));
    expect(theme.colorScheme.primary, AppColors.primaryOrange);
    expect(theme.colorScheme.error, AppColors.accentRed);
    expect(theme.scaffoldBackgroundColor, AppColors.background);
    expect(theme.cardTheme.color, AppColors.surface);
    expect(tester.takeException(), isNull);
  });

  test('palette tokens are the exact spec values', () {
    expect(AppColors.primaryOrange.toARGB32(), 0xFFFF6A00);
    expect(AppColors.primaryDark.toARGB32(), 0xFFE65E00);
    expect(AppColors.accentRed.toARGB32(), 0xFFFF4D4D);
    expect(AppColors.success.toARGB32(), 0xFF16A34A);
    expect(AppColors.background.toARGB32(), 0xFFFFFFFF);
    expect(AppColors.surface.toARGB32(), 0xFFF7F7F7);
    expect(AppColors.textPrimary.toARGB32(), 0xFF1A1A1A);
    expect(AppColors.textSecondary.toARGB32(), 0xFF6B6B6B);
    expect(AppColors.border.toARGB32(), 0xFFE5E5E5);
  });
}
