import 'package:flutter/foundation.dart';

/// Kind of a schema object shown in the sidebar.
enum TableKind { table, view }

/// A table or a view of the opened database.
@immutable
class TableInfo {
  const TableInfo({required this.name, required this.kind});

  final String name;
  final TableKind kind;

  @override
  bool operator ==(Object other) =>
      other is TableInfo && other.name == name && other.kind == kind;

  @override
  int get hashCode => Object.hash(name, kind);
}

/// Column metadata from `PRAGMA table_xinfo`.
@immutable
class ColumnInfo {
  const ColumnInfo({
    required this.name,
    required this.declaredType,
    required this.notNull,
    required this.primaryKeyIndex,
    this.defaultValue,
  });

  final String name;

  /// Type as written in `CREATE TABLE`, may be empty.
  final String declaredType;
  final bool notNull;

  /// 1-based position in the primary key, 0 if the column is not part of it.
  final int primaryKeyIndex;
  final String? defaultValue;

  bool get isPrimaryKey => primaryKeyIndex > 0;

  /// SQLite type affinity derived from [declaredType]
  /// (https://www.sqlite.org/datatype3.html#determination_of_column_affinity).
  ColumnAffinity get affinity {
    final t = declaredType.toUpperCase();
    if (t.contains('INT')) return ColumnAffinity.integer;
    if (t.contains('CHAR') || t.contains('CLOB') || t.contains('TEXT')) {
      return ColumnAffinity.text;
    }
    if (t.isEmpty || t.contains('BLOB')) return ColumnAffinity.blob;
    if (t.contains('REAL') || t.contains('FLOA') || t.contains('DOUB')) {
      return ColumnAffinity.real;
    }
    return ColumnAffinity.numeric;
  }

  bool get isNumeric =>
      affinity == ColumnAffinity.integer ||
      affinity == ColumnAffinity.real ||
      affinity == ColumnAffinity.numeric;
}

enum ColumnAffinity { integer, text, blob, real, numeric }

/// Comparison applied by a per-column filter.
enum FilterOperator {
  contains('Contains', needsValue: true),
  notContains('Does not contain', needsValue: true),
  equals('Equals', needsValue: true),
  notEquals('Not equals', needsValue: true),
  startsWith('Starts with', needsValue: true),
  endsWith('Ends with', needsValue: true),
  greaterThan('>', needsValue: true),
  greaterOrEqual('≥', needsValue: true),
  lessThan('<', needsValue: true),
  lessOrEqual('≤', needsValue: true),
  isNull('Is NULL', needsValue: false),
  isNotNull('Is not NULL', needsValue: false),
  isEmpty('Is empty', needsValue: false),
  isNotEmpty('Is not empty', needsValue: false);

  const FilterOperator(this.label, {required this.needsValue});

  final String label;
  final bool needsValue;
}

@immutable
class ColumnFilter {
  const ColumnFilter({required this.column, required this.op, this.value = ''});

  final String column;
  final FilterOperator op;
  final String value;

  /// A filter that needs a value but has none does not restrict anything.
  bool get isActive => !op.needsValue || value.isNotEmpty;

  @override
  bool operator ==(Object other) =>
      other is ColumnFilter &&
      other.column == column &&
      other.op == op &&
      other.value == value;

  @override
  int get hashCode => Object.hash(column, op, value);
}

enum SortDirection { asc, desc }

@immutable
class SortSpec {
  const SortSpec(this.column, this.direction);

  final String column;
  final SortDirection direction;

  @override
  bool operator ==(Object other) =>
      other is SortSpec &&
      other.column == column &&
      other.direction == direction;

  @override
  int get hashCode => Object.hash(column, direction);
}

/// Everything that defines which rows of a table are visible, except paging.
@immutable
class TableQuery {
  const TableQuery({required this.table, this.filters = const [], this.sort});

  final String table;
  final List<ColumnFilter> filters;
  final SortSpec? sort;
}

/// One page of rows. Values are `null`, `int`, `double`, `String`,
/// `Uint8List` or `BigInt` (64-bit integers on the web).
@immutable
class RowPage {
  const RowPage({required this.offset, required this.rows});

  final int offset;
  final List<List<Object?>> rows;
}

/// A foreign key of a table, from `PRAGMA foreign_key_list`.
///
/// [to] always names the parent columns: a key declared as
/// `REFERENCES parent` without columns is resolved to the parent's primary
/// key by the reader.
@immutable
class ForeignKey {
  const ForeignKey({required this.table, required this.from, required this.to});

  /// The referenced (parent) table.
  final String table;

  /// Child columns, in key order.
  final List<String> from;

  /// Parent columns matching [from] one by one, same length.
  final List<String> to;

  @override
  bool operator ==(Object other) =>
      other is ForeignKey &&
      other.table == table &&
      listEquals(other.from, from) &&
      listEquals(other.to, to);

  @override
  int get hashCode =>
      Object.hash(table, Object.hashAll(from), Object.hashAll(to));

  @override
  String toString() => '(${from.join(', ')}) → $table(${to.join(', ')})';
}

/// The parent row a foreign key value points to.
@immutable
class ReferencedRow {
  const ReferencedRow({
    required this.table,
    required this.columns,
    required this.values,
    this.foreignKeys = const [],
  });

  final String table;
  final List<ColumnInfo> columns;
  final List<Object?> values;

  /// Foreign keys of [table], so the row's own references can be followed
  /// without another round-trip.
  final List<ForeignKey> foreignKeys;
}
