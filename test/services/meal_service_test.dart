import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:preppick/models/models.dart';
import 'package:preppick/services/database_service.dart';
import 'package:preppick/services/meal_service.dart';
import 'package:preppick/services/seed_service.dart';
import 'package:preppick/utils/date_utils.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late Directory tempDir;
  late DatabaseService database;
  late MealService service;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('preppick_meal_test');
    database = DatabaseService(
      factory: databaseFactoryFfi,
      databaseName: '${tempDir.path}/preppick_test.db',
    );
    service = MealService(database);
  });

  tearDown(() async {
    await database.close();
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  Future<void> seed() => SeedService(database).seedIfEmpty();

  /// Creates a confirmed plan that uses [mealVariantId], as a real week would.
  Future<String> planMeal(String mealVariantId) async {
    final db = await database.database;
    const planId = 'plan-1';
    await db.insert(
      'weekly_plans',
      WeeklyPlan(
        id: planId,
        weekStart: DateTime.utc(2026, 3, 2),
        status: PlanStatus.confirmed,
        createdAt: DateTime.utc(2026, 3, 1),
        confirmedAt: DateTime.utc(2026, 3, 1),
      ).toMap(),
    );
    await db.insert('weekly_plan_items', {
      'id': 'item-1',
      'weekly_plan_id': planId,
      'meal_variant_id': mealVariantId,
      'meal_type': MealType.dinner.value,
      'slot_index': 0,
    });
    return planId;
  }

  group('reads', () {
    test('returns every seeded meal, ordered by name', () async {
      await seed();

      final meals = await service.getAllMealVariants();

      expect(meals, isNotEmpty);
      final names = meals.map((m) => m.name.toLowerCase()).toList();
      expect(names, orderedEquals(List.of(names)..sort()));
    });

    test('an empty library reads as an empty list, not an error', () async {
      expect(await service.getAllMealVariants(), isEmpty);
      expect(await service.getAllMealFamilies(), isEmpty);
    });

    test('filters breakfast, lunch and dinner through the family', () async {
      await seed();

      final breakfast = await service.getMealsByType(MealType.breakfast);
      final lunch = await service.getMealsByType(MealType.lunch);
      final dinner = await service.getMealsByType(MealType.dinner);

      expect(breakfast, isNotEmpty);
      expect(lunch, isNotEmpty);
      expect(dinner, isNotEmpty);

      // Every returned meal really belongs to a family of that type.
      for (final entry in {
        MealType.breakfast: breakfast,
        MealType.lunch: lunch,
        MealType.dinner: dinner,
      }.entries) {
        for (final meal in entry.value) {
          final family = await service.getMealFamily(meal.mealFamilyId);
          expect(family!.mealType, entry.key);
        }
      }

      // The three sets partition the library; nothing is lost or double-counted.
      final all = await service.getAllMealVariants();
      expect(breakfast.length + lunch.length + dinner.length, all.length);
    });

    test(
      'getMealFamily and getMealVariant return null for unknown ids',
      () async {
        expect(await service.getMealFamily('nope'), isNull);
        expect(await service.getMealVariant('nope'), isNull);
      },
    );

    test('reads a meal recipe with names and quantities attached', () async {
      await seed();
      final meals = await service.getAllMealVariants();
      final withRecipe = meals.firstWhere(
        (m) => m.name.toLowerCase().contains('spaghetti'),
      );

      final recipe = await service.getIngredientsForMeal(withRecipe.id);

      expect(recipe, isNotEmpty);
      expect(recipe.every((line) => line.name.isNotEmpty), isTrue);
      // Ordered by ingredient name so the detail screen is stable.
      final names = recipe.map((line) => line.name.toLowerCase()).toList();
      expect(names, orderedEquals(List.of(names)..sort()));
    });

    test(
      'preserves an unknown quantity as null rather than inventing one',
      () async {
        await seed();
        final meals = await service.getAllMealVariants();

        var sawUnmeasured = false;
        for (final meal in meals) {
          for (final line in await service.getIngredientsForMeal(meal.id)) {
            if (!line.hasQuantity) {
              sawUnmeasured = true;
              expect(line.quantity, isNull);
              expect(line.baseServings, isNull);
            }
          }
        }
        // The seed deliberately contains unmeasured lines (olive oil, salt).
        expect(sawUnmeasured, isTrue);
      },
    );

    test('a meal with no recipe reads as an empty list', () async {
      final meal = await service.addMeal(
        familyName: 'Toast',
        mealType: MealType.breakfast,
      );

      expect(await service.getIngredientsForMeal(meal.id), isEmpty);
    });
  });

  group('creating meals', () {
    test('adds a family and a variant in one step', () async {
      final meal = await service.addMeal(
        familyName: 'Jollof Rice',
        mealType: MealType.dinner,
        variantName: 'Jollof Rice + Turkey',
        protein: 'turkey',
      );

      expect(meal.name, 'Jollof Rice + Turkey');
      expect(meal.protein, 'turkey');

      final family = await service.getMealFamily(meal.mealFamilyId);
      expect(family!.name, 'Jollof Rice');
      expect(family.mealType, MealType.dinner);

      expect(await service.getMealsByType(MealType.dinner), hasLength(1));
    });

    test('names a variant after its family when none is given', () async {
      final meal = await service.addMeal(
        familyName: 'Breakfast Muffins',
        mealType: MealType.breakfast,
      );

      expect(meal.name, 'Breakfast Muffins');
    });

    test('reuses a family with the same normalised name and type', () async {
      final first = await service.addMeal(
        familyName: 'Fried Rice',
        mealType: MealType.dinner,
        variantName: 'Fried Rice + Chicken',
      );
      final second = await service.addMeal(
        familyName: '  fried   rice ',
        mealType: MealType.dinner,
        variantName: 'Fried Rice + Prawn',
      );

      expect(second.mealFamilyId, first.mealFamilyId);
      expect(await service.getAllMealFamilies(), hasLength(1));
      expect(await service.getAllMealVariants(), hasLength(2));
    });

    test(
      'treats the same name under a different meal type as its own family',
      () async {
        await service.addMeal(familyName: 'Paninis', mealType: MealType.lunch);
        await service.addMeal(familyName: 'Paninis', mealType: MealType.dinner);

        expect(await service.getAllMealFamilies(), hasLength(2));
      },
    );

    test('trims names and rejects blank ones', () async {
      final meal = await service.addMeal(
        familyName: '  Burger  ',
        mealType: MealType.dinner,
      );
      expect(meal.name, 'Burger');

      expect(
        () => service.addMeal(familyName: '   ', mealType: MealType.dinner),
        throwsArgumentError,
      );
    });

    test('refuses a variant under a family that does not exist', () async {
      expect(
        () => service.createMealVariant(mealFamilyId: 'nope', name: 'X'),
        throwsArgumentError,
      );
    });

    test('gives every new row a distinct id', () async {
      final a = await service.addMeal(
        familyName: 'Fish',
        mealType: MealType.dinner,
        variantName: 'Fish + Rice',
      );
      final b = await service.addMeal(
        familyName: 'Fish',
        mealType: MealType.dinner,
        variantName: 'Fish + Chips',
      );

      expect(a.id, isNot(b.id));
      expect(a.id, isNotEmpty);
    });
  });

  group('updating meals', () {
    test('renames a meal and changes its protein', () async {
      final meal = await service.addMeal(
        familyName: 'Pasta',
        mealType: MealType.dinner,
        variantName: 'Pasta + Mince',
        protein: 'beef',
      );

      final updated = await service.updateMealVariant(
        meal.id,
        name: 'Pasta + Turkey Mince',
        protein: 'turkey',
      );

      expect(updated.name, 'Pasta + Turkey Mince');
      expect(updated.protein, 'turkey');
      expect(
        (await service.getMealVariant(meal.id))!.name,
        'Pasta + Turkey Mince',
      );
    });

    test('leaves the protein alone when none is passed', () async {
      final meal = await service.addMeal(
        familyName: 'Fish',
        mealType: MealType.dinner,
        protein: 'salmon',
      );

      final updated = await service.updateMealVariant(
        meal.id,
        name: 'Fish pie',
      );

      expect(updated.protein, 'salmon');
    });

    test('clears the protein only when explicitly asked', () async {
      final meal = await service.addMeal(
        familyName: 'Fish',
        mealType: MealType.dinner,
        protein: 'salmon',
      );

      final updated = await service.updateMealVariant(
        meal.id,
        clearProtein: true,
      );

      expect(updated.protein, isNull);
      expect((await service.getMealVariant(meal.id))!.protein, isNull);
    });

    test('preserves planning history across an edit', () async {
      final meal = await service.addMeal(
        familyName: 'Burger',
        mealType: MealType.dinner,
      );
      final db = await database.database;
      await db.update(
        'meal_variants',
        {
          'times_planned': 4,
          'last_planned_at': PrepDates.toIso(DateTime.utc(2026, 3, 2)),
        },
        where: 'id = ?',
        whereArgs: [meal.id],
      );

      final updated = await service.updateMealVariant(
        meal.id,
        name: 'Big Burger',
      );

      expect(updated.timesPlanned, 4);
      expect(updated.lastPlannedAt, DateTime.utc(2026, 3, 2));
    });

    test('renames a family and can move it to another meal type', () async {
      final meal = await service.addMeal(
        familyName: 'Wraps',
        mealType: MealType.dinner,
      );

      final updated = await service.updateMealFamily(
        meal.mealFamilyId,
        name: 'Chicken Wraps',
        mealType: MealType.lunch,
      );

      expect(updated.name, 'Chicken Wraps');
      expect(await service.getMealsByType(MealType.lunch), hasLength(1));
      expect(await service.getMealsByType(MealType.dinner), isEmpty);
    });

    test('rejects a blank rename and an unknown id', () async {
      final meal = await service.addMeal(
        familyName: 'Fish',
        mealType: MealType.dinner,
      );

      expect(
        () => service.updateMealVariant(meal.id, name: '  '),
        throwsArgumentError,
      );
      expect(
        () => service.updateMealVariant('nope', name: 'X'),
        throwsArgumentError,
      );
    });
  });

  group('ingredients', () {
    late MealVariant meal;

    setUp(() async {
      meal = await service.addMeal(
        familyName: 'Lou Lou Spaghetti',
        mealType: MealType.dinner,
        variantName: 'Lou Lou Spaghetti + Chicken',
      );
    });

    test('attaches an ingredient with its quantity', () async {
      final line = await service.addIngredientToMeal(
        mealVariantId: meal.id,
        ingredientName: 'Chicken breast',
        category: IngredientCategory.protein,
        quantity: 500,
        unit: 'g',
        baseServings: 4,
      );

      expect(line.name, 'Chicken breast');
      expect(line.quantity, 500);
      expect(line.unit, 'g');
      expect(line.category, IngredientCategory.protein);

      final recipe = await service.getIngredientsForMeal(meal.id);
      expect(recipe, hasLength(1));
      expect(recipe.single.name, 'Chicken breast');
    });

    test('keeps an unmeasured ingredient unmeasured', () async {
      final line = await service.addIngredientToMeal(
        mealVariantId: meal.id,
        ingredientName: 'Olive oil',
      );

      expect(line.quantity, isNull);
      expect(line.unit, isNull);
      // A serving basis is meaningless without a quantity to scale.
      expect(line.baseServings, isNull);
    });

    test('reuses an ingredient whose normalised name already exists', () async {
      final other = await service.addMeal(
        familyName: 'Fried Rice',
        mealType: MealType.dinner,
      );

      final first = await service.addIngredientToMeal(
        mealVariantId: meal.id,
        ingredientName: 'Chicken breast',
        category: IngredientCategory.protein,
        quantity: 500,
        unit: 'g',
      );
      final second = await service.addIngredientToMeal(
        mealVariantId: other.id,
        ingredientName: '  chicken   BREAST ',
        quantity: 750,
        unit: 'g',
      );

      // One shared ingredient row, which is what lets the shopping list merge.
      expect(second.ingredient.id, first.ingredient.id);
      final db = await database.database;
      expect(await db.query('ingredients'), hasLength(1));
      // The spelling it was first saved with is kept.
      expect(second.ingredient.name, 'Chicken breast');
    });

    test('fills in a missing category but never overwrites one', () async {
      await service.findOrCreateIngredient(name: 'Tomatoes');
      final filled = await service.findOrCreateIngredient(
        name: 'tomatoes',
        category: IngredientCategory.produce,
      );
      expect(filled.category, IngredientCategory.produce);

      final unchanged = await service.findOrCreateIngredient(
        name: 'Tomatoes',
        category: IngredientCategory.frozen,
      );
      expect(unchanged.category, IngredientCategory.produce);
    });

    test(
      're-adding the same ingredient updates the line, not duplicates it',
      () async {
        await service.addIngredientToMeal(
          mealVariantId: meal.id,
          ingredientName: 'Chicken breast',
          quantity: 500,
          unit: 'g',
        );
        await service.addIngredientToMeal(
          mealVariantId: meal.id,
          ingredientName: 'chicken breast',
          quantity: 750,
          unit: 'g',
        );

        final recipe = await service.getIngredientsForMeal(meal.id);
        expect(recipe, hasLength(1));
        expect(recipe.single.quantity, 750);
      },
    );

    test('updates a quantity on an existing line', () async {
      final line = await service.addIngredientToMeal(
        mealVariantId: meal.id,
        ingredientName: 'Spaghetti',
        quantity: 400,
        unit: 'g',
      );

      final updated = await service.updateMealIngredient(
        line.id,
        quantity: 500,
      );

      expect(updated.quantity, 500);
      expect(updated.unit, 'g');
    });

    test('clearing a quantity clears the unit and serving basis too', () async {
      final line = await service.addIngredientToMeal(
        mealVariantId: meal.id,
        ingredientName: 'Sea salt',
        quantity: 5,
        unit: 'g',
        baseServings: 4,
      );

      final updated = await service.updateMealIngredient(
        line.id,
        clearQuantity: true,
      );

      expect(updated.quantity, isNull);
      expect(updated.unit, isNull);
      expect(updated.baseServings, isNull);
    });

    test('removing a line leaves the shared ingredient in place', () async {
      final other = await service.addMeal(
        familyName: 'Fried Rice',
        mealType: MealType.dinner,
      );
      final line = await service.addIngredientToMeal(
        mealVariantId: meal.id,
        ingredientName: 'Chicken breast',
      );
      await service.addIngredientToMeal(
        mealVariantId: other.id,
        ingredientName: 'Chicken breast',
      );

      await service.removeMealIngredient(line.id);

      expect(await service.getIngredientsForMeal(meal.id), isEmpty);
      // The other meal still resolves it, so the row must still exist.
      expect(await service.getIngredientsForMeal(other.id), hasLength(1));
      expect(await service.findIngredientByName('chicken breast'), isNotNull);
    });

    test(
      'an ingredient still used by another recipe is not tidied away',
      () async {
        final other = await service.addMeal(
          familyName: 'Fried Rice',
          mealType: MealType.dinner,
        );
        final line = await service.addIngredientToMeal(
          mealVariantId: meal.id,
          ingredientName: 'Chicken breast',
        );
        await service.addIngredientToMeal(
          mealVariantId: other.id,
          ingredientName: 'Chicken breast',
        );
        await service.removeMealIngredient(line.id);

        final removed = await service.deleteIngredientIfUnused(
          line.ingredient.id,
        );

        expect(removed, isFalse);
        expect(await service.getIngredient(line.ingredient.id), isNotNull);
      },
    );

    test('an orphaned ingredient can be tidied away deliberately', () async {
      final line = await service.addIngredientToMeal(
        mealVariantId: meal.id,
        ingredientName: 'Scotch bonnet',
      );
      await service.removeMealIngredient(line.id);

      expect(
        await service.deleteIngredientIfUnused(line.ingredient.id),
        isTrue,
      );
      expect(await service.getIngredient(line.ingredient.id), isNull);
    });

    test(
      'refuses to attach an ingredient to a meal that does not exist',
      () async {
        expect(
          () => service.addIngredientToMeal(
            mealVariantId: 'nope',
            ingredientName: 'Rice',
          ),
          throwsArgumentError,
        );
      },
    );

    test('rejects a blank ingredient name', () async {
      expect(
        () => service.findOrCreateIngredient(name: '   '),
        throwsArgumentError,
      );
    });
  });

  group('archiving and deleting', () {
    test('an archived meal leaves the active library', () async {
      final meal = await service.addMeal(
        familyName: 'Burger',
        mealType: MealType.dinner,
      );

      await service.archiveMealVariant(meal.id);

      expect(await service.getAllMealVariants(), isEmpty);
      expect(await service.getMealsByType(MealType.dinner), isEmpty);
      // Still readable by id, so history can render its name.
      expect((await service.getMealVariant(meal.id))!.isArchived, isTrue);
      expect(
        await service.getAllMealVariants(includeArchived: true),
        hasLength(1),
      );
    });

    test('restoring brings it back', () async {
      final meal = await service.addMeal(
        familyName: 'Burger',
        mealType: MealType.dinner,
      );
      await service.archiveMealVariant(meal.id);

      await service.restoreMealVariant(meal.id);

      expect(await service.getAllMealVariants(), hasLength(1));
      expect((await service.getMealVariant(meal.id))!.isArchived, isFalse);
    });

    test('archiving a family hides every meal under it', () async {
      final first = await service.addMeal(
        familyName: 'Fish',
        mealType: MealType.dinner,
        variantName: 'Fish + Rice',
      );
      await service.createMealVariant(
        mealFamilyId: first.mealFamilyId,
        name: 'Fish + Chips',
      );

      await service.archiveMealFamily(first.mealFamilyId);

      expect(await service.getAllMealVariants(), isEmpty);
      expect(await service.getAllMealFamilies(), isEmpty);
      expect(
        await service.getAllMealVariants(includeArchived: true),
        hasLength(2),
      );
    });

    test('deletes an unplanned meal outright, with its recipe lines', () async {
      final meal = await service.addMeal(
        familyName: 'Toast',
        mealType: MealType.breakfast,
      );
      await service.addIngredientToMeal(
        mealVariantId: meal.id,
        ingredientName: 'Bread',
      );

      await service.deleteMealVariant(meal.id);

      expect(await service.getMealVariant(meal.id), isNull);
      final db = await database.database;
      expect(
        await db.query(
          'meal_ingredients',
          where: 'meal_variant_id = ?',
          whereArgs: [meal.id],
        ),
        isEmpty,
      );
      // The shared ingredient survives its last recipe going away.
      expect(await service.findIngredientByName('Bread'), isNotNull);
    });

    test('refuses to delete a meal a plan still uses', () async {
      final meal = await service.addMeal(
        familyName: 'Burger',
        mealType: MealType.dinner,
      );
      await planMeal(meal.id);

      expect(
        () => service.deleteMealVariant(meal.id),
        throwsA(isA<MealInUseException>()),
      );
      expect(await service.getMealVariant(meal.id), isNotNull);
    });

    test('removeMealVariant deletes when unplanned', () async {
      final meal = await service.addMeal(
        familyName: 'Toast',
        mealType: MealType.breakfast,
      );

      expect(await service.removeMealVariant(meal.id), MealRemoval.deleted);
      expect(await service.getMealVariant(meal.id), isNull);
    });

    test(
      'removeMealVariant archives when planned, keeping history intact',
      () async {
        final meal = await service.addMeal(
          familyName: 'Burger',
          mealType: MealType.dinner,
        );
        final planId = await planMeal(meal.id);

        expect(await service.removeMealVariant(meal.id), MealRemoval.archived);

        // Gone from the library...
        expect(await service.getAllMealVariants(), isEmpty);
        // ...but the plan item still resolves to a real, nameable meal.
        final db = await database.database;
        final items = await db.query(
          'weekly_plan_items',
          where: 'weekly_plan_id = ?',
          whereArgs: [planId],
        );
        expect(items, hasLength(1));
        final planned = await service.getMealVariant(
          items.single['meal_variant_id']! as String,
        );
        expect(planned, isNotNull);
        expect(planned!.name, 'Burger');
      },
    );

    test('countPlanUses reports how many items reference a meal', () async {
      final meal = await service.addMeal(
        familyName: 'Burger',
        mealType: MealType.dinner,
      );
      expect(await service.countPlanUses(meal.id), 0);

      await planMeal(meal.id);

      expect(await service.countPlanUses(meal.id), 1);
    });

    test('stores and clears an optional estimated cooking time', () async {
      final meal = await service.addMeal(
        familyName: 'Jollof Rice',
        mealType: MealType.dinner,
        variantName: 'Jollof Rice + Turkey',
        estimatedMinutes: 60,
      );

      expect((await service.getMealVariant(meal.id))!.estimatedMinutes, 60);

      await service.updateMealVariant(
        meal.id,
        estimatedMinutes: null,
        clearEstimatedMinutes: true,
      );

      expect((await service.getMealVariant(meal.id))!.estimatedMinutes, isNull);
    });
  });
}
