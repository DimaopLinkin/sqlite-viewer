import 'dart:isolate';

import 'package:file_picker/file_picker.dart';
import 'package:sqlite3/sqlite3.dart';

import 'db_source.dart';
import 'models.dart';
import 'sqlite_reader.dart';

/// Opens a picked file on desktop and mobile.
Future<DbSource> openDbSource(PlatformFile file) async {
  final path = file.path;
  if (path == null) {
    throw StateError('The picked file has no path on this platform.');
  }
  return NativeDbSource.open(path, name: file.name);
}

/// Reads the database straight from disk in background isolates, so the file
/// is never loaded into memory and long queries do not block the UI.
///
/// Every call opens its own short-lived read-only connection inside
/// [Isolate.run]. Opening is cheap compared to the queries and keeps the
/// implementation free of long-lived isolate plumbing.
class NativeDbSource implements DbSource {
  NativeDbSource._(this._path, this.name, this._immutable);

  final String _path;
  final bool _immutable;

  @override
  final String name;

  @override
  String? get notice => _immutable
      ? 'Opened as a read-only snapshot: SQLite could not create its -shm '
            'file next to this WAL database, so changes still in the -wal '
            'file are not shown.'
      : null;

  static Future<NativeDbSource> open(
    String path, {
    required String name,
  }) async {
    final immutable = await Isolate.run(() => _probe(path));
    return NativeDbSource._(path, name, immutable);
  }

  /// Returns whether the file has to be opened with `immutable=1`.
  ///
  /// A plain read-only open fails for WAL databases when SQLite cannot create
  /// the `-shm` file next to them, for example in the macOS sandbox where only
  /// the picked file itself is accessible. Immutable mode reads the main file
  /// without any locking or side files.
  static bool _probe(String path) {
    try {
      _withReader(path, false, (r) => r.probe());
      return false;
    } on SqliteException {
      _withReader(path, true, (r) => r.probe());
      return true;
    }
  }

  static T _withReader<T>(
    String path,
    bool immutable,
    T Function(SqliteReader reader) action, {
    bool write = false,
  }) {
    final Database db;
    if (immutable) {
      final uri = Uri.file(path).replace(queryParameters: {'immutable': '1'});
      db = sqlite3.open(uri.toString(), mode: OpenMode.readOnly, uri: true);
    } else {
      db = sqlite3.open(
        path,
        mode: write ? OpenMode.readWrite : OpenMode.readOnly,
      );
    }
    try {
      // The viewer's own reads run in other isolates; let a write wait for
      // their shared locks instead of failing with "database is locked".
      if (write) db.execute('PRAGMA busy_timeout = 5000');
      return action(SqliteReader(db));
    } finally {
      db.close();
    }
  }

  Future<T> _run<T>(T Function(SqliteReader reader) action) {
    final path = _path;
    final immutable = _immutable;
    return Isolate.run(() => _withReader(path, immutable, action));
  }

  @override
  Future<List<TableInfo>> listTables() => _run((r) => r.listTables());

  @override
  Future<Map<String, int?>> countRows(List<String> tables) =>
      _run((r) => r.countRows(tables));

  @override
  Future<List<ColumnInfo>> columns(String table) =>
      _run((r) => r.columns(table));

  @override
  Future<int> count(TableQuery query) => _run((r) => r.count(query));

  @override
  Future<RowPage> page(
    TableQuery query, {
    required List<String> columns,
    required int limit,
    required int offset,
  }) => _run(
    (r) => r.page(query, columns: columns, limit: limit, offset: offset),
  );

  @override
  bool get canWrite => !_immutable;

  @override
  String? get writeNotice => null;

  @override
  Future<SqlResult> execute(String sql, {required bool allowWrites}) {
    final path = _path;
    final immutable = _immutable;
    final write = allowWrites && !immutable;
    return Isolate.run(() {
      final result = _withReader(
        path,
        immutable,
        (r) => r.execute(sql, allowWrites: write),
        write: write,
      );
      if (!write || !_journalFailed(result)) return result;
      // In the macOS sandbox only the picked file itself is writable, so
      // SQLite cannot create its -journal file next to it. Nothing was
      // written yet; run again with the rollback journal kept in memory.
      return _withReader(path, immutable, (r) {
        final mode = r.db.select('PRAGMA journal_mode').first.values.first;
        if (mode is! String || !_fileJournalModes.contains(mode)) {
          return result;
        }
        r.db.execute('PRAGMA journal_mode = MEMORY');
        return r.execute(sql, allowWrites: true);
      }, write: true);
    });
  }

  static const _fileJournalModes = {'delete', 'truncate', 'persist'};

  static bool _journalFailed(SqlResult result) {
    final error = result.error;
    // Retry only when nothing could have been committed.
    if (error == null ||
        result.wroteData ||
        result.rolledBack ||
        result.changes > 0) {
      return false;
    }
    final primary = error.code & 0xFF;
    return primary == _sqliteCantOpen ||
        primary == _sqliteIoErr ||
        error.code == _sqliteReadOnlyDirectory;
  }

  static const _sqliteIoErr = 10;
  static const _sqliteCantOpen = 14;
  static const _sqliteReadOnlyDirectory = 8 | (6 << 8);

  @override
  Future<void> close() async {}
}
