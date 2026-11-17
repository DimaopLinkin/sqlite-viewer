import 'models.dart';

/// Read-only access to an opened SQLite file.
///
/// All methods are asynchronous so the native implementation can run queries
/// off the UI isolate.
abstract interface class DbSource {
  /// Display name, usually the file name.
  String get name;

  /// Something the user should know about how the file was opened, or
  /// `null`.
  String? get notice;

  Future<List<TableInfo>> listTables();

  Future<Map<String, int?>> countRows(List<String> tables);

  Future<List<ColumnInfo>> columns(String table);

  Future<int> count(TableQuery query);

  Future<RowPage> page(
    TableQuery query, {
    required List<String> columns,
    required int limit,
    required int offset,
  });

  Future<void> close();
}
