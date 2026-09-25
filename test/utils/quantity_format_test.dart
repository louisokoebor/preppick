import 'package:flutter_test/flutter_test.dart';
import 'package:preppick/utils/quantity_format.dart';

void main() {
  group('PrepQuantityFormat.label', () {
    test('drops the decimal point on a whole amount', () {
      expect(PrepQuantityFormat.label(500, 'g'), '500 g');
      expect(PrepQuantityFormat.label(500.0, 'g'), '500 g');
    });

    test('keeps only the decimals an amount needs', () {
      expect(PrepQuantityFormat.label(1.25, 'kg'), '1.25 kg');
      expect(PrepQuantityFormat.label(0.5, 'l'), '0.5 l');
    });

    test('writes a count with no unit at all', () {
      expect(PrepQuantityFormat.label(2, null), '2');
      expect(PrepQuantityFormat.label(2, '  '), '2');
    });

    test('canonicalises the unit it prints', () {
      expect(PrepQuantityFormat.label(300, 'Grams'), '300 g');
      expect(PrepQuantityFormat.label(2, 'TBSP'), '2 tbsp');
    });

    test('returns null for an unknown quantity — never "0"', () {
      expect(PrepQuantityFormat.label(null, 'g'), isNull);
      expect(PrepQuantityFormat.label(null, null), isNull);
    });

    test('still prints a genuine zero, which is not the same thing', () {
      expect(PrepQuantityFormat.label(0, 'g'), '0 g');
    });

    test('trims floating-point noise', () {
      expect(PrepQuantityFormat.label(0.1 + 0.2, 'l'), '0.3 l');
    });
  });
}
