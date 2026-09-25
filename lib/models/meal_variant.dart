import '../utils/date_utils.dart';

/// A version of a [MealFamily], such as "Lou Lou Spaghetti + Chicken".
class MealVariant {
  const MealVariant({
    required this.id,
    required this.mealFamilyId,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    this.protein,
    this.estimatedMinutes,
    this.lastPlannedAt,
    this.timesPlanned = 0,
    this.archivedAt,
  });

  factory MealVariant.fromMap(Map<String, Object?> map) => MealVariant(
    id: map['id']! as String,
    mealFamilyId: map['meal_family_id']! as String,
    name: map['name']! as String,
    protein: map['protein'] as String?,
    estimatedMinutes: (map['estimated_minutes'] as num?)?.toInt(),
    lastPlannedAt: PrepDates.fromIsoOrNull(map['last_planned_at']),
    timesPlanned: (map['times_planned']! as num).toInt(),
    createdAt: PrepDates.fromIso(map['created_at']! as String),
    updatedAt: PrepDates.fromIso(map['updated_at']! as String),
    archivedAt: PrepDates.fromIsoOrNull(map['archived_at']),
  );

  final String id;
  final String mealFamilyId;
  final String name;
  final String? protein;
  final int? estimatedMinutes;
  final DateTime? lastPlannedAt;
  final int timesPlanned;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Set when the meal has been archived. Archived meals are hidden from the
  /// library and never planned, but stay in the database so confirmed plans
  /// that reference them remain intact.
  final DateTime? archivedAt;

  bool get isArchived => archivedAt != null;

  Map<String, Object?> toMap() => {
    'id': id,
    'meal_family_id': mealFamilyId,
    'name': name,
    'protein': protein,
    'estimated_minutes': estimatedMinutes,
    'last_planned_at': PrepDates.toIsoOrNull(lastPlannedAt),
    'times_planned': timesPlanned,
    'created_at': PrepDates.toIso(createdAt),
    'updated_at': PrepDates.toIso(updatedAt),
    'archived_at': PrepDates.toIsoOrNull(archivedAt),
  };

  MealVariant copyWith({
    String? name,
    String? protein,
    int? estimatedMinutes,
    DateTime? lastPlannedAt,
    int? timesPlanned,
    DateTime? updatedAt,
    DateTime? archivedAt,
  }) => MealVariant(
    id: id,
    mealFamilyId: mealFamilyId,
    name: name ?? this.name,
    protein: protein ?? this.protein,
    estimatedMinutes: estimatedMinutes ?? this.estimatedMinutes,
    lastPlannedAt: lastPlannedAt ?? this.lastPlannedAt,
    timesPlanned: timesPlanned ?? this.timesPlanned,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    archivedAt: archivedAt ?? this.archivedAt,
  );
}
