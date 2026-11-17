import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite_viewer/ui/format.dart';

void main() {
  test('formatCount matches the compact sidebar style', () {
    expect(formatCount(0), '0');
    expect(formatCount(999), '999');
    expect(formatCount(2310), '2.3K');
    expect(formatCount(8600), '8.6K');
    expect(formatCount(387200), '387K');
    expect(formatCount(1000), '1K');
    expect(formatCount(2500000), '2.5M');
  });

  test('cellText renders special values', () {
    expect(cellText(null), 'NULL');
    expect(cellText(Uint8List(2048)), 'BLOB · 2.0 KB');
    expect(cellText('a\nb'), 'a b');
    expect(cellText(BigInt.parse('173987886904923343')), '173987886904923343');
  });

  test('rowToJson keeps blobs and big integers lossless', () {
    final json = rowToJson(
      ['id', 'blob', 'big'],
      [
        1,
        Uint8List.fromList([1, 2]),
        BigInt.parse('9007199254740993'),
      ],
    );
    expect(json, contains('"blob": "AQI="'));
    expect(json, contains('"big": "9007199254740993"'));
  });

  test('hexDump caps long blobs', () {
    expect(hexDump(Uint8List.fromList([0, 255, 16])), '00 ff 10');
    expect(hexDump(Uint8List(40), maxBytes: 16), contains('24 B more'));
  });
}
