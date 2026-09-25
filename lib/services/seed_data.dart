/// Declarative description of the development/demo meal library.
///
/// **This is not a real household's data.** It exists so the planning, swap and
/// shopping-list flows can be exercised end to end before any meal has been
/// imported or entered by hand. Expect to delete it once real data exists.
///
/// The catalogue is deliberately shaped to cover the awkward cases the
/// shopping list has to survive:
///
/// * `Chicken breast` appears in two meals in the same unit (g), so the list
///   has something to merge.
/// * `Olive oil` and `Sea salt` are recorded with no quantity at all, because
///   nobody measures them. They must stay quantity-less, never guessed.
/// * `Tomatoes` appear in one meal by weight and another by count, so the list
///   has a pair it must refuse to merge.
/// * Ingredients span produce, protein, pantry, chilled, frozen, household and
///   specialist so category grouping has something to group.
library;

import '../models/models.dart';

/// One ingredient in the demo catalogue.
class SeedIngredient {
  const SeedIngredient(this.name, this.category);

  final String name;
  final String category;
}

/// One recipe line: an ingredient plus how much of it a meal uses.
///
/// [quantity] is null wherever the amount genuinely is not known.
class SeedRecipeLine {
  const SeedRecipeLine(
    this.ingredient, {
    this.quantity,
    this.unit,
    this.baseServings,
  });

  /// Ingredient name, matched against [SeedData.ingredients].
  final String ingredient;
  final double? quantity;
  final String? unit;
  final int? baseServings;
}

/// One variant of a family, with its recipe.
class SeedVariant {
  const SeedVariant(
    this.name, {
    this.protein,
    this.estimatedMinutes,
    this.lines = const [],
  });

  final String name;
  final String? protein;
  final int? estimatedMinutes;
  final List<SeedRecipeLine> lines;
}

/// One meal family and its variants.
class SeedFamily {
  const SeedFamily(this.name, this.mealType, this.variants);

  final String name;
  final MealType mealType;
  final List<SeedVariant> variants;
}

/// The demo catalogue itself.
class SeedData {
  const SeedData._();

  /// Serving count every demo recipe is written for.
  static const int baseServings = 4;

  static const List<SeedIngredient> ingredients = [
    // produce
    SeedIngredient('Onion', IngredientCategory.produce),
    SeedIngredient('Garlic', IngredientCategory.produce),
    SeedIngredient('Tomatoes', IngredientCategory.produce),
    SeedIngredient('Red pepper', IngredientCategory.produce),
    SeedIngredient('Spring onion', IngredientCategory.produce),
    SeedIngredient('Sweet potato', IngredientCategory.produce),
    SeedIngredient('Lettuce', IngredientCategory.produce),
    SeedIngredient('Lemon', IngredientCategory.produce),
    SeedIngredient('Banana', IngredientCategory.produce),
    // protein
    SeedIngredient('Chicken breast', IngredientCategory.protein),
    SeedIngredient('Turkey mince', IngredientCategory.protein),
    SeedIngredient('Beef mince', IngredientCategory.protein),
    SeedIngredient('Beef burger patties', IngredientCategory.protein),
    SeedIngredient('Salmon fillets', IngredientCategory.protein),
    SeedIngredient('Eggs', IngredientCategory.protein),
    // pantry
    SeedIngredient('Spaghetti', IngredientCategory.pantry),
    SeedIngredient('Penne pasta', IngredientCategory.pantry),
    SeedIngredient('Long grain rice', IngredientCategory.pantry),
    SeedIngredient('Chopped tomatoes', IngredientCategory.pantry),
    SeedIngredient('Tomato puree', IngredientCategory.pantry),
    SeedIngredient('Olive oil', IngredientCategory.pantry),
    SeedIngredient('Sea salt', IngredientCategory.pantry),
    SeedIngredient('Soy sauce', IngredientCategory.pantry),
    SeedIngredient('Plain flour', IngredientCategory.pantry),
    SeedIngredient('Burger buns', IngredientCategory.pantry),
    SeedIngredient('Ciabatta rolls', IngredientCategory.pantry),
    // chilled
    SeedIngredient('Cheddar', IngredientCategory.chilled),
    SeedIngredient('Mozzarella', IngredientCategory.chilled),
    SeedIngredient('Butter', IngredientCategory.chilled),
    SeedIngredient('Milk', IngredientCategory.chilled),
    SeedIngredient('Pesto', IngredientCategory.chilled),
    // frozen
    SeedIngredient('Frozen peas', IngredientCategory.frozen),
    SeedIngredient('Frozen sweetcorn', IngredientCategory.frozen),
    // household
    SeedIngredient('Foil trays', IngredientCategory.household),
    SeedIngredient('Freezer bags', IngredientCategory.household),
    // specialist
    SeedIngredient('Jollof spice blend', IngredientCategory.specialist),
    SeedIngredient('Scotch bonnet', IngredientCategory.specialist),
  ];

  static const List<SeedFamily> families = [
    SeedFamily('Lou Lou Spaghetti', MealType.dinner, [
      SeedVariant(
        'Lou Lou Spaghetti + Chicken',
        protein: 'Chicken',
        estimatedMinutes: 45,
        lines: [
          SeedRecipeLine('Spaghetti', quantity: 500, unit: 'g'),
          // Shared with Fried Rice + Chicken in the same unit: merges.
          SeedRecipeLine('Chicken breast', quantity: 500, unit: 'g'),
          SeedRecipeLine('Chopped tomatoes', quantity: 2, unit: 'tin'),
          SeedRecipeLine('Tomato puree', quantity: 2, unit: 'tbsp'),
          SeedRecipeLine('Onion', quantity: 1, unit: 'unit'),
          SeedRecipeLine('Garlic', quantity: 3, unit: 'clove'),
          // Nobody measures the oil. Leave it unknown.
          SeedRecipeLine('Olive oil'),
          SeedRecipeLine('Sea salt'),
          SeedRecipeLine('Foil trays', quantity: 4, unit: 'unit'),
        ],
      ),
      SeedVariant(
        'Lou Lou Spaghetti + Turkey',
        protein: 'Turkey',
        estimatedMinutes: 45,
        lines: [
          SeedRecipeLine('Spaghetti', quantity: 500, unit: 'g'),
          SeedRecipeLine('Turkey mince', quantity: 500, unit: 'g'),
          SeedRecipeLine('Chopped tomatoes', quantity: 2, unit: 'tin'),
          SeedRecipeLine('Onion', quantity: 1, unit: 'unit'),
          SeedRecipeLine('Garlic', quantity: 3, unit: 'clove'),
          SeedRecipeLine('Olive oil'),
          SeedRecipeLine('Foil trays', quantity: 4, unit: 'unit'),
        ],
      ),
    ]),
    SeedFamily('Fried Rice', MealType.dinner, [
      SeedVariant(
        'Fried Rice + Chicken',
        protein: 'Chicken',
        estimatedMinutes: 50,
        lines: [
          SeedRecipeLine('Long grain rice', quantity: 400, unit: 'g'),
          SeedRecipeLine('Chicken breast', quantity: 750, unit: 'g'),
          SeedRecipeLine('Frozen peas', quantity: 200, unit: 'g'),
          SeedRecipeLine('Frozen sweetcorn', quantity: 200, unit: 'g'),
          SeedRecipeLine('Eggs', quantity: 3, unit: 'unit'),
          SeedRecipeLine('Spring onion', quantity: 1, unit: 'bunch'),
          SeedRecipeLine('Soy sauce', quantity: 4, unit: 'tbsp'),
          SeedRecipeLine('Olive oil'),
          SeedRecipeLine('Freezer bags', quantity: 1, unit: 'pack'),
        ],
      ),
    ]),
    SeedFamily('Jollof Rice', MealType.dinner, [
      SeedVariant(
        'Jollof Rice + Turkey',
        protein: 'Turkey',
        estimatedMinutes: 60,
        lines: [
          SeedRecipeLine('Long grain rice', quantity: 500, unit: 'g'),
          SeedRecipeLine('Turkey mince', quantity: 600, unit: 'g'),
          SeedRecipeLine('Jollof spice blend', quantity: 2, unit: 'tbsp'),
          SeedRecipeLine('Scotch bonnet', quantity: 1, unit: 'unit'),
          SeedRecipeLine('Red pepper', quantity: 2, unit: 'unit'),
          // Counted here, weighed in Paninis: these must not merge.
          SeedRecipeLine('Tomatoes', quantity: 4, unit: 'unit'),
          SeedRecipeLine('Onion', quantity: 2, unit: 'unit'),
          SeedRecipeLine('Tomato puree', quantity: 3, unit: 'tbsp'),
          SeedRecipeLine('Olive oil'),
          SeedRecipeLine('Foil trays', quantity: 4, unit: 'unit'),
        ],
      ),
    ]),
    SeedFamily('Burger', MealType.dinner, [
      SeedVariant(
        'Burger + Sweet Potato',
        protein: 'Beef',
        estimatedMinutes: 40,
        lines: [
          SeedRecipeLine('Beef burger patties', quantity: 4, unit: 'unit'),
          SeedRecipeLine('Burger buns', quantity: 4, unit: 'unit'),
          SeedRecipeLine('Sweet potato', quantity: 800, unit: 'g'),
          SeedRecipeLine('Cheddar', quantity: 100, unit: 'g'),
          SeedRecipeLine('Lettuce', quantity: 1, unit: 'unit'),
          SeedRecipeLine('Olive oil'),
          SeedRecipeLine('Sea salt'),
        ],
      ),
    ]),
    SeedFamily('Fish', MealType.dinner, [
      SeedVariant(
        'Fish + Rice',
        protein: 'Salmon',
        estimatedMinutes: 35,
        lines: [
          SeedRecipeLine('Salmon fillets', quantity: 4, unit: 'unit'),
          SeedRecipeLine('Long grain rice', quantity: 300, unit: 'g'),
          SeedRecipeLine('Frozen peas', quantity: 200, unit: 'g'),
          SeedRecipeLine('Lemon', quantity: 1, unit: 'unit'),
          SeedRecipeLine('Butter', quantity: 30, unit: 'g'),
          SeedRecipeLine('Sea salt'),
        ],
      ),
    ]),
    SeedFamily('Pasta', MealType.dinner, [
      SeedVariant(
        'Pasta + Mince',
        protein: 'Beef',
        estimatedMinutes: 40,
        lines: [
          SeedRecipeLine('Penne pasta', quantity: 500, unit: 'g'),
          SeedRecipeLine('Beef mince', quantity: 500, unit: 'g'),
          SeedRecipeLine('Chopped tomatoes', quantity: 2, unit: 'tin'),
          SeedRecipeLine('Onion', quantity: 1, unit: 'unit'),
          SeedRecipeLine('Garlic', quantity: 2, unit: 'clove'),
          SeedRecipeLine('Cheddar', quantity: 150, unit: 'g'),
          SeedRecipeLine('Olive oil'),
          SeedRecipeLine('Foil trays', quantity: 4, unit: 'unit'),
        ],
      ),
    ]),
    SeedFamily('Breakfast Muffins', MealType.breakfast, [
      SeedVariant(
        'Breakfast Muffins',
        estimatedMinutes: 30,
        lines: [
          SeedRecipeLine('Plain flour', quantity: 300, unit: 'g'),
          SeedRecipeLine('Eggs', quantity: 3, unit: 'unit'),
          SeedRecipeLine('Milk', quantity: 250, unit: 'ml'),
          SeedRecipeLine('Butter', quantity: 100, unit: 'g'),
          SeedRecipeLine('Banana', quantity: 3, unit: 'unit'),
          SeedRecipeLine('Sea salt'),
        ],
      ),
    ]),
    SeedFamily('Paninis', MealType.lunch, [
      SeedVariant(
        'Paninis',
        estimatedMinutes: 25,
        lines: [
          SeedRecipeLine('Ciabatta rolls', quantity: 4, unit: 'unit'),
          SeedRecipeLine('Mozzarella', quantity: 200, unit: 'g'),
          // Weighed here, counted in Jollof Rice: these must not merge.
          SeedRecipeLine('Tomatoes', quantity: 250, unit: 'g'),
          SeedRecipeLine('Pesto', quantity: 3, unit: 'tbsp'),
          SeedRecipeLine('Olive oil'),
        ],
      ),
    ]),
  ];
}
