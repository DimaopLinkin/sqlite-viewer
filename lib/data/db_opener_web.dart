import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:sqlite3/wasm.dart';
import 'package:typed_data/typed_buffers.dart';

import 'db_source.dart';
import 'models.dart';
import 'sqlite_reader.dart';

/// Opens a picked file in the browser.
Future<DbSource> openDbSource(PlatformFile file) async {
  final bytes = await file.readAsBytes();
  return WebDbSource.open(bytes, name: file.name);
}

Future<WasmSqlite3>? _sqlite;
var _nextFile = 0;

/// Runs queries on the WASM build of SQLite over an in-memory copy of the
/// file. Browsers cannot read local files by path, so the bytes are loaded
/// once when the file is picked.
class WebDbSource implements DbSource {
  WebDbSource._(this.name, this._db, this._reader, this._fs, this._path);

  @override
  final String name;

  @override
  String? get notice => null;
  final CommonDatabase _db;
  final SqliteReader _reader;
  final InMemoryFileSystem _fs;
  final String _path;

  static Future<WebDbSource> open(
    Uint8List bytes, {
    required String name,
  }) async {
    final sqlite = await (_sqlite ??= _load());
    final fs = InMemoryFileSystem(name: 'sv-memory-$_nextFile');
    final path = '/db-${_nextFile++}.sqlite';
    final data = Uint8Buffer()..addAll(bytes);
    // The WASM build has no shared memory for WAL. Switching the header's
    // read/write versions back to the rollback journal (1) makes SQLite read
    // the copy as an ordinary database; the original file is untouched.
    if (data.length > 19 && data[18] == 2 && data[19] == 2) {
      data[18] = 1;
      data[19] = 1;
    }
    fs.fileData[path] = data;
    sqlite.registerVirtualFileSystem(fs);
    try {
      final db = sqlite.open(path, vfs: fs.name, mode: OpenMode.readOnly);
      final reader = SqliteReader(db);
      try {
        reader.probe();
      } catch (_) {
        db.close();
        rethrow;
      }
      return WebDbSource._(name, db, reader, fs, path);
    } catch (_) {
      sqlite.unregisterVirtualFileSystem(fs);
      rethrow;
    }
  }

  static Future<WasmSqlite3> _load() =>
      WasmSqlite3.loadFromUrl(Uri.base.resolve('sqlite3.wasm'));

  @override
  Future<List<TableInfo>> listTables() async => _reader.listTables();

  @override
  Future<Map<String, int?>> countRows(List<String> tables) async =>
      _reader.countRows(tables);

  @override
  Future<List<ColumnInfo>> columns(String table) async =>
      _reader.columns(table);

  @override
  Future<int> count(TableQuery query) async => _reader.count(query);

  @override
  Future<RowPage> page(
    TableQuery query, {
    required List<String> columns,
    required int limit,
    required int offset,
  }) async =>
      _reader.page(query, columns: columns, limit: limit, offset: offset);

  @override
  Future<void> close() async {
    _db.close();
    _fs.fileData.remove(_path);
    (await _sqlite)?.unregisterVirtualFileSystem(_fs);
  }
}
