import 'package:flutter/widgets.dart';

import '../data/db_source.dart';
import '../data/models.dart';

/// State of the SQL console of one opened file: the script, the write
/// switch and the last result.
class SqlController extends ChangeNotifier {
  SqlController({required this.source, required this.onDataChanged});

  final DbSource source;

  /// Called after a script changed the database, so the schema, the row
  /// counts and the table views can be reloaded.
  final VoidCallback onDataChanged;

  final editor = TextEditingController();

  bool _allowWrites = false;
  bool get allowWrites => _allowWrites && source.canWrite;

  bool _running = false;
  bool get running => _running;

  SqlResult? _result;
  SqlResult? get result => _result;

  /// A failure outside SQLite itself, e.g. the background isolate died.
  String? _failure;
  String? get failure => _failure;

  /// Text that was run last, so error offsets can be mapped back.
  String _ranText = '';
  int _ranFrom = 0;

  bool _disposed = false;

  set allowWrites(bool value) {
    if (_allowWrites == value) return;
    _allowWrites = value;
    notifyListeners();
  }

  /// Runs the selected text, or the whole script when nothing is selected.
  Future<void> run() async {
    if (_running) return;
    final text = editor.text;
    final selection = editor.selection;
    final useSelection =
        selection.isValid &&
        !selection.isCollapsed &&
        selection.textInside(text).trim().isNotEmpty;
    final sql = useSelection ? selection.textInside(text) : text;
    if (sql.trim().isEmpty) return;

    _running = true;
    _failure = null;
    _ranText = text;
    _ranFrom = useSelection ? selection.start : 0;
    notifyListeners();
    try {
      final result = await source.execute(sql, allowWrites: allowWrites);
      if (_disposed) return;
      _result = result;
      if (result.wroteData) onDataChanged();
    } catch (e) {
      if (_disposed) return;
      _result = null;
      _failure = '$e';
    } finally {
      if (!_disposed) {
        _running = false;
        notifyListeners();
      }
    }
  }

  /// Moves the cursor to where SQLite reported the error, if the script was
  /// not edited since.
  void selectErrorPosition() {
    final offset = _result?.error?.offset;
    if (offset == null || editor.text != _ranText) return;
    final position = (_ranFrom + offset).clamp(0, editor.text.length);
    editor.selection = TextSelection.collapsed(offset: position);
  }

  @override
  void dispose() {
    _disposed = true;
    editor.dispose();
    super.dispose();
  }
}
