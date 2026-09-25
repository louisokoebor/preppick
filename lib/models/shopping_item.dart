import 'ingredient.dart';

/// One line on a week's shopping list.
///
/// [ingredientId] is null for items the household typed in themselves.
/// [quantity] stays null when no quantity is known — PrepPick never invents one.
class ShoppingItem {
  const ShoppingItem({
    required this.id,
    required this.weeklyPlanId,
    required this.name,
    required this.category,
    this.ingredientId,
    this.quantity,
    this.unit,
    this.isChecked = false,
    this.isManual = false,
  });

  factory ShoppingItem.fromMap(Map<String, Object?> map) => ShoppingItem(
    id: map['id']! as String,
    weeklyPlanId: map['weekly_plan_id']! as String,
    ingredientId: map['ingredient_id'] as String?,
    name: map['name']! as String,
    quantity: (map['quantity'] as num?)?.toDouble(),
    unit: map['unit'] as String?,
    category: map['category']! as String,
    isChecked: _bool(map['is_checked']),
    isManual: _bool(map['is_manual']),
  );

  /// SQLite stores booleans as 0/1 integers.
  static bool _bool(Object? value) => (value! as num).toInt() != 0;

  final String id;
  final String weeklyPlanId;
  final String? ingredientId;
  final String name;
  final double? quantity;
  final String? unit;
  final String category;
  final bool isChecked;
  final bool isManual;

  Map<String, Object?> toMap() => {
    'id': id,
    'weekly_plan_id': weeklyPlanId,
    'ingredient_id': ingredientId,
    'name': name,
    'quantity': quantity,
    'unit': unit,
    'category': category,
    'is_checked': isChecked ? 1 : 0,
    'is_manual': isManual ? 1 : 0,
  };

  ShoppingItem copyWith({
    String? name,
    double? quantity,
    String? unit,
    String? category,
    bool? isChecked,
  }) => ShoppingItem(
    id: id,
    weeklyPlanId: weeklyPlanId,
    ingredientId: ingredientId,
    name: name ?? this.name,
    quantity: quantity ?? this.quantity,
    unit: unit ?? this.unit,
    category: category ?? this.category,
    isChecked: isChecked ?? this.isChecked,
    isManual: isManual,
  );

  /// Category fallback used when an ingredient has never been categorised.
  static String categoryOr(String? category) =>
      category ?? IngredientCategory.other;
}
