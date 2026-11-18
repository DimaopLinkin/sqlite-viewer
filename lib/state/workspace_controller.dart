import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../data/db_source.dart';
import 'viewer_controller.dart';

/// The set of open files, one [ViewerController] per tab.
class WorkspaceController extends ChangeNotifier {
  final List<ViewerController> _tabs = [];
  List<ViewerController> get tabs => List.unmodifiable(_tabs);

  int _activeIndex = -1;

  /// Index of the shown tab, or -1 when nothing is open.
  int get activeIndex => _activeIndex;

  ViewerController? get active => _activeIndex < 0 ? null : _tabs[_activeIndex];

  bool _opening = false;

  /// True while a file is being picked or opened for a new tab.
  bool get opening => _opening;

  /// Why the last attempt to open a file failed, or `null`.
  String? _error;
  String? get error => _error;

  bool _disposed = false;

  /// Opens a file in a new tab and shows it. [open] returns `null` when the
  /// user cancels the picker; then nothing changes.
  Future<void> openWith(Future<DbSource?> Function() open) async {
    if (_opening) return;
    _opening = true;
    _error = null;
    notifyListeners();
    ViewerController? tab;
    String? error;
    try {
      tab = await ViewerController.openWith(open);
    } catch (e) {
      error = 'Could not open the file: $e';
    }
    if (_disposed) {
      tab?.dispose();
      return;
    }
    _opening = false;
    _error = error;
    if (tab != null) {
      _tabs.add(tab);
      _activeIndex = _tabs.length - 1;
    }
    notifyListeners();
  }

  void activate(int index) {
    if (index == _activeIndex || index < 0 || index >= _tabs.length) return;
    _activeIndex = index;
    notifyListeners();
  }

  /// Closes the tab at [index] and its file. The tab to the right becomes
  /// active, or the one to the left if it was the last.
  void closeTab(int index) {
    if (index < 0 || index >= _tabs.length) return;
    final tab = _tabs.removeAt(index);
    if (_tabs.isEmpty) {
      _activeIndex = -1;
    } else if (index < _activeIndex || _activeIndex >= _tabs.length) {
      _activeIndex--;
    }
    notifyListeners();
    // The tab's widgets stay mounted until the next frame and may still
    // query the source, so close it only after that frame.
    SchedulerBinding.instance
      ..addPostFrameCallback((_) => tab.dispose())
      ..ensureVisualUpdate();
  }

  void dismissError() {
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final tab in _tabs) {
      tab.dispose();
    }
    _tabs.clear();
    super.dispose();
  }
}
