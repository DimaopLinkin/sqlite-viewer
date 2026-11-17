import 'package:flutter/material.dart';

import '../data/models.dart';
import '../state/table_controller.dart';
import 'theme.dart';

/// Column header: name, type, sort toggle, filter field and resize handle.
class HeaderCell extends StatelessWidget {
  const HeaderCell({super.key, required this.controller, required this.column});

  final TableController controller;
  final ColumnInfo column;

  @override
  Widget build(BuildContext context) {
    final colors = ViewerColors.of(context);
    final sort = controller.sort;
    final sorted = sort?.column == column.name ? sort!.direction : null;

    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 10, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Tooltip(
                  message:
                      '${column.name}'
                      '${column.declaredType.isEmpty ? '' : '  ${column.declaredType}'}'
                      '${column.isPrimaryKey ? '  PRIMARY KEY' : ''}'
                      '${column.notNull ? '  NOT NULL' : ''}'
                      '\nClick to sort',
                  child: InkWell(
                    onTap: () => controller.toggleSort(column.name),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            column.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (sorted != null)
                          Icon(
                            sorted == SortDirection.asc
                                ? Icons.arrow_upward
                                : Icons.arrow_downward,
                            size: 14,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        if (column.isPrimaryKey)
                          Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: Icon(
                              Icons.key,
                              size: 12,
                              color: colors.muted,
                            ),
                          ),
                        const SizedBox(width: 4),
                        _TypeBadge(column: column),
                      ],
                    ),
                  ),
                ),
              ),
              SizedBox(
                height: 28,
                child: FilterField(
                  // Recreated per column so a recycled cell never shows the
                  // text of another column.
                  key: ValueKey(column.name),
                  controller: controller,
                  column: column.name,
                ),
              ),
            ],
          ),
        ),
        Positioned(
          top: 0,
          bottom: 0,
          right: 0,
          width: 8,
          child: _ResizeHandle(controller: controller, column: column.name),
        ),
      ],
    );
  }
}

class _TypeBadge extends StatelessWidget {
  const _TypeBadge({required this.column});

  final ColumnInfo column;

  @override
  Widget build(BuildContext context) {
    final colors = ViewerColors.of(context);
    final label = switch (column.affinity) {
      ColumnAffinity.integer ||
      ColumnAffinity.real ||
      ColumnAffinity.numeric => '#',
      ColumnAffinity.text => 'abc',
      ColumnAffinity.blob => column.declaredType.isEmpty ? 'any' : 'bin',
    };
    return Text(
      label,
      style: TextStyle(
        fontSize: 10,
        color: colors.muted,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _ResizeHandle extends StatefulWidget {
  const _ResizeHandle({required this.controller, required this.column});

  final TableController controller;
  final String column;

  @override
  State<_ResizeHandle> createState() => _ResizeHandleState();
}

class _ResizeHandleState extends State<_ResizeHandle> {
  double _startWidth = 0;
  double _dragged = 0;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (_) {
          _startWidth = widget.controller.columnWidth(widget.column);
          _dragged = 0;
        },
        onHorizontalDragUpdate: (d) {
          _dragged += d.delta.dx;
          widget.controller.setColumnWidth(
            widget.column,
            _startWidth + _dragged,
          );
        },
      ),
    );
  }
}

/// Text filter with an operator menu. Typing filters after a short pause.
class FilterField extends StatefulWidget {
  const FilterField({
    super.key,
    required this.controller,
    required this.column,
  });

  final TableController controller;
  final String column;

  @override
  State<FilterField> createState() => _FilterFieldState();
}

class _FilterFieldState extends State<FilterField> {
  late final TextEditingController _text = TextEditingController(
    text: widget.controller.filterFor(widget.column).value,
  );

  @override
  void didUpdateWidget(FilterField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Keep the field in sync when filters are cleared from the toolbar.
    final value = widget.controller.filterFor(widget.column).value;
    if (value != _text.text) _text.text = value;
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = ViewerColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final filter = widget.controller.filterFor(widget.column);
    final custom = filter.op != FilterOperator.contains;

    return TextField(
      controller: _text,
      readOnly: !filter.op.needsValue,
      onChanged: (v) => widget.controller.setFilter(widget.column, value: v),
      style: const TextStyle(fontSize: 12),
      decoration: InputDecoration(
        hintText: filter.op.needsValue
            ? (custom ? filter.op.label : 'Filter…')
            : filter.op.label,
        hintStyle: TextStyle(
          color: filter.op.needsValue ? colors.muted : scheme.primary,
          fontSize: 12,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (filter.value.isNotEmpty || custom)
              _SmallIcon(
                icon: Icons.close,
                tooltip: 'Clear filter',
                onTap: () {
                  _text.clear();
                  widget.controller.setFilter(
                    widget.column,
                    op: FilterOperator.contains,
                    value: '',
                  );
                },
              ),
            PopupMenuButton<FilterOperator>(
              tooltip: 'Filter type',
              initialValue: filter.op,
              padding: EdgeInsets.zero,
              onSelected: (op) =>
                  widget.controller.setFilter(widget.column, op: op),
              itemBuilder: (context) => [
                for (final op in FilterOperator.values)
                  PopupMenuItem(
                    value: op,
                    height: 32,
                    child: Text(op.label, style: const TextStyle(fontSize: 13)),
                  ),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Icon(
                  Icons.filter_list,
                  size: 14,
                  color: custom ? scheme.primary : colors.muted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SmallIcon extends StatelessWidget {
  const _SmallIcon({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Icon(icon, size: 13, color: ViewerColors.of(context).muted),
        ),
      ),
    );
  }
}
