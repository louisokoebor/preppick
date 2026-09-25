import 'package:flutter/foundation.dart';

import '../models/models.dart';
import '../services/meal_service.dart';

/// Owns the meal-library state: the meals, their families, and whether a load
/// is in flight or has failed.
///
/// Families are loaded alongside the meals and kept in [familyById] because
/// almost every meal view needs its family's meal type, and looking that up
/// per card would mean one query per row.
class MealProvider extends ChangeNotifier {
  MealProvider(this._service);

  final MealService _service;

  List<MealVariant> _meals = const [];
  Map<String, MealFamily> _familyById = const {};
  bool _isLoading = false;
  bool _hasLoaded = false;
  bool _isDisposed = false;
  Object? _error;

  /// Active meals, ordered by name.
  List<MealVariant> get meals => _meals;

  /// Families of the loaded meals, keyed by id.
  Map<String, MealFamily> get familyById => _familyById;

  /// True while [load] is in flight.
  bool get isLoading => _isLoading;

  /// True once a load has completed, successfully or not.
  bool get hasLoaded => _hasLoaded;

  /// The last load failure, or null. Cleared when a load succeeds.
  Object? get error => _error;

  /// True when a load failed and the screen has nothing to show.
  bool get hasError => error != null;

  /// True when the library loaded cleanly but holds no meals — an empty
  /// library, not a failure. The two need different screens.
  bool get isEmpty => hasLoaded && !hasError && meals.isEmpty;

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }

  /// Notifies unless this provider is gone, so a load that finishes after the
  /// screen is closed cannot throw on the way out.
  void _safeNotify() {
    if (_isDisposed) return;
    notifyListeners();
  }

  /// The family a meal belongs to, or null if it was not loaded.
  MealFamily? familyOf(MealVariant meal) => familyById[meal.mealFamilyId];

  /// The meal type of a meal, via its family.
  MealType? typeOf(MealVariant meal) => familyOf(meal)?.mealType;

  /// Loads the joined data used by Meal Detail and Meal Edit.
  Future<MealDetail?> getDetail(String mealVariantId) async {
    final meal = await _service.getMealVariant(mealVariantId);
    if (meal == null) return null;
    final family = await _service.getMealFamily(meal.mealFamilyId);
    if (family == null) return null;
    final ingredients = await _service.getIngredientsForMeal(meal.id);
    return MealDetail(meal: meal, family: family, ingredients: ingredients);
  }

  /// Loaded meals of one type.
  ///
  /// Filters what is already in memory rather than re-querying, so switching a
  /// filter chip does not hit the database.
  List<MealVariant> mealsOfType(MealType type) =>
      meals.where((meal) => typeOf(meal) == type).toList();

  /// Loads the compact library index, including reviewed import aliases.
  Future<List<ImportLibraryEntry>> getImportLibraryEntries() =>
      _service.getImportLibraryEntries();

  /// Loads the library. Concurrent calls collapse into the one already
  /// running.
  Future<void> load() async {
    if (_isLoading) return;
    _isLoading = true;
    _error = null;
    _safeNotify();

    try {
      final meals = await _service.getAllMealVariants();
      final families = await _service.getAllMealFamilies(
        // A meal is only active when its family is too, but loading archived
        // families as well means a meal can always resolve its own family.
        includeArchived: true,
      );
      _meals = meals;
      _familyById = {for (final family in families) family.id: family};
    } catch (error) {
      // Leave the last good list in place: a failed refresh should not blank
      // a library the household was reading.
      _error = error;
    } finally {
      _isLoading = false;
      _hasLoaded = true;
      _safeNotify();
    }
  }

  /// Reloads after a change made elsewhere.
  Future<void> refresh() async {
    _hasLoaded = false;
    await load();
  }

  /// Adds a meal and reloads.
  Future<MealVariant> addMeal({
    required String familyName,
    required MealType mealType,
    String? variantName,
    String? protein,
    int? estimatedMinutes,
  }) async {
    final meal = await _service.addMeal(
      familyName: familyName,
      mealType: mealType,
      variantName: variantName,
      protein: protein,
      estimatedMinutes: estimatedMinutes,
    );
    await refresh();
    return meal;
  }

  /// Saves a new or existing meal and its complete recipe, then refreshes the
  /// library so callers see the saved meal immediately.
  Future<MealVariant> saveMeal({
    String? mealVariantId,
    required String familyName,
    required MealType mealType,
    String? variantName,
    String? protein,
    int? estimatedMinutes,
    required List<MealIngredientDraft> ingredients,
  }) async {
    final meal = await _service.saveMeal(
      mealVariantId: mealVariantId,
      familyName: familyName,
      mealType: mealType,
      variantName: variantName,
      protein: protein,
      estimatedMinutes: estimatedMinutes,
      ingredients: ingredients,
    );
    await refresh();
    return meal;
  }

  /// Renames a meal or changes its protein, then reloads.
  Future<MealVariant> updateMeal(
    String id, {
    String? name,
    String? protein,
    bool clearProtein = false,
    int? estimatedMinutes,
    bool clearEstimatedMinutes = false,
    String? familyName,
    MealType? mealType,
    List<MealIngredientDraft>? ingredients,
  }) async {
    final meal = familyName != null || mealType != null || ingredients != null
        ? await _updateCompleteMeal(
            id,
            name: name,
            protein: protein,
            clearProtein: clearProtein,
            estimatedMinutes: estimatedMinutes,
            clearEstimatedMinutes: clearEstimatedMinutes,
            familyName: familyName,
            mealType: mealType,
            ingredients: ingredients,
          )
        : await _service.updateMealVariant(
            id,
            name: name,
            protein: protein,
            clearProtein: clearProtein,
            estimatedMinutes: estimatedMinutes,
            clearEstimatedMinutes: clearEstimatedMinutes,
          );
    await refresh();
    return meal;
  }

  Future<MealVariant> _updateCompleteMeal(
    String id, {
    String? name,
    String? protein,
    required bool clearProtein,
    int? estimatedMinutes,
    required bool clearEstimatedMinutes,
    String? familyName,
    MealType? mealType,
    List<MealIngredientDraft>? ingredients,
  }) async {
    final detail = await getDetail(id);
    if (detail == null) {
      throw ArgumentError.value(id, 'id', 'No such meal');
    }
    return _service.saveMeal(
      mealVariantId: id,
      familyName: familyName ?? detail.family.name,
      mealType: mealType ?? detail.family.mealType,
      variantName: name ?? detail.meal.name,
      protein: clearProtein ? null : (protein ?? detail.meal.protein),
      estimatedMinutes: clearEstimatedMinutes
          ? null
          : (estimatedMinutes ?? detail.meal.estimatedMinutes),
      ingredients:
          ingredients ??
          [for (final line in detail.ingredients) draftFromRecipeLine(line)],
    );
  }

  /// Removes a meal from the library, archiving it instead when a plan still
  /// refers to it. Returns which of the two happened.
  Future<MealRemoval> removeMeal(String id) async {
    final outcome = await _service.removeMealVariant(id);
    await refresh();
    return outcome;
  }

  /// A meal's recipe lines. Not cached: only the detail screen needs them.
  Future<List<MealRecipeLine>> ingredientsFor(String mealVariantId) =>
      _service.getIngredientsForMeal(mealVariantId);
}
