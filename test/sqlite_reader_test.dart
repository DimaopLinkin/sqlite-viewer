import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:sqlite_viewer/data/db_opener_native.dart';
import 'package:sqlite_viewer/data/models.dart';
import 'package:sqlite_viewer/data/query_builder.dart';
import 'package:sqlite_viewer/data/sqlite_reader.dart';

void main() {
  late Database db;
  late SqliteReader reader;

  setUp(() {
    db = sqlite3.openInMemory();
    db.execute('''
      CREATE TABLE "my ""table""" (
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        score REAL,
        data BLOB
      );
      CREATE TABLE empty_one (x);
      CREATE VIEW high_scores AS SELECT * FROM "my ""table""" WHERE score > 5;
    ''');
    final insert = db.prepare(
      'INSERT INTO "my ""table""" (name, score, data) VALUES (?, ?, ?)',
    );
    for (var i = 1; i <= 250; i++) {
      insert.execute([
        i.isEven ? 'Иван $i' : 'Petr $i',
        i == 7 ? null : i / 10,
        i == 3 ? Uint8List.fromList([1, 2, 255]) : null,
      ]);
    }
    insert.close();
    reader = SqliteReader(db);
  });

  tearDown(() => db.close());

  const table = 'my "table"';

  test('lists tables and views without internal tables', () {
    expect(reader.listTables(), [
      const TableInfo(name: 'empty_one', kind: TableKind.table),
      const TableInfo(name: 'high_scores', kind: TableKind.view),
      const TableInfo(name: table, kind: TableKind.table),
    ]);
  });

  test('counts rows per table', () {
    expect(reader.countRows([table, 'empty_one', 'high_scores', 'missing']), {
      table: 250,
      'empty_one': 0,
      'high_scores': 200,
      'missing': null,
    });
  });

  test('reads column metadata', () {
    final columns = reader.columns(table);
    expect([for (final c in columns) c.name], ['id', 'name', 'score', 'data']);
    expect(columns[0].isPrimaryKey, isTrue);
    expect(columns[0].affinity, ColumnAffinity.integer);
    expect(columns[1].notNull, isTrue);
    expect(columns[1].affinity, ColumnAffinity.text);
    expect(columns[2].affinity, ColumnAffinity.real);
    expect(reader.columns('empty_one').single.affinity, ColumnAffinity.blob);
  });

  test('pages with limit and offset', () {
    final page = reader.page(
      const TableQuery(table: table),
      columns: const ['id', 'data'],
      limit: 100,
      offset: 200,
    );
    expect(page.offset, 200);
    expect(page.rows.length, 50);
    expect(page.rows.first, [201, null]);
    final third = reader.page(
      const TableQuery(table: table),
      columns: const ['data'],
      limit: 1,
      offset: 2,
    );
    expect(third.rows.single.single, Uint8List.fromList([1, 2, 255]));
  });

  test('sorts by a column', () {
    final page = reader.page(
      const TableQuery(table: table, sort: SortSpec('id', SortDirection.desc)),
      columns: const ['id'],
      limit: 3,
      offset: 0,
    );
    expect(page.rows, [
      [250],
      [249],
      [248],
    ]);
  });

  int countWhere(FilterOperator op, [String value = '', String col = 'name']) =>
      reader.count(
        TableQuery(
          table: table,
          filters: [ColumnFilter(column: col, op: op, value: value)],
        ),
      );

  test('contains is case-insensitive for Cyrillic', () {
    expect(countWhere(FilterOperator.contains, 'иВАН'), 125);
    expect(countWhere(FilterOperator.notContains, 'иван'), 125);
    expect(countWhere(FilterOperator.startsWith, 'petr 1'), 56);
    expect(countWhere(FilterOperator.endsWith, ' 9'), 1);
  });

  test('numeric filters compare numbers', () {
    expect(countWhere(FilterOperator.equals, '1', 'score'), 1);
    expect(countWhere(FilterOperator.equals, '1.0', 'score'), 1);
    expect(countWhere(FilterOperator.greaterThan, '24', 'score'), 10);
    expect(countWhere(FilterOperator.lessOrEqual, '0.2', 'score'), 2);
    expect(countWhere(FilterOperator.notEquals, '1', 'score'), 249);
  });

  test('numeric filters compare numbers stored as text numerically', () {
    db.execute(
      "CREATE TABLE t (v TEXT); INSERT INTO t VALUES ('9'), ('10'), ('100'), (NULL);",
    );
    expect(
      reader.count(
        const TableQuery(
          table: 't',
          filters: [
            ColumnFilter(
              column: 'v',
              op: FilterOperator.greaterThan,
              value: '5',
            ),
          ],
        ),
      ),
      3,
    );
  });

  test('null and empty filters', () {
    expect(countWhere(FilterOperator.isNull, '', 'score'), 1);
    expect(countWhere(FilterOperator.isNotNull, '', 'score'), 249);
    expect(countWhere(FilterOperator.isNotEmpty, '', 'data'), 1);
    expect(countWhere(FilterOperator.isEmpty, '', 'name'), 0);
  });

  test('inactive filters are ignored', () {
    expect(countWhere(FilterOperator.contains, ''), 250);
  });

  test('filter values are bound, not interpolated', () {
    expect(countWhere(FilterOperator.equals, "x' OR 1=1 --"), 0);
    final statement = QueryBuilder.condition(
      const ColumnFilter(
        column: 'a"b',
        op: FilterOperator.equals,
        value: "x' OR 1=1",
      ),
    );
    expect(statement.sql, 'CAST("a""b" AS TEXT) = ?');
    expect(statement.args, ["x' OR 1=1"]);
  });

  group('NativeDbSource', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('sv_test'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('reads a file in background isolates', () async {
      final path = '${dir.path}/test.sqlite';
      db.execute('VACUUM INTO ?', [path]);
      final source = await NativeDbSource.open(path, name: 'test.sqlite');
      expect((await source.listTables()).length, 3);
      expect(await source.count(const TableQuery(table: table)), 250);
      final page = await source.page(
        const TableQuery(table: table),
        columns: const ['name'],
        limit: 2,
        offset: 0,
      );
      expect(page.rows, [
        ['Petr 1'],
        ['Иван 2'],
      ]);
    });

    test('opens WAL databases read-only', () async {
      final path = '${dir.path}/wal.sqlite';
      final file = sqlite3.open(path)
        ..execute('PRAGMA journal_mode=WAL')
        ..execute('CREATE TABLE t (x); INSERT INTO t VALUES (1), (2);');
      file.close();
      final source = await NativeDbSource.open(path, name: 'wal.sqlite');
      expect(await source.count(const TableQuery(table: 't')), 2);
    });

    test('rejects files that are not databases', () async {
      final path = '${dir.path}/text.txt';
      File(path).writeAsStringSync('definitely not sqlite ' * 100);
      expect(
        NativeDbSource.open(path, name: 'text.txt'),
        throwsA(isA<SqliteException>()),
      );
    });
  });
}
