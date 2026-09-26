import 'package:drift/drift.dart';

/// Web never constructs AppDatabase (see main.dart / provider setup) — the
/// storefront web app always talks to the API directly, since the SRS
/// requires the web app to have an internet connection and only the
/// desktop/mobile POS side needs offline SQLite. This stub exists purely so
/// the shared data layer compiles for the web target without pulling in
/// dart:io/dart:ffi.
QueryExecutor openConnection() {
  throw UnsupportedError(
    'Local SQLite storage is not available on web. This should never be called — '
    'web builds must not construct AppDatabase.',
  );
}
