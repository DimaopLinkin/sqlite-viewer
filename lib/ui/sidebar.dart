import 'package:flutter/material.dart';

import '../data/models.dart';
import '../state/viewer_controller.dart';
import 'format.dart';
import 'theme.dart';

/// Left panel: searchable list of tables and views with row counts.
class Sidebar extends StatefulWidget {
  const Sidebar({super.key, required this.controller});

  final ViewerController controller;

  @override
  State<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<Sidebar> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = ViewerColors.of(context);
    final controller = widget.controller;
    final needle = _query.trim().toLowerCase();
    final visible = [
      for (final t in controller.tables)
        if (needle.isEmpty || t.name.toLowerCase().contains(needle)) t,
    ];
    final tables = [
      for (final t in visible)
        if (t.kind == TableKind.table) t,
    ];
    final views = [
      for (final t in visible)
        if (t.kind == TableKind.view) t,
    ];

    return ColoredBox(
      color: colors.sidebar,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 30,
            child: _NavTile(
              icon: Icons.terminal,
              label: 'SQL query',
              selected: controller.sqlOpen,
              onTap: controller.openSql,
            ),
          ),
          Divider(height: 1, color: colors.gridLine),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
            child: TextField(
              controller: _search,
              onChanged: (v) => setState(() => _query = v),
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Filter ${controller.tables.length} tables…',
                prefixIcon: const Icon(Icons.search, size: 16),
                prefixIconConstraints: const BoxConstraints(minWidth: 32),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear',
                        iconSize: 14,
                        visualDensity: VisualDensity.compact,
                        onPressed: () {
                          _search.clear();
                          setState(() => _query = '');
                        },
                        icon: const Icon(Icons.close),
                      ),
              ),
            ),
          ),
          Expanded(
            child: visible.isEmpty
                ? Center(
                    child: Text(
                      controller.tables.isEmpty
                          ? 'No tables'
                          : 'Nothing matches “$_query”',
                      style: TextStyle(color: colors.muted, fontSize: 12),
                    ),
                  )
                : CustomScrollView(
                    slivers: [
                      if (tables.isNotEmpty) ...[
                        _sectionHeader('TABLES', tables.length, colors),
                        _list(tables),
                      ],
                      if (views.isNotEmpty) ...[
                        _sectionHeader('VIEWS', views.length, colors),
                        _list(views),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, int count, ViewerColors colors) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: Text(
          '$title  $count',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: colors.muted,
          ),
        ),
      ),
    );
  }

  Widget _list(List<TableInfo> items) {
    return SliverFixedExtentList.builder(
      itemExtent: 26,
      itemCount: items.length,
      itemBuilder: (context, i) => _TableTile(
        table: items[i],
        count: widget.controller.rowCounts[items[i].name],
        countKnown: widget.controller.rowCounts.containsKey(items[i].name),
        selected:
            !widget.controller.sqlOpen &&
            widget.controller.selected == items[i],
        onTap: () => widget.controller.select(items[i]),
      ),
    );
  }
}

class _TableTile extends StatelessWidget {
  const _TableTile({
    required this.table,
    required this.count,
    required this.countKnown,
    required this.selected,
    required this.onTap,
  });

  final TableInfo table;
  final int? count;
  final bool countKnown;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = ViewerColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final countText = !countKnown
        ? '…'
        : (count == null ? '?' : formatCount(count!));
    return Tooltip(
      message: count == null
          ? table.name
          : '${table.name}\n${formatInt(count!)} rows',
      child: Material(
        color: selected ? colors.selection : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Container(
            decoration: selected
                ? BoxDecoration(border: Border.all(color: scheme.primary))
                : null,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Icon(
                  table.kind == TableKind.view
                      ? Icons.visibility_outlined
                      : Icons.table_chart_outlined,
                  size: 14,
                  color: colors.muted,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    table.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  countText,
                  style: TextStyle(fontSize: 11, color: colors.muted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Sidebar entry that is not a table, e.g. the SQL console.
class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = ViewerColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? colors.selection : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: selected
              ? BoxDecoration(border: Border.all(color: scheme.primary))
              : null,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Icon(icon, size: 14, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
