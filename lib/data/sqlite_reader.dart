import 'dart:convert';

import 'package:sqlite3/common.dart';

import 'models.dart';
import 'query_builder.dart';

/// Synchronous queries over an open SQLite connection.
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

  /// Runs a user-written script statement by statement.
  ///
  /// Statements are prepared one at a time, so later statements can use
  /// tables created by earlier ones. With [allowWrites] off the connection is
  /// switched to `query_only`, so anything that would change the file fails
  /// with an error instead. A transaction the script leaves open is rolled
  /// back, because the connection is shared with the viewer (web) or closed
  /// right after (native).
  SqlResult execute(String sql, {required bool allowWrites}) {
    final watch = Stopwatch()..start();
    db.execute('PRAGMA query_only = ${allowWrites ? 0 : 1}');
    final changesBefore = _totalChanges();
    final rowIdBefore = db.lastInsertRowId;

    var consumed = 0;
    var statements = 0;
    var wrote = false;
    var columns = const <String>[];
    var rows = const <List<Object?>>[];
    var truncated = false;
    SqlScriptError? error;

    while (true) {
      // Empty statements (stray semicolons) would make SQLite skip ahead
      // without returning a statement, so drop them here.
      while (consumed < sql.length && _isSeparator(sql.codeUnitAt(consumed))) {
        consumed++;
      }
      if (consumed >= sql.length) break;
      final rest = sql.substring(consumed);
      final CommonPreparedStatement statement;
      try {
        statement = db.prepare(rest);
      } on ArgumentError {
        break; // Only whitespace or comments are left.
      } on SqliteException catch (e) {
        error = _error(e, statements, rest, consumed);
        break;
      }
      try {
        final readOnly = statement.isReadOnly;
        final cursor = statement.iterateWith(const StatementParameters.empty());
        if (cursor.columnNames.isEmpty) {
          while (cursor.moveNext()) {}
        } else {
          final kept = <List<Object?>>[];
          var more = false;
          while (cursor.moveNext()) {
            if (kept.length < SqlResult.maxRows) {
              kept.add(List.of(cursor.current.values));
            } else {
              more = true;
              // A write with RETURNING has to run to the end; a read can stop.
              if (readOnly) break;
            }
          }
          columns = List.unmodifiable(cursor.columnNames);
          rows = kept;
          truncated = more;
        }
        statements++;
        if (!readOnly) wrote = true;
      } on SqliteException catch (e) {
        error = _error(e, statements, rest, consumed);
        break;
      } finally {
        statement.close();
      }
      // The statement text starts at the beginning of [rest] unless SQLite
      // skipped an empty statement hidden behind a comment.
      final start = rest.indexOf(statement.sql);
      consumed += (start < 0 ? 0 : start) + statement.sql.length;
    }

    final rolledBack = !db.autocommit;
    if (rolledBack) db.execute('ROLLBACK');
    final changes = _totalChanges() - changesBefore;
    final rowId = db.lastInsertRowId;
    db.execute('PRAGMA query_only = 1');
    return SqlResult(
      statementCount: statements,
      columns: columns,
      rows: rows,
      truncated: truncated,
      changes: rolledBack ? 0 : changes,
      wroteData: wrote && !rolledBack,
      rolledBack: rolledBack,
      lastInsertRowId: !rolledBack && rowId != rowIdBefore ? rowId : null,
      elapsed: watch.elapsed,
      error: error,
    );
  }

  static bool _isSeparator(int c) =>
      c == 0x3B || c == 0x20 || c == 0x0A || c == 0x0D || c == 0x09;

  int _totalChanges() =>
      _asInt(db.select('SELECT total_changes()').rows.first.first);

  static SqlScriptError _error(
    SqliteException e,
    int statementIndex,
    String rest,
    int consumed,
  ) {
    int? offset;
    if (e.offset case final bytes? when bytes >= 0) {
      // SQLite reports a byte offset into the UTF-8 text of the statement.
      final encoded = utf8.encode(rest);
      final end = bytes > encoded.length ? encoded.length : bytes;
      offset =
          consumed +
          utf8.decode(encoded.sublist(0, end), allowMalformed: true).length;
    }
    return SqlScriptError(
      message: e.message,
      code: e.extendedResultCode,
      statementIndex: statementIndex,
      offset: offset,
    );
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
