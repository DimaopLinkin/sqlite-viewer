import 'package:flutter/foundation.dart';

import '../data/db_source.dart';
import '../data/models.dart';

/// State of one open file (one tab): its tables and the selected table.
class ViewerController extends ChangeNotifier {
  DbSource? _source;
  DbSource? get source => _source;

  List<TableInfo> _tables = const [];
  List<TableInfo> get tables => _tables;

  /// Row counts arrive after the table list; missing key means "loading",
  /// `null` value means the table could not be counted.
  Map<String, int?> _rowCounts = const {};
  Map<String, int?> get rowCounts => _rowCounts;

  TableInfo? _selected;
  TableInfo? get selected => _selected;

  /// Changes on every schema reload, so open table views rebuild from
  /// scratch even when the selected table itself did not change.
  int _schemaVersion = 0;
  int get schemaVersion => _schemaVersion;

  bool _busy = false;
  bool get busy => _busy;

  String? _error;
  String? get error => _error;

  /// Increases on every open/close so late results of an older file are
  /// dropped.
  int _generation = 0;

  /// Opens a new source and replaces the current one. [open] picks and opens
  /// the file; it returns `null` when the user cancels the picker.
  Future<void> openWith(Future<DbSource?> Function() open) async {
    final generation = ++_generation;
    _busy = true;
    _error = null;
    notifyListeners();
    DbSource? source;
    try {
      source = await open();
      if (source == null) {
        if (generation == _generation) {
          _busy = false;
          notifyListeners();
        }
        return;
      }
      final tables = await source.listTables();
      if (generation != _generation) {
        await source.close();
        return;
      }
      final previous = _source;
      _source = source;
      _tables = tables;
      _rowCounts = const {};
      _selected = _defaultSelection(tables);
      _busy = false;
      notifyListeners();
      await previous?.close();
      _loadCounts(source, generation);
    } catch (e) {
      await source?.close();
      if (generation != _generation) return;
      _busy = false;
      _error = 'Could not open the file: $e';
      notifyListeners();
    }
  }

  Future<void> _loadCounts(DbSource source, int generation) async {
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
    final source = _source;
    if (source == null || _busy) return;
    final generation = ++_generation;
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
      notifyListeners();
      _loadCounts(source, generation);
    } catch (e) {
      if (generation != _generation) return;
      _error = 'Could not reload: $e';
      notifyListeners();
    }
  }

  /// First table, or the first view if there are no tables.
  static TableInfo? _defaultSelection(List<TableInfo> tables) =>
      tables.where((t) => t.kind == TableKind.table).firstOrNull ??
      tables.firstOrNull;

  void select(TableInfo table) {
    if (_selected == table) return;
    _selected = table;
    notifyListeners();
  }

  void dismissError() {
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    // Drops late results (counts, reload) that would notify after dispose.
    ++_generation;
    _source?.close();
    super.dispose();
  }
}
