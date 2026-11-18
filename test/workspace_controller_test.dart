import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite_viewer/data/db_source.dart';
import 'package:sqlite_viewer/data/models.dart';
import 'package:sqlite_viewer/state/workspace_controller.dart';

class _FakeSource implements DbSource {
  _FakeSource(this.name);

  @override
  final String name;

  bool closed = false;

  @override
  String? get notice => null;

  @override
  Future<List<TableInfo>> listTables() async => const [];

  @override
  Future<Map<String, int?>> countRows(List<String> tables) async => const {};

  @override
  Future<List<ColumnInfo>> columns(String table) async => const [];

  @override
  Future<int> count(TableQuery query) async => 0;

  @override
  Future<RowPage> page(
    TableQuery query, {
    required List<String> columns,
    required int limit,
    required int offset,
  }) => throw UnimplementedError();

  @override
  bool get canWrite => false;

  @override
  String? get writeNotice => null;

  @override
  Future<SqlResult> execute(String sql, {required bool allowWrites}) =>
      throw UnimplementedError();

  @override
  Future<void> close() async => closed = true;
}

void main() {
  late WorkspaceController workspace;

  setUp(() => workspace = WorkspaceController());
  tearDown(() => workspace.dispose());

  List<String> names() => [for (final t in workspace.tabs) t.source.name];

  Future<void> openAll(List<String> list) async {
    for (final n in list) {
      await workspace.openWith(() async => _FakeSource(n));
    }
  }

  test('each opened file gets its own active tab', () async {
    await openAll(['a', 'b', 'c']);
    expect(names(), ['a', 'b', 'c']);
    expect(workspace.activeIndex, 2);
    workspace.activate(0);
    expect(workspace.active!.source.name, 'a');
  });

  test('reload marks the tab busy until the schema is read', () async {
    await openAll(['a']);
    final tab = workspace.active!;
    final reload = tab.reload();
    expect(tab.busy, isTrue);
    await reload;
    expect(tab.busy, isFalse);
    expect(tab.schemaVersion, 1);
  });

  test('cancelled picker changes nothing', () async {
    await openAll(['a']);
    await workspace.openWith(() async => null);
    expect(names(), ['a']);
    expect(workspace.opening, isFalse);
    expect(workspace.error, isNull);
  });

  test('failed open reports an error without a tab', () async {
    await workspace.openWith(() async => throw StateError('broken'));
    expect(workspace.tabs, isEmpty);
    expect(workspace.activeIndex, -1);
    expect(workspace.error, contains('broken'));
  });

  testWidgets('closing tabs keeps a sensible active tab and closes files', (
    tester,
  ) async {
    final sources = <_FakeSource>[];
    for (final n in ['a', 'b', 'c', 'd']) {
      await workspace.openWith(() async => sources.addAndReturn(n));
    }
    workspace.activate(2); // c
    workspace.closeTab(0); // a, left of active
    expect(workspace.active!.source.name, 'c');
    workspace.closeTab(1); // c itself → the tab to its right
    expect(workspace.active!.source.name, 'd');
    workspace.closeTab(1); // d, the last → the tab to its left
    expect(workspace.active!.source.name, 'b');
    workspace.closeTab(0);
    expect(workspace.active, isNull);
    // Files close after the frame that removes their widgets.
    expect(sources.any((s) => s.closed), isFalse);
    await tester.pump();
    expect(sources.every((s) => s.closed), isTrue);
  });
}

extension on List<_FakeSource> {
  _FakeSource addAndReturn(String name) {
    final s = _FakeSource(name);
    add(s);
    return s;
  }
}
