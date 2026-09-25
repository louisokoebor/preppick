/// Links a meal variant to one ingredient.
///
/// [quantity] stays null when the household has never recorded one. PrepPick
/// never invents a missing quantity.
class MealIngredient {
  const MealIngredient({
    required this.id,
    required this.mealVariantId,
    required this.ingredientId,
    this.quantity,
    this.unit,
    this.baseServings,
  });

  factory MealIngredient.fromMap(Map<String, Object?> map) => MealIngredient(
    id: map['id']! as String,
    mealVariantId: map['meal_variant_id']! as String,
    ingredientId: map['ingredient_id']! as String,
    quantity: (map['quantity'] as num?)?.toDouble(),
    unit: map['unit'] as String?,
    baseServings: (map['base_servings'] as num?)?.toInt(),
  );

  final String id;
  final String mealVariantId;
  final String ingredientId;
  final double? quantity;
  final String? unit;
  final int? baseServings;

  Map<String, Object?> toMap() => {
    'id': id,
    'meal_variant_id': mealVariantId,
    'ingredient_id': ingredientId,
    'quantity': quantity,
    'unit': unit,
    'base_servings': baseServings,
  };

  MealIngredient copyWith({
    double? quantity,
    String? unit,
    int? baseServings,
  }) => MealIngredient(
    id: id,
    mealVariantId: mealVariantId,
    ingredientId: ingredientId,
    quantity: quantity ?? this.quantity,
    unit: unit ?? this.unit,
    baseServings: baseServings ?? this.baseServings,
  );
}
