import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:sqlite_viewer/data/db_source.dart';
import 'package:sqlite_viewer/data/models.dart';
import 'package:sqlite_viewer/data/sqlite_reader.dart';
import 'package:sqlite_viewer/main.dart';
import 'package:sqlite_viewer/ui/sql_console.dart';

/// Runs the real reader on an in-memory database, on the test isolate.
class _MemorySource implements DbSource {
  _MemorySource(this._db, {this.name = 'memory.sqlite'})
    : _reader = SqliteReader(_db);

  final Database _db;
  final SqliteReader _reader;

  @override
  final String name;

  @override
  String? get notice => null;

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
  bool get canWrite => true;

  @override
  String? get writeNotice => null;

  @override
  Future<SqlResult> execute(String sql, {required bool allowWrites}) async =>
      _reader.execute(sql, allowWrites: allowWrites);

  @override
  Future<void> close() async => _db.close();
}

DbSource _sampleSource() {
  final db = sqlite3.openInMemory()
    ..execute('''
      CREATE TABLE employee (local_id TEXT PRIMARY KEY, server_id INTEGER, note TEXT);
      CREATE TABLE general_agency (id INTEGER PRIMARY KEY, title TEXT);
      CREATE TABLE general_category (id INTEGER PRIMARY KEY);
    ''');
  final insert = db.prepare('INSERT INTO employee VALUES (?, ?, ?)');
  for (var i = 1; i <= 230; i++) {
    insert.execute(['uuid-$i', 1000 + i, i == 2 ? null : 'note $i']);
  }
  insert.close();
  return _MemorySource(db);
}

DbSource _otherSource() {
  final db = sqlite3.openInMemory()
    ..execute('''
      CREATE TABLE city (id INTEGER PRIMARY KEY, title TEXT);
      INSERT INTO city VALUES (1, 'Lisbon'), (2, 'Porto');
    ''');
  return _MemorySource(db, name: 'other.db');
}

void main() {
  Future<void> openApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      SqliteViewerApp(picker: () async => _sampleSource()),
    );
    await tester.tap(find.text('Open file…'));
    await tester.pumpAndSettle();
  }

  testWidgets('opens a file, lists tables and shows the first page', (
    tester,
  ) async {
    await openApp(tester);

    expect(find.text('memory.sqlite'), findsOneWidget);
    expect(find.text('general_agency'), findsOneWidget);
    expect(find.text('230'), findsOneWidget); // row count in the sidebar
    expect(find.text('Rows: 230'), findsOneWidget);
    expect(find.text('uuid-1'), findsOneWidget);
    expect(find.text('Page 1 / 3'), findsOneWidget);
    expect(find.text('NULL'), findsOneWidget);
  });

  testWidgets('filters the table list by name', (tester) async {
    await openApp(tester);
    await tester.enterText(
      find.widgetWithText(TextField, 'Filter 3 tables…'),
      'GENERAL',
    );
    await tester.pump();
    expect(find.text('general_agency'), findsOneWidget);
    expect(find.text('general_category'), findsOneWidget);
    // Still shown in the toolbar of the open table, gone from the list.
    expect(find.text('employee'), findsOneWidget);
  });

  testWidgets('column filter, sort and paging go through SQL', (tester) async {
    await openApp(tester);

    await tester.tap(find.byTooltip('Next page'));
    await tester.pumpAndSettle();
    expect(find.text('uuid-101'), findsOneWidget);
    expect(find.text('Page 2 / 3'), findsOneWidget);

    // Filter the "note" column.
    final filters = find.widgetWithText(TextField, 'Filter…');
    await tester.enterText(filters.at(2), 'NOTE 22');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('Rows: 11'), findsOneWidget); // 22, 220..229
    expect(find.text('Page 1 / 1'), findsOneWidget);

    // Sort by server_id descending (two taps).
    await tester.tap(find.text('server_id'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('server_id'));
    await tester.pumpAndSettle();
    final first = tester.getTopLeft(find.text('uuid-229'));
    final last = tester.getTopLeft(find.text('uuid-22'));
    expect(first.dy, lessThan(last.dy));
  });

  testWidgets('row dialog shows selectable values and navigates', (
    tester,
  ) async {
    await openApp(tester);
    await tester.tap(find.text('uuid-2'));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('employee  /  2', findRichText: true), findsOneWidget);
    final values = tester
        .widgetList<TextField>(
          find.descendant(
            of: find.byType(Dialog),
            matching: find.byType(TextField),
          ),
        )
        .toList();
    expect(values.map((f) => f.controller!.text), ['uuid-2', '1002', '']);
    expect(values.every((f) => f.readOnly), isTrue);

    await tester.tap(find.byTooltip('Next row (Alt+↓)'));
    await tester.pumpAndSettle();
    expect(find.text('employee  /  3', findRichText: true), findsOneWidget);
    expect(
      find.descendant(of: find.byType(Dialog), matching: find.text('uuid-3')),
      findsOneWidget,
    );
  });

  testWidgets('opens several files in tabs and keeps each tab state', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final sources = [_sampleSource, _otherSource];
    var opened = 0;
    await tester.pumpWidget(
      SqliteViewerApp(picker: () async => sources[opened++]()),
    );
    await tester.tap(find.text('Open file…'));
    await tester.pumpAndSettle();

    // Move the first file to page 2, then open a second file.
    await tester.tap(find.byTooltip('Next page'));
    await tester.pumpAndSettle();
    expect(find.text('Page 2 / 3'), findsOneWidget);

    await tester.tap(find.text('Open file'));
    await tester.pumpAndSettle();
    expect(find.text('memory.sqlite'), findsOneWidget);
    expect(find.text('other.db'), findsOneWidget);
    expect(find.text('Lisbon'), findsOneWidget);
    expect(find.text('uuid-101'), findsNothing);

    // Back to the first tab: its page is kept.
    await tester.tap(find.text('memory.sqlite'));
    await tester.pumpAndSettle();
    expect(find.text('uuid-101'), findsOneWidget);
    expect(find.text('Page 2 / 3'), findsOneWidget);
    expect(find.text('Lisbon'), findsNothing);

    // Closing the active first tab shows the remaining one.
    await tester.tap(find.byTooltip('Close tab').first);
    await tester.pumpAndSettle();
    expect(find.text('memory.sqlite'), findsNothing);
    expect(find.text('Lisbon'), findsOneWidget);

    await tester.tap(find.byTooltip('Close tab').first);
    await tester.pumpAndSettle();
    expect(find.text('Open file…'), findsOneWidget);
  });

  testWidgets('SQL console runs selects and writes', (tester) async {
    await openApp(tester);
    await tester.tap(find.text('SQL query'));
    await tester.pumpAndSettle();

    final editor = find.descendant(
      of: find.byType(SqlConsole),
      matching: find.byType(TextField),
    );
    await tester.enterText(
      editor,
      'SELECT local_id, server_id FROM employee WHERE server_id <= 1002',
    );
    await tester.tap(find.text('Run'));
    await tester.pumpAndSettle();
    expect(find.text('uuid-2'), findsOneWidget);
    expect(find.textContaining('2 rows · '), findsOneWidget);

    // Writes are off by default.
    await tester.enterText(
      editor,
      "INSERT INTO general_agency (title) VALUES ('new')",
    );
    await tester.tap(find.text('Run'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Allow writes” to change'), findsOneWidget);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Run'));
    await tester.pumpAndSettle();
    expect(find.textContaining('1 row affected'), findsOneWidget);
    // The sidebar count of the changed table is reloaded.
    expect(find.text('1'), findsWidgets);

    // The script stays when switching to a table and back.
    await tester.tap(find.text('general_agency'));
    await tester.pumpAndSettle();
    expect(find.text('new'), findsOneWidget);
    await tester.tap(find.text('SQL query'));
    await tester.pumpAndSettle();
    expect(find.textContaining('INSERT INTO general_agency'), findsOneWidget);
  });
}
