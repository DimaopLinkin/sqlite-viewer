import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/db_opener.dart';
import '../data/db_source.dart';
import '../state/viewer_controller.dart';
import '../state/workspace_controller.dart';
import 'sidebar.dart';
import 'sql_console.dart';
import 'table_viewer.dart';
import 'theme.dart';

/// Picks a file and opens it. Replaceable in tests.
typedef SourcePicker = Future<DbSource?> Function();

Future<DbSource?> pickAndOpenSqlite() async {
  final file = await FilePicker.pickFile(dialogTitle: 'Open SQLite database');
  if (file == null) return null;
  return openDbSource(file);
}

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.themeMode,
    required this.onToggleTheme,
    this.picker = pickAndOpenSqlite,
  });

  final ThemeMode themeMode;
  final VoidCallback onToggleTheme;
  final SourcePicker picker;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _workspace = WorkspaceController();
  double _sidebarWidth = 280;

  @override
  void dispose() {
    _workspace.dispose();
    super.dispose();
  }

  Future<void> _open() => _workspace.openWith(widget.picker);

  void _resizeSidebar(double delta) => setState(() {
    final max = MediaQuery.sizeOf(context).width * 0.6;
    _sidebarWidth = (_sidebarWidth + delta).clamp(
      180.0,
      max < 180 ? 180.0 : max,
    );
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListenableBuilder(
        listenable: _workspace,
        builder: (context, _) {
          final tabs = _workspace.tabs;
          final active = _workspace.active;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Rebuilds with the active tab so reload/busy state stay live.
              ListenableBuilder(
                listenable: active ?? _workspace,
                builder: (context, _) => _TopBar(
                  busy: _workspace.opening || (active?.busy ?? false),
                  themeMode: widget.themeMode,
                  onOpen: _workspace.opening ? null : _open,
                  onReload: active == null || active.busy
                      ? null
                      : active.reload,
                  onClose: active == null
                      ? null
                      : () => _workspace.closeTab(_workspace.activeIndex),
                  onToggleTheme: widget.onToggleTheme,
                ),
              ),
              if (tabs.isNotEmpty)
                _TabBar(
                  tabs: tabs,
                  activeIndex: _workspace.activeIndex,
                  onSelect: _workspace.activate,
                  onClose: _workspace.closeTab,
                ),
              if (_workspace.error case final error?)
                _ErrorBanner(
                  message: error,
                  onDismiss: _workspace.dismissError,
                ),
              Expanded(
                child: tabs.isEmpty
                    ? _EmptyState(onOpen: _open, busy: _workspace.opening)
                    // Keeps every tab alive so filters, sort, page and scroll
                    // survive switching between files.
                    : IndexedStack(
                        index: _workspace.activeIndex,
                        sizing: StackFit.expand,
                        children: [
                          for (final (i, tab) in tabs.indexed)
                            TickerMode(
                              key: ObjectKey(tab),
                              enabled: i == _workspace.activeIndex,
                              child: _DbTab(
                                viewer: tab,
                                sidebarWidth: _sidebarWidth,
                                onResizeSidebar: _resizeSidebar,
                              ),
                            ),
                        ],
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Contents of one tab: notice, errors, sidebar and the selected table.
class _DbTab extends StatelessWidget {
  const _DbTab({
    required this.viewer,
    required this.sidebarWidth,
    required this.onResizeSidebar,
  });

  final ViewerController viewer;
  final double sidebarWidth;
  final ValueChanged<double> onResizeSidebar;

  @override
  Widget build(BuildContext context) {
    final colors = ViewerColors.of(context);
    return ListenableBuilder(
      listenable: viewer,
      builder: (context, _) {
        final source = viewer.source;
        final selected = viewer.selected;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (source.notice case final notice?)
              Container(
                color: colors.toolbar,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 16, color: colors.muted),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        notice,
                        style: TextStyle(fontSize: 12, color: colors.muted),
                      ),
                    ),
                  ],
                ),
              ),
            if (viewer.error case final error?)
              _ErrorBanner(message: error, onDismiss: viewer.dismissError),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: sidebarWidth,
                    child: Sidebar(controller: viewer),
                  ),
                  MouseRegion(
                    cursor: SystemMouseCursors.resizeColumn,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onHorizontalDragUpdate: (d) =>
                          onResizeSidebar(d.delta.dx),
                      child: Container(
                        width: 4,
                        color: colors.sidebar,
                        child: VerticalDivider(
                          width: 1,
                          color: colors.gridLine,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: viewer.sqlOpen
                        ? SqlConsole(controller: viewer.sql)
                        : selected == null
                        ? Center(
                            child: Text(
                              'The database has no tables',
                              style: TextStyle(color: colors.muted),
                            ),
                          )
                        : TableViewer(
                            key: ValueKey((
                              source,
                              selected,
                              viewer.schemaVersion,
                            )),
                            source: source,
                            table: selected,
                          ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// One tab per open file, scrollable when they do not fit.
class _TabBar extends StatefulWidget {
  const _TabBar({
    required this.tabs,
    required this.activeIndex,
    required this.onSelect,
    required this.onClose,
  });

  final List<ViewerController> tabs;
  final int activeIndex;
  final ValueChanged<int> onSelect;
  final ValueChanged<int> onClose;

  @override
  State<_TabBar> createState() => _TabBarState();
}

class _TabBarState extends State<_TabBar> {
  final _keys = Expando<GlobalKey>();
  ViewerController? _shown;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _revealActive();
  }

  @override
  void didUpdateWidget(_TabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _revealActive();
  }

  /// Scrolls a newly activated tab into view, e.g. one just opened at the
  /// end of an overflowing strip.
  void _revealActive() {
    final active = widget.tabs[widget.activeIndex];
    if (identical(active, _shown)) return;
    _shown = active;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _keys[active]?.currentContext;
      if (context == null || !context.mounted) return;
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 150),
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 150),
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = ViewerColors.of(context);
    return Container(
      height: 34,
      decoration: BoxDecoration(
        color: colors.sidebar,
        border: Border(bottom: BorderSide(color: colors.gridLine)),
      ),
      // A Row in a scroll view (not a lazy ListView) so the active tab is
      // always built and can be scrolled to.
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final (i, tab) in widget.tabs.indexed)
              _FileTab(
                key: _keys[tab] ??= GlobalKey(),
                name: tab.source.name,
                active: i == widget.activeIndex,
                onSelect: () => widget.onSelect(i),
                onClose: () => widget.onClose(i),
              ),
          ],
        ),
      ),
    );
  }
}

class _FileTab extends StatelessWidget {
  const _FileTab({
    super.key,
    required this.name,
    required this.active,
    required this.onSelect,
    required this.onClose,
  });

  final String name;
  final bool active;
  final VoidCallback onSelect;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colors = ViewerColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      // Middle click closes the tab, as in browsers and editors.
      onTertiaryTapUp: (_) => onClose(),
      child: Tooltip(
        message: name,
        waitDuration: const Duration(milliseconds: 600),
        child: InkWell(
          onTap: onSelect,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 240),
            padding: const EdgeInsets.only(left: 12, right: 4),
            decoration: BoxDecoration(
              color: active ? colors.toolbar : null,
              border: Border(
                top: BorderSide(
                  color: active ? primary : Colors.transparent,
                  width: 2,
                ),
                right: BorderSide(color: colors.gridLine),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.description_outlined,
                  size: 15,
                  color: active ? primary : colors.muted,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    name,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: active ? null : colors.muted,
                    ),
                  ),
                ),
                const SizedBox(width: 2),
                IconButton(
                  tooltip: 'Close tab',
                  iconSize: 14,
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints.tightFor(
                    width: 24,
                    height: 24,
                  ),
                  padding: EdgeInsets.zero,
                  onPressed: onClose,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.busy,
    required this.themeMode,
    required this.onOpen,
    required this.onReload,
    required this.onClose,
    required this.onToggleTheme,
  });

  final bool busy;
  final ThemeMode themeMode;
  final VoidCallback? onOpen;
  final VoidCallback? onReload;
  final VoidCallback? onClose;
  final VoidCallback onToggleTheme;

  @override
  Widget build(BuildContext context) {
    final colors = ViewerColors.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: colors.toolbar,
        border: Border(bottom: BorderSide(color: colors.gridLine)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.storage,
            size: 18,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 8),
          const Text(
            'SQLite Viewer',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 16),
          FilledButton.tonalIcon(
            onPressed: onOpen,
            icon: const Icon(Icons.folder_open, size: 16),
            label: const Text('Open file'),
          ),
          const SizedBox(width: 12),
          if (busy)
            const SizedBox.square(
              dimension: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          const Spacer(),
          if (onReload != null)
            IconButton(
              tooltip: 'Reload schema',
              iconSize: 18,
              onPressed: onReload,
              icon: const Icon(Icons.refresh),
            ),
          if (onClose != null)
            IconButton(
              tooltip: 'Close tab',
              iconSize: 18,
              onPressed: onClose,
              icon: const Icon(Icons.close),
            ),
          IconButton(
            tooltip: dark ? 'Light theme' : 'Dark theme',
            iconSize: 18,
            onPressed: onToggleTheme,
            icon: Icon(
              dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onOpen, required this.busy});

  final VoidCallback onOpen;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final colors = ViewerColors.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.storage, size: 56, color: colors.muted),
          const SizedBox(height: 16),
          const Text(
            'Open a SQLite database to browse its tables',
            style: TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 4),
          Text(
            '.sqlite, .sqlite3, .db, .db3 or any other SQLite file',
            style: TextStyle(color: colors.muted),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: busy ? null : onOpen,
            icon: const Icon(Icons.folder_open),
            label: const Text('Open file…'),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) => MaterialBanner(
    leading: const Icon(Icons.error_outline),
    content: SelectableText(message),
    actions: [TextButton(onPressed: onDismiss, child: const Text('Dismiss'))],
  );
}
