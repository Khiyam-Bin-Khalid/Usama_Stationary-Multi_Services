import 'dart:ffi';
import 'package:sqlite3/open.dart';

/// `flutter test` runs without the app's bundled SQLite, so use the system's.
void useSystemSqlite() {
  open.overrideFor(OperatingSystem.linux, () => DynamicLibrary.open('libsqlite3.so.0'));
}
