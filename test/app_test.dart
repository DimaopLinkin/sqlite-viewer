import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:sqlite_viewer/data/db_source.dart';
import 'package:sqlite_viewer/data/models.dart';
import 'package:sqlite_viewer/data/sqlite_reader.dart';
import 'package:sqlite_viewer/main.dart';

/// Runs the real reader on an in-memory database, on the test isolate.
class _MemorySource implements DbSource {
  _MemorySource(this._db) : _reader = SqliteReader(_db);

  final Database _db;
  final SqliteReader _reader;

  @override
  String get name => 'memory.sqlite';

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
  Future<List<ForeignKey>> foreignKeys(String table) async =>
      _reader.foreignKeys(table);

  @override
  Future<ReferencedRow?> referencedRow(
    ForeignKey key,
    List<Object?> values,
  ) async => _reader.referencedRow(key, values);

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
  Future<void> close() async => _db.close();
}

DbSource _sampleSource() {
  final db = sqlite3.openInMemory()
    ..execute('''
      CREATE TABLE employee (local_id TEXT PRIMARY KEY, server_id INTEGER, note TEXT,
        agency_id INTEGER REFERENCES general_agency(id));
      CREATE TABLE general_agency (id INTEGER PRIMARY KEY, title TEXT,
        category_id INTEGER REFERENCES general_category);
      CREATE TABLE general_category (id INTEGER PRIMARY KEY, label TEXT);
      INSERT INTO general_category VALUES (7, 'Retail');
      INSERT INTO general_agency VALUES (1, 'Agency one', 7), (2, 'Agency two', NULL);
    ''');
  final insert = db.prepare('INSERT INTO employee VALUES (?, ?, ?, ?)');
  for (var i = 1; i <= 230; i++) {
    insert.execute([
      'uuid-$i',
      1000 + i,
      i == 2 ? null : 'note $i',
      i == 1 ? null : (i.isEven ? 1 : 2),
    ]);
  }
  insert.close();
  return _MemorySource(db);
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
    expect(find.text('NULL'), findsNWidgets(2));
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
    expect(values.map((f) => f.controller!.text), ['uuid-2', '1002', '', '1']);
    expect(values.every((f) => f.readOnly), isTrue);

    await tester.tap(find.byTooltip('Next row (Alt+↓)'));
    await tester.pumpAndSettle();
    expect(find.text('employee  /  3', findRichText: true), findsOneWidget);
    expect(
      find.descendant(of: find.byType(Dialog), matching: find.text('uuid-3')),
      findsOneWidget,
    );
  });

  testWidgets('row dialog expands referenced rows', (tester) async {
    await openApp(tester);
    await tester.tap(find.text('uuid-2'));
    await tester.pumpAndSettle();

    final toggle = find.text('general_agency (id)');
    expect(toggle, findsOneWidget);
    expect(find.text('Agency one'), findsNothing);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(find.text('Agency one'), findsOneWidget);

    // The parent's own key can be followed too.
    await tester.tap(find.text('general_category (id)'));
    await tester.pumpAndSettle();
    expect(find.text('Retail'), findsOneWidget);

    // Stays open on the next row, showing that row's parent.
    await tester.tap(find.byTooltip('Next row (Alt+↓)'));
    await tester.pumpAndSettle();
    expect(find.text('Agency two'), findsOneWidget);
    expect(find.text('Agency one'), findsNothing);
    expect(find.text('general_category (id)'), findsNothing); // NULL

    // A NULL reference cannot be expanded.
    await tester.tap(find.byTooltip('Previous row (Alt+↑)'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Previous row (Alt+↑)'));
    await tester.pumpAndSettle();
    expect(find.text('employee  /  1', findRichText: true), findsOneWidget);
    expect(find.text('Agency one'), findsNothing);
    expect(find.text('Agency two'), findsNothing);
  });
}
