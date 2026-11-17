import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../data/db_source.dart';
import '../data/models.dart';
import '../ui/format.dart';

/// State of one table view: columns, filters, sort and the visible page.
///
/// Only one page of rows is held in memory. Counting and paging are done by
/// SQL (`COUNT(*)`, `LIMIT/OFFSET`), so tables with hundreds of thousands of
/// rows open instantly.
class TableController extends ChangeNotifier {
  TableController({
    required this.source,
    required this.table,
    this.filterDebounce = const Duration(milliseconds: 300),
  }) {
    _loadColumns();
  }

  static const pageSizes = [50, 100, 250, 500, 1000];

  final DbSource source;
  final TableInfo table;
  final Duration filterDebounce;

  List<ColumnInfo> _columns = const [];
  List<ColumnInfo> get columns => _columns;
  List<String> get columnNames => [for (final c in _columns) c.name];

  final Map<String, ColumnFilter> _filters = {};

  /// Current filter of [column], active or not.
  ColumnFilter filterFor(String column) =>
      _filters[column] ??
      ColumnFilter(column: column, op: FilterOperator.contains);

  int get activeFilterCount => _filters.values.where((f) => f.isActive).length;

  SortSpec? _sort;
  SortSpec? get sort => _sort;

  int _pageSize = 100;
  int get pageSize => _pageSize;

  int _pageIndex = 0;
  int get pageIndex => _pageIndex;

  int? _total;

  /// Number of rows matching the filters, `null` while counting.
  int? get total => _total;

  int get pageCount =>
      _total == null ? 1 : math.max(1, (_total! / _pageSize).ceil());

  RowPage? _page;
  RowPage? get page => _page;

  bool _loading = true;
  bool get loading => _loading;

  String? _error;
  String? get error => _error;

  final Map<String, double> _columnWidths = {};
  static const minColumnWidth = 60.0;
  static const maxAutoColumnWidth = 360.0;

  double columnWidth(String column) => _columnWidths[column] ?? 140;

  void setColumnWidth(String column, double width) {
    _columnWidths[column] = math.max(minColumnWidth, width);
    notifyListeners();
  }

  bool _disposed = false;
  int _countId = 0;
  int _pageId = 0;
  Timer? _debounce;

  TableQuery get query => TableQuery(
    table: table.name,
    filters: [
      for (final f in _filters.values)
        if (f.isActive) f,
    ],
    sort: _sort,
  );

  Future<void> _loadColumns() async {
    try {
      final columns = await source.columns(table.name);
      if (_disposed) return;
      if (columns.length != _columns.length) _page = null;
      _columns = columns;
      final names = {for (final c in columns) c.name};
      // Forget settings of columns that disappeared since the last load.
      _filters.removeWhere((name, _) => !names.contains(name));
      if (_sort != null && !names.contains(_sort!.column)) _sort = null;
      for (final c in columns) {
        _columnWidths.putIfAbsent(c.name, () => _headerWidth(c));
      }
      _refresh(countRows: true, fitColumns: _page == null);
    } catch (e) {
      if (_disposed) return;
      _loading = false;
      _error = '$e';
      notifyListeners();
    }
  }

  static double _headerWidth(ColumnInfo c) =>
      (c.name.length * 7.5 + 64).clamp(120, 240).toDouble();

  /// Widens columns to their content on the first page, so short columns
  /// stay narrow and long text gets room.
  void _fitColumnsToContent(RowPage page) {
    for (var i = 0; i < _columns.length; i++) {
      final column = _columns[i];
      var longest = 0;
      for (final row in page.rows.take(50)) {
        longest = math.max(longest, cellText(row[i]).length);
      }
      final content = (longest * 7.5 + 24).clamp(80, maxAutoColumnWidth);
      _columnWidths[column.name] = math.max(
        _headerWidth(column),
        content.toDouble(),
      );
    }
  }

  /// Reloads what the current settings show. Counting and paging are
  /// tracked separately, so a page change during a long `COUNT(*)` does not
  /// throw the count away.
  void _refresh({bool countRows = false, bool fitColumns = false}) {
    if (countRows) _recount();
    _loadPage(fitColumns: fitColumns);
  }

  Future<void> _recount() async {
    final id = ++_countId;
    _total = null;
    notifyListeners();
    try {
      final total = await source.count(query);
      if (id != _countId || _disposed) return;
      _total = total;
      // A reload may have shrunk the result below the current page.
      final lastPage = pageCount - 1;
      if (_pageIndex > lastPage) {
        _pageIndex = lastPage;
        _loadPage();
      } else {
        notifyListeners();
      }
    } catch (e) {
      if (id != _countId || _disposed) return;
      _error = '$e';
      notifyListeners();
    }
  }

  Future<void> _loadPage({bool fitColumns = false}) async {
    final id = ++_pageId;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final page = await source.page(
        query,
        columns: columnNames,
        limit: _pageSize,
        offset: _pageIndex * _pageSize,
      );
      if (id != _pageId || _disposed) return;
      if (fitColumns) _fitColumnsToContent(page);
      _page = page;
      _loading = false;
      notifyListeners();
    } catch (e) {
      if (id != _pageId || _disposed) return;
      _loading = false;
      _error = '$e';
      notifyListeners();
    }
  }

  void setFilter(String column, {FilterOperator? op, String? value}) {
    final current = filterFor(column);
    final next = ColumnFilter(
      column: column,
      op: op ?? current.op,
      value: value ?? current.value,
    );
    if (next == current) return;
    final changesResult = next.isActive || current.isActive;
    _filters[column] = next;
    if (!changesResult) {
      notifyListeners();
      return;
    }
    _debounce?.cancel();
    // Typing is debounced; picking an operator applies at once.
    if (value != null && filterDebounce > Duration.zero) {
      notifyListeners();
      _debounce = Timer(filterDebounce, _applyFilters);
    } else {
      _applyFilters();
    }
  }

  void clearFilters() {
    _debounce?.cancel();
    final hadActive = activeFilterCount > 0;
    _filters.clear();
    if (hadActive) {
      _applyFilters();
    } else {
      notifyListeners();
    }
  }

  void _applyFilters() {
    _pageIndex = 0;
    _refresh(countRows: true);
  }

  /// Cycles ascending → descending → unsorted.
  void toggleSort(String column) {
    final current = _sort;
    if (current == null || current.column != column) {
      _sort = SortSpec(column, SortDirection.asc);
    } else if (current.direction == SortDirection.asc) {
      _sort = SortSpec(column, SortDirection.desc);
    } else {
      _sort = null;
    }
    _pageIndex = 0;
    _refresh();
  }

  void goToPage(int index) {
    final clamped = index.clamp(0, pageCount - 1);
    if (clamped == _pageIndex && _page != null) return;
    _pageIndex = clamped;
    _refresh();
  }

  void setPageSize(int size) {
    if (size == _pageSize) return;
    // Keep the first visible row on screen.
    final firstRow = _pageIndex * _pageSize;
    _pageSize = size;
    _pageIndex = firstRow ~/ size;
    _refresh();
  }

  /// Re-reads columns, count and the current page, e.g. after the file was
  /// changed by another app.
  void reload() => _loadColumns();

  /// Row at an absolute position in the filtered and sorted result, used by
  /// the detail dialog to step past the current page.
  Future<List<Object?>?> rowAt(int index) async {
    final page = _page;
    if (page != null &&
        index >= page.offset &&
        index < page.offset + page.rows.length) {
      return page.rows[index - page.offset];
    }
    if (index < 0 || (_total != null && index >= _total!)) return null;
    final result = await source.page(
      query,
      columns: columnNames,
      limit: 1,
      offset: index,
    );
    return result.rows.firstOrNull;
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    super.dispose();
  }
}
