import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/db_opener.dart';
import '../data/db_source.dart';
import '../state/viewer_controller.dart';
import 'sidebar.dart';
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
  final _viewer = ViewerController();
  double _sidebarWidth = 280;

  @override
  void dispose() {
    _viewer.dispose();
    super.dispose();
  }

  Future<void> _open() => _viewer.openWith(widget.picker);

  @override
  Widget build(BuildContext context) {
    final colors = ViewerColors.of(context);
    return Scaffold(
      body: ListenableBuilder(
        listenable: _viewer,
        builder: (context, _) {
          final source = _viewer.source;
          final selected = _viewer.selected;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _TopBar(
                fileName: source?.name,
                busy: _viewer.busy,
                themeMode: widget.themeMode,
                onOpen: _open,
                onReload: source == null ? null : _viewer.reload,
                onClose: source == null ? null : _viewer.closeFile,
                onToggleTheme: widget.onToggleTheme,
              ),
              if (_viewer.error != null)
                MaterialBanner(
                  leading: const Icon(Icons.error_outline),
                  content: SelectableText(_viewer.error!),
                  actions: [
                    TextButton(
                      onPressed: _viewer.dismissError,
                      child: const Text('Dismiss'),
                    ),
                  ],
                ),
              Expanded(
                child: source == null
                    ? _EmptyState(onOpen: _open, busy: _viewer.busy)
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            width: _sidebarWidth,
                            child: Sidebar(controller: _viewer),
                          ),
                          MouseRegion(
                            cursor: SystemMouseCursors.resizeColumn,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onHorizontalDragUpdate: (d) => setState(() {
                                final max =
                                    MediaQuery.sizeOf(context).width * 0.6;
                                _sidebarWidth = (_sidebarWidth + d.delta.dx)
                                    .clamp(180.0, max < 180 ? 180.0 : max);
                              }),
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
                            child: selected == null
                                ? Center(
                                    child: Text(
                                      'The database has no tables',
                                      style: TextStyle(color: colors.muted),
                                    ),
                                  )
                                : TableViewer(
                                    key: ValueKey((source, selected)),
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
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.fileName,
    required this.busy,
    required this.themeMode,
    required this.onOpen,
    required this.onReload,
    required this.onClose,
    required this.onToggleTheme,
  });

  final String? fileName;
  final bool busy;
  final ThemeMode themeMode;
  final VoidCallback onOpen;
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
            onPressed: busy ? null : onOpen,
            icon: const Icon(Icons.folder_open, size: 16),
            label: const Text('Open file'),
          ),
          const SizedBox(width: 12),
          if (busy)
            const SizedBox.square(
              dimension: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          Expanded(
            child: Row(
              children: [
                if (fileName != null) ...[
                  Icon(
                    Icons.description_outlined,
                    size: 16,
                    color: colors.muted,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      fileName!,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: colors.muted),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (onReload != null)
            IconButton(
              tooltip: 'Reload schema',
              iconSize: 18,
              onPressed: onReload,
              icon: const Icon(Icons.refresh),
            ),
          if (onClose != null)
            IconButton(
              tooltip: 'Close file',
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
