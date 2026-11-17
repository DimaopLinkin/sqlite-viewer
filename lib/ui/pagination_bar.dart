import 'package:flutter/material.dart';

import '../state/table_controller.dart';
import 'format.dart';
import 'theme.dart';

/// Bottom bar: page navigation, page size and row range.
class PaginationBar extends StatefulWidget {
  const PaginationBar({super.key, required this.controller});

  final TableController controller;

  @override
  State<PaginationBar> createState() => _PaginationBarState();
}

class _PaginationBarState extends State<PaginationBar> {
  final _pageField = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _pageField.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit(String text) {
    final page = int.tryParse(text.trim());
    if (page != null) widget.controller.goToPage(page - 1);
    _pageField.text = '${widget.controller.pageIndex + 1}';
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final colors = ViewerColors.of(context);
    final current = '${c.pageIndex + 1}';
    if (!_focus.hasFocus && _pageField.text != current) {
      _pageField.text = current;
    }
    final first = c.pageIndex == 0;
    final last = c.pageIndex >= c.pageCount - 1;
    final total = c.total;
    final rowsOnPage = c.page?.rows.length ?? 0;
    final from = c.pageIndex * c.pageSize + (rowsOnPage == 0 ? 0 : 1);
    final to = c.pageIndex * c.pageSize + rowsOnPage;

    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: colors.toolbar,
        border: Border(top: BorderSide(color: colors.gridLine)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          _NavButton(
            icon: Icons.first_page,
            tooltip: 'First page',
            onPressed: first ? null : () => c.goToPage(0),
          ),
          _NavButton(
            icon: Icons.chevron_left,
            tooltip: 'Previous page',
            onPressed: first ? null : () => c.goToPage(c.pageIndex - 1),
          ),
          SizedBox(
            width: 64,
            child: TextField(
              controller: _pageField,
              focusNode: _focus,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12),
              keyboardType: TextInputType.number,
              onSubmitted: _submit,
              onTapOutside: (_) {
                if (_focus.hasFocus) {
                  _focus.unfocus();
                  _submit(_pageField.text);
                }
              },
            ),
          ),
          _NavButton(
            icon: Icons.chevron_right,
            tooltip: 'Next page',
            onPressed: last ? null : () => c.goToPage(c.pageIndex + 1),
          ),
          _NavButton(
            icon: Icons.last_page,
            tooltip: 'Last page',
            onPressed: last ? null : () => c.goToPage(c.pageCount - 1),
          ),
          const SizedBox(width: 8),
          Text(
            'Page ${c.pageIndex + 1} / ${total == null ? '…' : formatInt(c.pageCount)}',
            style: const TextStyle(fontSize: 12),
          ),
          const Spacer(),
          Text(
            total == null
                ? 'Counting…'
                : '${formatInt(from)}–${formatInt(to)} of ${formatInt(total)}',
            style: TextStyle(fontSize: 12, color: colors.muted),
          ),
          const SizedBox(width: 16),
          Text(
            'Rows per page',
            style: TextStyle(fontSize: 12, color: colors.muted),
          ),
          const SizedBox(width: 8),
          DropdownButton<int>(
            value: c.pageSize,
            isDense: true,
            underline: const SizedBox.shrink(),
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            onChanged: (v) {
              if (v != null) c.setPageSize(v);
            },
            items: [
              for (final size in TableController.pageSizes)
                DropdownMenuItem(value: size, child: Text('$size')),
            ],
          ),
        ],
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      iconSize: 18,
      visualDensity: VisualDensity.compact,
      onPressed: onPressed,
      icon: Icon(icon),
    );
  }
}
