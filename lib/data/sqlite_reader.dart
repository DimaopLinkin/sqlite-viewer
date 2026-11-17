import 'package:sqlite3/common.dart';

import 'models.dart';
import 'query_builder.dart';

/// Synchronous read-only queries over an open SQLite connection.
///
/// Shared by the native implementation (which runs it inside a background
/// isolate) and the web implementation (which runs it on the WASM build).
class SqliteReader {
  SqliteReader(this.db) {
    _registerFunctions(db);
  }

  final CommonDatabase db;

  /// Sanity check that the file is a readable SQLite database.
  void probe() => db.select('SELECT COUNT(*) FROM sqlite_schema');

  List<TableInfo> listTables() {
    final result = db.select(
      "SELECT name, type FROM sqlite_schema "
      "WHERE type IN ('table', 'view') AND name NOT LIKE 'sqlite\\_%' ESCAPE '\\' "
      'ORDER BY name COLLATE NOCASE',
    );
    return [
      for (final row in result)
        TableInfo(
          name: row['name'] as String,
          kind: row['type'] == 'view' ? TableKind.view : TableKind.table,
        ),
    ];
  }

  /// Row count per table. A table that cannot be counted (for example a view
  /// over a missing table, or a virtual table with an unknown module) maps to
  /// `null` instead of failing the whole batch.
  Map<String, int?> countRows(List<String> tables) {
    return {for (final table in tables) table: _tryCount(table)};
  }

  int? _tryCount(String table) {
    try {
      return count(TableQuery(table: table));
    } on SqliteException {
      return null;
    }
  }

  List<ColumnInfo> columns(String table) {
    final result = db.select(
      'SELECT name, type, "notnull", dflt_value, pk, hidden '
      'FROM pragma_table_xinfo(?)',
      [table],
    );
    return [
      for (final row in result)
        // hidden = 1 marks hidden columns of virtual tables; generated columns
        // (2 and 3) are regular values for a viewer.
        if (row['hidden'] != 1)
          ColumnInfo(
            name: row['name'] as String,
            declaredType: (row['type'] as String?) ?? '',
            notNull: row['notnull'] == 1,
            primaryKeyIndex: (row['pk'] as int?) ?? 0,
            defaultValue: row['dflt_value']?.toString(),
          ),
    ];
  }

  int count(TableQuery query) {
    final statement = QueryBuilder.count(query);
    final result = db.select(statement.sql, statement.args);
    return _asInt(result.rows.first.first);
  }

  RowPage page(
    TableQuery query, {
    required List<String> columns,
    required int limit,
    required int offset,
  }) {
    final statement = QueryBuilder.page(
      query,
      columns: columns,
      limit: limit,
      offset: offset,
    );
    final result = db.select(statement.sql, statement.args);
    return RowPage(offset: offset, rows: result.rows);
  }

  static int _asInt(Object? value) => switch (value) {
    final int v => v,
    final BigInt v => v.toInt(),
    _ => 0,
  };

  static void _registerFunctions(CommonDatabase db) {
    void register(String name, bool Function(String text, String needle) test) {
      db.createFunction(
        functionName: name,
        argumentCount: const AllowedArgumentCount(2),
        deterministic: true,
        function: (args) {
          final text = args[0];
          final needle = args[1];
          if (text is! String || needle is! String) return 0;
          return test(text.toLowerCase(), needle.toLowerCase()) ? 1 : 0;
        },
      );
    }

    register(SqlFunctions.contains, (t, n) => t.contains(n));
    register(SqlFunctions.startsWith, (t, n) => t.startsWith(n));
    register(SqlFunctions.endsWith, (t, n) => t.endsWith(n));
  }
}
