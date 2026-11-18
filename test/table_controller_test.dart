import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite_viewer/data/db_source.dart';
import 'package:sqlite_viewer/data/models.dart';
import 'package:sqlite_viewer/state/table_controller.dart';

/// A source whose counts finish only when the test says so.
class _SlowCountSource implements DbSource {
  final counts = <Completer<int>>[];
  final pages = <TableQuery>[];

  @override
  String get name => 'slow';

  @override
  String? get notice => null;

  @override
  Future<List<TableInfo>> listTables() async => const [];

  @override
  Future<Map<String, int?>> countRows(List<String> tables) async => const {};

  @override
  Future<List<ColumnInfo>> columns(String table) async => const [
    ColumnInfo(
      name: 'a',
      declaredType: 'TEXT',
      notNull: false,
      primaryKeyIndex: 0,
    ),
  ];

  @override
  Future<int> count(TableQuery query) {
    final c = Completer<int>();
    counts.add(c);
    return c.future;
  }

  @override
  Future<RowPage> page(
    TableQuery query, {
    required List<String> columns,
    required int limit,
    required int offset,
  }) async {
    pages.add(query);
    return RowPage(
      offset: offset,
      rows: const [
        ['x'],
      ],
    );
  }

  @override
  bool get canWrite => false;

  @override
  String? get writeNotice => null;

  @override
  Future<SqlResult> execute(String sql, {required bool allowWrites}) =>
      throw UnimplementedError();

  @override
  Future<void> close() async {}
}

void main() {
  test('sorting while counting keeps the count', () async {
    final source = _SlowCountSource();
    final controller = TableController(
      source: source,
      table: const TableInfo(name: 't', kind: TableKind.table),
      filterDebounce: Duration.zero,
    );
    await pumpEventQueue();
    expect(source.counts, hasLength(1));

    controller.toggleSort('a');
    await pumpEventQueue();
    source.counts.single.complete(1234);
    await pumpEventQueue();

    expect(controller.total, 1234);
    expect(controller.pageCount, 13);
    expect(source.pages.last.sort, const SortSpec('a', SortDirection.asc));
    controller.dispose();
  });

  test('a newer filter count wins over an older one', () async {
    final source = _SlowCountSource();
    final controller = TableController(
      source: source,
      table: const TableInfo(name: 't', kind: TableKind.table),
      filterDebounce: Duration.zero,
    );
    await pumpEventQueue();
    controller.setFilter('a', value: 'x');
    await pumpEventQueue();
    expect(source.counts, hasLength(2));
    source.counts[1].complete(5);
    source.counts[0].complete(1000);
    await pumpEventQueue();
    expect(controller.total, 5);
    controller.dispose();
  });
}
