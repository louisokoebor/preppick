/// Named routes for PrepPick.
///
/// Screens are registered here as they are built. The Swap Meal interaction is
/// a modal bottom sheet and deliberately has no route.
class AppRoutes {
  const AppRoutes._();

  static const startup = '/';

  /// Select Meal Count — first step of the weekly workflow.
  static const selectMealCount = '/select-meal-count';

  /// Plan This Week — the empty week, ready to generate.
  static const plan = '/plan';

  /// Generated Plan — the week PrepPick chose, before confirmation.
  static const generatedPlan = '/generated-plan';

  /// Shopping List — built from a confirmed plan, and where Generated Plan
  /// lands the moment a plan is confirmed.
  static const shoppingList = '/shopping';

  /// Past Shopping Lists — previous weeks' saved lists, opened from the
  /// history icon on the Shopping List.
  static const shoppingHistory = '/shopping/history';

  /// One previous week's list, read-only, with the plan id as a route
  /// argument.
  static const shoppingHistoryWeek = '/shopping/history/week';

  /// Plan History — confirmed weeks, newest first.
  static const planHistory = '/history';

  /// Meal Library — where a household fixes a "not enough meals" shortage.
  static const mealLibrary = '/meals';

  /// Import History — pasted meal history before review.
  static const importHistory = '/import';

  /// Review Import — parsed candidates before saving to the meal library.
  static const reviewImport = '/import/review';

  /// Meal Detail — one meal, opened from the library with the variant id as a
  /// route argument. Deep links use [mealDetailPath].
  static const mealDetail = '/meal';

  /// Deep-link path for Meal Detail.
  static String mealDetailPath(String id) => '/meal/${Uri.encodeComponent(id)}';

  /// Add Meal — a new meal for the library.
  static const addMeal = '/meals/add';

  /// Edit Meal — updates an existing variant in place.
  static const editMeal = '/meals/edit';
}
