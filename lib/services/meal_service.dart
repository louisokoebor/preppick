import 'package:sqflite/sqflite.dart';

import '../models/models.dart';
import '../utils/date_utils.dart';
import '../utils/id_utils.dart';
import 'database_service.dart';

/// Thrown when a meal cannot be hard-deleted because a plan still refers to it.
///
/// This is a normal outcome, not a bug: plan history is deliberately protected
/// by the schema. Callers that just want the meal out of the library should
/// use [MealService.removeMealVariant], which archives in this case.
class MealInUseException implements Exception {
  const MealInUseException(this.mealVariantId, this.planCount);

  final String mealVariantId;

  /// How many plan items still reference the meal.
  final int planCount;

  @override
  String toString() =>
      'MealInUseException: meal $mealVariantId is used by $planCount '
      'plan item(s) and cannot be deleted. Archive it instead.';
}

/// What [MealService.removeMealVariant] actually did.
enum MealRemoval {
  /// The row was deleted outright; no plan referred to it.
  deleted,

  /// The meal was planned at some point, so it was archived to keep that
  /// history readable.
  archived,
}

/// All reads and writes for the meal library.
///
/// Owns every statement that touches `meal_families`, `meal_variants`,
/// `ingredients` and `meal_ingredients`. Providers and widgets never see SQL.
///
/// ## Active versus archived
///
/// Meals are never silently removed. A variant counts as *active* only when
/// neither it nor its family is archived, and every read defaults to active
/// meals only. Archived meals stay in the database so a confirmed plan from
/// three weeks ago still resolves to a real meal name. Pass
/// `includeArchived: true` to see them.
///
/// ## Ingredient identity
///
/// Ingredients are shared rows, not per-meal copies: two meals that both use
/// chicken breast point at the same `ingredients` row, which is what lets the
/// shopping list merge them. [findOrCreateIngredient] is therefore the only
/// way new ingredients are made, and it reuses an existing row whenever the
/// normalised name matches ([Ingredient.normaliseName]).
class MealService {
  MealService(this._databaseService);

  final DatabaseService _databaseService;

  Future<Database> get _db => _databaseService.database;

  // ---------------------------------------------------------------- reads

  /// Every meal in the library, ordered by name.
  Future<List<MealVariant>> getAllMealVariants({
    bool includeArchived = false,
  }) async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT v.* FROM meal_variants v
      JOIN meal_families f ON f.id = v.meal_family_id
      ${includeArchived ? '' : 'WHERE v.archived_at IS NULL '
              'AND f.archived_at IS NULL'}
      ORDER BY v.name COLLATE NOCASE
    ''');
    return rows.map(MealVariant.fromMap).toList();
  }

  /// Meals of one type, ordered by name.
  ///
  /// The type lives on the family, not the variant, so this filters through
  /// the join rather than on a column of `meal_variants`.
  Future<List<MealVariant>> getMealsByType(
    MealType type, {
    bool includeArchived = false,
  }) async {
    final db = await _db;
    final rows = await db.rawQuery(
      '''
      SELECT v.* FROM meal_variants v
      JOIN meal_families f ON f.id = v.meal_family_id
      WHERE f.meal_type = ?
      ${includeArchived ? '' : 'AND v.archived_at IS NULL '
                'AND f.archived_at IS NULL'}
      ORDER BY v.name COLLATE NOCASE
    ''',
      [type.value],
    );
    return rows.map(MealVariant.fromMap).toList();
  }

  /// Every family in the library, ordered by name.
  Future<List<MealFamily>> getAllMealFamilies({
    bool includeArchived = false,
  }) async {
    final db = await _db;
    final rows = await db.query(
      'meal_families',
      where: includeArchived ? null : 'archived_at IS NULL',
      orderBy: 'name COLLATE NOCASE',
    );
    return rows.map(MealFamily.fromMap).toList();
  }

  /// One family, or null when the id is unknown.
  ///
  /// Archived families are returned: a plan item that points at one still has
  /// to render its name.
  Future<MealFamily?> getMealFamily(String id) async {
    final db = await _db;
    final rows = await db.query(
      'meal_families',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : MealFamily.fromMap(rows.first);
  }

  /// One meal, or null when the id is unknown. Archived meals are returned.
  Future<MealVariant?> getMealVariant(String id) async {
    final db = await _db;
    final rows = await db.query(
      'meal_variants',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : MealVariant.fromMap(rows.first);
  }

  /// Every variant belonging to one family, ordered by name.
  Future<List<MealVariant>> getVariantsForFamily(
    String mealFamilyId, {
    bool includeArchived = false,
  }) async {
    final db = await _db;
    final rows = await db.query(
      'meal_variants',
      where: includeArchived
          ? 'meal_family_id = ?'
          : 'meal_family_id = ? AND archived_at IS NULL',
      whereArgs: [mealFamilyId],
      orderBy: 'name COLLATE NOCASE',
    );
    return rows.map(MealVariant.fromMap).toList();
  }

  /// A meal's recipe: every line with the ingredient it points at, ordered by
  /// ingredient name.
  ///
  /// Returns an empty list for a meal with no recorded ingredients, which is a
  /// normal state — a meal can be planned before its recipe is filled in.
  Future<List<MealRecipeLine>> getIngredientsForMeal(
    String mealVariantId,
  ) async {
    final db = await _db;
    final lineRows = await db.query(
      'meal_ingredients',
      where: 'meal_variant_id = ?',
      whereArgs: [mealVariantId],
    );
    if (lineRows.isEmpty) return const [];

    final lines = lineRows.map(MealIngredient.fromMap).toList();
    final ingredients = await _ingredientsByIds(
      db,
      lines.map((line) => line.ingredientId).toSet(),
    );

    final recipe = <MealRecipeLine>[];
    for (final line in lines) {
      final ingredient = ingredients[line.ingredientId];
      // A missing ingredient means a foreign key was bypassed; skipping is
      // better than crashing a screen over one corrupt row.
      if (ingredient == null) continue;
      recipe.add(MealRecipeLine(line: line, ingredient: ingredient));
    }
    recipe.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return recipe;
  }

  /// One ingredient, or null when the id is unknown.
  Future<Ingredient?> getIngredient(String id) async {
    final db = await _db;
    final rows = await db.query(
      'ingredients',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : Ingredient.fromMap(rows.first);
  }

  /// The ingredient whose normalised name matches [name], or null.
  Future<Ingredient?> findIngredientByName(String name) async {
    final db = await _db;
    return _findIngredientByName(db, name);
  }

  /// Updates an ingredient's category without changing its shared identity.
  Future<Ingredient> updateIngredient(
    String id, {
    String? category,
    DateTime? now,
  }) async {
    final db = await _db;
    final existing = await getIngredient(id);
    if (existing == null) {
      throw ArgumentError.value(id, 'id', 'No such ingredient');
    }
    final updated = existing.copyWith(
      category: category?.trim().isEmpty ?? true ? null : category?.trim(),
      updatedAt: now ?? DateTime.now().toUtc(),
    );
    await db.update(
      'ingredients',
      updated.toMap(),
      where: 'id = ?',
      whereArgs: [id],
    );
    return updated;
  }

  // --------------------------------------------------------------- writes

  /// Creates a meal family.
  ///
  /// Reuses an existing family when one already has the same normalised name
  /// *and* the same meal type, so "Fried Rice" typed twice does not become two
  /// families. The same name under a different meal type is a different
  /// family: a household may well have a lunch Paninis and a dinner Paninis.
  Future<MealFamily> createMealFamily({
    required String name,
    required MealType mealType,
    DateTime? now,
  }) async {
    final db = await _db;
    final timestamp = now ?? DateTime.now().toUtc();
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(name, 'name', 'Meal family name is required');
    }

    final existing = await _findFamilyByName(db, trimmed, mealType);
    if (existing != null) return existing;

    final family = MealFamily(
      id: PrepIds.newId(),
      name: trimmed,
      mealType: mealType,
      createdAt: timestamp,
      updatedAt: timestamp,
    );
    await db.insert('meal_families', family.toMap());
    return family;
  }

  /// Creates a meal (a variant of a family).
  Future<MealVariant> createMealVariant({
    required String mealFamilyId,
    required String name,
    String? protein,
    int? estimatedMinutes,
    DateTime? now,
  }) async {
    final db = await _db;
    final timestamp = now ?? DateTime.now().toUtc();
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(name, 'name', 'Meal name is required');
    }
    if (await getMealFamily(mealFamilyId) == null) {
      throw ArgumentError.value(
        mealFamilyId,
        'mealFamilyId',
        'No such meal family',
      );
    }

    final variant = MealVariant(
      id: PrepIds.newId(),
      mealFamilyId: mealFamilyId,
      name: trimmed,
      protein: protein?.trim().isEmpty ?? true ? null : protein!.trim(),
      estimatedMinutes: _normaliseEstimatedMinutes(estimatedMinutes),
      createdAt: timestamp,
      updatedAt: timestamp,
    );
    await db.insert('meal_variants', variant.toMap());
    return variant;
  }

  /// Adds a meal in one step, creating or reusing its family.
  ///
  /// This is what the "Add meal" flow calls: a household thinks in terms of
  /// "a dinner called Jollof Rice with turkey", not of two tables.
  Future<MealVariant> addMeal({
    required String familyName,
    required MealType mealType,
    String? variantName,
    String? protein,
    int? estimatedMinutes,
    DateTime? now,
  }) async {
    final timestamp = now ?? DateTime.now().toUtc();
    final family = await createMealFamily(
      name: familyName,
      mealType: mealType,
      now: timestamp,
    );
    return createMealVariant(
      mealFamilyId: family.id,
      // A meal with no variant name is just the family by name, which is the
      // common case for something like "Breakfast Muffins".
      name: variantName?.trim().isNotEmpty ?? false
          ? variantName!.trim()
          : family.name,
      protein: protein,
      estimatedMinutes: estimatedMinutes,
      now: timestamp,
    );
  }

  /// Creates or updates one complete meal and its recipe.
  ///
  /// An edit always updates [mealVariantId] in place. It never calls
  /// [addMeal], which is important because a family can have several
  /// variants and editing one of them must not create a second variant by
  /// accident. Ingredient names are resolved through the same shared-row
  /// normalisation used by [addIngredientToMeal].
  Future<MealVariant> saveMeal({
    String? mealVariantId,
    required String familyName,
    required MealType mealType,
    String? variantName,
    String? protein,
    int? estimatedMinutes,
    required List<MealIngredientDraft> ingredients,
    DateTime? now,
  }) async {
    final trimmedFamilyName = familyName.trim();
    if (trimmedFamilyName.isEmpty) {
      throw ArgumentError.value(
        familyName,
        'familyName',
        'Meal family name is required',
      );
    }
    for (final draft in ingredients) {
      if (draft.name.trim().isEmpty) {
        throw ArgumentError.value(
          draft.name,
          'ingredients',
          'Ingredient name is required',
        );
      }
    }

    final timestamp = now ?? DateTime.now().toUtc();
    late final MealVariant meal;
    if (mealVariantId == null) {
      meal = await addMeal(
        familyName: trimmedFamilyName,
        mealType: mealType,
        variantName: variantName,
        protein: protein,
        estimatedMinutes: estimatedMinutes,
        now: timestamp,
      );
    } else {
      final existing = await getMealVariant(mealVariantId);
      if (existing == null) {
        throw ArgumentError.value(
          mealVariantId,
          'mealVariantId',
          'No such meal',
        );
      }
      await updateMealFamily(
        existing.mealFamilyId,
        name: trimmedFamilyName,
        mealType: mealType,
        now: timestamp,
      );
      meal = await updateMealVariant(
        existing.id,
        name: variantName?.trim().isNotEmpty ?? false
            ? variantName!.trim()
            : trimmedFamilyName,
        protein: protein,
        clearProtein: protein?.trim().isEmpty ?? true,
        estimatedMinutes: estimatedMinutes,
        clearEstimatedMinutes: estimatedMinutes == null,
        now: timestamp,
      );
    }

    await _saveRecipe(meal.id, ingredients, now: timestamp);
    return (await getMealVariant(meal.id))!;
  }

  /// Renames a family or moves it to a different meal type.
  Future<MealFamily> updateMealFamily(
    String id, {
    String? name,
    MealType? mealType,
    DateTime? now,
  }) async {
    final db = await _db;
    final existing = await getMealFamily(id);
    if (existing == null) {
      throw ArgumentError.value(id, 'id', 'No such meal family');
    }

    final trimmed = name?.trim();
    if (trimmed != null && trimmed.isEmpty) {
      throw ArgumentError.value(name, 'name', 'Meal family name is required');
    }

    final updated = existing.copyWith(
      name: trimmed,
      mealType: mealType,
      updatedAt: now ?? DateTime.now().toUtc(),
    );
    await db.update(
      'meal_families',
      updated.toMap(),
      where: 'id = ?',
      whereArgs: [id],
    );
    return updated;
  }

  /// Renames a meal or changes its protein.
  ///
  /// Pass `clearProtein: true` to remove a protein entirely — a null [protein]
  /// means "leave it alone", which is the usual `copyWith` convention and
  /// cannot otherwise express "set this back to nothing".
  Future<MealVariant> updateMealVariant(
    String id, {
    String? name,
    String? protein,
    bool clearProtein = false,
    int? estimatedMinutes,
    bool clearEstimatedMinutes = false,
    DateTime? now,
  }) async {
    final db = await _db;
    final existing = await getMealVariant(id);
    if (existing == null) {
      throw ArgumentError.value(id, 'id', 'No such meal');
    }

    final trimmed = name?.trim();
    if (trimmed != null && trimmed.isEmpty) {
      throw ArgumentError.value(name, 'name', 'Meal name is required');
    }
    final newProtein = protein?.trim();

    final updated = MealVariant(
      id: existing.id,
      mealFamilyId: existing.mealFamilyId,
      name: trimmed ?? existing.name,
      protein: clearProtein
          ? null
          : (newProtein?.isNotEmpty ?? false ? newProtein : existing.protein),
      estimatedMinutes: clearEstimatedMinutes
          ? null
          : _normaliseEstimatedMinutes(
              estimatedMinutes ?? existing.estimatedMinutes,
            ),
      lastPlannedAt: existing.lastPlannedAt,
      timesPlanned: existing.timesPlanned,
      createdAt: existing.createdAt,
      updatedAt: now ?? DateTime.now().toUtc(),
      archivedAt: existing.archivedAt,
    );
    await db.update(
      'meal_variants',
      updated.toMap(),
      where: 'id = ?',
      whereArgs: [id],
    );
    return updated;
  }

  static int? _normaliseEstimatedMinutes(int? minutes) {
    if (minutes == null || minutes <= 0) return null;
    return minutes;
  }

  /// Hides a meal from the library without touching plan history.
  Future<void> archiveMealVariant(String id, {DateTime? now}) async {
    final db = await _db;
    await db.update(
      'meal_variants',
      {
        'archived_at': PrepDates.toIso(now ?? DateTime.now().toUtc()),
        'updated_at': PrepDates.toIso(now ?? DateTime.now().toUtc()),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Brings an archived meal back into the library.
  Future<void> restoreMealVariant(String id, {DateTime? now}) async {
    final db = await _db;
    await db.update(
      'meal_variants',
      {
        'archived_at': null,
        'updated_at': PrepDates.toIso(now ?? DateTime.now().toUtc()),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Archives a family and every variant under it.
  ///
  /// Variants are stamped too rather than being left to inherit the family's
  /// state, so a later "restore this one meal" cannot quietly resurrect the
  /// whole family.
  Future<void> archiveMealFamily(String id, {DateTime? now}) async {
    final db = await _db;
    final stamp = PrepDates.toIso(now ?? DateTime.now().toUtc());
    await db.transaction((txn) async {
      await txn.update(
        'meal_variants',
        {'archived_at': stamp, 'updated_at': stamp},
        where: 'meal_family_id = ? AND archived_at IS NULL',
        whereArgs: [id],
      );
      await txn.update(
        'meal_families',
        {'archived_at': stamp, 'updated_at': stamp},
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  /// Deletes a meal outright, taking its recipe lines with it.
  ///
  /// Throws [MealInUseException] when a plan still references the meal. The
  /// shared ingredients it pointed at are left alone — other meals use them.
  Future<void> deleteMealVariant(String id) async {
    final db = await _db;
    final planCount = await countPlanUses(id);
    if (planCount > 0) throw MealInUseException(id, planCount);

    await db.transaction((txn) async {
      // Recipe lines cascade at the schema level, but deleting them here keeps
      // the intent explicit and the behaviour independent of PRAGMA state.
      await txn.delete(
        'meal_ingredients',
        where: 'meal_variant_id = ?',
        whereArgs: [id],
      );
      await txn.delete('meal_variants', where: 'id = ?', whereArgs: [id]);
    });
  }

  /// Removes a meal from the library the safe way.
  ///
  /// Deletes it when nothing refers to it, archives it when a plan does. This
  /// is what a "Delete meal" button should call: the household's intent is
  /// "stop showing me this", and which of the two happens is an implementation
  /// detail that must never cost them their history.
  Future<MealRemoval> removeMealVariant(String id, {DateTime? now}) async {
    if (await countPlanUses(id) > 0) {
      await archiveMealVariant(id, now: now);
      return MealRemoval.archived;
    }
    await deleteMealVariant(id);
    return MealRemoval.deleted;
  }

  /// How many plan items reference this meal.
  Future<int> countPlanUses(String mealVariantId) async {
    final db = await _db;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM weekly_plan_items WHERE meal_variant_id = ?',
      [mealVariantId],
    );
    return (rows.first['c']! as num).toInt();
  }

  // ---------------------------------------------------------- ingredients

  /// Returns the ingredient matching [name], creating it only if none exists.
  ///
  /// Matching is on the normalised name, so "Chicken breast" and
  /// "chicken  breast " resolve to the same row. The stored name keeps the
  /// spelling it was first created with; a later [category] fills in a
  /// category the original lacked but never overwrites one already set.
  Future<Ingredient> findOrCreateIngredient({
    required String name,
    String? category,
    DateTime? now,
  }) async {
    final db = await _db;
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(name, 'name', 'Ingredient name is required');
    }
    final timestamp = now ?? DateTime.now().toUtc();

    final existing = await _findIngredientByName(db, trimmed);
    if (existing != null) {
      if (existing.category != null || category == null) return existing;
      final filled = existing.copyWith(
        category: category,
        updatedAt: timestamp,
      );
      await db.update(
        'ingredients',
        filled.toMap(),
        where: 'id = ?',
        whereArgs: [existing.id],
      );
      return filled;
    }

    final ingredient = Ingredient(
      id: PrepIds.newId(),
      name: trimmed,
      category: category,
      createdAt: timestamp,
      updatedAt: timestamp,
    );
    await db.insert('ingredients', ingredient.toMap());
    return ingredient;
  }

  /// Adds an ingredient to a meal's recipe, or updates the line if that
  /// ingredient is already on it.
  ///
  /// Re-adding rather than duplicating is deliberate: two lines for the same
  /// ingredient on one meal would double it on the shopping list, and a
  /// household typing it twice means "I got the amount wrong", not "use it
  /// twice".
  ///
  /// [quantity] stays null when the amount is genuinely unknown.
  Future<MealRecipeLine> addIngredientToMeal({
    required String mealVariantId,
    required String ingredientName,
    String? category,
    double? quantity,
    String? unit,
    int? baseServings,
    DateTime? now,
  }) async {
    final db = await _db;
    if (await getMealVariant(mealVariantId) == null) {
      throw ArgumentError.value(mealVariantId, 'mealVariantId', 'No such meal');
    }

    final ingredient = await findOrCreateIngredient(
      name: ingredientName,
      category: category,
      now: now,
    );

    final existing = await db.query(
      'meal_ingredients',
      where: 'meal_variant_id = ? AND ingredient_id = ?',
      whereArgs: [mealVariantId, ingredient.id],
      limit: 1,
    );

    final line = MealIngredient(
      id: existing.isEmpty ? PrepIds.newId() : existing.first['id']! as String,
      mealVariantId: mealVariantId,
      ingredientId: ingredient.id,
      quantity: quantity,
      // A unit without a number is not useful and would imply precision we
      // do not have, so keep the unmeasured form fully unknown.
      unit: quantity == null
          ? null
          : (unit?.trim().isEmpty ?? true ? null : unit!.trim()),
      // An unmeasured line has no serving basis to scale from.
      baseServings: quantity == null ? null : baseServings,
    );

    if (existing.isEmpty) {
      await db.insert('meal_ingredients', line.toMap());
    } else {
      await db.update(
        'meal_ingredients',
        line.toMap(),
        where: 'id = ?',
        whereArgs: [line.id],
      );
    }
    return MealRecipeLine(line: line, ingredient: ingredient);
  }

  /// Changes the amount on one recipe line.
  ///
  /// Pass `clearQuantity: true` to record that the amount is not known, which
  /// also clears the unit and serving basis — they mean nothing without a
  /// number.
  Future<MealIngredient> updateMealIngredient(
    String id, {
    double? quantity,
    String? unit,
    int? baseServings,
    bool clearQuantity = false,
  }) async {
    final db = await _db;
    final rows = await db.query(
      'meal_ingredients',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw ArgumentError.value(id, 'id', 'No such recipe line');
    }
    final existing = MealIngredient.fromMap(rows.first);

    final updated = MealIngredient(
      id: existing.id,
      mealVariantId: existing.mealVariantId,
      ingredientId: existing.ingredientId,
      quantity: clearQuantity ? null : (quantity ?? existing.quantity),
      unit: clearQuantity ? null : (unit?.trim() ?? existing.unit),
      baseServings: clearQuantity
          ? null
          : (baseServings ?? existing.baseServings),
    );
    await db.update(
      'meal_ingredients',
      updated.toMap(),
      where: 'id = ?',
      whereArgs: [id],
    );
    return updated;
  }

  /// Synchronises the recipe rows for one meal with the edit form.
  Future<void> _saveRecipe(
    String mealVariantId,
    List<MealIngredientDraft> drafts, {
    required DateTime now,
  }) async {
    final existing = await getIngredientsForMeal(mealVariantId);
    final usedLineIds = <String>{};

    for (final draft in drafts) {
      MealRecipeLine? matching;
      if (draft.lineId != null) {
        for (final line in existing) {
          if (line.id == draft.lineId && !usedLineIds.contains(line.id)) {
            matching = line;
            break;
          }
        }
      }
      // A row may have been created before the form was opened and therefore
      // have no line id in a caller-created draft. Name matching still keeps
      // the edit idempotent and avoids duplicate recipe links.
      matching ??= existing.cast<MealRecipeLine?>().firstWhere(
        (line) =>
            line != null &&
            !usedLineIds.contains(line.id) &&
            Ingredient.normaliseName(line.name) ==
                Ingredient.normaliseName(draft.name),
        orElse: () => null,
      );

      if (matching != null) {
        usedLineIds.add(matching.id);
        if (Ingredient.normaliseName(matching.name) !=
            Ingredient.normaliseName(draft.name)) {
          await removeMealIngredient(matching.id);
          await addIngredientToMeal(
            mealVariantId: mealVariantId,
            ingredientName: draft.name,
            category: draft.category,
            quantity: draft.quantity,
            unit: draft.unit,
            baseServings: draft.baseServings,
            now: now,
          );
        } else {
          await updateMealIngredient(
            matching.id,
            quantity: draft.quantity,
            unit: draft.unit,
            baseServings: draft.baseServings,
            clearQuantity: draft.quantity == null,
          );
          // Categories belong to the shared ingredient. An explicit edit is
          // allowed to change it, while findOrCreateIngredient deliberately
          // remains conservative for imports and new recipe lines.
          await updateIngredient(
            matching.ingredient.id,
            category: draft.category,
            now: now,
          );
        }
      } else {
        final line = await addIngredientToMeal(
          mealVariantId: mealVariantId,
          ingredientName: draft.name,
          category: draft.category,
          quantity: draft.quantity,
          unit: draft.unit,
          baseServings: draft.baseServings,
          now: now,
        );
        usedLineIds.add(line.id);
      }
    }

    for (final line in existing) {
      if (!usedLineIds.contains(line.id)) {
        await removeMealIngredient(line.id);
      }
    }
  }

  /// Takes one ingredient off a meal's recipe.
  ///
  /// Deletes only the link row. The ingredient itself is shared and stays put
  /// — other meals almost certainly use it, and the shopping list relies on
  /// every meal that uses chicken pointing at the same chicken.
  Future<void> removeMealIngredient(String id) async {
    final db = await _db;
    await db.delete('meal_ingredients', where: 'id = ?', whereArgs: [id]);
  }

  /// Deletes an ingredient only if no recipe and no shopping list uses it.
  ///
  /// Returns true when it was removed. Housekeeping, called deliberately —
  /// never as a side effect of editing a recipe.
  Future<bool> deleteIngredientIfUnused(String id) async {
    final db = await _db;
    final recipeUses = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM meal_ingredients WHERE ingredient_id = ?',
      [id],
    );
    if ((recipeUses.first['c']! as num).toInt() > 0) return false;

    final listUses = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM shopping_items WHERE ingredient_id = ?',
      [id],
    );
    if ((listUses.first['c']! as num).toInt() > 0) return false;

    final deleted = await db.delete(
      'ingredients',
      where: 'id = ?',
      whereArgs: [id],
    );
    return deleted > 0;
  }

  // --------------------------------------------------------------- shared

  Future<MealFamily?> _findFamilyByName(
    Database db,
    String name,
    MealType mealType,
  ) async {
    final rows = await db.query(
      'meal_families',
      where: 'meal_type = ?',
      whereArgs: [mealType.value],
    );
    final target = Ingredient.normaliseName(name);
    for (final row in rows) {
      final family = MealFamily.fromMap(row);
      if (Ingredient.normaliseName(family.name) == target) return family;
    }
    return null;
  }

  Future<Ingredient?> _findIngredientByName(Database db, String name) async {
    final target = Ingredient.normaliseName(name);
    // SQLite's LOWER() is ASCII-only and cannot collapse inner whitespace, so
    // the comparison is done in Dart against the same normaliser the rest of
    // the app uses. The ingredient table is small enough that this is cheap,
    // and correctness here is what keeps the shopping list merging.
    final rows = await db.query('ingredients');
    for (final row in rows) {
      final ingredient = Ingredient.fromMap(row);
      if (Ingredient.normaliseName(ingredient.name) == target) {
        return ingredient;
      }
    }
    return null;
  }

  Future<Map<String, Ingredient>> _ingredientsByIds(
    Database db,
    Set<String> ids,
  ) async {
    if (ids.isEmpty) return const {};
    final rows = await db.query(
      'ingredients',
      where: 'id IN (${List.filled(ids.length, '?').join(', ')})',
      whereArgs: ids.toList(),
    );
    return {
      for (final row in rows) row['id']! as String: Ingredient.fromMap(row),
    };
  }
}
