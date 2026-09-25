import '../models/models.dart';

class ImportLineClassification {
  const ImportLineClassification({required this.type, this.heading, this.note});

  final ImportLineType type;
  final String? heading;
  final String? note;
}

/// Conservative, deterministic classification for pasted history.
///
/// This deliberately removes only obvious non-meal lines. Anything that is
/// not confidently a heading, shopping item or household item remains a meal
/// candidate and can be marked ambiguous for human review.
class ImportLineClassifier {
  const ImportLineClassifier._();

  static final RegExp _leadingBullet = RegExp(r'^\s*[-*•–—]\s+');
  static final RegExp _leadingCheckbox = RegExp(r'^\s*\[[ xX]\]\s*');
  static final RegExp _leadingNumber = RegExp(r'^\s*\d+[\).:-]\s+');
  static final RegExp _dateOnly = RegExp(
    r'^(?:\d{1,2}[\/-]\d{1,2}(?:[\/-]\d{2,4})?|\d{4}[\/-]\d{1,2}[\/-]\d{1,2})$',
  );
  static final RegExp _weekHeading = RegExp(
    r'^(?:week|w/c|week commencing)(?:\s+of)?(?:\s+\d{1,2}[\/-]\d{1,2}(?:[\/-]\d{2,4})?)?$',
  );

  static const _mealHeadings = {
    'breakfast',
    'lunch',
    'dinner',
    'snack',
    'snacks',
    'meals',
    'meal plan',
    'meal history',
    'shopping list',
    'groceries',
  };

  static const _dayHeadings = {
    'monday',
    'tuesday',
    'wednesday',
    'thursday',
    'friday',
    'saturday',
    'sunday',
    'mon',
    'tue',
    'wed',
    'thu',
    'fri',
    'sat',
    'sun',
  };

  static const _shoppingItems = {
    'egg',
    'eggs',
    'milk',
    'bread',
    'salt',
    'oil',
    'flour',
    'sugar',
    'rice',
    'chicken',
    'fish',
  };

  static const _householdItems = {
    'african shop',
    'dish soap',
    'washing up liquid',
    'toilet roll',
    'toilet paper',
    'laundry detergent',
  };

  static ImportLineClassification classify(String rawLine) {
    final cleaned = cleanLine(rawLine);
    if (cleaned.isEmpty) {
      return const ImportLineClassification(
        type: ImportLineType.blank,
        note: 'Blank source line',
      );
    }

    final normalized = cleaned.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    if (_isHeading(normalized)) {
      return ImportLineClassification(
        type: ImportLineType.heading,
        heading: cleaned,
        note: 'Recognised section or date heading',
      );
    }
    if (_householdItems.contains(normalized)) {
      return const ImportLineClassification(
        type: ImportLineType.householdItem,
        note: 'Looks like a household or shop entry, not a meal',
      );
    }
    if (_shoppingItems.contains(normalized)) {
      return const ImportLineClassification(
        type: ImportLineType.shoppingItem,
        note: 'Looks like a standalone ingredient or shopping item',
      );
    }
    return const ImportLineClassification(type: ImportLineType.meal);
  }

  static String cleanLine(String line) {
    var cleaned = line.trim();
    cleaned = cleaned.replaceFirst(_leadingCheckbox, '');
    cleaned = cleaned.replaceFirst(_leadingBullet, '');
    cleaned = cleaned.replaceFirst(_leadingNumber, '');
    return cleaned.trim();
  }

  static bool _isHeading(String normalized) {
    if (_mealHeadings.contains(normalized) ||
        _dayHeadings.contains(normalized) ||
        _weekHeading.hasMatch(normalized) ||
        _dateOnly.hasMatch(normalized)) {
      return true;
    }
    return normalized.endsWith(':') && normalized.length < 40;
  }
}
