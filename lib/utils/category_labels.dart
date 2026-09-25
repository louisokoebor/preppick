import '../models/models.dart';

/// Display names for the shopping categories.
///
/// The stored values are lowercase keys ('produce', 'chilled'), which is what
/// belongs in the database but not what belongs on a shopping list. An
/// unrecognised key is title-cased rather than hidden, so a category that
/// arrives from an import still reads as a word.
class PrepCategoryLabels {
  const PrepCategoryLabels._();

  static const Map<String, String> _names = {
    IngredientCategory.produce: 'Produce',
    IngredientCategory.protein: 'Protein',
    IngredientCategory.chilled: 'Chilled',
    IngredientCategory.frozen: 'Frozen',
    IngredientCategory.pantry: 'Pantry',
    IngredientCategory.household: 'Household',
    IngredientCategory.specialist: 'Specialist',
    IngredientCategory.other: 'Other',
  };

  static String labelFor(String category) =>
      _names[category] ?? _titleCase(category);

  static String _titleCase(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return 'Other';
    return trimmed[0].toUpperCase() + trimmed.substring(1);
  }
}
