import 'package:flutter_test/flutter_test.dart';
import 'package:preppick/services/quantity_math.dart';

void main() {
  group('canonicalUnit', () {
    test('folds spellings of the same unit together', () {
      expect(QuantityMath.canonicalUnit('Grams'), 'g');
      expect(QuantityMath.canonicalUnit(' KG '), 'kg');
      expect(QuantityMath.canonicalUnit('litres'), 'l');
    });

    test('treats blank and null as a count', () {
      expect(QuantityMath.canonicalUnit(null), isNull);
      expect(QuantityMath.canonicalUnit('   '), isNull);
    });

    test('keeps an unknown unit rather than discarding it', () {
      expect(QuantityMath.canonicalUnit('TBSP'), 'tbsp');
    });
  });

  group('canCombine', () {
    test('units on the same metric scale combine', () {
      expect(QuantityMath.canCombine('g', 'kg'), isTrue);
      expect(QuantityMath.canCombine('ml', 'litre'), isTrue);
    });

    test('different scales do not combine', () {
      expect(QuantityMath.canCombine('g', 'ml'), isFalse);
      expect(QuantityMath.canCombine('kg', null), isFalse);
    });

    test('an unknown unit combines only with itself', () {
      expect(QuantityMath.canCombine('tbsp', 'tbsp'), isTrue);
      expect(QuantityMath.canCombine('tbsp', 'clove'), isFalse);
      expect(QuantityMath.canCombine('tbsp', 'g'), isFalse);
    });
  });

  group('sum', () {
    test('returns null for nothing to add', () {
      expect(QuantityMath.sum([]), isNull);
    });

    test('adds within one unit', () {
      expect(
        QuantityMath.sum([const Quantity(200, 'g'), const Quantity(150, 'g')]),
        const Quantity(350, 'g'),
      );
    });

    test('converts up once the total earns the larger unit', () {
      expect(
        QuantityMath.sum([const Quantity(500, 'g'), const Quantity(750, 'g')]),
        const Quantity(1.25, 'kg'),
      );
      expect(
        QuantityMath.sum([const Quantity(1, 'kg'), const Quantity(250, 'g')]),
        const Quantity(1.25, 'kg'),
      );
    });

    test('stays in the small unit below the threshold', () {
      expect(
        QuantityMath.sum([const Quantity(0.5, 'kg'), const Quantity(250, 'g')]),
        const Quantity(750, 'g'),
      );
    });

    test('adds counts and keeps them unit-less', () {
      expect(
        QuantityMath.sum([const Quantity(2, null), const Quantity(3, null)]),
        const Quantity(5, null),
      );
    });

    test('adds an unconvertible unit to itself without converting', () {
      expect(
        QuantityMath.sum([
          const Quantity(2, 'tbsp'),
          const Quantity(1, 'Tbsp'),
        ]),
        const Quantity(3, 'tbsp'),
      );
    });

    test('refuses to add across buckets', () {
      expect(
        () =>
            QuantityMath.sum([const Quantity(1, 'g'), const Quantity(1, 'ml')]),
        throwsArgumentError,
      );
    });

    test('trims floating point noise', () {
      expect(
        QuantityMath.sum([const Quantity(0.1, 'l'), const Quantity(0.2, 'l')]),
        const Quantity(300, 'ml'),
      );
    });
  });
}
