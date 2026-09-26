// Smoke test for the brand gradient theme: pumps a representative screen in
// both brightnesses and checks nothing throws. To eyeball it, temporarily
// add `await expectLater(find.byType(MaterialApp), matchesGoldenFile('theme.png'));`
// and run `flutter test --update-goldens test/theme_screenshot_test.dart`.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:usama_book_depot/core/theme/app_background.dart';
import 'package:usama_book_depot/core/theme/app_theme.dart';
import 'package:usama_book_depot/core/theme/status_style.dart';

Widget _sample(ThemeData theme) {
  return MaterialApp(
    theme: theme,
    debugShowCheckedModeBanner: false,
    builder: (context, child) => AppBackground(child: child ?? const SizedBox.shrink()),
    home: Scaffold(
      appBar: AppBar(title: const Text('Usama Book Depot')),
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: 0,
            labelType: NavigationRailLabelType.all,
            destinations: const [
              NavigationRailDestination(icon: Icon(Icons.point_of_sale), label: Text('POS')),
              NavigationRailDestination(icon: Icon(Icons.inventory_2_outlined), label: Text('Inventory')),
              NavigationRailDestination(icon: Icon(Icons.bar_chart_outlined), label: Text('Reports')),
            ],
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Builder(builder: (context) => Text('Heading on gradient', style: Theme.of(context).textTheme.headlineSmall)),
                  const Text('Body text drawn directly on the gradient background.'),
                  Builder(
                    builder: (context) => Text('Secondary text (onSurfaceVariant)',
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Card surface'),
                          const SizedBox(height: 8),
                          const TextField(decoration: InputDecoration(labelText: 'Email')),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              ElevatedButton(onPressed: () {}, child: const Text('Log in')),
                              const SizedBox(width: 8),
                              TextButton(onPressed: () {}, child: const Text('Cancel')),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Wrap(spacing: 8, children: [
                            StatusBadge(label: 'Active', tone: StatusTone.success),
                            StatusBadge(label: 'Low stock', tone: StatusTone.warning),
                            StatusBadge(label: 'Rejected', tone: StatusTone.danger),
                            StatusBadge(label: 'Pending', tone: StatusTone.info),
                            StatusBadge(label: 'Disabled', tone: StatusTone.neutral),
                          ]),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

void main() {
  for (final entry in {'light': AppTheme.light, 'dark': AppTheme.dark}.entries) {
    testWidgets('brand gradient theme renders (${entry.key})', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1100, 640));
      await tester.pumpWidget(_sample(entry.value));
      await tester.pumpAndSettle();
      expect(find.text('Usama Book Depot'), findsOneWidget);
      expect(find.byType(AppBackground), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
