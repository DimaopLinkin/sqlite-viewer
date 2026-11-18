import 'models.dart';

/// SQL text with its positional `?` arguments.
class SqlStatement {
  const SqlStatement(this.sql, this.args);

  final String sql;
  final List<Object?> args;

  @override
  String toString() => '$sql  $args';
}

/// Names of the custom SQL functions registered by `SqliteReader`.
///
/// They do Unicode-aware, case-insensitive matching. The built-in `LIKE`
/// only folds ASCII letters, which is not enough for Cyrillic data.
abstract final class SqlFunctions {
  static const contains = 'sv_contains';
  static const startsWith = 'sv_starts_with';
  static const endsWith = 'sv_ends_with';
}

/// Quotes an identifier so any table or column name is safe to embed.
String quoteIdentifier(String name) => '"${name.replaceAll('"', '""')}"';

/// Builds the read-only queries the viewer runs. Pure, so it is unit tested
/// without a database.
abstract final class QueryBuilder {
  static SqlStatement count(TableQuery query) {
    final where = _where(query.filters);
    return SqlStatement(
      'SELECT COUNT(*) FROM ${quoteIdentifier(query.table)}${where.sql}',
      where.args,
    );
  }

  static SqlStatement page(
    TableQuery query, {
    required List<String> columns,
    required int limit,
    required int offset,
  }) {
    final where = _where(query.filters);
    final select = columns.isEmpty
        ? '*'
        : columns.map(quoteIdentifier).join(', ');
    final order = switch (query.sort) {
      null => '',
      SortSpec(:final column, :final direction) =>
        ' ORDER BY ${quoteIdentifier(column)} '
            '${direction == SortDirection.asc ? 'ASC' : 'DESC'}',
    };
    return SqlStatement(
      'SELECT $select FROM ${quoteIdentifier(query.table)}'
      '${where.sql}$order LIMIT ? OFFSET ?',
      [...where.args, limit, offset],
    );
  }

  /// The first row of [table] whose [columns] equal [values], compared with
  /// `=` like SQLite compares a foreign key with its parent key.
  static SqlStatement lookup(
    String table, {
    required List<String> select,
    required List<String> columns,
    required List<Object?> values,
  }) {
    assert(columns.length == values.length && columns.isNotEmpty);
    final list = select.isEmpty ? '*' : select.map(quoteIdentifier).join(', ');
    final where = [for (final c in columns) '${quoteIdentifier(c)} = ?'];
    return SqlStatement(
      'SELECT $list FROM ${quoteIdentifier(table)} '
      'WHERE ${where.join(' AND ')} LIMIT 1',
      values,
    );
  }

  static SqlStatement _where(List<ColumnFilter> filters) {
    final parts = <String>[];
    final args = <Object?>[];
    for (final filter in filters) {
      if (!filter.isActive) continue;
      final clause = condition(filter);
      parts.add(clause.sql);
      args.addAll(clause.args);
    }
    if (parts.isEmpty) return const SqlStatement('', []);
    return SqlStatement(' WHERE ${parts.join(' AND ')}', args);
  }

  /// The boolean SQL expression for one filter.
  static SqlStatement condition(ColumnFilter filter) {
    final col = quoteIdentifier(filter.column);
    final text = 'CAST($col AS TEXT)';
    final value = filter.value;
    final number = num.tryParse(value.trim());

    switch (filter.op) {
      case FilterOperator.contains:
        return SqlStatement('${SqlFunctions.contains}($text, ?)', [value]);
      case FilterOperator.notContains:
        return SqlStatement(
          '($col IS NULL OR NOT ${SqlFunctions.contains}($text, ?))',
          [value],
        );
      case FilterOperator.startsWith:
        return SqlStatement('${SqlFunctions.startsWith}($text, ?)', [value]);
      case FilterOperator.endsWith:
        return SqlStatement('${SqlFunctions.endsWith}($text, ?)', [value]);
      case FilterOperator.equals:
        return _equals(col, text, value, number);
      case FilterOperator.notEquals:
        final eq = _equals(col, text, value, number);
        return SqlStatement('($col IS NULL OR NOT ${eq.sql})', eq.args);
      case FilterOperator.greaterThan:
        return _compare(col, text, '>', value, number);
      case FilterOperator.greaterOrEqual:
        return _compare(col, text, '>=', value, number);
      case FilterOperator.lessThan:
        return _compare(col, text, '<', value, number);
      case FilterOperator.lessOrEqual:
        return _compare(col, text, '<=', value, number);
      case FilterOperator.isNull:
        return SqlStatement('$col IS NULL', const []);
      case FilterOperator.isNotNull:
        return SqlStatement('$col IS NOT NULL', const []);
      case FilterOperator.isEmpty:
        return SqlStatement("$text = ''", const []);
      case FilterOperator.isNotEmpty:
        return SqlStatement("($col IS NOT NULL AND $text <> '')", const []);
    }
  }

  static SqlStatement _equals(String col, String text, String value, num? n) {
    // A number typed by the user should match 1, 1.0 and '1' alike.
    if (n != null) {
      return SqlStatement('($col = ? OR $text = ?)', [n, value]);
    }
    return SqlStatement('$text = ?', [value]);
  }

  static SqlStatement _compare(
    String col,
    String text,
    String op,
    String value,
    num? n,
  ) {
    // CAST makes numbers stored as text ('10', '9') compare as numbers too;
    // a plain comparison would apply the column's TEXT affinity.
    if (n != null) return SqlStatement('CAST($col AS NUMERIC) $op ?', [n]);
    return SqlStatement('$text $op ?', [value]);
  }
}
