import 'package:flutter/material.dart';

import '../data/db_source.dart';
import '../data/models.dart';
import '../state/table_controller.dart';
import 'data_grid.dart';
import 'format.dart';
import 'pagination_bar.dart';
import 'row_dialog.dart';
import 'theme.dart';

/// Right panel: toolbar, grid and pagination of one table.
///
/// Give it a key per table so switching tables starts with fresh state.
class TableViewer extends StatefulWidget {
  const TableViewer({super.key, required this.source, required this.table});

  final DbSource source;
  final TableInfo table;

  @override
  State<TableViewer> createState() => _TableViewerState();
}

class _TableViewerState extends State<TableViewer> {
  late final TableController _controller = TableController(
    source: widget.source,
    table: widget.table,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = ViewerColors.of(context);
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final c = _controller;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: colors.toolbar,
                border: Border(bottom: BorderSide(color: colors.gridLine)),
              ),
              child: Row(
                children: [
                  Icon(
                    widget.table.kind == TableKind.view
                        ? Icons.visibility_outlined
                        : Icons.table_chart_outlined,
                    size: 16,
                    color: colors.muted,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: SelectableText(
                            widget.table.name,
                            maxLines: 1,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Text(
                          c.total == null
                              ? 'Rows: …'
                              : 'Rows: ${formatInt(c.total!)}',
                          style: TextStyle(color: colors.muted, fontSize: 12),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Columns: ${c.columns.length}',
                          style: TextStyle(color: colors.muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  if (c.activeFilterCount > 0)
                    TextButton.icon(
                      onPressed: c.clearFilters,
                      icon: const Icon(Icons.filter_alt_off_outlined, size: 16),
                      label: Text(
                        'Clear ${c.activeFilterCount} '
                        'filter${c.activeFilterCount == 1 ? '' : 's'}',
                      ),
                    ),
                  IconButton(
                    tooltip: 'Reload table',
                    iconSize: 16,
                    visualDensity: VisualDensity.compact,
                    onPressed: c.reload,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
            ),
            if (c.error != null)
              MaterialBanner(
                content: SelectableText(c.error!),
                leading: const Icon(Icons.error_outline),
                actions: [
                  TextButton(onPressed: c.reload, child: const Text('Retry')),
                ],
              ),
            Expanded(
              child: DataGrid(
                controller: c,
                onOpenRow: (index) =>
                    showRowDialog(context, controller: c, index: index),
              ),
            ),
            PaginationBar(controller: c),
          ],
        );
      },
    );
  }
}
