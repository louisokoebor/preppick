import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:preppick/models/models.dart';
import 'package:preppick/services/database_service.dart';
import 'package:preppick/services/meal_service.dart';
import 'package:preppick/services/planning_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late Directory tempDir;
  late DatabaseService database;
  late MealService meals;
  late PlanningService planner;

  /// A fixed Monday, so week boundaries in assertions are unambiguous.
  final now = DateTime.utc(2026, 3, 16);

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('preppick_planning_test');
    database = DatabaseService(
      factory: databaseFactoryFfi,
      databaseName: '${tempDir.path}/preppick_test.db',
    );
    meals = MealService(database);
    // A seeded Random keeps generation reproducible across runs while still
    // exercising the jitter path.
    planner = PlanningService(database, meals, random: Random(42));
  });

  tearDown(() async {
    await database.close();
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  /// Adds one meal, creating its family on demand.
  Future<MealVariant> addMeal({
    required String family,
    required MealType type,
    required String name,
    String? protein,
    int? estimatedMinutes,
  }) => meals.addMeal(
    familyName: family,
    mealType: type,
    variantName: name,
    protein: protein,
    estimatedMinutes: estimatedMinutes,
    now: now.subtract(const Duration(days: 90)),
  );

  /// A library with enough variety that no rule needs relaxing.
  Future<void> seedVariedLibrary() async {
    await addMeal(
      family: 'Breakfast Muffins',
      type: MealType.breakfast,
      name: 'Breakfast Muffins',
      protein: 'Egg',
    );
    await addMeal(
      family: 'Overnight Oats',
      type: MealType.breakfast,
      name: 'Overnight Oats',
    );
    await addMeal(family: 'Paninis', type: MealType.lunch, name: 'Paninis');
    await addMeal(
      family: 'Wraps',
      type: MealType.lunch,
      name: 'Chicken Wraps',
      protein: 'Chicken',
    );
    await addMeal(
      family: 'Lou Lou Spaghetti',
      type: MealType.dinner,
      name: 'Lou Lou Spaghetti + Chicken',
      protein: 'Chicken',
    );
    await addMeal(
      family: 'Lou Lou Spaghetti',
      type: MealType.dinner,
      name: 'Lou Lou Spaghetti + Turkey',
      protein: 'Turkey',
    );
    await addMeal(
      family: 'Fried Rice',
      type: MealType.dinner,
      name: 'Fried Rice + Chicken',
      protein: 'Chicken',
    );
    await addMeal(
      family: 'Jollof Rice',
      type: MealType.dinner,
      name: 'Jollof Rice + Turkey',
      protein: 'Turkey',
    );
    await addMeal(
      family: 'Fish and Rice',
      type: MealType.dinner,
      name: 'Fish + Rice',
      protein: 'Salmon',
    );
  }

  Future<MealVariant> reload(String id) async =>
      (await meals.getMealVariant(id))!;

  Future<MealFamily> familyOf(MealVariant meal) async =>
      (await meals.getMealFamily(meal.mealFamilyId))!;

  const settings = AppSettings(
    breakfastCount: 1,
    lunchCount: 1,
    dinnerCount: 2,
  );

  group('generateWeeklyPlan', () {
    test('produces exactly the requested number of slots', () async {
      await seedVariedLibrary();

      final result = await planner.generateWeeklyPlan(settings, now: now);

      expect(result.outcome, PlanGenerationOutcome.generated);
      expect(result.items, hasLength(settings.totalMeals));
      expect(result.shortages, isEmpty);
    });

    test('gives every item the meal type its slot asks for', () async {
      await seedVariedLibrary();

      final result = await planner.generateWeeklyPlan(settings, now: now);

      for (final item in result.items) {
        final meal = await reload(item.mealVariantId);
        expect((await familyOf(meal)).mealType, item.mealType);
      }
    });

    test('numbers slots of a type from zero without gaps', () async {
      await seedVariedLibrary();

      final result = await planner.generateWeeklyPlan(
        const AppSettings(breakfastCount: 0, lunchCount: 0, dinnerCount: 3),
        now: now,
      );

      expect(result.items.map((item) => item.slotIndex), [0, 1, 2]);
    });

    test('does not repeat a meal family when alternatives exist', () async {
      await seedVariedLibrary();

      final result = await planner.generateWeeklyPlan(
        const AppSettings(breakfastCount: 0, lunchCount: 0, dinnerCount: 4),
        now: now,
      );

      final families = <String>[];
      for (final item in result.items) {
        families.add((await reload(item.mealVariantId)).mealFamilyId);
      }
      expect(families.toSet(), hasLength(4));
    });

    test(
      'does not repeat a protein within a category when it can avoid it',
      () async {
        await seedVariedLibrary();

        final result = await planner.generateWeeklyPlan(
          const AppSettings(breakfastCount: 0, lunchCount: 0, dinnerCount: 3),
          now: now,
        );

        final proteins = <String?>[];
        for (final item in result.items) {
          proteins.add((await reload(item.mealVariantId)).protein);
        }
        expect(proteins.whereType<String>().toSet(), hasLength(3));
      },
    );

    test('prefers meals that have not been eaten recently', () async {
      await seedVariedLibrary();

      // Confirm one week, then plan the next. The dinners just eaten should
      // give way to the ones that were not.
      final first = await planner.generateWeeklyPlan(
        const AppSettings(breakfastCount: 0, lunchCount: 0, dinnerCount: 2),
        now: now,
      );
      await planner.confirmPlan(first.plan!.id, now: now);
      final eaten = first.items.map((item) => item.mealVariantId).toSet();

      final second = await planner.generateWeeklyPlan(
        const AppSettings(breakfastCount: 0, lunchCount: 0, dinnerCount: 2),
        now: now.add(const Duration(days: 7)),
      );

      expect(
        second.items.map((item) => item.mealVariantId).toSet(),
        isNot(anyElement(isIn(eaten))),
      );
    });

    test(
      'relaxes rather than fails when only one eligible meal exists',
      () async {
        await addMeal(
          family: 'Fish and Rice',
          type: MealType.dinner,
          name: 'Fish + Rice',
          protein: 'Salmon',
        );

        final result = await planner.generateWeeklyPlan(
          const AppSettings(breakfastCount: 0, lunchCount: 0, dinnerCount: 3),
          now: now,
        );

        expect(result.outcome, PlanGenerationOutcome.generatedWithShortages);
        expect(result.items, hasLength(3), reason: 'the week is still filled');
        expect(
          result.items.map((item) => item.mealVariantId).toSet(),
          hasLength(1),
          reason: 'the one meal repeats instead of the plan failing',
        );
        final shortage = result.shortages.single;
        expect(shortage.mealType, MealType.dinner);
        expect(shortage.usedRepeats, isTrue);
        expect(shortage.isUnfilled, isFalse);
      },
    );

    test('a breakfast count of zero produces no breakfast items', () async {
      await seedVariedLibrary();

      final result = await planner.generateWeeklyPlan(
        const AppSettings(breakfastCount: 0, lunchCount: 1, dinnerCount: 2),
        now: now,
      );

      expect(
        result.items.where((item) => item.mealType == MealType.breakfast),
        isEmpty,
      );
      expect(result.items, hasLength(3));
      expect(result.shortages, isEmpty);
    });

    test('persists the draft and its items so they survive a reload', () async {
      await seedVariedLibrary();

      final result = await planner.generateWeeklyPlan(settings, now: now);
      final reloaded = await planner.getPlanWithItems(result.plan!.id);

      expect(reloaded!.plan.status, PlanStatus.draft);
      expect(reloaded.plan.confirmedAt, isNull);
      expect(reloaded.plan.weekStart, DateTime.utc(2026, 3, 16));
      expect(reloaded.items, hasLength(settings.totalMeals));
      expect(reloaded.mealsById.values, isNotEmpty);
    });

    test('orders items breakfast, then lunch, then dinner', () async {
      await seedVariedLibrary();

      final result = await planner.generateWeeklyPlan(settings, now: now);
      final detail = await planner.getPlanWithItems(result.plan!.id);

      expect(detail!.items.map((item) => item.mealType), [
        MealType.breakfast,
        MealType.lunch,
        MealType.dinner,
        MealType.dinner,
      ]);
    });

    test('never plans an archived meal', () async {
      final keep = await addMeal(
        family: 'Fried Rice',
        type: MealType.dinner,
        name: 'Fried Rice + Chicken',
        protein: 'Chicken',
      );
      final gone = await addMeal(
        family: 'Burgers',
        type: MealType.dinner,
        name: 'Burger + Sweet Potato',
        protein: 'Beef',
      );
      await meals.archiveMealVariant(gone.id, now: now);

      final result = await planner.generateWeeklyPlan(
        const AppSettings(breakfastCount: 0, lunchCount: 0, dinnerCount: 2),
        now: now,
      );

      expect(result.items.map((item) => item.mealVariantId).toSet(), {keep.id});
    });
  });

  group('regenerating a draft', () {
    test('does not increment timesPlanned', () async {
      await seedVariedLibrary();

      for (var i = 0; i < 5; i++) {
        await planner.generateWeeklyPlan(settings, now: now);
      }

      for (final meal in await meals.getAllMealVariants()) {
        expect(meal.timesPlanned, 0, reason: '${meal.name} was never eaten');
        expect(meal.lastPlannedAt, isNull);
      }
    });

    test(
      'updates the same weekly draft row rather than piling drafts up',
      () async {
        await seedVariedLibrary();

        final first = await planner.generateWeeklyPlan(settings, now: now);
        final second = await planner.generateWeeklyPlan(settings, now: now);

        expect(second.plan!.id, first.plan!.id);
        expect(await planner.getPlan(first.plan!.id), isNotNull);
        expect(await planner.getPlanHistory(includeDrafts: true), hasLength(1));
      },
    );

    test(
      'does not create a draft beside a confirmed plan for the same week',
      () async {
        await seedVariedLibrary();

        final confirmedPlan = await planner.generateWeeklyPlan(
          settings,
          now: now,
        );
        await planner.confirmPlan(confirmedPlan.plan!.id, now: now);
        await planner.generateWeeklyPlan(settings, now: now);

        final kept = await planner.getPlan(confirmedPlan.plan!.id);
        expect(kept, isNotNull);
        expect(kept!.status, PlanStatus.confirmed);
        expect(await planner.getPlanHistory(includeDrafts: true), hasLength(1));
      },
    );
  });

  group('swapMeal', () {
    test('changes only the targeted slot', () async {
      await seedVariedLibrary();
      final result = await planner.generateWeeklyPlan(settings, now: now);
      final target = result.items.firstWhere(
        (item) => item.mealType == MealType.dinner && item.slotIndex == 0,
      );
      final before = {
        for (final item in result.items) item.id: item.mealVariantId,
      };

      final swapped = await planner.swapMeal(target.id, now: now);

      expect(swapped.mealVariantId, isNot(before[target.id]));
      final after = await planner.getPlanItems(result.plan!.id);
      for (final item in after.where((item) => item.id != target.id)) {
        expect(item.mealVariantId, before[item.id]);
      }
      expect(after, hasLength(settings.totalMeals));
    });

    test('honours an explicit replacement chosen in the swap sheet', () async {
      await seedVariedLibrary();
      final result = await planner.generateWeeklyPlan(settings, now: now);
      final target = result.items.firstWhere(
        (item) => item.mealType == MealType.dinner,
      );
      final wanted = (await planner.getSwapCandidates(
        target.id,
        now: now,
      )).last;

      final swapped = await planner.swapMeal(
        target.id,
        replacementMealVariantId: wanted.id,
        now: now,
      );

      expect(swapped.mealVariantId, wanted.id);
      expect(swapped.slotIndex, target.slotIndex);
      expect(swapped.mealType, target.mealType);
    });

    test('rejects a replacement of the wrong meal type', () async {
      await seedVariedLibrary();
      final result = await planner.generateWeeklyPlan(settings, now: now);
      final dinnerSlot = result.items.firstWhere(
        (item) => item.mealType == MealType.dinner,
      );
      final breakfast = (await meals.getMealsByType(MealType.breakfast)).first;

      expect(
        () => planner.swapMeal(
          dinnerSlot.id,
          replacementMealVariantId: breakfast.id,
        ),
        throwsA(isA<PlanningException>()),
      );
    });

    test('never offers the meal already in the slot', () async {
      await seedVariedLibrary();
      final result = await planner.generateWeeklyPlan(settings, now: now);
      final target = result.items.firstWhere(
        (item) => item.mealType == MealType.dinner,
      );

      final candidates = await planner.getSwapCandidates(target.id, now: now);

      expect(
        candidates.map((meal) => meal.id),
        isNot(contains(target.mealVariantId)),
      );
    });

    test(
      'ranks candidates that keep the rest of the week varied first',
      () async {
        await seedVariedLibrary();
        final result = await planner.generateWeeklyPlan(
          const AppSettings(breakfastCount: 0, lunchCount: 0, dinnerCount: 2),
          now: now,
        );
        final target = result.items.first;
        final otherMealId = result.items.last.mealVariantId;
        final otherFamily = (await reload(otherMealId)).mealFamilyId;

        final candidates = await planner.getSwapCandidates(target.id, now: now);

        expect(candidates.first.mealFamilyId, isNot(otherFamily));
      },
    );

    test('edits a confirmed plan in place', () async {
      await seedVariedLibrary();
      final result = await planner.generateWeeklyPlan(settings, now: now);
      await planner.confirmPlan(result.plan!.id, now: now);
      final before = await planner.getPlan(result.plan!.id);

      final swapped = await planner.swapMeal(
        result.items.first.id,
        now: now.add(const Duration(hours: 2)),
      );

      final after = await planner.getPlan(result.plan!.id);
      expect(swapped.weeklyPlanId, result.plan!.id);
      expect(after!.id, before!.id);
      expect(after.status, PlanStatus.confirmed);
      expect(after.updatedAt, now.add(const Duration(hours: 2)));
      expect(await planner.getPlanHistory(includeDrafts: true), hasLength(1));
    });

    test('reports a clear error when there is nothing to swap to', () async {
      await addMeal(
        family: 'Fish and Rice',
        type: MealType.dinner,
        name: 'Fish + Rice',
      );
      final result = await planner.generateWeeklyPlan(
        const AppSettings(breakfastCount: 0, lunchCount: 0, dinnerCount: 1),
        now: now,
      );

      expect(
        () => planner.swapMeal(result.items.single.id),
        throwsA(isA<PlanningException>()),
      );
    });

    test('only ever offers meals of the slot\'s own type', () async {
      await seedVariedLibrary();
      final result = await planner.generateWeeklyPlan(settings, now: now);

      for (final item in result.items) {
        final candidates = await planner.getSwapCandidates(item.id, now: now);
        expect(candidates, isNotEmpty);
        for (final meal in candidates) {
          final family = await meals.getMealFamily(meal.mealFamilyId);
          expect(family!.mealType, item.mealType);
        }
      }
    });

    test('survives a reload, because the swap is written not cached', () async {
      await seedVariedLibrary();
      final result = await planner.generateWeeklyPlan(settings, now: now);
      final target = result.items.firstWhere(
        (item) => item.mealType == MealType.dinner,
      );
      final swapped = await planner.swapMeal(target.id, now: now);

      // A second service over the same file is what a restart looks like.
      final reopened = PlanningService(database, meals, random: Random(42));
      final reloaded = await reopened.getPlanItems(result.plan!.id);

      expect(
        reloaded.firstWhere((item) => item.id == target.id).mealVariantId,
        swapped.mealVariantId,
      );
    });

    test('writes no planning history until the plan is confirmed', () async {
      await seedVariedLibrary();
      final result = await planner.generateWeeklyPlan(settings, now: now);
      final target = result.items.firstWhere(
        (item) => item.mealType == MealType.dinner,
      );

      final swapped = await planner.swapMeal(target.id, now: now);

      // Neither the meal swapped out nor the one swapped in has been eaten
      // yet, so neither counter may move.
      for (final id in {target.mealVariantId, swapped.mealVariantId}) {
        final meal = await reload(id);
        expect(meal.timesPlanned, 0);
        expect(meal.lastPlannedAt, isNull);
      }
    });

    test('reports a clear error for an unknown plan item', () async {
      expect(
        () => planner.swapMeal('no-such-item'),
        throwsA(isA<PlanningException>()),
      );
    });
  });

  group('confirmPlan', () {
    test('marks the plan confirmed and stamps confirmedAt once', () async {
      await seedVariedLibrary();
      final result = await planner.generateWeeklyPlan(settings, now: now);

      final confirmed = await planner.confirmPlan(result.plan!.id, now: now);

      expect(confirmed.status, PlanStatus.confirmed);
      expect(confirmed.confirmedAt, now);
    });

    test(
      'increments timesPlanned exactly once for each planned meal',
      () async {
        await seedVariedLibrary();
        final result = await planner.generateWeeklyPlan(settings, now: now);

        await planner.confirmPlan(result.plan!.id, now: now);

        final planned = result.items.map((item) => item.mealVariantId).toSet();
        for (final meal in await meals.getAllMealVariants()) {
          final expected = planned.contains(meal.id) ? 1 : 0;
          expect(meal.timesPlanned, expected, reason: meal.name);
          expect(meal.lastPlannedAt, planned.contains(meal.id) ? now : isNull);
        }
      },
    );

    test('counts a meal filling two slots once, not twice', () async {
      final only = await addMeal(
        family: 'Fish and Rice',
        type: MealType.dinner,
        name: 'Fish + Rice',
      );
      final result = await planner.generateWeeklyPlan(
        const AppSettings(breakfastCount: 0, lunchCount: 0, dinnerCount: 2),
        now: now,
      );

      await planner.confirmPlan(result.plan!.id, now: now);

      expect(result.items, hasLength(2));
      expect((await reload(only.id)).timesPlanned, 1);
    });

    test('confirming the same plan twice does not double-increment', () async {
      await seedVariedLibrary();
      final result = await planner.generateWeeklyPlan(settings, now: now);

      final first = await planner.confirmPlan(result.plan!.id, now: now);
      final second = await planner.confirmPlan(
        result.plan!.id,
        now: now.add(const Duration(days: 1)),
      );

      expect(
        second.confirmedAt,
        first.confirmedAt,
        reason: 'confirmedAt is stamped once and never moves',
      );
      final planned = result.items.map((item) => item.mealVariantId).toSet();
      for (final id in planned) {
        expect((await reload(id)).timesPlanned, 1);
      }
    });

    test('concurrent confirmations still increment only once', () async {
      await seedVariedLibrary();
      final result = await planner.generateWeeklyPlan(settings, now: now);

      await Future.wait([
        planner.confirmPlan(result.plan!.id, now: now),
        planner.confirmPlan(result.plan!.id, now: now),
      ]);

      for (final id in result.items.map((item) => item.mealVariantId).toSet()) {
        expect((await reload(id)).timesPlanned, 1);
      }
    });

    test('reports a clear error for an unknown plan', () async {
      expect(
        () => planner.confirmPlan('no-such-plan'),
        throwsA(isA<PlanningException>()),
      );
    });
  });

  group('getPlanHistory', () {
    test('returns confirmed plans newest week first, hiding drafts', () async {
      await seedVariedLibrary();

      final week1 = await planner.generateWeeklyPlan(settings, now: now);
      await planner.confirmPlan(week1.plan!.id, now: now);
      final week2 = await planner.generateWeeklyPlan(
        settings,
        now: now.add(const Duration(days: 7)),
      );
      await planner.confirmPlan(
        week2.plan!.id,
        now: now.add(const Duration(days: 7)),
      );
      // A third, still-draft week that history must not show.
      await planner.generateWeeklyPlan(
        settings,
        now: now.add(const Duration(days: 14)),
      );

      final history = await planner.getPlanHistory(
        now: now.add(const Duration(days: 21)),
      );

      expect(history.map((plan) => plan.id), [week2.plan!.id, week1.plan!.id]);
      expect(await planner.getPlanHistory(includeDrafts: true), hasLength(3));
    });

    test('hides the current week from history until it has passed', () async {
      await seedVariedLibrary();

      final current = await planner.generateWeeklyPlan(settings, now: now);
      await planner.confirmPlan(current.plan!.id, now: now);

      expect(await planner.getPlanHistory(now: now), isEmpty);
      expect(
        (await planner.getPlanHistory(
          now: now.add(const Duration(days: 7)),
        )).map((plan) => plan.id),
        [current.plan!.id],
      );
    });

    test('is empty before anything is confirmed', () async {
      await seedVariedLibrary();
      await planner.generateWeeklyPlan(settings, now: now);

      expect(await planner.getPlanHistory(), isEmpty);
    });

    test(
      'persists multiple confirmed weeks as resolved history details',
      () async {
        await seedVariedLibrary();

        final first = await planner.generateWeeklyPlan(settings, now: now);
        await planner.confirmPlan(first.plan!.id, now: now);
        final second = await planner.generateWeeklyPlan(
          settings,
          now: now.add(const Duration(days: 7)),
        );
        await planner.confirmPlan(
          second.plan!.id,
          now: now.add(const Duration(days: 7)),
        );

        final history = await planner.getPlanHistoryDetails(
          now: now.add(const Duration(days: 14)),
        );

        expect(history.map((detail) => detail.plan.id), [
          second.plan!.id,
          first.plan!.id,
        ]);
        expect(history.expand((detail) => detail.items), hasLength(8));
        for (final detail in history) {
          for (final item in detail.items) {
            expect(detail.mealFor(item), isNotNull);
          }
        }
      },
    );

    test(
      'plan detail returns the correct items for one historic plan',
      () async {
        await seedVariedLibrary();
        final result = await planner.generateWeeklyPlan(settings, now: now);
        await planner.confirmPlan(result.plan!.id, now: now);

        final detail = await planner.getPlanWithItems(result.plan!.id);

        expect(detail, isNotNull);
        expect(detail!.plan.id, result.plan!.id);
        expect(detail.items.map((item) => item.id), [
          for (final item in result.items) item.id,
        ]);
        expect(detail.items.map((item) => item.mealVariantId), [
          for (final item in result.items) item.mealVariantId,
        ]);
      },
    );
  });

  group('edge cases', () {
    test(
      'an empty meal library returns a controlled result, saving nothing',
      () async {
        final result = await planner.generateWeeklyPlan(settings, now: now);

        expect(result.outcome, PlanGenerationOutcome.emptyLibrary);
        expect(result.hasPlan, isFalse);
        expect(result.items, isEmpty);
        expect(await planner.getPlanHistory(includeDrafts: true), isEmpty);
      },
    );

    test(
      'no dinner meals but a dinner count reports a clear shortage',
      () async {
        await addMeal(
          family: 'Breakfast Muffins',
          type: MealType.breakfast,
          name: 'Breakfast Muffins',
        );

        final result = await planner.generateWeeklyPlan(
          const AppSettings(breakfastCount: 1, lunchCount: 0, dinnerCount: 2),
          now: now,
        );

        expect(result.outcome, PlanGenerationOutcome.generatedWithShortages);
        final shortage = result.shortages.single;
        expect(shortage.mealType, MealType.dinner);
        expect(shortage.requested, 2);
        expect(shortage.available, 0);
        expect(shortage.filled, 0);
        expect(shortage.isUnfilled, isTrue);
        // The breakfast that *could* be planned still is.
        expect(result.items.single.mealType, MealType.breakfast);
      },
    );

    test('all counts zero saves no plan and cannot be confirmed', () async {
      await seedVariedLibrary();

      final result = await planner.generateWeeklyPlan(
        const AppSettings(breakfastCount: 0, lunchCount: 0, dinnerCount: 0),
        now: now,
      );

      expect(result.outcome, PlanGenerationOutcome.noMealsRequested);
      expect(result.hasPlan, isFalse);
      expect(await planner.getPlanHistory(includeDrafts: true), isEmpty);
    });

    test('a plan with no items cannot be confirmed', () async {
      await addMeal(
        family: 'Breakfast Muffins',
        type: MealType.breakfast,
        name: 'Breakfast Muffins',
      );
      // Only dinners requested, and there are none: a plan row with no items.
      final result = await planner.generateWeeklyPlan(
        const AppSettings(breakfastCount: 0, lunchCount: 0, dinnerCount: 2),
        now: now,
      );

      expect(result.items, isEmpty);
      expect(
        () => planner.confirmPlan(result.plan!.id, now: now),
        throwsA(isA<PlanningException>()),
      );
    });

    test('getPlanWithItems returns null for an unknown plan', () async {
      expect(await planner.getPlanWithItems('no-such-plan'), isNull);
    });

    test('deleteDraft removes a draft but protects a confirmed plan', () async {
      await seedVariedLibrary();
      final draft = await planner.generateWeeklyPlan(settings, now: now);
      final confirmedWeek = await planner.generateWeeklyPlan(
        settings,
        now: now.add(const Duration(days: 7)),
      );
      await planner.confirmPlan(
        confirmedWeek.plan!.id,
        now: now.add(const Duration(days: 7)),
      );

      await planner.deleteDraft(draft.plan!.id);

      expect(await planner.getPlan(draft.plan!.id), isNull);
      expect(
        () => planner.deleteDraft(confirmedWeek.plan!.id),
        throwsA(isA<PlanningException>()),
      );
    });

    test('getCurrentDraft finds this week and ignores other weeks', () async {
      await seedVariedLibrary();
      final draft = await planner.generateWeeklyPlan(settings, now: now);

      expect((await planner.getCurrentDraft(now: now))!.id, draft.plan!.id);
      expect(
        await planner.getCurrentDraft(now: now.add(const Duration(days: 7))),
        isNull,
      );
    });
  });

  group('prep timing', () {
    test('meals without a time can still be planned', () async {
      await addMeal(
        family: 'Fish and Rice',
        type: MealType.dinner,
        name: 'Fish + Rice',
      );

      final result = await planner.generateWeeklyPlan(
        const AppSettings(breakfastCount: 0, lunchCount: 0, dinnerCount: 1),
        now: now,
      );

      final detail = await planner.getPlanWithItems(result.plan!.id);
      final meal = detail!.mealFor(detail.items.single)!;
      expect(meal.estimatedMinutes, isNull);
      expect(detail.items.single.prepTiming, PrepTiming.mainPrep);
    });

    test(
      'stores prep-session estimate separately from meal time totals',
      () async {
        await addMeal(
          family: 'A',
          type: MealType.dinner,
          name: 'Meal A',
          estimatedMinutes: 30,
        );
        await addMeal(
          family: 'B',
          type: MealType.dinner,
          name: 'Meal B',
          estimatedMinutes: 45,
        );
        await addMeal(
          family: 'C',
          type: MealType.dinner,
          name: 'Meal C',
          estimatedMinutes: 60,
        );
        final result = await planner.generateWeeklyPlan(
          const AppSettings(breakfastCount: 0, lunchCount: 0, dinnerCount: 3),
          now: now,
        );

        await planner.updatePrepSessionEstimate(
          result.plan!.id,
          estimatedPrepMinutes: 90,
          now: now,
        );
        final detail = await planner.getPlanWithItems(result.plan!.id);
        final mealTotal = detail!.items
            .map((item) => detail.mealFor(item)!.estimatedMinutes!)
            .fold<int>(0, (total, minutes) => total + minutes);

        expect(mealTotal, 135);
        expect(detail.plan.estimatedPrepMinutes, 90);
      },
    );

    test('stores cook-later timing on one plan item only', () async {
      await seedVariedLibrary();
      final result = await planner.generateWeeklyPlan(settings, now: now);
      final item = result.items.firstWhere(
        (item) => item.mealType == MealType.dinner,
      );
      final tuesday = result.plan!.weekStart.add(const Duration(days: 1));

      await planner.updatePlanItemTiming(
        item.id,
        prepTiming: PrepTiming.later,
        plannedCookDate: tuesday,
        now: now,
      );

      final items = await planner.getPlanItems(result.plan!.id);
      final updated = items.firstWhere((candidate) => candidate.id == item.id);
      expect(updated.prepTiming, PrepTiming.later);
      expect(updated.plannedCookDate, tuesday);
      expect(
        items.where(
          (candidate) =>
              candidate.id != item.id &&
              candidate.prepTiming == PrepTiming.mainPrep,
        ),
        isNotEmpty,
      );
    });

    test(
      'the same meal can have different timing in different weeks',
      () async {
        final meal = await addMeal(
          family: 'Fish and Rice',
          type: MealType.dinner,
          name: 'Fish + Rice',
        );
        final first = await planner.generateWeeklyPlan(
          const AppSettings(breakfastCount: 0, lunchCount: 0, dinnerCount: 1),
          now: now,
        );
        final second = await planner.generateWeeklyPlan(
          const AppSettings(breakfastCount: 0, lunchCount: 0, dinnerCount: 1),
          now: now.add(const Duration(days: 7)),
        );

        expect(first.items.single.mealVariantId, meal.id);
        expect(second.items.single.mealVariantId, meal.id);
        await planner.updatePlanItemTiming(
          second.items.single.id,
          prepTiming: PrepTiming.later,
          plannedCookDate: second.plan!.weekStart.add(const Duration(days: 1)),
          now: now,
        );

        expect(
          (await planner.getPlanItems(first.plan!.id)).single.prepTiming,
          PrepTiming.mainPrep,
        );
        expect(
          (await planner.getPlanItems(second.plan!.id)).single.prepTiming,
          PrepTiming.later,
        );
      },
    );
  });
}
