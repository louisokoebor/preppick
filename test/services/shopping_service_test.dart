import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:preppick/models/models.dart';
import 'package:preppick/services/database_service.dart';
import 'package:preppick/services/meal_service.dart';
import 'package:preppick/services/planning_service.dart';
import 'package:preppick/services/shopping_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late Directory tempDir;
  late DatabaseService database;
  late MealService meals;
  late PlanningService planner;
  late ShoppingService shopping;

  /// A fixed Monday, so week boundaries in assertions are unambiguous.
  final now = DateTime.utc(2026, 3, 16);

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('preppick_shopping_test');
    database = DatabaseService(
      factory: databaseFactoryFfi,
      databaseName: '${tempDir.path}/preppick_test.db',
    );
    meals = MealService(database);
    planner = PlanningService(database, meals, random: Random(7));
    shopping = ShoppingService(database, meals, planner);
  });

  tearDown(() async {
    await database.close();
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  Future<MealVariant> addDinner(String name) => meals.addMeal(
    familyName: name,
    mealType: MealType.dinner,
    variantName: name,
    now: now.subtract(const Duration(days: 90)),
  );

  Future<MealRecipeLine> addIngredient(
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

  /// Plans exactly [dinnerCount] dinners and confirms the result, so the
  /// plan's membership is the whole dinner library and nothing is random.
  Future<WeeklyPlan> confirmedPlanOf(int dinnerCount) async {
    final result = await planner.generateWeeklyPlan(
      AppSettings(breakfastCount: 0, lunchCount: 0, dinnerCount: dinnerCount),
      now: now,
    );
    expect(result.hasPlan, isTrue);
    return planner.confirmPlan(result.plan!.id, now: now);
  }

  ShoppingItem lineFor(
    List<ShoppingItem> items,
    String name, {
    bool? quantified,
  }) => items.firstWhere(
    (item) =>
        item.name == name &&
        (quantified == null || (item.quantity != null) == quantified),
  );

  // ------------------------------------------------------------ aggregation

  group('generateFromPlan aggregation', () {
    test(
      'sums the same ingredient across two meals in the same unit',
      () async {
        final a = await addDinner('Fried Rice');
        final b = await addDinner('Jollof Rice');
        await addIngredient(
          a,
          'Chicken',
          quantity: 200,
          unit: 'g',
          category: IngredientCategory.protein,
        );
        await addIngredient(b, 'Chicken', quantity: 150, unit: 'g');

        final plan = await confirmedPlanOf(2);
        final items = await shopping.generateFromPlan(plan.id);

        final chicken = lineFor(items, 'Chicken');
        expect(chicken.quantity, 350);
        expect(chicken.unit, 'g');
        expect(items.where((i) => i.name == 'Chicken'), hasLength(1));
      },
    );

    test('normalises 500 g + 750 g to 1.25 kg', () async {
      final a = await addDinner('Fried Rice');
      final b = await addDinner('Jollof Rice');
      await addIngredient(a, 'Chicken', quantity: 500, unit: 'g');
      await addIngredient(b, 'Chicken', quantity: 750, unit: 'g');

      final plan = await confirmedPlanOf(2);
      final items = await shopping.generateFromPlan(plan.id);

      final chicken = lineFor(items, 'Chicken');
      expect(chicken.quantity, 1.25);
      expect(chicken.unit, 'kg');
    });

    test('keeps an unknown quantity on its own line rather than inventing '
        'or swallowing one', () async {
      final a = await addDinner('Fried Rice');
      final b = await addDinner('Jollof Rice');
      await addIngredient(a, 'Chicken', quantity: 500, unit: 'g');
      await addIngredient(b, 'Chicken'); // no amount ever recorded

      final plan = await confirmedPlanOf(2);
      final items = await shopping.generateFromPlan(plan.id);

      final chicken = items.where((i) => i.name == 'Chicken').toList();
      expect(chicken, hasLength(2));
      // The known amount is not inflated to cover the unknown one...
      expect(lineFor(items, 'Chicken', quantified: true).quantity, 500);
      // ...and the unknown one is still on the list, with no number.
      expect(lineFor(items, 'Chicken', quantified: false).quantity, isNull);
      // The quantified line reads first.
      expect(chicken.first.quantity, 500);
    });

    test(
      'an ingredient with no quantity anywhere makes one bare line',
      () async {
        final a = await addDinner('Fried Rice');
        final b = await addDinner('Jollof Rice');
        await addIngredient(a, 'Salt');
        await addIngredient(b, 'Salt');

        final plan = await confirmedPlanOf(2);
        final items = await shopping.generateFromPlan(plan.id);

        final salt = items.where((i) => i.name == 'Salt').toList();
        expect(salt, hasLength(1));
        expect(salt.single.quantity, isNull);
        expect(salt.single.unit, isNull);
      },
    );

    test('does not add amounts in units it cannot reconcile', () async {
      final a = await addDinner('Fried Rice');
      final b = await addDinner('Jollof Rice');
      await addIngredient(a, 'Stock', quantity: 300, unit: 'ml');
      await addIngredient(b, 'Stock', quantity: 2, unit: 'cube');

      final plan = await confirmedPlanOf(2);
      final items = await shopping.generateFromPlan(plan.id);

      final stock = items.where((i) => i.name == 'Stock').toList();
      expect(stock, hasLength(2));
      expect(
        stock.map((i) => '${i.quantity} ${i.unit}'),
        containsAll(['300.0 ml', '2.0 cube']),
      );
    });

    test('preserves each ingredient category', () async {
      final meal = await addDinner('Fried Rice');
      await addIngredient(
        meal,
        'Chicken',
        quantity: 1,
        unit: 'kg',
        category: IngredientCategory.protein,
      );
      await addIngredient(
        meal,
        'Peppers',
        quantity: 2,
        category: IngredientCategory.produce,
      );
      await addIngredient(meal, 'Soy Sauce', quantity: 50, unit: 'ml');

      final plan = await confirmedPlanOf(1);
      final items = await shopping.generateFromPlan(plan.id);

      expect(lineFor(items, 'Chicken').category, IngredientCategory.protein);
      expect(lineFor(items, 'Peppers').category, IngredientCategory.produce);
      // Never categorised, so it lands in the fallback rather than nowhere.
      expect(lineFor(items, 'Soy Sauce').category, IngredientCategory.other);
    });

    test('counts a meal once per slot it fills', () async {
      final meal = await addDinner('Fried Rice');
      await addIngredient(meal, 'Rice', quantity: 200, unit: 'g');

      // One dinner meal, two dinner slots: the planner must repeat it.
      final plan = await confirmedPlanOf(2);
      expect(await planner.getPlanItems(plan.id), hasLength(2));

      final items = await shopping.generateFromPlan(plan.id);
      expect(lineFor(items, 'Rice').quantity, 400);
    });

    test('includes cook-later meals in the whole-week shopping list', () async {
      final main = await addDinner('Fried Rice');
      final later = await addDinner('Fish + Rice');
      await addIngredient(main, 'Rice', quantity: 200, unit: 'g');
      await addIngredient(later, 'Salmon', quantity: 4, unit: 'unit');

      final result = await planner.generateWeeklyPlan(
        const AppSettings(breakfastCount: 0, lunchCount: 0, dinnerCount: 2),
        now: now,
      );
      final laterItem = result.items.firstWhere(
        (item) => item.mealVariantId == later.id,
      );
      await planner.updatePlanItemTiming(
        laterItem.id,
        prepTiming: PrepTiming.later,
        plannedCookDate: result.plan!.weekStart.add(const Duration(days: 1)),
        now: now,
      );
      final plan = await planner.confirmPlan(result.plan!.id, now: now);

      final items = await shopping.generateFromPlan(plan.id);

      expect(lineFor(items, 'Rice').quantity, 200);
      expect(lineFor(items, 'Salmon').quantity, 4);
    });

    test('orders the list by shopping category then name', () async {
      final meal = await addDinner('Fried Rice');
      await addIngredient(
        meal,
        'Rice',
        quantity: 200,
        unit: 'g',
        category: IngredientCategory.pantry,
      );
      await addIngredient(
        meal,
        'Chicken',
        quantity: 1,
        unit: 'kg',
        category: IngredientCategory.protein,
      );
      await addIngredient(
        meal,
        'Spring Onion',
        quantity: 1,
        category: IngredientCategory.produce,
      );
      await addIngredient(
        meal,
        'Peppers',
        quantity: 2,
        category: IngredientCategory.produce,
      );

      final plan = await confirmedPlanOf(1);
      final items = await shopping.generateFromPlan(plan.id);

      expect(items.map((i) => i.name), [
        'Peppers',
        'Spring Onion',
        'Chicken',
        'Rice',
      ]);
    });

    test('groups the saved list into ordered category sections', () async {
      final meal = await addDinner('Fried Rice');
      await addIngredient(
        meal,
        'Rice',
        quantity: 200,
        unit: 'g',
        category: IngredientCategory.pantry,
      );
      await addIngredient(
        meal,
        'Peppers',
        quantity: 2,
        category: IngredientCategory.produce,
      );

      final plan = await confirmedPlanOf(1);
      await shopping.generateFromPlan(plan.id);

      final groups = await shopping.loadGroupedShoppingList(plan.id);
      expect(groups.map((g) => g.category), [
        IngredientCategory.produce,
        IngredientCategory.pantry,
      ]);
      expect(groups.first.items.single.name, 'Peppers');
    });
  });

  // ------------------------------------------------------------ idempotency

  group('regeneration', () {
    test('generating twice does not duplicate rows', () async {
      final meal = await addDinner('Fried Rice');
      await addIngredient(meal, 'Rice', quantity: 200, unit: 'g');
      await addIngredient(meal, 'Chicken', quantity: 500, unit: 'g');

      final plan = await confirmedPlanOf(1);
      final first = await shopping.generateFromPlan(plan.id);
      final second = await shopping.generateFromPlan(plan.id);

      expect(first, hasLength(2));
      expect(second, hasLength(2));
      expect(await shopping.loadShoppingList(plan.id), hasLength(2));
    });

    test('an unchanged line keeps its id and its checked state', () async {
      final meal = await addDinner('Fried Rice');
      await addIngredient(meal, 'Rice', quantity: 200, unit: 'g');

      final plan = await confirmedPlanOf(1);
      final before = (await shopping.generateFromPlan(plan.id)).single;
      await shopping.toggleItem(before.id);

      final after = (await shopping.generateFromPlan(plan.id)).single;
      expect(after.id, before.id);
      expect(after.isChecked, isTrue);
    });

    test('picks up a recipe change without stranding the old line', () async {
      final meal = await addDinner('Fried Rice');
      final rice = await addIngredient(meal, 'Rice', quantity: 200, unit: 'g');

      final plan = await confirmedPlanOf(1);
      await shopping.generateFromPlan(plan.id);

      await meals.updateMealIngredient(rice.id, quantity: 350);
      final items = await shopping.generateFromPlan(plan.id);

      expect(items, hasLength(1));
      expect(items.single.quantity, 350);
    });

    test('manual items survive regeneration untouched', () async {
      final meal = await addDinner('Fried Rice');
      await addIngredient(meal, 'Rice', quantity: 200, unit: 'g');

      final plan = await confirmedPlanOf(1);
      await shopping.generateFromPlan(plan.id);
      final manual = await shopping.addManualItem(
        planId: plan.id,
        name: 'Bin bags',
        category: IngredientCategory.household,
      );
      await shopping.toggleItem(manual.id);

      final items = await shopping.generateFromPlan(plan.id);
      final reloaded = items.firstWhere((i) => i.id == manual.id);
      expect(reloaded.name, 'Bin bags');
      expect(reloaded.isManual, isTrue);
      expect(reloaded.isChecked, isTrue);
      expect(items, hasLength(2));
    });

    test('loading never generates', () async {
      final meal = await addDinner('Fried Rice');
      await addIngredient(meal, 'Rice', quantity: 200, unit: 'g');
      final plan = await confirmedPlanOf(1);

      expect(await shopping.loadShoppingList(plan.id), isEmpty);
      await shopping.generateFromPlan(plan.id);
      expect(await shopping.loadShoppingList(plan.id), hasLength(1));
      expect(await shopping.loadShoppingList(plan.id), hasLength(1));
    });
  });

  // ------------------------------------------------------------ persistence

  group('persistence', () {
    /// Reopens the database file to prove state survived a restart.
    Future<ShoppingService> reopen() async {
      await database.close();
      database = DatabaseService(
        factory: databaseFactoryFfi,
        databaseName: '${tempDir.path}/preppick_test.db',
      );
      meals = MealService(database);
      planner = PlanningService(database, meals, random: Random(7));
      return shopping = ShoppingService(database, meals, planner);
    }

    test('a checked item is still checked after a restart', () async {
      final meal = await addDinner('Fried Rice');
      await addIngredient(meal, 'Rice', quantity: 200, unit: 'g');
      final plan = await confirmedPlanOf(1);
      final item = (await shopping.generateFromPlan(plan.id)).single;
      await shopping.toggleItem(item.id);

      final reopened = await reopen();
      expect(
        (await reopened.loadShoppingList(plan.id)).single.isChecked,
        isTrue,
      );
    });

    test('toggle flips back, and can be set explicitly', () async {
      final meal = await addDinner('Fried Rice');
      await addIngredient(meal, 'Rice', quantity: 200, unit: 'g');
      final plan = await confirmedPlanOf(1);
      final item = (await shopping.generateFromPlan(plan.id)).single;

      expect((await shopping.toggleItem(item.id)).isChecked, isTrue);
      expect((await shopping.toggleItem(item.id)).isChecked, isFalse);
      expect(
        (await shopping.toggleItem(item.id, isChecked: true)).isChecked,
        isTrue,
      );
      // Setting it to what it already is is a no-op, not an error.
      expect(
        (await shopping.toggleItem(item.id, isChecked: true)).isChecked,
        isTrue,
      );
    });

    test('clearChecked unticks the whole list', () async {
      final meal = await addDinner('Fried Rice');
      await addIngredient(meal, 'Rice', quantity: 200, unit: 'g');
      final plan = await confirmedPlanOf(1);
      final item = (await shopping.generateFromPlan(plan.id)).single;
      await shopping.toggleItem(item.id);

      await shopping.clearChecked(plan.id);
      expect(
        (await shopping.loadShoppingList(plan.id)).every((i) => !i.isChecked),
        isTrue,
      );
    });
  });

  // ----------------------------------------------------------- manual items

  group('manual items', () {
    late WeeklyPlan plan;

    setUp(() async {
      final meal = await addDinner('Fried Rice');
      await addIngredient(meal, 'Rice', quantity: 200, unit: 'g');
      plan = await confirmedPlanOf(1);
      await shopping.generateFromPlan(plan.id);
    });

    test('are marked manual and carry no ingredient', () async {
      final item = await shopping.addManualItem(
        planId: plan.id,
        name: '  Foil  ',
        quantity: 2,
        unit: 'Rolls',
        category: IngredientCategory.household,
      );
      expect(item.isManual, isTrue);
      expect(item.ingredientId, isNull);
      expect(item.name, 'Foil');
      expect(item.unit, 'rolls');
    });

    test('reject an empty name', () async {
      expect(
        () => shopping.addManualItem(planId: plan.id, name: '   '),
        throwsA(isA<ShoppingException>()),
      );
    });

    test('cannot be added to a plan that does not exist', () async {
      expect(
        () => shopping.addManualItem(planId: 'nope', name: 'Foil'),
        throwsA(isA<ShoppingException>()),
      );
    });

    test('update persists and survives a reload', () async {
      final item = await shopping.addManualItem(
        planId: plan.id,
        name: 'Foil',
        quantity: 1,
      );
      await shopping.updateItem(
        item.id,
        name: 'Kitchen foil',
        quantity: 3,
        unit: 'rolls',
        category: IngredientCategory.household,
      );

      final reloaded = (await shopping.loadShoppingList(
        plan.id,
      )).firstWhere((i) => i.id == item.id);
      expect(reloaded.name, 'Kitchen foil');
      expect(reloaded.quantity, 3);
      expect(reloaded.unit, 'rolls');
      expect(reloaded.category, IngredientCategory.household);
      expect(reloaded.isManual, isTrue);
    });

    test('update can clear a quantity rather than only replace it', () async {
      final item = await shopping.addManualItem(
        planId: plan.id,
        name: 'Foil',
        quantity: 2,
        unit: 'rolls',
      );
      final cleared = await shopping.updateItem(
        item.id,
        clearQuantity: true,
        clearUnit: true,
      );
      expect(cleared.quantity, isNull);
      expect(cleared.unit, isNull);
    });

    test('update leaves a generated line alone', () async {
      final generated = (await shopping.loadShoppingList(
        plan.id,
      )).firstWhere((i) => !i.isManual);
      expect(
        () => shopping.updateItem(generated.id, name: 'Something else'),
        throwsA(isA<ShoppingException>()),
      );
    });

    test('delete removes a manual item', () async {
      final item = await shopping.addManualItem(planId: plan.id, name: 'Foil');
      await shopping.deleteManualItem(item.id);
      expect(await shopping.getItem(item.id), isNull);
      expect(await shopping.loadShoppingList(plan.id), hasLength(1));
    });

    test('delete refuses a generated line', () async {
      final generated = (await shopping.loadShoppingList(
        plan.id,
      )).firstWhere((i) => !i.isManual);
      expect(
        () => shopping.deleteManualItem(generated.id),
        throwsA(isA<ShoppingException>()),
      );
      expect(await shopping.getItem(generated.id), isNotNull);
    });
  });

  // ----------------------------------------------------------------- guards

  group('guards', () {
    test('cannot generate from a plan that does not exist', () async {
      expect(
        () => shopping.generateFromPlan('no-such-plan'),
        throwsA(isA<ShoppingException>()),
      );
    });

    test('cannot generate from an unconfirmed draft', () async {
      final meal = await addDinner('Fried Rice');
      await addIngredient(meal, 'Rice', quantity: 200, unit: 'g');
      final result = await planner.generateWeeklyPlan(
        const AppSettings(breakfastCount: 0, lunchCount: 0, dinnerCount: 1),
        now: now,
      );

      expect(
        () => shopping.generateFromPlan(result.plan!.id),
        throwsA(isA<ShoppingException>()),
      );
      // Nothing was written on the way out.
      expect(await shopping.loadShoppingList(result.plan!.id), isEmpty);

      // Confirming makes the same call succeed.
      await planner.confirmPlan(result.plan!.id, now: now);
      expect(await shopping.generateFromPlan(result.plan!.id), hasLength(1));
    });

    test('a confirmed plan whose meals have no recipes generates an empty '
        'list rather than failing', () async {
      await addDinner('Fried Rice');
      final plan = await confirmedPlanOf(1);
      expect(await shopping.generateFromPlan(plan.id), isEmpty);
    });

    test('toggling an item that does not exist throws', () async {
      expect(
        () => shopping.toggleItem('no-such-item'),
        throwsA(isA<ShoppingException>()),
      );
    });
  });

  // --------------------------------------------------------------- history

  group('shopping history', () {
    /// Plans and confirms one dinner for the week [weeksAgo] before [now].
    Future<WeeklyPlan> confirmedWeek(
      int weeksAgo, {
      bool confirm = true,
    }) async {
      final at = now.subtract(Duration(days: 7 * weeksAgo));
      final result = await planner.generateWeeklyPlan(
        const AppSettings(breakfastCount: 0, lunchCount: 0, dinnerCount: 1),
        now: at,
      );
      expect(result.hasPlan, isTrue);
      if (!confirm) return result.plan!;
      return planner.confirmPlan(result.plan!.id, now: at);
    }

    setUp(() async {
      final dinner = await addDinner('Fried Rice');
      await addIngredient(dinner, 'Rice', quantity: 500, unit: 'g');
      await addIngredient(dinner, 'Chicken', quantity: 400, unit: 'g');
    });

    test('lists previous confirmed weeks with a saved list, newest first, '
        'with their counts', () async {
      final older = await confirmedWeek(3);
      final newer = await confirmedWeek(1);
      final olderLines = await shopping.generateFromPlan(older.id);
      await shopping.generateFromPlan(newer.id);
      await shopping.toggleItem(olderLines.first.id);

      final history = await shopping.getShoppingHistory(now: now);

      expect(history.map((s) => s.plan.id), [newer.id, older.id]);
      expect(history.last.itemCount, 2);
      expect(history.last.checkedCount, 1);
      expect(history.first.checkedCount, 0);
    });

    test('leaves out the current week, drafts and weeks with no saved '
        'list', () async {
      final current = await confirmedWeek(0);
      await shopping.generateFromPlan(current.id);
      await confirmedWeek(1); // Confirmed, but its list was never built.
      await confirmedWeek(2, confirm: false); // Still a draft.

      expect(await shopping.getShoppingHistory(now: now), isEmpty);
    });

    test('reading a saved week returns its lines grouped and never '
        'generates one', () async {
      final shopped = await confirmedWeek(2);
      await shopping.generateFromPlan(shopped.id);
      final unshopped = await confirmedWeek(1);

      final saved = await shopping.getSavedShoppingList(shopped.id);
      expect(saved!.plan.id, shopped.id);
      expect(saved.itemCount, 2);
      expect(saved.groups.map((g) => g.category), isNotEmpty);

      final empty = await shopping.getSavedShoppingList(unshopped.id);
      expect(empty!.isEmpty, isTrue);
      // Still nothing saved: a past week is only ever read.
      expect(await shopping.loadShoppingList(unshopped.id), isEmpty);

      expect(await shopping.getSavedShoppingList('no-such-plan'), isNull);
    });
  });
}
