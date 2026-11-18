import 'package:flutter/foundation.dart';

import '../data/db_source.dart';
import '../data/models.dart';
import 'sql_controller.dart';

/// State of one open file (one tab): its tables and the selected table.
///
/// Owns [source] and closes it on [dispose].
class ViewerController extends ChangeNotifier {
  ViewerController({required this.source, required List<TableInfo> tables})
    : _tables = tables,
      _selected = _defaultSelection(tables) {
    _loadCounts(_generation);
  }

  /// Opens a file with [open] and reads its table list. Returns `null` when
  /// [open] does (the user cancelled the picker). Throws if the file cannot
  /// be read; the source is closed then.
  static Future<ViewerController?> openWith(
    Future<DbSource?> Function() open,
  ) async {
    final source = await open();
    if (source == null) return null;
    try {
      final tables = await source.listTables();
      return ViewerController(source: source, tables: tables);
    } catch (_) {
      await source.close();
      rethrow;
    }
  }

  final DbSource source;

  List<TableInfo> _tables;
  List<TableInfo> get tables => _tables;

  /// Row counts arrive after the table list; missing key means "loading",
  /// `null` value means the table could not be counted.
  Map<String, int?> _rowCounts = const {};
  Map<String, int?> get rowCounts => _rowCounts;

  TableInfo? _selected;
  TableInfo? get selected => _selected;

  /// SQL console of this file; its script and result survive switching to a
  /// table and back.
  late final sql = SqlController(source: source, onDataChanged: reload);

  /// The SQL console is shown instead of the selected table.
  bool _sqlOpen = false;
  bool get sqlOpen => _sqlOpen;

  /// Changes on every schema reload, so open table views rebuild from
  /// scratch even when the selected table itself did not change.
  int _schemaVersion = 0;
  int get schemaVersion => _schemaVersion;

  bool _busy = false;

  /// True while the schema is being reloaded.
  bool get busy => _busy;

  String? _error;
  String? get error => _error;

  /// Increases on every reload and on dispose so late results of an older
  /// read are dropped.
  int _generation = 0;

  Future<void> _loadCounts(int generation) async {
    try {
      final counts = await source.countRows([for (final t in _tables) t.name]);
      if (generation != _generation) return;
      _rowCounts = counts;
      notifyListeners();
    } catch (_) {
      // Counts are decorative; the tables stay usable without them.
    }
  }

  /// Re-reads the schema, e.g. after the file was changed by another app.
  Future<void> reload() async {
    if (_busy) return;
    final generation = ++_generation;
    _busy = true;
    notifyListeners();
    try {
      final tables = await source.listTables();
      if (generation != _generation) return;
      _tables = tables;
      _schemaVersion++;
      _rowCounts = const {};
      if (!tables.contains(_selected)) {
        _selected = _defaultSelection(tables);
      }
      _error = null;
      _busy = false;
      notifyListeners();
      _loadCounts(generation);
    } catch (e) {
      if (generation != _generation) return;
      _busy = false;
      _error = 'Could not reload: $e';
      notifyListeners();
    }
  }

  /// First table, or the first view if there are no tables.
  static TableInfo? _defaultSelection(List<TableInfo> tables) =>
      tables.where((t) => t.kind == TableKind.table).firstOrNull ??
      tables.firstOrNull;

  void select(TableInfo table) {
    if (_selected == table && !_sqlOpen) return;
    _selected = table;
    _sqlOpen = false;
    notifyListeners();
  }

  void openSql() {
    if (_sqlOpen) return;
    _sqlOpen = true;
    notifyListeners();
  }

  void dismissError() {
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    ++_generation;
    sql.dispose();
    source.close();
    super.dispose();
  }
}
