import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Icon button that copies [text] and briefly shows a check mark.
class CopyButton extends StatefulWidget {
  const CopyButton({
    super.key,
    required this.text,
    this.tooltip = 'Copy',
    this.label,
    this.size = 16,
  });

  final String Function() text;
  final String tooltip;

  /// Shows a text button with this label instead of a bare icon.
  final String? label;
  final double size;

  @override
  State<CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<CopyButton> {
  bool _copied = false;
  Timer? _timer;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.text()));
    if (!mounted) return;
    setState(() => _copied = true);
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final icon = Icon(
      _copied ? Icons.check : Icons.copy_outlined,
      size: widget.size,
      color: _copied ? Colors.green : null,
    );
    final label = widget.label;
    if (label != null) {
      return TextButton.icon(
        onPressed: _copy,
        icon: icon,
        label: Text(_copied ? 'Copied' : label),
      );
    }
    return IconButton(
      tooltip: _copied ? 'Copied' : widget.tooltip,
      visualDensity: VisualDensity.compact,
      iconSize: widget.size,
      onPressed: _copy,
      icon: icon,
    );
  }
}
