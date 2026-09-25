import 'package:sqflite/sqflite.dart';

import '../models/models.dart';
import '../utils/date_utils.dart';
import 'database_service.dart';
import 'seed_data.dart';

/// Loads the development/demo meal library described by [SeedData].
///
/// **The seeded meals are demo data, not the household's real library.** They
/// exist so the weekly planning and shopping flows can be exercised before any
/// meal has been imported. Every seeded row carries an id prefixed with
/// [idPrefix], so demo data stays identifiable and can be removed wholesale by
/// [removeSeedData].
///
/// Seeding is idempotent in two independent ways, because either alone can be
/// defeated:
///
/// * [seedIfEmpty] does nothing at all once the library holds any meal, so a
///   household that has added or deleted their own meals is never overwritten.
/// * Ids are derived from names rather than generated, and every insert uses
///   `INSERT OR IGNORE`, so even a forced re-seed cannot duplicate a row.
class SeedService {
  SeedService(this._databaseService);

  /// Prefix on every id this service writes.
  static const String idPrefix = 'seed';

  /// Settings key recording that the demo data has been loaded.
  static const String seededSettingKey = 'demo_seed_version';

  /// Bump when the catalogue changes in a way an existing install should pick
  /// up. Recorded against [seededSettingKey] for diagnostics.
  static const int seedVersion = 1;

  final DatabaseService _databaseService;

  /// Loads the demo library only if no meal variant exists yet.
  ///
  /// Returns true when rows were written, false when the library was already
  /// populated and seeding was skipped.
  Future<bool> seedIfEmpty({DateTime? now}) async {
    final db = await _databaseService.database;
    if (await _hasAnyMeal(db)) return false;
    await _insertAll(db, now ?? DateTime.now().toUtc());
    return true;
  }

  /// True when the meal library holds at least one variant, seeded or not.
  Future<bool> hasMeals() async => _hasAnyMeal(await _databaseService.database);

  /// Removes every row this service wrote, leaving household data alone.
  ///
  /// Development helper. Seeded meals that a plan already references are
  /// protected by the schema, so this throws rather than corrupting history.
  Future<void> removeSeedData() async {
    final db = await _databaseService.database;
    await db.transaction((txn) async {
      const like = "id LIKE '$idPrefix-%'";
      await txn.delete('meal_ingredients', where: like);
      await txn.delete('meal_variants', where: like);
      await txn.delete('meal_families', where: like);
      await txn.delete('ingredients', where: like);
      await txn.delete(
        'settings',
        where: 'key = ?',
        whereArgs: [seededSettingKey],
      );
    });
  }

  Future<bool> _hasAnyMeal(Database db) async {
    final rows = await db.rawQuery('SELECT 1 FROM meal_variants LIMIT 1');
    return rows.isNotEmpty;
  }

  Future<void> _insertAll(Database db, DateTime now) async {
    await db.transaction((txn) async {
      final batch = txn.batch();

      // One ingredient row per catalogue name, so meals that share an
      // ingredient share its id and the shopping list can merge them.
      final ingredientIds = <String, String>{};
      for (final ingredient in SeedData.ingredients) {
        final key = normaliseIngredientName(ingredient.name);
        final id = ingredientIds[key] ??= ingredientId(ingredient.name);
        batch.insert(
          'ingredients',
          Ingredient(
            id: id,
            name: ingredient.name,
            category: ingredient.category,
            createdAt: now,
            updatedAt: now,
          ).toMap(),
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }

      for (final family in SeedData.families) {
        final familyId = SeedService.familyId(family.name);
        batch.insert(
          'meal_families',
          MealFamily(
            id: familyId,
            name: family.name,
            mealType: family.mealType,
            createdAt: now,
            updatedAt: now,
          ).toMap(),
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );

        for (final variant in family.variants) {
          final variantId = SeedService.variantId(variant.name);
          batch.insert(
            'meal_variants',
            MealVariant(
              id: variantId,
              mealFamilyId: familyId,
              name: variant.name,
              protein: variant.protein,
              estimatedMinutes: variant.estimatedMinutes,
              createdAt: now,
              updatedAt: now,
            ).toMap(),
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );

          for (final line in variant.lines) {
            final key = normaliseIngredientName(line.ingredient);
            final resolved = ingredientIds[key];
            if (resolved == null) {
              throw StateError(
                'Seed recipe "${variant.name}" references unknown ingredient '
                '"${line.ingredient}".',
              );
            }
            batch.insert(
              'meal_ingredients',
              MealIngredient(
                id: '$idPrefix-mi-${_slug(variant.name)}-${_slug(line.ingredient)}',
                mealVariantId: variantId,
                ingredientId: resolved,
                quantity: line.quantity,
                unit: line.unit,
                // Unmeasured lines have no serving basis to scale from.
                baseServings: line.quantity == null
                    ? null
                    : line.baseServings ?? SeedData.baseServings,
              ).toMap(),
              conflictAlgorithm: ConflictAlgorithm.ignore,
            );
          }
        }
      }

      batch.insert('settings', {
        'key': seededSettingKey,
        'value': '$seedVersion@${PrepDates.toIso(now)}',
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      await batch.commit(noResult: true);
    });
  }

  /// Collapses an ingredient name to the key two meals must agree on to be
  /// treated as the same ingredient.
  ///
  /// The rule itself lives on [Ingredient] so the seed and [MealService] can
  /// never drift apart on what counts as the same ingredient.
  static String normaliseIngredientName(String name) =>
      Ingredient.normaliseName(name);

  /// Deterministic id for a seeded ingredient.
  static String ingredientId(String name) => '$idPrefix-ing-${_slug(name)}';

  /// Deterministic id for a seeded meal family.
  static String familyId(String name) => '$idPrefix-fam-${_slug(name)}';

  /// Deterministic id for a seeded meal variant.
  static String variantId(String name) => '$idPrefix-var-${_slug(name)}';

  static String _slug(String value) => normaliseIngredientName(
    value,
  ).replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-|-$'), '');
}
