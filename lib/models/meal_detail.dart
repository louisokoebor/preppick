import 'meal_recipe_line.dart';
import 'meal_variant.dart';
import 'meal_family.dart';

/// The complete read model needed by Meal Detail and Meal Edit.
///
/// The database keeps families, variants and recipe lines separate. Keeping
/// the joined read here means UI code can render one meal without reaching
/// across several services or making assumptions about that relationship.
class MealDetail {
  const MealDetail({
    required this.meal,
    required this.family,
    required this.ingredients,
  });

  final MealVariant meal;
  final MealFamily family;
  final List<MealRecipeLine> ingredients;
}

/// Input for one ingredient row in the add/edit form.
class MealIngredientDraft {
  const MealIngredientDraft({
    this.lineId,
    required this.name,
    this.category,
    this.quantity,
    this.unit,
    this.baseServings,
  });

  final String? lineId;
  final String name;
  final String? category;
  final double? quantity;
  final String? unit;
  final int? baseServings;
}

/// An ingredient with its current category, useful to form a draft from an
/// existing recipe without losing the category on save.
MealIngredientDraft draftFromRecipeLine(MealRecipeLine line) =>
    MealIngredientDraft(
      lineId: line.id,
      name: line.name,
      category: line.category,
      quantity: line.quantity,
      unit: line.unit,
      baseServings: line.baseServings,
    );
