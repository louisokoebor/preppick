import '../utils/date_utils.dart';

/// The kind of meal a family belongs to.
///
/// Persisted as a stable string, never as an enum index.
enum MealType {
  breakfast('breakfast'),
  lunch('lunch'),
  dinner('dinner');

  const MealType(this.value);

  /// Stable value written to SQLite.
  final String value;

  static MealType fromValue(String value) => MealType.values.firstWhere(
    (type) => type.value == value,
    orElse: () => throw ArgumentError.value(value, 'value', 'Unknown MealType'),
  );
}

/// A core meal concept, such as "Lou Lou Spaghetti" or "Fried Rice".
class MealFamily {
  const MealFamily({
    required this.id,
    required this.name,
    required this.mealType,
    required this.createdAt,
    required this.updatedAt,
    this.archivedAt,
  });

  factory MealFamily.fromMap(Map<String, Object?> map) => MealFamily(
    id: map['id']! as String,
    name: map['name']! as String,
    mealType: MealType.fromValue(map['meal_type']! as String),
    createdAt: PrepDates.fromIso(map['created_at']! as String),
    updatedAt: PrepDates.fromIso(map['updated_at']! as String),
    archivedAt: PrepDates.fromIsoOrNull(map['archived_at']),
  );

  final String id;
  final String name;
  final MealType mealType;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Set when the family has been archived. Archived families stay in the
  /// database so confirmed plans that reference them remain intact.
  final DateTime? archivedAt;

  bool get isArchived => archivedAt != null;

  Map<String, Object?> toMap() => {
    'id': id,
    'name': name,
    'meal_type': mealType.value,
    'created_at': PrepDates.toIso(createdAt),
    'updated_at': PrepDates.toIso(updatedAt),
    'archived_at': PrepDates.toIsoOrNull(archivedAt),
  };

  MealFamily copyWith({
    String? name,
    MealType? mealType,
    DateTime? updatedAt,
    DateTime? archivedAt,
  }) => MealFamily(
    id: id,
    name: name ?? this.name,
    mealType: mealType ?? this.mealType,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    archivedAt: archivedAt ?? this.archivedAt,
  );
}
