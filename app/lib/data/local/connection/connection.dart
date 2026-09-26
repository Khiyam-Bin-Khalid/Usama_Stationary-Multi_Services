import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Native (Android/iOS/desktop) SQLite connection via sqlite3. This file is
/// only imported on non-web platforms — see the conditional import in
/// app_database.dart, which swaps in connection_web.dart for web builds.
QueryExecutor openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'usama_book_depot.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
