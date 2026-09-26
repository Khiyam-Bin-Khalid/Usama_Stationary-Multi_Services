// Smoke test: the app should boot straight to the login screen when there is
// no stored session, without touching the network or platform SQLite plugin.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:usama_book_depot/core/providers.dart';
import 'package:usama_book_depot/data/models/user.dart';
import 'package:usama_book_depot/main.dart';

class _NoSessionAuthState extends AuthState {
  @override
  Future<AppUser?> build() async => null;
}

void main() {
  testWidgets('boots to the login screen when logged out', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // Skip the real drift/sqlite3 database plugin, which isn't
          // available in the widget-test environment.
          appDatabaseProvider.overrideWithValue(null),
          // Resolve instantly to "no user" instead of hitting secure storage
          // and the real API client.
          authStateProvider.overrideWith(_NoSessionAuthState.new),
        ],
        child: const UsamaBookDepotApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Usama Book Depot'), findsOneWidget);
    expect(find.text('Log in'), findsOneWidget);
  });
}
