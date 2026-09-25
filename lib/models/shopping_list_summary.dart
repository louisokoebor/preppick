import 'weekly_plan.dart';

/// One previous week's shopping list, reduced to what a history card shows.
///
/// Counts are read from the saved lines, not recomputed from the plan's
/// recipes: a past list is a record of what was bought that week, and a
/// recipe edited since must not rewrite it.
class ShoppingListSummary {
  const ShoppingListSummary({
    required this.plan,
    required this.itemCount,
    required this.checkedCount,
  });

  /// Reads a `weekly_plans` row carrying the aggregate columns
  /// `item_count` and `checked_count`.
  factory ShoppingListSummary.fromMap(Map<String, Object?> map) =>
      ShoppingListSummary(
        plan: WeeklyPlan.fromMap(map),
        itemCount: (map['item_count']! as num).toInt(),
        checkedCount: ((map['checked_count'] as num?) ?? 0).toInt(),
      );

  final WeeklyPlan plan;

  /// Every saved line, generated and manual.
  final int itemCount;

  /// Lines that were ticked off.
  final int checkedCount;

  DateTime get weekStart => plan.weekStart;
}
