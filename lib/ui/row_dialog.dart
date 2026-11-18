import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/models.dart';
import '../state/table_controller.dart';
import 'copy_button.dart';
import 'format.dart';
import 'reference_panel.dart';
import 'theme.dart';

/// Opens the detail dialog for the row at absolute [index].
Future<void> showRowDialog(
  BuildContext context, {
  required TableController controller,
  required int index,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => RowDialog(controller: controller, initialIndex: index),
  );
}

/// All values of one row, each in a read-only field that can be selected
/// and copied. ↑/↓ in the title (or Alt+↑/↓) move to the neighbour rows.
class RowDialog extends StatefulWidget {
  const RowDialog({
    super.key,
    required this.controller,
    required this.initialIndex,
  });

  final TableController controller;
  final int initialIndex;

  @override
  State<RowDialog> createState() => _RowDialogState();
}

class _RowDialogState extends State<RowDialog> {
  late int _index = widget.initialIndex;
  List<Object?>? _row;
  String? _error;
  int _request = 0;

  /// Foreign keys whose parent row is shown. Kept while stepping through
  /// rows, so an opened reference stays open on the next row.
  final Set<ForeignKey> _expanded = {};

  @override
  void initState() {
    super.initState();
    _load(_index);
  }

  Future<void> _load(int index) async {
    final request = ++_request;
    try {
      final row = await widget.controller.rowAt(index);
      if (!mounted || request != _request || row == null) return;
      setState(() {
        _index = index;
        _row = row;
        _error = null;
      });
    } catch (e) {
      if (!mounted || request != _request) return;
      setState(() => _error = '$e');
    }
  }

  bool get _hasPrevious => _index > 0;
  bool get _hasNext {
    final total = widget.controller.total;
    return total == null || _index < total - 1;
  }

  void _previous() {
    if (_hasPrevious) _load(_index - 1);
  }

  void _next() {
    if (_hasNext) _load(_index + 1);
  }

  @override
  Widget build(BuildContext context) {
    final colors = ViewerColors.of(context);
    final size = MediaQuery.sizeOf(context);
    final columns = widget.controller.columns;
    final row = _row;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowUp, alt: true): _previous,
        const SingleActivator(LogicalKeyboardKey.arrowDown, alt: true): _next,
      },
      child: Dialog(
        backgroundColor: colors.dialog,
        surfaceTintColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(24),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: BorderSide(color: colors.gridLine),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 960,
            maxHeight: size.height * 0.85,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                color: colors.toolbar,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Previous row (Alt+↑)',
                      iconSize: 18,
                      onPressed: _hasPrevious ? _previous : null,
                      icon: const Icon(Icons.arrow_upward),
                    ),
                    IconButton(
                      tooltip: 'Next row (Alt+↓)',
                      iconSize: 18,
                      onPressed: _hasNext ? _next : null,
                      icon: const Icon(Icons.arrow_downward),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: widget.controller.table.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            TextSpan(
                              text: '  /  ${_index + 1}',
                              style: TextStyle(color: colors.muted),
                            ),
                          ],
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (row != null)
                      CopyButton(
                        label: 'Copy as JSON',
                        text: () =>
                            rowToJson([for (final c in columns) c.name], row),
                      ),
                    IconButton(
                      tooltip: 'Close',
                      iconSize: 18,
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: _error != null
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: SelectableText(_error!),
                      )
                    : row == null
                    ? const Padding(
                        padding: EdgeInsets.all(48),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    : _Fields(
                        columns: columns,
                        row: row,
                        controller: widget.controller,
                        expanded: _expanded,
                        onToggle: (key) => setState(() {
                          if (!_expanded.remove(key)) _expanded.add(key);
                        }),
                        key: ValueKey(_index),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Fields extends StatelessWidget {
  const _Fields({
    super.key,
    required this.columns,
    required this.row,
    required this.controller,
    required this.expanded,
    required this.onToggle,
  });

  final List<ColumnInfo> columns;
  final List<Object?> row;
  final TableController controller;
  final Set<ForeignKey> expanded;
  final ValueChanged<ForeignKey> onToggle;

  Widget? _reference(ColumnInfo column) {
    final keys = foreignKeysAt(controller.foreignKeys, column.name);
    if (keys.isEmpty) return null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [for (final key in keys) ..._referenceOf(key)],
    );
  }

  /// Toggle, and the parent row when expanded. A NULL in the key disables it.
  List<Widget> _referenceOf(ForeignKey key) {
    final values = keyValues(key, columns, row);
    final usable = values != null && values.every((v) => v != null);
    final open = usable && expanded.contains(key);
    return [
      ReferenceToggle(
        foreignKey: key,
        expanded: open,
        onToggle: usable ? () => onToggle(key) : null,
      ),
      if (open)
        ReferencePanel(
          source: controller.source,
          foreignKey: key,
          values: values,
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final perRow = constraints.maxWidth >= 640 ? 2 : 1;
        const gap = 20.0;
        final width = (constraints.maxWidth - 40 - gap * (perRow - 1)) / perRow;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Wrap(
            spacing: gap,
            runSpacing: 16,
            children: [
              for (var i = 0; i < columns.length && i < row.length; i++)
                SizedBox(
                  width: width,
                  child: _Field(
                    column: columns[i],
                    value: row[i],
                    reference: _reference(columns[i]),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Field extends StatefulWidget {
  const _Field({required this.column, required this.value, this.reference});

  final ColumnInfo column;
  final Object? value;

  /// Link to the row a foreign key value points to.
  final Widget? reference;

  @override
  State<_Field> createState() => _FieldState();
}

class _FieldState extends State<_Field> {
  /// Very long values make text layout slow; the copy button still copies
  /// everything.
  static const _maxShownChars = 100000;

  late final String _full = fullText(widget.value);
  late final TextEditingController _text = TextEditingController(
    text: _full.length > _maxShownChars
        ? '${_full.substring(0, _maxShownChars)}\n… (${formatInt(_full.length - _maxShownChars)} more characters, use Copy)'
        : _full,
  );

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = ViewerColors.of(context);
    final column = widget.column;
    final value = widget.value;
    final isNull = value == null;
    final mono = value is Uint8List;
    final long = _full.length > 60 || _full.contains('\n');
    final caption = TextStyle(fontSize: 11, color: colors.muted);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                column.name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            if (column.isPrimaryKey) ...[
              const SizedBox(width: 6),
              Icon(Icons.key, size: 13, color: colors.muted),
            ],
          ],
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _text,
          readOnly: true,
          minLines: long ? 3 : 1,
          maxLines: long ? 8 : 1,
          style: TextStyle(
            fontSize: 13,
            fontFamily: mono ? 'monospace' : null,
            fontFamilyFallback: mono ? const ['Menlo', 'Courier'] : null,
          ),
          decoration: InputDecoration(
            hintText: isNull ? 'NULL' : null,
            hintStyle: TextStyle(
              color: colors.nullValue,
              fontStyle: FontStyle.italic,
            ),
            suffixIcon: isNull
                ? null
                : CopyButton(
                    text: () => copyText(widget.value),
                    tooltip: 'Copy value',
                    size: 14,
                  ),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Text(
              [
                if (column.isPrimaryKey) 'PRIMARY KEY',
                if (column.notNull) 'NOT NULL',
              ].join(' · '),
              style: caption,
            ),
            const Spacer(),
            Text(
              [
                if (column.declaredType.isNotEmpty)
                  column.declaredType.toUpperCase(),
                if (!isNull && _unexpectedStorage(column, value))
                  'stored as ${storageClass(value)}',
                if (value is Uint8List) formatBytes(value.length),
              ].join(' · '),
              style: caption,
            ),
          ],
        ),
        if (widget.reference case final reference?) ...[
          const SizedBox(height: 2),
          reference,
        ],
      ],
    );
  }
}

/// Whether the stored value differs from what the column's affinity
/// suggests, e.g. text in an INTEGER column. Worth pointing out in a viewer.
bool _unexpectedStorage(ColumnInfo column, Object? value) {
  final expected = switch (column.affinity) {
    ColumnAffinity.integer => 'INTEGER',
    ColumnAffinity.real => 'REAL',
    ColumnAffinity.text => 'TEXT',
    ColumnAffinity.blob || ColumnAffinity.numeric => null,
  };
  if (column.declaredType.isEmpty) return true;
  return expected != null && storageClass(value) != expected;
}
