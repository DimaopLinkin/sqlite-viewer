import 'package:flutter/material.dart';

import '../data/db_source.dart';
import '../data/models.dart';
import 'copy_button.dart';
import 'format.dart';
import 'theme.dart';

/// How many references deep the row dialog lets the user follow. Keeps
/// cyclic keys (e.g. `employee.manager_id → employee`) from nesting forever.
const maxReferenceDepth = 4;

/// The foreign key that starts at [column], if any. A composite key is shown
/// on its first column.
ForeignKey? foreignKeyAt(List<ForeignKey> keys, String column) {
  for (final key in keys) {
    if (key.from.first == column) return key;
  }
  return null;
}

/// Child values of [key] taken from a row, or `null` if a column is missing.
List<Object?>? keyValues(
  ForeignKey key,
  List<ColumnInfo> columns,
  List<Object?> row,
) {
  final values = <Object?>[];
  for (final name in key.from) {
    final i = columns.indexWhere((c) => c.name == name);
    if (i < 0 || i >= row.length) return null;
    values.add(row[i]);
  }
  return values;
}

/// `general_agency (id)`, for the toggle and tooltips.
String referenceLabel(ForeignKey key) => '${key.table} (${key.to.join(', ')})';

/// Clickable line under a value that shows or hides the referenced row.
class ReferenceToggle extends StatelessWidget {
  const ReferenceToggle({
    super.key,
    required this.foreignKey,
    required this.expanded,
    required this.onToggle,
  });

  final ForeignKey foreignKey;
  final bool expanded;

  /// `null` disables the toggle, e.g. for a NULL value.
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final colors = ViewerColors.of(context);
    final enabled = onToggle != null;
    final color = enabled
        ? Theme.of(context).colorScheme.primary
        : colors.muted;
    return Align(
      alignment: Alignment.centerLeft,
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(3),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                expanded ? Icons.expand_more : Icons.chevron_right,
                size: 16,
                color: color,
              ),
              Icon(Icons.link, size: 14, color: color),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  referenceLabel(foreignKey),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The parent row of [foreignKey] for [values], loaded when shown. Its own
/// reference columns can be expanded in turn, up to [maxReferenceDepth].
class ReferencePanel extends StatefulWidget {
  const ReferencePanel({
    super.key,
    required this.source,
    required this.foreignKey,
    required this.values,
    this.depth = 1,
  });

  final DbSource source;
  final ForeignKey foreignKey;
  final List<Object?> values;
  final int depth;

  @override
  State<ReferencePanel> createState() => _ReferencePanelState();
}

class _ReferencePanelState extends State<ReferencePanel> {
  ReferencedRow? _row;
  List<ForeignKey> _keys = const [];
  bool _loading = true;
  String? _error;
  final Set<ForeignKey> _expanded = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final row = await widget.source.referencedRow(
        widget.foreignKey,
        widget.values,
      );
      var keys = const <ForeignKey>[];
      if (row != null && widget.depth < maxReferenceDepth) {
        try {
          keys = await widget.source.foreignKeys(widget.foreignKey.table);
        } catch (_) {
          // Nested links are optional.
        }
      }
      if (!mounted) return;
      setState(() {
        _row = row;
        _keys = keys;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = ViewerColors.of(context);
    final key = widget.foreignKey;
    final row = _row;
    final where = [
      for (var i = 0; i < key.to.length; i++)
        '${key.to[i]} = ${cellText(widget.values[i])}',
    ].join(', ');

    final Widget body;
    if (_loading) {
      body = const Padding(
        padding: EdgeInsets.all(12),
        child: Center(
          child: SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    } else if (_error != null) {
      body = Padding(
        padding: const EdgeInsets.all(8),
        child: SelectableText(_error!, style: const TextStyle(fontSize: 12)),
      );
    } else if (row == null) {
      body = Padding(
        padding: const EdgeInsets.all(8),
        child: Text(
          'No row in ${key.table} where $where',
          style: TextStyle(
            fontSize: 12,
            color: colors.nullValue,
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < row.columns.length && i < row.values.length; i++)
            _entry(context, row, i),
        ],
      );
    }

    return Container(
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
        color: colors.input,
        border: Border.all(color: colors.gridLine),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: colors.toolbar,
            padding: const EdgeInsets.only(left: 8),
            child: Row(
              children: [
                Flexible(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: key.table,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        TextSpan(
                          text: '  $where',
                          style: TextStyle(color: colors.muted),
                        ),
                      ],
                    ),
                    style: const TextStyle(fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Spacer(),
                if (row != null)
                  CopyButton(
                    tooltip: 'Copy as JSON',
                    size: 14,
                    text: () => rowToJson([
                      for (final c in row.columns) c.name,
                    ], row.values),
                  )
                else
                  const SizedBox(height: 32),
              ],
            ),
          ),
          body,
        ],
      ),
    );
  }

  Widget _entry(BuildContext context, ReferencedRow row, int i) {
    final colors = ViewerColors.of(context);
    final column = row.columns[i];
    final value = row.values[i];
    final nested = value == null ? null : foreignKeyAt(_keys, column.name);
    final nestedValues = nested == null
        ? null
        : keyValues(nested, row.columns, row.values);
    final canExpand =
        nestedValues != null && nestedValues.every((v) => v != null);
    final expanded = canExpand && _expanded.contains(nested);

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 120,
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          column.name,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: colors.muted),
                        ),
                      ),
                      if (column.isPrimaryKey) ...[
                        const SizedBox(width: 4),
                        Icon(Icons.key, size: 11, color: colors.muted),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: value == null
                    ? Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          'NULL',
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.nullValue,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      )
                    : Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: SelectableText(
                          cellText(value),
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
              ),
              if (value != null)
                SizedBox(
                  height: 20,
                  child: CopyButton(
                    text: () => copyText(value),
                    tooltip: 'Copy value',
                    size: 12,
                  ),
                ),
            ],
          ),
          if (nested != null && canExpand)
            Padding(
              padding: const EdgeInsets.only(left: 124),
              child: ReferenceToggle(
                foreignKey: nested,
                expanded: expanded,
                onToggle: () => setState(() {
                  if (!_expanded.remove(nested)) _expanded.add(nested);
                }),
              ),
            ),
          if (expanded && nested != null)
            ReferencePanel(
              source: widget.source,
              foreignKey: nested,
              values: nestedValues,
              depth: widget.depth + 1,
            ),
        ],
      ),
    );
  }
}
