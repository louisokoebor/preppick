import '../utils/date_utils.dart';

/// Shopping categories PrepPick groups ingredients by.
class IngredientCategory {
  const IngredientCategory._();

  static const String produce = 'produce';
  static const String protein = 'protein';
  static const String pantry = 'pantry';
  static const String chilled = 'chilled';
  static const String frozen = 'frozen';
  static const String household = 'household';
  static const String specialist = 'specialist';
  static const String other = 'other';

  static const List<String> all = [
    produce,
    protein,
    pantry,
    chilled,
    frozen,
    household,
    specialist,
    other,
  ];
}

/// A single shoppable ingredient.
class Ingredient {
  /// Collapses a name to the key two meals must agree on to be treated as
  /// the same ingredient: trimmed, lowercased, inner runs of whitespace
  /// reduced to one space.
  ///
  /// This is deliberately shallow. It catches the cases that actually occur
  /// when a household types the same thing twice — `"Chicken breast "`,
  /// `"chicken breast"`, `"Chicken  breast"` — and nothing more. Plurals,
  /// synonyms and spelling slips are left alone: merging "tomato" with
  /// "tomatoes" would be a guess, and a wrong guess silently corrupts a
  /// shopping list. Fuzzy matching belongs in the import review flow, where a
  /// person can confirm it.
  static String normaliseName(String name) =>
      name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  const Ingredient({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    this.category,
  });

  factory Ingredient.fromMap(Map<String, Object?> map) => Ingredient(
    id: map['id']! as String,
    name: map['name']! as String,
    category: map['category'] as String?,
    createdAt: PrepDates.fromIso(map['created_at']! as String),
    updatedAt: PrepDates.fromIso(map['updated_at']! as String),
  );

  final String id;
  final String name;
  final String? category;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, Object?> toMap() => {
    'id': id,
    'name': name,
    'category': category,
    'created_at': PrepDates.toIso(createdAt),
    'updated_at': PrepDates.toIso(updatedAt),
  };

  Ingredient copyWith({String? name, String? category, DateTime? updatedAt}) =>
      Ingredient(
        id: id,
        name: name ?? this.name,
        category: category ?? this.category,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}
