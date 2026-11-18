import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:sqlite_viewer/data/db_opener_native.dart';
import 'package:sqlite_viewer/data/models.dart';
import 'package:sqlite_viewer/data/sqlite_reader.dart';
import 'package:sqlite_viewer/ui/sql_console.dart';

void main() {
  late Database db;
  late SqliteReader reader;

  setUp(() {
    db = sqlite3.openInMemory()
      ..execute('''
        CREATE TABLE item (id INTEGER PRIMARY KEY, name TEXT);
        INSERT INTO item (name) VALUES ('a'), ('b'), ('c');
      ''');
    reader = SqliteReader(db);
  });

  tearDown(() => db.close());

  SqlResult run(String sql, {bool write = false}) =>
      reader.execute(sql, allowWrites: write);

  test('select returns columns and rows', () {
    final r = run('SELECT id, name AS title FROM item ORDER BY id');
    expect(r.error, isNull);
    expect(r.columns, ['id', 'title']);
    expect(r.rows, [
      [1, 'a'],
      [2, 'b'],
      [3, 'c'],
    ]);
    expect(r.wroteData, isFalse);
    expect(describeSqlResult(r), startsWith('3 rows · '));
  });

  test('writes are rejected unless allowed', () {
    final r = run("INSERT INTO item (name) VALUES ('d')");
    expect(r.error, isNotNull);
    expect(r.error!.code & 0xFF, 8); // SQLITE_READONLY
    expect(r.wroteData, isFalse);
    expect(run('SELECT count(*) FROM item').rows.single.single, 3);
    expect(
      describeSqlError(r.error!, r, writesOff: true),
      contains('Allow writes'),
    );
  });

  test('insert, update and delete report affected rows', () {
    final insert = run(
      "INSERT INTO item (name) VALUES ('d'), ('e')",
      write: true,
    );
    expect(insert.error, isNull);
    expect(insert.changes, 2);
    expect(insert.lastInsertRowId, 5);
    expect(insert.wroteData, isTrue);
    expect(insert.hasResultSet, isFalse);
    expect(describeSqlResult(insert), contains('2 rows affected'));

    final update = run("UPDATE item SET name = 'x' WHERE id > 3", write: true);
    expect(update.changes, 2);
    expect(update.lastInsertRowId, isNull);

    final delete = run('DELETE FROM item WHERE id = 1', write: true);
    expect(delete.changes, 1);
    expect(run('SELECT count(*) FROM item').rows.single.single, 4);
  });

  test('read-only mode is restored after a write run', () {
    run("INSERT INTO item (name) VALUES ('d')", write: true);
    expect(run("INSERT INTO item (name) VALUES ('e')").error, isNotNull);
  });

  test('later statements see tables created by earlier ones', () {
    final r = run('''
      -- set up
      CREATE TABLE t (x);;
      INSERT INTO t VALUES (1), (2);
      SELECT x * 10 AS v FROM t ORDER BY x;
      -- trailing comment
    ''', write: true);
    expect(r.error, isNull);
    expect(r.statementCount, 3);
    expect(r.changes, 2);
    expect(r.columns, ['v']);
    expect(r.rows, [
      [10],
      [20],
    ]);
  });

  test('a failing statement stops the script and is located', () {
    const sql = "INSERT INTO item (name) VALUES ('d');\nSELEC 1;\nSELECT 2;";
    final r = run(sql, write: true);
    expect(r.statementCount, 1);
    expect(r.changes, 1);
    expect(r.error!.statementIndex, 1);
    expect(r.error!.message, contains('syntax error'));
    expect(r.error!.offset, sql.indexOf('SELEC 1'));
    expect(
      describeSqlError(r.error!, r, writesOff: true),
      allOf(startsWith('Statement 2: '), contains('changed 1 row')),
    );
  });

  test('runtime errors are reported', () {
    final r = run('SELECT * FROM missing');
    expect(r.error!.message, contains('no such table'));
    expect(r.error!.statementIndex, 0);
  });

  test('an open transaction is rolled back', () {
    final r = run("BEGIN; INSERT INTO item (name) VALUES ('d');", write: true);
    expect(r.rolledBack, isTrue);
    expect(r.wroteData, isFalse);
    expect(db.autocommit, isTrue);
    expect(run('SELECT count(*) FROM item').rows.single.single, 3);

    final committed = run(
      "BEGIN; INSERT INTO item (name) VALUES ('d'); COMMIT;",
      write: true,
    );
    expect(committed.rolledBack, isFalse);
    expect(committed.changes, 1);
  });

  test('writes committed before an open transaction are kept', () {
    final r = run(
      "INSERT INTO item (name) VALUES ('d'); BEGIN; "
      "INSERT INTO item (name) VALUES ('e');",
      write: true,
    );
    expect(r.rolledBack, isTrue);
    expect(r.wroteData, isTrue);
    expect(r.changes, 1);
    expect(r.lastInsertRowId, 4);
    expect(run('SELECT count(*) FROM item').rows.single.single, 4);
  });

  test('comments before a statement do not shift the next one', () {
    final r = run('/* select 1 */; select 1; -- x\n/* ; */ select 2 AS v');
    expect(r.error, isNull);
    expect(r.statementCount, 2);
    expect(r.columns, ['v']);
  });

  test('large results are cut', () {
    final r = run(
      'WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n '
      'WHERE i < ${SqlResult.maxRows + 5}) SELECT i FROM n',
    );
    expect(r.rows.length, SqlResult.maxRows);
    expect(r.truncated, isTrue);
  });

  test('returning rows of a write are shown', () {
    final r = run(
      "INSERT INTO item (name) VALUES ('d') RETURNING id, name",
      write: true,
    );
    expect(r.rows, [
      [4, 'd'],
    ]);
    expect(r.changes, 1);
  });

  test('only comments or whitespace do nothing', () {
    final r = run('  -- nothing\n  ;  ');
    expect(r.error, isNull);
    expect(r.statementCount, 0);
    expect(describeSqlResult(r), startsWith('Done'));
  });

  test('non-ASCII text before an error keeps the offset right', () {
    const sql = "SELECT 'привет';\nSELEC 1";
    final r = run(sql);
    expect(r.error!.offset, sql.indexOf('SELEC 1'));
  });

  group('NativeDbSource.execute', () {
    late Directory dir;
    late String path;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('sv_sql');
      path = '${dir.path}/test.sqlite';
      sqlite3.open(path)
        ..execute('CREATE TABLE t (x); INSERT INTO t VALUES (1);')
        ..close();
    });

    tearDown(() => dir.deleteSync(recursive: true));

    test('writes to the file only when allowed', () async {
      final source = await NativeDbSource.open(path, name: 'test.sqlite');
      expect(source.canWrite, isTrue);

      final denied = await source.execute(
        'INSERT INTO t VALUES (2)',
        allowWrites: false,
      );
      expect(denied.error, isNotNull);

      final ok = await source.execute(
        'INSERT INTO t VALUES (2)',
        allowWrites: true,
      );
      expect(ok.error, isNull);
      expect(ok.changes, 1);

      final check = sqlite3.open(path);
      addTearDown(check.close);
      expect(check.select('SELECT count(*) FROM t').single.values.single, 2);
    });
  });
}
