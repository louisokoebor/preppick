/// The kinds of measurement PrepPick is willing to add up.
///
/// [count] covers unit-less amounts — "2 onions", "3 wraps". A null unit is a
/// count, not an unknown: the household wrote a number and no unit because
/// none was needed.
enum MeasureDimension { mass, volume, count }

/// An amount and the unit it is expressed in.
class Quantity {
  const Quantity(this.amount, this.unit);

  final double amount;

  /// Null for a count.
  final String? unit;

  @override
  bool operator ==(Object other) =>
      other is Quantity && other.amount == amount && other.unit == unit;

  @override
  int get hashCode => Object.hash(amount, unit);

  @override
  String toString() => unit == null ? '$amount' : '$amount $unit';
}

/// The unit arithmetic behind shopping-list aggregation.
///
/// ## Why this is deliberately small
///
/// A universal unit converter is a liability on a shopping list. Grams to
/// kilograms is a fact; tablespoons to grams depends on what is being
/// measured, and "2 cloves" to "30 g" is a guess. A wrong conversion produces
/// a confident number that sends someone home with the wrong amount of food,
/// which is worse than two honest lines.
///
/// So PrepPick converts within exactly two scales — metric mass and metric
/// volume — and treats every other unit as an opaque label that only ever
/// adds to an identical label. Anything it cannot add, it keeps apart.
class QuantityMath {
  const QuantityMath._();

  /// Spellings that mean the same unit. Only unambiguous ones belong here.
  static const Map<String, String> _aliases = {
    'g': 'g',
    'gram': 'g',
    'grams': 'g',
    'gr': 'g',
    'kg': 'kg',
    'kilo': 'kg',
    'kilos': 'kg',
    'kilogram': 'kg',
    'kilograms': 'kg',
    'ml': 'ml',
    'millilitre': 'ml',
    'millilitres': 'ml',
    'milliliter': 'ml',
    'milliliters': 'ml',
    'l': 'l',
    'litre': 'l',
    'litres': 'l',
    'liter': 'l',
    'liters': 'l',
  };

  /// How many base units (grams, millilitres) one of each unit is worth.
  static const Map<String, double> _inBaseUnits = {
    'g': 1,
    'kg': 1000,
    'ml': 1,
    'l': 1000,
  };

  static const Map<String, MeasureDimension> _dimensions = {
    'g': MeasureDimension.mass,
    'kg': MeasureDimension.mass,
    'ml': MeasureDimension.volume,
    'l': MeasureDimension.volume,
  };

  /// The base and display units of each convertible scale.
  static const Map<MeasureDimension, (String base, String large, double step)>
  _scales = {
    MeasureDimension.mass: ('g', 'kg', 1000),
    MeasureDimension.volume: ('ml', 'l', 1000),
  };

  /// The canonical spelling of [unit], or null for a count.
  ///
  /// An unrecognised unit keeps its own trimmed, lowercased spelling: PrepPick
  /// does not understand "tbsp", but it can still tell one "tbsp" from another.
  static String? canonicalUnit(String? unit) {
    final trimmed = unit?.trim().toLowerCase();
    if (trimmed == null || trimmed.isEmpty) return null;
    return _aliases[trimmed] ?? trimmed;
  }

  /// The scale [unit] belongs to, or null when it is a label PrepPick cannot
  /// convert within.
  static MeasureDimension? dimensionOf(String? unit) {
    final canonical = canonicalUnit(unit);
    if (canonical == null) return MeasureDimension.count;
    return _dimensions[canonical];
  }

  /// True when [a] and [b] can be safely added together.
  static bool canCombine(String? a, String? b) => bucketKey(a) == bucketKey(b);

  /// The group two amounts must share to be added.
  ///
  /// Convertible units collapse to their scale, so `g` and `kg` share a
  /// bucket. Everything else buckets on its exact spelling, so `tbsp` adds to
  /// `tbsp` and never to `clove`.
  static String bucketKey(String? unit) {
    final canonical = canonicalUnit(unit);
    if (canonical == null) return 'count';
    final dimension = _dimensions[canonical];
    return dimension == null ? 'unit:$canonical' : dimension.name;
  }

  /// [amount] of [unit] expressed in its scale's base unit, or null when
  /// [unit] is not on a convertible scale.
  static double? toBaseUnits(double amount, String? unit) {
    final canonical = canonicalUnit(unit);
    if (canonical == null) return amount;
    final factor = _inBaseUnits[canonical];
    return factor == null ? null : amount * factor;
  }

  /// Adds amounts that share a bucket, returning the total in the unit a
  /// person would want to read.
  ///
  /// Returns null for an empty list. Throws [ArgumentError] if the parts do
  /// not share a bucket — callers group first, so a mismatch here is a bug,
  /// not bad data.
  static Quantity? sum(List<Quantity> parts) {
    if (parts.isEmpty) return null;
    final bucket = bucketKey(parts.first.unit);
    var total = 0.0;
    for (final part in parts) {
      if (bucketKey(part.unit) != bucket) {
        throw ArgumentError(
          'Cannot add ${part.unit ?? 'count'} to a $bucket total.',
        );
      }
      // An opaque unit has no base to convert to, but every part in this
      // bucket carries that same unit, so the amounts add as they stand.
      total += toBaseUnits(part.amount, part.unit) ?? part.amount;
    }

    final dimension = dimensionOf(parts.first.unit);
    final scale = dimension == null ? null : _scales[dimension];
    if (scale == null) {
      // A count, or an opaque label: the unit never changed, so the total is
      // already in the unit it started in.
      return Quantity(round(total), canonicalUnit(parts.first.unit));
    }

    final (base, large, step) = scale;
    // 1250 g reads better as 1.25 kg; 750 g does not read better as 0.75 kg.
    return total >= step
        ? Quantity(round(total / step), large)
        : Quantity(round(total), base);
  }

  /// Trims binary floating-point noise so 0.1 + 0.2 shows as 0.3.
  ///
  /// Three decimals is past any amount a kitchen cares about, and keeps
  /// 1.25 kg exact.
  static double round(double value) => double.parse(value.toStringAsFixed(3));
}
