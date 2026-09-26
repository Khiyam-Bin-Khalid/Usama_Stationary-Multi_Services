import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/providers.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_background.dart';
import 'core/theme/app_theme.dart';

void main() {
  runApp(const ProviderScope(child: UsamaBookDepotApp()));
}

class UsamaBookDepotApp extends ConsumerWidget {
  const UsamaBookDepotApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Touch appDatabaseProvider/syncServiceProvider once at the root so the
    // offline sync loop starts as soon as the app launches, not only when
    // the POS screen happens to be visited first.
    ref.watch(syncServiceProvider);
    final router = ref.watch(goRouterProvider);

    return MaterialApp.router(
      title: 'Usama Book Depot',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      routerConfig: router,
      // Brand gradient behind every route; scaffolds are transparent (AppTheme).
      builder: (context, child) => AppBackground(child: child ?? const SizedBox.shrink()),
    );
  }
}
