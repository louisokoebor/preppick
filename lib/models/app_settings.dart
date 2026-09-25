import 'meal_family.dart';

/// How many meal-prep batches the household wants this week.
///
/// Stored in the key/value `settings` table rather than a row of its own.
///
/// ## Allowed range
///
/// Each count is constrained to [minCount]..[maxCount] (0..7). Zero is a
/// legitimate answer — a household that never preps breakfast should be able
/// to say so — and seven is one batch per day, which is the most a single
/// week can absorb. The ceiling is a V1 product decision, not a storage
/// limit: it keeps the generated plan and the shopping list readable, and it
/// keeps the planner from being asked for more distinct meals than a small
/// library can supply. Raise it here, in one place, if that changes.
///
/// Out-of-range values are clamped rather than rejected, consistently in
/// every direction: [clampCount] is applied when a value is constructed via
/// [fromMap] or [copyWith], so a value written by an older build, a manual
/// database edit, or a future screen can never put the app into a state the
/// UI cannot represent.
class AppSettings {
  const AppSettings({
    this.breakfastCount = 1,
    this.lunchCount = 1,
    this.dinnerCount = 2,
  });

  /// Reads a stored map, falling back to the matching default for any key
  /// that is missing or unreadable and clamping the rest.
  factory AppSettings.fromMap(Map<String, Object?> map) => AppSettings(
    breakfastCount: _count(map['breakfast_count'], defaults.breakfastCount),
    lunchCount: _count(map['lunch_count'], defaults.lunchCount),
    dinnerCount: _count(map['dinner_count'], defaults.dinnerCount),
  );

  static int _count(Object? value, int fallback) => clampCount(switch (value) {
    null => fallback,
    final num n => n.toInt(),
    final String s => int.tryParse(s) ?? fallback,
    _ => fallback,
  });

  /// Smallest count a category may hold. Zero means "we don't prep this".
  static const int minCount = 0;

  /// Largest count a category may hold in V1 — one batch per day.
  static const int maxCount = 7;

  /// Brings any integer into [minCount]..[maxCount].
  static int clampCount(int value) => value.clamp(minCount, maxCount);

  /// First-run counts: breakfast is optional but on by default, one lunch,
  /// two dinners.
  static const AppSettings defaults = AppSettings();

  final int breakfastCount;
  final int lunchCount;
  final int dinnerCount;

  int get totalMeals => breakfastCount + lunchCount + dinnerCount;

  /// True when every category is zero. A plan cannot be generated from this;
  /// the UI explains that rather than letting the planner run empty.
  bool get isEmpty => totalMeals == 0;

  /// The count for a single category.
  int countFor(MealType type) => switch (type) {
    MealType.breakfast => breakfastCount,
    MealType.lunch => lunchCount,
    MealType.dinner => dinnerCount,
  };

  /// This settings object with one category replaced, clamped to range.
  AppSettings withCount(MealType type, int value) => switch (type) {
    MealType.breakfast => copyWith(breakfastCount: value),
    MealType.lunch => copyWith(lunchCount: value),
    MealType.dinner => copyWith(dinnerCount: value),
  };

  Map<String, Object?> toMap() => {
    'breakfast_count': breakfastCount,
    'lunch_count': lunchCount,
    'dinner_count': dinnerCount,
  };

  AppSettings copyWith({
    int? breakfastCount,
    int? lunchCount,
    int? dinnerCount,
  }) => AppSettings(
    breakfastCount: clampCount(breakfastCount ?? this.breakfastCount),
    lunchCount: clampCount(lunchCount ?? this.lunchCount),
    dinnerCount: clampCount(dinnerCount ?? this.dinnerCount),
  );

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.breakfastCount == breakfastCount &&
      other.lunchCount == lunchCount &&
      other.dinnerCount == dinnerCount;

  @override
  int get hashCode => Object.hash(breakfastCount, lunchCount, dinnerCount);

  @override
  String toString() =>
      'AppSettings(breakfast: $breakfastCount, lunch: $lunchCount, '
      'dinner: $dinnerCount)';
}
