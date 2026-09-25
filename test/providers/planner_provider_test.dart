import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:preppick/models/models.dart';
import 'package:preppick/providers/planner_provider.dart';
import 'package:preppick/services/database_service.dart';
import 'package:preppick/services/meal_service.dart';
import 'package:preppick/services/planning_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// A planning service whose reads and writes fail, to exercise the provider's
/// error path. Extends rather than implements, because [PlanningService] has
/// private members no outside class could satisfy.
class _FailingPlanningService extends PlanningService {
  _FailingPlanningService(super.database, super.meals);

  @override
  Future<PlanGenerationResult> generateWeeklyPlan(
    AppSettings settings, {
    DateTime? now,
    DateTime? weekStart,
  }) async => throw StateError('database is gone');

  @override
  Future<WeeklyPlan?> getCurrentDraft({DateTime? now}) async =>
      throw StateError('database is gone');

  @override
  Future<WeeklyPlan?> getCurrentPlan({DateTime? now}) async =>
      throw StateError('database is gone');

  @override
  Future<List<WeeklyPlanDetail>> getPlanHistoryDetails({DateTime? now}) async =>
      throw StateError('database is gone');
}

void main() {
  sqfliteFfiInit();

  late Directory tempDir;
  late DatabaseService database;
  late MealService meals;
  late PlanningService service;
  late PlannerProvider provider;

  /// A fixed Monday, so the week the provider reports is unambiguous.
  final now = DateTime.utc(2026, 3, 16);

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('preppick_planner_test');
    database = DatabaseService(
      factory: databaseFactoryFfi,
      databaseName: '${tempDir.path}/preppick_test.db',
    );
    meals = MealService(database);
    service = PlanningService(database, meals, random: Random(7));
    provider = PlannerProvider(service, clock: () => now);
  });

  tearDown(() async {
    provider.dispose();
    await database.close();
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  Future<MealVariant> addMeal({
    required String family,
    required MealType type,
    String? protein,
  }) => meals.addMeal(
    familyName: family,
    mealType: type,
    variantName: family,
    protein: protein,
    now: now.subtract(const Duration(days: 60)),
  );

  /// Enough meals that a default week needs no rule relaxed.
  Future<void> seedLibrary() async {
    await addMeal(family: 'Breakfast Muffins', type: MealType.breakfast);
    await addMeal(family: 'Paninis', type: MealType.lunch);
    await addMeal(
      family: 'Lou Lou Spaghetti',
      type: MealType.dinner,
      protein: 'Chicken',
    );
    await addMeal(
      family: 'Jollof Rice',
      type: MealType.dinner,
      protein: 'Turkey',
    );
    await addMeal(
      family: 'Fried Rice',
      type: MealType.dinner,
      protein: 'Salmon',
    );
  }

  test('starts with no plan and this week showing', () {
    expect(provider.hasPlan, isFalse);
    expect(provider.items, isEmpty);
    expect(provider.shortageMessage, isNull);
    expect(provider.weekStart, DateTime.utc(2026, 3, 16));
  });

  test('generates a draft with one item per requested slot', () async {
    await seedLibrary();

    final generated = await provider.generatePlan(const AppSettings());

    expect(generated, isTrue);
    expect(provider.items, hasLength(4));
    expect(provider.currentPlan!.status, PlanStatus.draft);
    expect(provider.shortages, isEmpty);
    expect(provider.shortageMessage, isNull);
    // Every item resolves to a real meal the screen can name.
    for (final item in provider.items) {
      expect(provider.mealFor(item), isNotNull);
    }
    expect(provider.countOfType(MealType.dinner), 2);
    expect(provider.isBusy, isFalse);
  });

  test(
    'an empty library generates nothing and points at the library',
    () async {
      final generated = await provider.generatePlan(const AppSettings());

      expect(generated, isFalse);
      expect(provider.hasPlan, isFalse);
      expect(provider.lastOutcome, PlanGenerationOutcome.emptyLibrary);
      expect(provider.needsMeals, isTrue);
      expect(provider.shortageMessage, contains('meal library is empty'));
    },
  );

  test('zero meal counts generate nothing and say why', () async {
    await seedLibrary();

    final generated = await provider.generatePlan(
      const AppSettings(breakfastCount: 0, lunchCount: 0, dinnerCount: 0),
    );

    expect(generated, isFalse);
    expect(provider.lastOutcome, PlanGenerationOutcome.noMealsRequested);
    expect(provider.needsMeals, isFalse);
    expect(provider.shortageMessage, contains('zero'));
  });

  test('a library too small still plans, and explains the repeats', () async {
    await addMeal(family: 'Fish and Rice', type: MealType.dinner);

    final generated = await provider.generatePlan(
      const AppSettings(breakfastCount: 0, lunchCount: 0, dinnerCount: 3),
    );

    expect(generated, isTrue);
    expect(provider.items, hasLength(3));
    expect(provider.shortages, hasLength(1));
    expect(provider.shortageMessage, contains('3 dinners'));
    expect(provider.shortageMessage, contains('library has 1'));
  });

  test(
    'a category with no meals leaves its slots unfilled and says so',
    () async {
      await addMeal(family: 'Fish and Rice', type: MealType.dinner);

      await provider.generatePlan(
        const AppSettings(breakfastCount: 2, lunchCount: 0, dinnerCount: 1),
      );

      expect(provider.countOfType(MealType.breakfast), 0);
      expect(provider.countOfType(MealType.dinner), 1);
      expect(provider.shortageMessage, contains('no breakfast meals yet'));
    },
  );

  test('regenerating updates the same weekly draft row', () async {
    await seedLibrary();
    await provider.generatePlan(const AppSettings());
    final firstPlanId = provider.currentPlan!.id;

    final regenerated = await provider.regeneratePlan(const AppSettings());

    expect(regenerated, isTrue);
    expect(provider.currentPlan!.id, firstPlanId);
    expect(provider.currentPlan!.status, PlanStatus.draft);
    expect(provider.isConfirmed, isFalse);
    expect(await service.getPlanHistory(includeDrafts: true), hasLength(1));
  });

  test('swapping changes one slot and leaves the rest alone', () async {
    await seedLibrary();
    await provider.generatePlan(const AppSettings());
    final before = {
      for (final item in provider.items) item.id: item.mealVariantId,
    };
    final target = provider.items.firstWhere(
      (item) => item.mealType == MealType.dinner,
    );

    final swapped = await provider.swapMeal(target.id);

    expect(swapped, isTrue);
    for (final item in provider.items) {
      if (item.id == target.id) {
        expect(item.mealVariantId, isNot(before[item.id]));
        // The new meal is resolved, so the card can name it immediately.
        expect(provider.mealFor(item), isNotNull);
      } else {
        expect(item.mealVariantId, before[item.id]);
      }
    }
  });

  test(
    'swapping when there is no alternative fails without changing the plan',
    () async {
      await addMeal(family: 'Fish and Rice', type: MealType.dinner);
      await provider.generatePlan(
        const AppSettings(breakfastCount: 0, lunchCount: 0, dinnerCount: 1),
      );
      final item = provider.items.single;

      final swapped = await provider.swapMeal(item.id);

      expect(swapped, isFalse);
      expect(provider.error, isA<PlanningException>());
      expect(provider.items.single.mealVariantId, item.mealVariantId);
    },
  );

  test('swap candidates exclude the meal already in the slot', () async {
    await seedLibrary();
    await provider.generatePlan(const AppSettings());
    final item = provider.items.firstWhere(
      (item) => item.mealType == MealType.dinner,
    );

    final candidates = await provider.swapCandidates(item.id);

    expect(candidates, isNotEmpty);
    expect(
      candidates.map((meal) => meal.id),
      isNot(contains(item.mealVariantId)),
    );
  });

  test('confirming marks the plan and records the meals once', () async {
    await seedLibrary();
    await provider.generatePlan(const AppSettings());
    final plannedIds = provider.items.map((item) => item.mealVariantId).toSet();

    final confirmed = await provider.confirmPlan();

    expect(confirmed, isTrue);
    expect(provider.isConfirmed, isTrue);
    expect(provider.currentPlan!.confirmedAt, isNotNull);
    for (final id in plannedIds) {
      final meal = await meals.getMealVariant(id);
      expect(meal!.timesPlanned, 1);
      expect(meal.lastPlannedAt, isNotNull);
    }
  });

  test('confirming twice does not count the meals twice', () async {
    await seedLibrary();
    await provider.generatePlan(const AppSettings());
    final id = provider.items.first.mealVariantId;

    expect(await provider.confirmPlan(), isTrue);
    expect(await provider.confirmPlan(), isTrue);

    expect((await meals.getMealVariant(id))!.timesPlanned, 1);
  });

  test('confirming with no plan does nothing', () async {
    expect(await provider.confirmPlan(), isFalse);
  });

  test('reads back this week’s plan on load', () async {
    await seedLibrary();
    await service.generateWeeklyPlan(const AppSettings(), now: now);

    await provider.loadCurrentPlan();

    expect(provider.hasLoaded, isTrue);
    expect(provider.hasPlan, isTrue);
    expect(provider.items, hasLength(4));
  });

  test(
    'loads confirmed plan history without replacing the current draft',
    () async {
      await seedLibrary();
      final confirmed = await service.generateWeeklyPlan(
        const AppSettings(),
        now: now.subtract(const Duration(days: 7)),
      );
      await service.confirmPlan(
        confirmed.plan!.id,
        now: now.subtract(const Duration(days: 7)),
      );
      await provider.generatePlan(const AppSettings());
      final draftId = provider.currentPlan!.id;

      await provider.loadPlanHistory();

      expect(provider.hasLoadedHistory, isTrue);
      expect(provider.history.map((detail) => detail.plan.id), [
        confirmed.plan!.id,
      ]);
      expect(provider.currentPlan!.id, draftId);
      expect(provider.history.single.items, hasLength(4));
    },
  );

  test('a load with no draft leaves the provider empty but loaded', () async {
    await provider.loadCurrentDraft();

    expect(provider.hasLoaded, isTrue);
    expect(provider.hasPlan, isFalse);
    expect(provider.error, isNull);
  });

  test('the week shown follows the plan once one exists', () async {
    await seedLibrary();
    await provider.generatePlan(const AppSettings());

    expect(provider.weekStart, DateTime.utc(2026, 3, 16));
  });

  test('a failure is recorded rather than thrown', () async {
    final failing = PlannerProvider(
      _FailingPlanningService(database, meals),
      clock: () => now,
    );
    addTearDown(failing.dispose);

    expect(await failing.generatePlan(const AppSettings()), isFalse);
    expect(failing.error, isA<StateError>());

    await failing.loadCurrentDraft();
    expect(failing.error, isA<StateError>());
    expect(failing.hasLoaded, isTrue);

    await failing.loadPlanHistory();
    expect(failing.historyError, isA<StateError>());
    expect(failing.hasLoadedHistory, isTrue);
  });

  test('notifies listeners around a generation', () async {
    await seedLibrary();
    var notifications = 0;
    provider.addListener(() => notifications++);

    await provider.generatePlan(const AppSettings());

    // At least the "started" and "finished" edges, so a button can go busy
    // and come back.
    expect(notifications, greaterThanOrEqualTo(2));
  });

  test('clear forgets the plan in memory but not the stored draft', () async {
    await seedLibrary();
    await provider.generatePlan(const AppSettings());

    provider.clear();

    expect(provider.hasPlan, isFalse);
    expect(await service.getCurrentDraft(now: now), isNotNull);
  });
}
