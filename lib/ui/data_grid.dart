import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:two_dimensional_scrollables/two_dimensional_scrollables.dart';

import '../state/table_controller.dart';
import 'format.dart';
import 'header_cell.dart';
import 'theme.dart';

const _headerHeight = 62.0;
const _rowHeight = 26.0;

/// Lazily built grid of the current page.
///
/// The header row and the row-number column are pinned, so the header stays
/// in place while scrolling down and row numbers stay visible while
/// scrolling sideways. Only visible cells are built.
class DataGrid extends StatefulWidget {
  const DataGrid({
    super.key,
    required this.controller,
    required this.onOpenRow,
  });

  final TableController controller;

  /// Called with the absolute row index in the filtered result.
  final ValueChanged<int> onOpenRow;

  @override
  State<DataGrid> createState() => _DataGridState();
}

class _DataGridState extends State<DataGrid> {
  final _vertical = ScrollController();
  final _horizontal = ScrollController();
  int? _hoveredRow;
  int? _lastPageOffset;

  @override
  void dispose() {
    _vertical.dispose();
    _horizontal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final colors = ViewerColors.of(context);
    final columns = controller.columns;
    final page = controller.page;
    final rows = page?.rows ?? const <List<Object?>>[];
    final offset = page?.offset ?? 0;

    // Jump back to the top when another page is shown.
    if (page != null && _lastPageOffset != page.offset) {
      _lastPageOffset = page.offset;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_vertical.hasClients) _vertical.jumpTo(0);
      });
    }

    final lastRowNumber = offset + rows.length;
    final numberWidth = (lastRowNumber.toString().length * 8.0 + 28).clamp(
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
              index == 0
                  ? numberWidth
                  : controller.columnWidth(columns[index - 1].name),
            ),
            foregroundDecoration: TableSpanDecoration(
              border: TableSpanBorder(
                trailing: BorderSide(color: colors.gridLine),
              ),
            ),
          ),
          rowBuilder: (index) {
            if (index == 0) {
              return TableSpan(
                extent: const FixedTableSpanExtent(_headerHeight),
                backgroundDecoration: TableSpanDecoration(color: colors.header),
                foregroundDecoration: TableSpanDecoration(
                  border: TableSpanBorder(
                    trailing: BorderSide(color: colors.gridLine),
                  ),
                ),
              );
            }
            final rowIndex = index - 1;
            return TableSpan(
              extent: const FixedTableSpanExtent(_rowHeight),
              backgroundDecoration: TableSpanDecoration(
                color: _hoveredRow == rowIndex
                    ? colors.rowHover
                    : (rowIndex.isOdd ? colors.rowAlt : null),
              ),
              cursor: SystemMouseCursors.click,
              onEnter: (_) => setState(() => _hoveredRow = rowIndex),
              onExit: (_) {
                if (_hoveredRow == rowIndex) setState(() => _hoveredRow = null);
              },
              recognizerFactories: {
                TapGestureRecognizer:
                    GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
                      TapGestureRecognizer.new,
                      (t) =>
                          t.onTap = () => widget.onOpenRow(offset + rowIndex),
                    ),
              },
            );
          },
          cellBuilder: (context, vicinity) {
            final row = vicinity.row;
            final col = vicinity.column;
            if (row == 0) {
              if (col == 0) {
                return TableViewCell(
                  child: Center(
                    child: Text(
                      '#',
                      style: TextStyle(color: colors.muted, fontSize: 12),
                    ),
                  ),
                );
              }
              return TableViewCell(
                child: HeaderCell(
                  controller: controller,
                  column: columns[col - 1],
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
                    '${offset + row}',
                    style: TextStyle(color: colors.muted, fontSize: 12),
                  ),
                ),
              );
            }
            return TableViewCell(
              child: _ValueCell(value: rows[row - 1][col - 1]),
            );
          },
        ),
      ),
    );

    return Stack(
      children: [
        Positioned.fill(child: grid),
        if (controller.loading)
          const Positioned(
            top: _headerHeight,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(minHeight: 2),
          ),
        if (!controller.loading && rows.isEmpty && controller.error == null)
          Positioned.fill(
            top: _headerHeight + 24,
            child: Align(
              alignment: Alignment.topCenter,
              child: Text(
                controller.activeFilterCount > 0
                    ? 'No rows match the filters'
                    : 'The table is empty',
                style: TextStyle(color: colors.muted),
              ),
            ),
          ),
      ],
    );
  }
}

class _ValueCell extends StatelessWidget {
  const _ValueCell({required this.value});

  final Object? value;

  @override
  Widget build(BuildContext context) {
    final colors = ViewerColors.of(context);
    final value = this.value;
    final numeric = value is num || value is BigInt;
    final text = cellText(value);
    return GestureDetector(
      onSecondaryTapUp: (d) => _showMenu(context, d.globalPosition),
      onLongPressStart: (d) => _showMenu(context, d.globalPosition),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: numeric ? Alignment.centerRight : Alignment.centerLeft,
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            color: value == null || value is Uint8List
                ? colors.nullValue
                : null,
            fontStyle: value == null ? FontStyle.italic : null,
            fontFeatures: numeric ? const [FontFeature.tabularFigures()] : null,
          ),
        ),
      ),
    );
  }

  Future<void> _showMenu(BuildContext context, Offset position) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: const [
        PopupMenuItem(value: 'copy', height: 32, child: Text('Copy value')),
      ],
    );
    if (choice == 'copy') {
      await Clipboard.setData(ClipboardData(text: fullText(value)));
    }
  }
}
