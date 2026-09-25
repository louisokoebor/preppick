import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:preppick/models/models.dart';
import 'package:preppick/providers/shopping_provider.dart';
import 'package:preppick/services/database_service.dart';
import 'package:preppick/services/meal_service.dart';
import 'package:preppick/services/planning_service.dart';
import 'package:preppick/services/shopping_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late DatabaseService database;
  late MealService meals;
  late PlanningService planner;
  late ShoppingService shopping;
  late ShoppingProvider provider;

  /// A fixed Monday, so week boundaries are unambiguous.
  final now = DateTime.utc(2026, 3, 16);

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('preppick_shopping_prov');
    database = DatabaseService(
      factory: databaseFactoryFfi,
      databaseName: '${tempDir.path}/preppick_test.db',
    );
    meals = MealService(database);
    planner = PlanningService(database, meals, random: Random(7));
    shopping = ShoppingService(database, meals, planner);
    provider = ShoppingProvider(shopping);
  });

  tearDown(() async {
    provider.dispose();
    await database.close();
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  Future<MealVariant> addDinner(String name) => meals.addMeal(
    familyName: name,
    mealType: MealType.dinner,
    variantName: name,
    now: now.subtract(const Duration(days: 90)),
  );

  Future<void> addIngredient(
    MealVariant meal,
    String name, {
    double? quantity,
    String? unit,
    String? category,
  }) => meals.addIngredientToMeal(
    mealVariantId: meal.id,
    ingredientName: name,
    quantity: quantity,
    unit: unit,
    category: category,
    now: now,
  );

  Future<WeeklyPlan> confirmedPlanOf(int dinnerCount) async {
    final result = await planner.generateWeeklyPlan(
      AppSettings(breakfastCount: 0, lunchCount: 0, dinnerCount: dinnerCount),
      now: now,
    );
    return planner.confirmPlan(result.plan!.id, now: now);
  }

  /// A confirmed one-dinner week with a produce line, a protein line and a
  /// line whose amount was never recorded.
  Future<WeeklyPlan> seededPlan() async {
    final meal = await addDinner('Fried Rice');
    await addIngredient(
      meal,
      'Rice',
      quantity: 500,
      unit: 'g',
      category: IngredientCategory.pantry,
    );
    await addIngredient(
      meal,
      'Spring onions',
      quantity: 2,
      category: IngredientCategory.produce,
    );
    await addIngredient(meal, 'Chicken', category: IngredientCategory.protein);
    return confirmedPlanOf(1);
  }

  ShoppingItem lineFor(ShoppingProvider p, String name) =>
      p.items.firstWhere((item) => item.name == name);

  group('openForPlan', () {
    test('generates the list the first time and reports progress', () async {
      final plan = await seededPlan();
      await provider.openForPlan(plan.id);

      expect(provider.planId, plan.id);
      expect(provider.totalCount, 3);
      expect(provider.checkedCount, 0);
      expect(provider.isEmpty, isFalse);
      expect(provider.hasError, isFalse);
    });

    test('reopening loads the saved list rather than rebuilding it', () async {
      final plan = await seededPlan();
      await provider.openForPlan(plan.id);
      final firstIds = provider.items.map((i) => i.id).toList();

      await provider.toggleItem(lineFor(provider, 'Rice').id);

      final reopened = ShoppingProvider(shopping);
      addTearDown(reopened.dispose);
      await reopened.openForPlan(plan.id);

      // Same rows, same ids, and the tick survived — this is what makes
      // closing the app mid-shop safe.
      expect(reopened.items.map((i) => i.id).toList(), firstIds);
      expect(lineFor(reopened, 'Rice').isChecked, isTrue);
      expect(reopened.checkedCount, 1);
    });

    test(
      'records a failure rather than throwing when the plan is a draft',
      () async {
        final meal = await addDinner('Fried Rice');
        await addIngredient(meal, 'Rice', quantity: 500, unit: 'g');
        final result = await planner.generateWeeklyPlan(
          const AppSettings(breakfastCount: 0, lunchCount: 0, dinnerCount: 1),
          now: now,
        );

        await provider.openForPlan(result.plan!.id);

        expect(provider.hasError, isTrue);
        expect(provider.error, isA<ShoppingException>());
        expect(provider.items, isEmpty);
      },
    );

    test(
      'switching plans drops the previous week rather than mixing them',
      () async {
        final plan = await seededPlan();
        await provider.openForPlan(plan.id);
        expect(provider.totalCount, 3);

        await provider.openForPlan('no-such-plan');

        expect(provider.planId, 'no-such-plan');
        expect(provider.items, isEmpty);
      },
    );
  });

  group('grouping and filtering', () {
    test('groups into aisles in shopping order', () async {
      final plan = await seededPlan();
      await provider.openForPlan(plan.id);

      expect(provider.groups.map((g) => g.category).toList(), [
        IngredientCategory.produce,
        IngredientCategory.protein,
        IngredientCategory.pantry,
      ]);
      expect(
        provider.availableCategories,
        provider.groups.map((g) => g.category),
      );
    });

    test(
      'a filter narrows the groups without touching the loaded list',
      () async {
        final plan = await seededPlan();
        await provider.openForPlan(plan.id);

        provider.setCategoryFilter(IngredientCategory.protein);

        expect(provider.groups, hasLength(1));
        expect(provider.groups.single.category, IngredientCategory.protein);
        expect(provider.groups.single.items.single.name, 'Chicken');
        // The underlying list and its progress counters are unfiltered.
        expect(provider.totalCount, 3);
        expect(provider.availableCategories, hasLength(3));

        provider.setCategoryFilter(null);
        expect(provider.groups, hasLength(3));
      },
    );

    test('section counts track what is ticked', () async {
      final plan = await seededPlan();
      await provider.openForPlan(plan.id);
      await provider.toggleItem(lineFor(provider, 'Chicken').id);

      final protein = provider.groups.firstWhere(
        (g) => g.category == IngredientCategory.protein,
      );
      expect(protein.checkedCount, 1);
      expect(protein.isComplete, isTrue);
    });
  });

  group('toggleItem', () {
    test('persists immediately, with no save step', () async {
      final plan = await seededPlan();
      await provider.openForPlan(plan.id);
      final rice = lineFor(provider, 'Rice');

      expect(await provider.toggleItem(rice.id), isTrue);

      expect(lineFor(provider, 'Rice').isChecked, isTrue);
      // Straight from the database, not the provider's copy.
      expect((await shopping.getItem(rice.id))!.isChecked, isTrue);
      expect(provider.checkedCount, 1);
    });

    test('unticks again and reports completion', () async {
      final plan = await seededPlan();
      await provider.openForPlan(plan.id);
      for (final item in [...provider.items]) {
        await provider.toggleItem(item.id);
      }
      expect(provider.isComplete, isTrue);

      await provider.toggleItem(lineFor(provider, 'Rice').id);
      expect(provider.isComplete, isFalse);
      expect(provider.checkedCount, 2);
    });

    test('clearChecked unticks the whole week', () async {
      final plan = await seededPlan();
      await provider.openForPlan(plan.id);
      await provider.toggleItem(lineFor(provider, 'Rice').id);

      expect(await provider.clearChecked(), isTrue);

      expect(provider.checkedCount, 0);
      expect(provider.items.every((i) => !i.isChecked), isTrue);
    });

    test('an unknown id changes nothing', () async {
      final plan = await seededPlan();
      await provider.openForPlan(plan.id);

      expect(await provider.toggleItem('nope'), isFalse);
      expect(provider.checkedCount, 0);
    });
  });

  group('manual items', () {
    test('adds a line with no quantity when none was given', () async {
      final plan = await seededPlan();
      await provider.openForPlan(plan.id);

      expect(
        await provider.addItem(
          name: 'Bin bags',
          category: IngredientCategory.household,
        ),
        isTrue,
      );

      final added = lineFor(provider, 'Bin bags');
      expect(added.quantity, isNull);
      expect(added.isManual, isTrue);
      expect(provider.totalCount, 4);
      expect(
        provider.availableCategories,
        contains(IngredientCategory.household),
      );
    });

    test('keeps an amount when one was given', () async {
      final plan = await seededPlan();
      await provider.openForPlan(plan.id);
      await provider.addItem(name: 'Milk', quantity: 2, unit: 'litres');

      final milk = lineFor(provider, 'Milk');
      expect(milk.quantity, 2);
      expect(milk.unit, 'l');
    });

    test('a blank name is refused and recorded as an error', () async {
      final plan = await seededPlan();
      await provider.openForPlan(plan.id);

      expect(await provider.addItem(name: '   '), isFalse);
      expect(provider.error, isA<ShoppingException>());
      expect(provider.totalCount, 3);
    });

    test('deletes a manual line but not a generated one', () async {
      final plan = await seededPlan();
      await provider.openForPlan(plan.id);
      await provider.addItem(name: 'Bin bags');
      final manual = lineFor(provider, 'Bin bags');
      final generated = lineFor(provider, 'Rice');

      expect(await provider.deleteItem(manual.id), isTrue);
      expect(provider.items.where((i) => i.name == 'Bin bags'), isEmpty);

      expect(await provider.deleteItem(generated.id), isFalse);
      expect(provider.items.where((i) => i.name == 'Rice'), hasLength(1));
    });

    test('regenerate keeps manual lines and ticked progress', () async {
      final plan = await seededPlan();
      await provider.openForPlan(plan.id);
      await provider.addItem(name: 'Bin bags');
      await provider.toggleItem(lineFor(provider, 'Rice').id);

      expect(await provider.regenerate(), isTrue);

      expect(lineFor(provider, 'Bin bags').isManual, isTrue);
      expect(lineFor(provider, 'Rice').isChecked, isTrue);
    });
  });

  test('progress survives the app being closed and reopened', () async {
    final plan = await seededPlan();
    await provider.openForPlan(plan.id);
    // Five would be better, but this week only has three lines; tick every
    // one of them, which is the same journey.
    for (final item in [...provider.items]) {
      await provider.toggleItem(item.id);
    }
    expect(provider.isComplete, isTrue);

    // The nearest a test gets to force-closing the app: drop the connection
    // and every object above it, then come back to the same file with a new
    // stack, as a cold start does.
    await database.close();
    final reopenedDatabase = DatabaseService(
      factory: databaseFactoryFfi,
      databaseName: '${tempDir.path}/preppick_test.db',
    );
    final reopenedMeals = MealService(reopenedDatabase);
    final reopened = ShoppingProvider(
      ShoppingService(
        reopenedDatabase,
        reopenedMeals,
        PlanningService(reopenedDatabase, reopenedMeals),
      ),
    );
    addTearDown(() async {
      reopened.dispose();
      await reopenedDatabase.close();
    });

    await reopened.openForPlan(plan.id);

    expect(reopened.totalCount, 3);
    expect(reopened.checkedCount, 3);
    expect(reopened.isComplete, isTrue);
  });

  test('clear forgets the list without touching what is stored', () async {
    final plan = await seededPlan();
    await provider.openForPlan(plan.id);
    provider.clear();

    expect(provider.items, isEmpty);
    expect(provider.planId, isNull);
    expect(await shopping.loadShoppingList(plan.id), hasLength(3));
  });
}
