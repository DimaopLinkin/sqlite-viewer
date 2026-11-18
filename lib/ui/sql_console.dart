import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:two_dimensional_scrollables/two_dimensional_scrollables.dart';

import '../data/models.dart';
import '../state/sql_controller.dart';
import 'data_grid.dart';
import 'format.dart';
import 'theme.dart';

/// Right panel in SQL mode: an editor for a script, a run button and the
/// result of the last run.
class SqlConsole extends StatefulWidget {
  const SqlConsole({super.key, required this.controller});

  final SqlController controller;

  @override
  State<SqlConsole> createState() => _SqlConsoleState();
}

class _SqlConsoleState extends State<SqlConsole> {
  final _focus = FocusNode();
  double _editorHeight = 180;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    await widget.controller.run();
    if (!mounted) return;
    widget.controller.selectErrorPosition();
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final colors = ViewerColors.of(context);
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final c = widget.controller;
        final result = c.result;
        return LayoutBuilder(
          builder: (context, constraints) {
            final maxEditor = math.max(80.0, constraints.maxHeight - 160);
            final editorHeight = _editorHeight.clamp(80.0, maxEditor);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Toolbar(controller: c, onRun: _run),
                if (c.allowWrites && c.source.writeNotice != null)
                  _Notice(text: c.source.writeNotice!),
                SizedBox(
                  height: editorHeight,
                  child: _Editor(controller: c, focus: _focus, onRun: _run),
                ),
                MouseRegion(
                  cursor: SystemMouseCursors.resizeRow,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onVerticalDragUpdate: (d) => setState(() {
                      _editorHeight = (editorHeight + d.delta.dy).clamp(
                        80.0,
                        maxEditor,
                      );
                    }),
                    child: Container(
                      height: 5,
                      color: colors.toolbar,
                      alignment: Alignment.bottomCenter,
                      child: Divider(height: 1, color: colors.gridLine),
                    ),
                  ),
                ),
                _StatusBar(controller: c),
                Expanded(
                  child: result != null && result.hasResultSet
                      ? ResultGrid(
                          key: ObjectKey(result),
                          columns: result.columns,
                          rows: result.rows,
                        )
                      : Center(
                          child: Text(
                            result == null && c.failure == null
                                ? 'Run a query to see its result'
                                : '',
                            style: TextStyle(color: colors.muted),
                          ),
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.controller, required this.onRun});

  final SqlController controller;
  final VoidCallback onRun;

  @override
  Widget build(BuildContext context) {
    final colors = ViewerColors.of(context);
    final c = controller;
    final mac = defaultTargetPlatform == TargetPlatform.macOS;
    final writeSwitch = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Allow writes',
          style: TextStyle(fontSize: 12, color: colors.muted),
        ),
        const SizedBox(width: 4),
        Transform.scale(
          scale: 0.7,
          child: Switch(
            value: c.allowWrites,
            onChanged: c.source.canWrite && !c.running
                ? (v) => c.allowWrites = v
                : null,
          ),
        ),
      ],
    );
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: colors.toolbar,
        border: Border(bottom: BorderSide(color: colors.gridLine)),
      ),
      child: Row(
        children: [
          Icon(Icons.terminal, size: 16, color: colors.muted),
          const SizedBox(width: 8),
          const Text('SQL', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              c.source.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: colors.muted, fontSize: 12),
            ),
          ),
          Tooltip(
            message: c.source.canWrite
                ? 'Off: statements that change the database fail.\n'
                      'On: INSERT, UPDATE, DELETE and DDL are applied.'
                : 'This file is opened as a read-only snapshot.',
            child: writeSwitch,
          ),
          const SizedBox(width: 8),
          Tooltip(
            message:
                'Run the selection, or the whole script '
                '(${mac ? '⌘' : 'Ctrl'}+Enter)',
            child: FilledButton.icon(
              onPressed: c.running ? null : onRun,
              icon: c.running
                  ? const SizedBox.square(
                      dimension: 12,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.play_arrow, size: 16),
              label: const Text('Run'),
            ),
          ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = ViewerColors.of(context);
    return Container(
      color: colors.toolbar,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 16, color: colors.muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 12, color: colors.muted),
            ),
          ),
        ],
      ),
    );
  }
}

class _Editor extends StatelessWidget {
  const _Editor({
    required this.controller,
    required this.focus,
    required this.onRun,
  });

  final SqlController controller;
  final FocusNode focus;
  final VoidCallback onRun;

  @override
  Widget build(BuildContext context) {
    final colors = ViewerColors.of(context);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter, meta: true): onRun,
        const SingleActivator(LogicalKeyboardKey.enter, control: true): onRun,
        const SingleActivator(LogicalKeyboardKey.numpadEnter, meta: true):
            onRun,
        const SingleActivator(LogicalKeyboardKey.numpadEnter, control: true):
            onRun,
      },
      child: ColoredBox(
        color: colors.input,
        child: TextField(
          controller: controller.editor,
          focusNode: focus,
          autofocus: true,
          expands: true,
          maxLines: null,
          textAlignVertical: TextAlignVertical.top,
          keyboardType: TextInputType.multiline,
          autocorrect: false,
          enableSuggestions: false,
          smartQuotesType: SmartQuotesType.disabled,
          smartDashesType: SmartDashesType.disabled,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontFamilyFallback: ['Menlo', 'Consolas', 'Courier New'],
            fontSize: 13,
            height: 1.4,
          ),
          decoration: const InputDecoration(
            hintText: 'SELECT * FROM … ;',
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: EdgeInsets.all(12),
          ),
        ),
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.controller});

  final SqlController controller;

  @override
  Widget build(BuildContext context) {
    final colors = ViewerColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final c = controller;
    final result = c.result;

    final Widget content;
    if (c.failure != null) {
      content = _line(Icons.error_outline, scheme.error, c.failure!);
    } else if (result == null) {
      content = Text(
        c.running ? 'Running…' : 'Ready',
        style: TextStyle(fontSize: 12, color: colors.muted),
      );
    } else {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (result.error case final error?)
            _line(
              Icons.error_outline,
              scheme.error,
              describeSqlError(
                error,
                result,
                writesOff: c.source.canWrite && !c.allowWrites,
              ),
            )
          else
            _line(
              Icons.check_circle_outline,
              colors.number,
              describeSqlResult(result),
            ),
          if (result.rolledBack)
            _line(
              Icons.undo,
              colors.muted,
              'The script left a transaction open, so it was rolled back. '
              'End it with COMMIT to keep the changes.',
            ),
        ],
      );
    }
    return Container(
      constraints: const BoxConstraints(minHeight: 28),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: colors.toolbar,
        border: Border(bottom: BorderSide(color: colors.gridLine)),
      ),
      alignment: Alignment.centerLeft,
      child: content,
    );
  }

  Widget _line(IconData icon, Color color, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: SelectableText(
              text,
              style: TextStyle(fontSize: 12, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

String _plural(int n, String one, String many) =>
    '${formatInt(n)} ${n == 1 ? one : many}';

String _elapsed(Duration d) =>
    d.inMilliseconds < 1 ? '< 1 ms' : '${formatInt(d.inMilliseconds)} ms';

/// Summary of a successful run for the status bar.
String describeSqlResult(SqlResult result) {
  final parts = <String>[];
  if (result.hasResultSet) {
    parts.add(_plural(result.rows.length, 'row', 'rows'));
    if (result.truncated) {
      parts.add('only the first ${formatInt(SqlResult.maxRows)} are shown');
    }
  }
  if (result.changes > 0 || (result.wroteData && !result.hasResultSet)) {
    parts.add('${_plural(result.changes, 'row', 'rows')} affected');
  }
  if (result.lastInsertRowId case final id?) parts.add('last rowid $id');
  if (result.statementCount > 1) {
    parts.add(_plural(result.statementCount, 'statement', 'statements'));
  }
  if (parts.isEmpty) parts.add('Done');
  parts.add(_elapsed(result.elapsed));
  return parts.join(' · ');
}

/// Error line for the status bar, with what ran before the failure.
String describeSqlError(
  SqlScriptError error,
  SqlResult result, {
  required bool writesOff,
}) {
  final buffer = StringBuffer();
  if (error.statementIndex > 0 || result.statementCount > 0) {
    buffer.write('Statement ${error.statementIndex + 1}: ');
  }
  buffer.write(error.message);
  if (result.statementCount > 0) {
    buffer.write(
      '. ${_plural(result.statementCount, 'statement', 'statements')} '
      'before it ran',
    );
    if (result.changes > 0) {
      buffer.write(' and changed ${_plural(result.changes, 'row', 'rows')}');
    }
  }
  if (writesOff && error.code & 0xFF == _sqliteReadOnly) {
    buffer.write('. Turn on “Allow writes” to change the database');
  }
  return buffer.toString();
}

const _sqliteReadOnly = 8;

const _headerHeight = 30.0;
const _rowHeight = 26.0;

/// Grid of a query result. Columns are sized from their contents.
class ResultGrid extends StatefulWidget {
  const ResultGrid({super.key, required this.columns, required this.rows});

  final List<String> columns;
  final List<List<Object?>> rows;

  @override
  State<ResultGrid> createState() => _ResultGridState();
}

class _ResultGridState extends State<ResultGrid> {
  final _vertical = ScrollController();
  final _horizontal = ScrollController();
  late final List<double> _widths = [
    for (var i = 0; i < widget.columns.length; i++) _measure(i),
  ];

  double _measure(int column) {
    var chars = widget.columns[column].length;
    final sample = math.min(widget.rows.length, 100);
    for (var r = 0; r < sample; r++) {
      final row = widget.rows[r];
      if (column < row.length) {
        chars = math.max(chars, cellText(row[column]).length);
      }
    }
    return (chars * 7.5 + 24).clamp(60.0, 360.0);
  }

  @override
  void dispose() {
    _vertical.dispose();
    _horizontal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = ViewerColors.of(context);
    final rows = widget.rows;
    final columns = widget.columns;
    final numberWidth = (rows.length.toString().length * 8.0 + 28).clamp(
      48.0,
      120.0,
    );
    final grid = Scrollbar(
      controller: _vertical,
      thumbVisibility: true,
      child: Scrollbar(
        controller: _horizontal,
        thumbVisibility: true,
        notificationPredicate: (n) => n.depth == 1,
        child: TableView.builder(
          verticalDetails: ScrollableDetails.vertical(controller: _vertical),
          horizontalDetails: ScrollableDetails.horizontal(
            controller: _horizontal,
          ),
          diagonalDragBehavior: DiagonalDragBehavior.free,
          pinnedRowCount: 1,
          pinnedColumnCount: 1,
          rowCount: rows.length + 1,
          columnCount: columns.length + 1,
          columnBuilder: (index) => TableSpan(
            extent: FixedTableSpanExtent(
              index == 0 ? numberWidth : _widths[index - 1],
            ),
            foregroundDecoration: TableSpanDecoration(
              border: TableSpanBorder(
                trailing: BorderSide(color: colors.gridLine),
              ),
            ),
          ),
          rowBuilder: (index) => TableSpan(
            extent: FixedTableSpanExtent(
              index == 0 ? _headerHeight : _rowHeight,
            ),
            backgroundDecoration: TableSpanDecoration(
              color: index == 0
                  ? colors.header
                  : ((index - 1).isOdd ? colors.rowAlt : null),
            ),
            foregroundDecoration: index == 0
                ? TableSpanDecoration(
                    border: TableSpanBorder(
                      trailing: BorderSide(color: colors.gridLine),
                    ),
                  )
                : null,
          ),
          cellBuilder: (context, vicinity) {
            final row = vicinity.row;
            final col = vicinity.column;
            if (row == 0) {
              return TableViewCell(
                child: Container(
                  alignment: col == 0 ? Alignment.center : Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    col == 0 ? '#' : columns[col - 1],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: col == 0
                        ? TextStyle(color: colors.muted, fontSize: 12)
                        : const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                  ),
                ),
              );
            }
            if (col == 0) {
              return TableViewCell(
                child: Container(
                  alignment: Alignment.centerRight,
                  color: colors.header,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    '$row',
                    style: TextStyle(color: colors.muted, fontSize: 12),
                  ),
                ),
              );
            }
            final values = rows[row - 1];
            return TableViewCell(
              child: ValueCell(
                value: col - 1 < values.length ? values[col - 1] : null,
              ),
            );
          },
        ),
      ),
    );
    return Stack(
      children: [
        Positioned.fill(child: grid),
        if (rows.isEmpty)
          Positioned.fill(
            top: _headerHeight + 24,
            child: Align(
              alignment: Alignment.topCenter,
              child: Text('No rows', style: TextStyle(color: colors.muted)),
            ),
          ),
      ],
    );
  }
}
