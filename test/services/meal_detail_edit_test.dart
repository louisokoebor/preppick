import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:preppick/models/models.dart';
import 'package:preppick/services/database_service.dart';
import 'package:preppick/services/meal_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late Directory tempDir;
  late DatabaseService database;
  late MealService service;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('preppick_detail_test');
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

  test('saveMeal creates a meal and keeps a blank amount null', () async {
    final meal = await service.saveMeal(
      familyName: 'Jollof Rice',
      mealType: MealType.dinner,
      variantName: 'Jollof Rice + Turkey',
      protein: 'Turkey',
      ingredients: const [
        MealIngredientDraft(
          name: 'Turkey mince',
          category: IngredientCategory.protein,
        ),
      ],
    );

    final recipe = await service.getIngredientsForMeal(meal.id);
    expect(recipe, hasLength(1));
    expect(recipe.single.quantity, isNull);
    expect(recipe.single.category, IngredientCategory.protein);
  });

  test(
    'saveMeal edits the same variant and synchronises recipe lines',
    () async {
      final meal = await service.addMeal(
        familyName: 'Pasta',
        mealType: MealType.dinner,
        variantName: 'Pasta + Mince',
      );
      final first = await service.addIngredientToMeal(
        mealVariantId: meal.id,
        ingredientName: 'Beef mince',
        quantity: 500,
        unit: 'g',
      );

      final edited = await service.saveMeal(
        mealVariantId: meal.id,
        familyName: 'Pasta Bake',
        mealType: MealType.lunch,
        variantName: 'Pasta Bake + Turkey',
        protein: 'Turkey',
        ingredients: [
          MealIngredientDraft(
            lineId: first.id,
            name: 'Beef mince',
            quantity: 750,
            unit: 'g',
          ),
          const MealIngredientDraft(
            name: 'Penne pasta',
            quantity: 400,
            unit: 'g',
          ),
        ],
      );

      expect(edited.id, meal.id);
      expect(await service.getAllMealVariants(), hasLength(1));
      final detailMeal = (await service.getMealVariant(meal.id))!;
      expect(detailMeal.name, 'Pasta Bake + Turkey');
      expect(
        (await service.getMealFamily(meal.mealFamilyId))!.name,
        'Pasta Bake',
      );
      expect(
        (await service.getMealFamily(meal.mealFamilyId))!.mealType,
        MealType.lunch,
      );
      final recipe = await service.getIngredientsForMeal(meal.id);
      expect(
        recipe.map((line) => line.name),
        containsAll(['Beef mince', 'Penne pasta']),
      );
      expect(
        recipe.firstWhere((line) => line.name == 'Beef mince').quantity,
        750,
      );
    },
  );

  test('saveMeal removes recipe relations omitted from an edit', () async {
    final meal = await service.addMeal(
      familyName: 'Toast',
      mealType: MealType.breakfast,
    );
    final line = await service.addIngredientToMeal(
      mealVariantId: meal.id,
      ingredientName: 'Butter',
      quantity: 20,
      unit: 'g',
    );

    await service.saveMeal(
      mealVariantId: meal.id,
      familyName: 'Toast',
      mealType: MealType.breakfast,
      variantName: 'Toast',
      ingredients: const [],
    );

    expect(await service.getIngredientsForMeal(meal.id), isEmpty);
    // The shared ingredient is deliberately not deleted as a side effect.
    expect(await service.getIngredient(line.ingredient.id), isNotNull);
  });
}
