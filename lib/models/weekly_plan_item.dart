import '../utils/date_utils.dart';
import 'meal_family.dart';

/// When a planned meal will be cooked for this specific week.
///
/// Persisted as a stable string, never as an enum index.
enum PrepTiming {
  mainPrep('mainPrep'),
  later('later');

  const PrepTiming(this.value);

  /// Stable value written to SQLite.
  final String value;

  static PrepTiming fromValue(String? value) => PrepTiming.values.firstWhere(
    (timing) => timing.value == value,
    orElse: () => PrepTiming.mainPrep,
  );
}

/// Identifies one slot in a week's plan.
///
/// Slots are a meal type plus a zero-based index rather than a fixed
/// `dinner1`/`dinner2` enum, so the meal-count screen can stay configurable.
class MealSlot implements Comparable<MealSlot> {
  const MealSlot(this.mealType, this.slotIndex)
    : assert(slotIndex >= 0, 'slotIndex must not be negative');

  /// Parses the stable persisted form, e.g. `dinner:1`.
  factory MealSlot.fromKey(String key) {
    final parts = key.split(':');
    if (parts.length != 2) {
      throw ArgumentError.value(key, 'key', 'Malformed MealSlot key');
    }
    final index = int.tryParse(parts[1]);
    if (index == null) {
      throw ArgumentError.value(key, 'key', 'Malformed MealSlot index');
    }
    return MealSlot(MealType.fromValue(parts[0]), index);
  }

  final MealType mealType;

  /// Zero-based position among the slots of this meal type.
  final int slotIndex;

  /// Stable string form used for persistence and comparisons.
  String get key => '${mealType.value}:$slotIndex';

  /// Display label, numbered only when the week has more than one such slot.
  String label({int totalOfType = 1}) {
    final name = switch (mealType) {
      MealType.breakfast => 'Breakfast',
      MealType.lunch => 'Lunch',
      MealType.dinner => 'Dinner',
    };
    return totalOfType > 1 ? '$name ${slotIndex + 1}' : name;
  }

  @override
  int compareTo(MealSlot other) {
    final byType = mealType.index.compareTo(other.mealType.index);
    return byType != 0 ? byType : slotIndex.compareTo(other.slotIndex);
  }

  @override
  bool operator ==(Object other) =>
      other is MealSlot &&
      other.mealType == mealType &&
      other.slotIndex == slotIndex;

  @override
  int get hashCode => Object.hash(mealType, slotIndex);

  @override
  String toString() => 'MealSlot($key)';
}

/// One meal placed into one slot of a weekly plan.
class WeeklyPlanItem {
  const WeeklyPlanItem({
    required this.id,
    required this.weeklyPlanId,
    required this.mealVariantId,
    required this.mealType,
    required this.slotIndex,
    this.prepTiming = PrepTiming.mainPrep,
    this.plannedCookDate,
  });

  factory WeeklyPlanItem.fromMap(Map<String, Object?> map) => WeeklyPlanItem(
    id: map['id']! as String,
    weeklyPlanId: map['weekly_plan_id']! as String,
    mealVariantId: map['meal_variant_id']! as String,
    mealType: MealType.fromValue(map['meal_type']! as String),
    slotIndex: (map['slot_index']! as num).toInt(),
    prepTiming: PrepTiming.fromValue(map['prep_timing'] as String?),
    plannedCookDate: PrepDates.fromIsoOrNull(map['planned_cook_date']),
  );

  final String id;
  final String weeklyPlanId;
  final String mealVariantId;
  final MealType mealType;
  final int slotIndex;
  final PrepTiming prepTiming;
  final DateTime? plannedCookDate;

  /// The slot this item occupies.
  MealSlot get slot => MealSlot(mealType, slotIndex);

  Map<String, Object?> toMap() => {
    'id': id,
    'weekly_plan_id': weeklyPlanId,
    'meal_variant_id': mealVariantId,
    'meal_type': mealType.value,
    'slot_index': slotIndex,
    'prep_timing': prepTiming.value,
    'planned_cook_date': PrepDates.toIsoOrNull(plannedCookDate),
  };

  /// Replaces the meal in this slot, leaving every other slot untouched.
  WeeklyPlanItem copyWith({
    String? mealVariantId,
    PrepTiming? prepTiming,
    DateTime? plannedCookDate,
    bool clearPlannedCookDate = false,
  }) => WeeklyPlanItem(
    id: id,
    weeklyPlanId: weeklyPlanId,
    mealVariantId: mealVariantId ?? this.mealVariantId,
    mealType: mealType,
    slotIndex: slotIndex,
    prepTiming: prepTiming ?? this.prepTiming,
    plannedCookDate: clearPlannedCookDate
        ? null
        : (plannedCookDate ?? this.plannedCookDate),
  );
}
