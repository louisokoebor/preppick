import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:preppick/models/models.dart';
import 'package:preppick/providers/shopping_history_provider.dart';
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
  late ShoppingHistoryProvider history;

  final now = DateTime.utc(2026, 3, 16);

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('preppick_history_test');
    database = DatabaseService(
      factory: databaseFactoryFfi,
      databaseName: '${tempDir.path}/preppick_test.db',
    );
    meals = MealService(database);
    planner = PlanningService(database, meals, random: Random(7));
    shopping = ShoppingService(database, meals, planner);
    history = ShoppingHistoryProvider(shopping, clock: () => now);

    final dinner = await meals.addMeal(
      familyName: 'Fried Rice',
      mealType: MealType.dinner,
      variantName: 'Fried Rice',
      now: now.subtract(const Duration(days: 90)),
    );
    await meals.addIngredientToMeal(
      mealVariantId: dinner.id,
      ingredientName: 'Rice',
      quantity: 500,
      unit: 'g',
      now: now,
    );
  });

  tearDown(() async {
    history.dispose();
    await database.close();
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  Future<WeeklyPlan> shoppedWeek(int weeksAgo) async {
    final at = now.subtract(Duration(days: 7 * weeksAgo));
    final result = await planner.generateWeeklyPlan(
      const AppSettings(breakfastCount: 0, lunchCount: 0, dinnerCount: 1),
      now: at,
    );
    final plan = await planner.confirmPlan(result.plan!.id, now: at);
    await shopping.generateFromPlan(plan.id);
    return plan;
  }

  test('loadHistory reads past weeks using the injected clock', () async {
    final past = await shoppedWeek(1);
    await shoppedWeek(0); // This week: not history yet.

    await history.loadHistory();

    expect(history.hasLoaded, isTrue);
    expect(history.error, isNull);
    expect(history.summaries.map((s) => s.plan.id), [past.id]);
  });

  test('openWeek loads one saved week', () async {
    final past = await shoppedWeek(2);

    final opening = history.openWeek(past.id);
    expect(history.isLoadingWeek, isTrue);
    await opening;

    expect(history.isLoadingWeek, isFalse);
    expect(history.weekPlanId, past.id);
    expect(history.week!.itemCount, 1);
  });

  test('opening a different week drops the previous one immediately', () async {
    final first = await shoppedWeek(2);
    final second = await shoppedWeek(1);
    await history.openWeek(first.id);

    final opening = history.openWeek(second.id);
    expect(history.week, isNull);
    await opening;
    expect(history.week!.plan.id, second.id);
  });

  test('a failed read is reported, not thrown', () async {
    await database.close();
    await tempDir.delete(recursive: true);
    // Point the provider at a service whose database cannot open.
    final broken = ShoppingHistoryProvider(
      ShoppingService(
        DatabaseService(
          factory: databaseFactoryFfi,
          databaseName: '/no/such/dir/preppick.db',
        ),
        meals,
        planner,
      ),
      clock: () => now,
    );
    addTearDown(broken.dispose);

    await broken.loadHistory();
    expect(broken.error, isNotNull);
    expect(broken.summaries, isEmpty);
  });
}
