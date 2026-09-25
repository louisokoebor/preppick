import 'ingredient.dart';
import 'meal_ingredient.dart';

/// One line of a meal's recipe: the link row plus the ingredient it points at.
///
/// [MealIngredient] alone carries only ids, which no screen can render, and
/// [Ingredient] alone has no quantity. Every read of a meal's recipe needs
/// both, so they travel together rather than leaving each caller to join them.
class MealRecipeLine {
  const MealRecipeLine({required this.line, required this.ingredient});

  final MealIngredient line;
  final Ingredient ingredient;

  String get id => line.id;
  String get name => ingredient.name;
  String? get category => ingredient.category;

  /// Null whenever the household has never recorded an amount. PrepPick never
  /// invents one.
  double? get quantity => line.quantity;
  String? get unit => line.unit;
  int? get baseServings => line.baseServings;

  /// True when there is a number to show or add up.
  bool get hasQuantity => line.quantity != null;

  @override
  bool operator ==(Object other) =>
      other is MealRecipeLine &&
      other.line.id == line.id &&
      other.ingredient.id == ingredient.id;

  @override
  int get hashCode => Object.hash(line.id, ingredient.id);

  @override
  String toString() =>
      'MealRecipeLine(${ingredient.name}'
      '${line.quantity == null ? '' : ' ${line.quantity} ${line.unit ?? ''}'})';
}
