import '../services/quantity_math.dart';

/// How an amount is written on screen.
///
/// Separate from [QuantityMath], which decides what a total *is*: this only
/// decides how to spell it. The rule that matters is the null one — a line
/// with no recorded amount shows no amount at all. Rendering it as "0" would
/// be a fabricated quantity, and a shopper reading "Chicken 0 g" is worse off
/// than one reading "Chicken" and using their judgement.
class PrepQuantityFormat {
  const PrepQuantityFormat._();

  /// The amount to draw beside an item, or null when none is known.
  ///
  /// A whole number loses its decimal point (500 g, not 500.0 g); a fraction
  /// keeps only the digits it needs (1.25 kg, 0.5 l). A quantity with no unit
  /// is a count and is written bare — "2", meaning two of the thing named.
  static String? label(double? quantity, String? unit) {
    if (quantity == null) return null;
    final amount = _amount(quantity);
    final canonical = QuantityMath.canonicalUnit(unit);
    return canonical == null ? amount : '$amount $canonical';
  }

  static String _amount(double value) {
    final rounded = QuantityMath.round(value);
    if (rounded == rounded.roundToDouble()) {
      return rounded.toStringAsFixed(0);
    }
    // toString() on a rounded double is already minimal: 1.25, not 1.2500.
    return rounded.toString();
  }
}
