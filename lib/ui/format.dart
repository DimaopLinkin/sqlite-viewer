import 'dart:convert';
import 'dart:typed_data';

/// `2310` → `2.3K`, `387200` → `387.2K`, like the sidebar of the reference.
String formatCount(int n) {
  String compact(double v, String suffix) {
    final text = v >= 100 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
    return '${text.endsWith('.0') ? text.substring(0, text.length - 2) : text}'
        '$suffix';
  }

  // Thresholds sit where rounding would otherwise print "1000K".
  if (n < 1000) return '$n';
  if (n < 999500) return compact(n / 1000, 'K');
  if (n < 999500000) return compact(n / 1000000, 'M');
  return compact(n / 1000000000, 'B');
}

/// `1234567` → `1 234 567`.
String formatInt(int n) {
  final digits = n.abs().toString();
  final buffer = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(' ');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

/// Longest text rendered in a grid cell; the dialog shows the full value.
const _maxCellChars = 300;

/// One-line preview of a value for the grid.
String cellText(Object? value) {
  switch (value) {
    case null:
      return 'NULL';
    case final Uint8List bytes:
      return 'BLOB · ${formatBytes(bytes.length)}';
    case final String s:
      final oneLine = s.length > _maxCellChars
          ? '${s.substring(0, _maxCellChars)}…'
          : s;
      return oneLine.replaceAll(RegExp(r'[\r\n\t]+'), ' ');
    default:
      return value.toString();
  }
}

/// Value for the row dialog. Long blobs are shortened; use [copyText] for
/// the clipboard.
String fullText(Object? value) => switch (value) {
  null => '',
  final Uint8List bytes => hexDump(bytes),
  _ => value.toString(),
};

/// Complete value for the clipboard, blobs as hex without a size cap.
String copyText(Object? value) => switch (value) {
  final Uint8List bytes => hexDump(bytes, maxBytes: bytes.length),
  _ => fullText(value),
};

/// Storage class of a value as SQLite reports it with `typeof()`.
String storageClass(Object? value) => switch (value) {
  null => 'NULL',
  int() || BigInt() => 'INTEGER',
  double() => 'REAL',
  String() => 'TEXT',
  Uint8List() => 'BLOB',
  _ => value.runtimeType.toString(),
};

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// Hex representation of a blob, capped so huge blobs stay responsive.
String hexDump(Uint8List bytes, {int maxBytes = 64 * 1024}) {
  final shown = bytes.length > maxBytes ? bytes.sublist(0, maxBytes) : bytes;
  final buffer = StringBuffer();
  for (var i = 0; i < shown.length; i++) {
    if (i > 0) buffer.write(i % 16 == 0 ? '\n' : ' ');
    buffer.write(shown[i].toRadixString(16).padLeft(2, '0'));
  }
  if (shown.length < bytes.length) {
    buffer.write('\n… ${formatBytes(bytes.length - shown.length)} more');
  }
  return buffer.toString();
}

/// Converts a row to JSON. Blobs become base64, 64-bit integers that do not
/// fit a JS number stay exact as strings.
String rowToJson(List<String> columns, List<Object?> row) {
  Object? jsonValue(Object? v) => switch (v) {
    final Uint8List b => base64Encode(b),
    final BigInt b => b.toString(),
    // JSON has no Infinity or NaN.
    final double d when !d.isFinite => d.toString(),
    _ => v,
  };
  return const JsonEncoder.withIndent('  ').convert({
    for (var i = 0; i < columns.length && i < row.length; i++)
      columns[i]: jsonValue(row[i]),
  });
}
