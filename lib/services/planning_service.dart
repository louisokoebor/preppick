import 'dart:math';

import 'package:sqflite/sqflite.dart';

import '../models/models.dart';
import '../utils/date_utils.dart';
import '../utils/id_utils.dart';
import 'database_service.dart';
import 'meal_service.dart';
import 'plan_scoring.dart';

/// Why a category could not be planned exactly as asked.
///
/// A shortage is information for the UI, not a failure: the plan is still
/// generated and still usable. It exists so the Generated Plan screen can say
/// "you asked for 3 dinners but your library only has 1" instead of silently
/// producing a week of the same meal.
class PlanShortage {
  const PlanShortage({
    required this.mealType,
    required this.requested,
    required this.available,
    required this.filled,
  });

  final MealType mealType;

  /// Slots the household asked for.
  final int requested;

  /// Distinct eligible meals of this type in the library.
  final int available;

  /// Slots that actually received a meal.
  final int filled;

  /// No meal of this type exists, so these slots are empty.
  bool get isUnfilled => filled < requested;

  /// The slots were filled, but only by repeating meals.
  bool get usedRepeats => available > 0 && available < requested;

  @override
  String toString() =>
      'PlanShortage(${mealType.value}: requested $requested, '
      'available $available, filled $filled)';
}

/// How [PlanningService.generateWeeklyPlan] ended.
enum PlanGenerationOutcome {
  /// Every requested slot was filled from a library with room to spare.
  generated,

  /// A plan exists and is usable, but [PlanGenerationResult.shortages]
  /// explains where the library ran thin.
  generatedWithShortages,

  /// The meal library holds no active meals at all. Nothing was saved; the UI
  /// should send the household to add or import meals first.
  emptyLibrary,

  /// Every meal count is zero. Nothing was saved — an empty week is not a
  /// plan, and confirming one would be meaningless.
  noMealsRequested,
}

/// The result of generating a week.
///
/// A result object rather than an exception, because "your library is empty"
/// is an ordinary thing for a new household to hit, and the screen needs to
/// explain it rather than crash.
class PlanGenerationResult {
  const PlanGenerationResult({
    required this.outcome,
    this.plan,
    this.items = const [],
    this.shortages = const [],
  });

  final PlanGenerationOutcome outcome;

  /// The saved draft, or null when nothing could be planned.
  final WeeklyPlan? plan;

  /// The saved items, ordered by slot.
  final List<WeeklyPlanItem> items;

  /// One entry per category that could not be satisfied exactly.
  final List<PlanShortage> shortages;

  /// True when a draft was written to the database.
  bool get hasPlan => plan != null;
}

/// A plan together with everything the UI needs to draw it.
class WeeklyPlanDetail {
  const WeeklyPlanDetail({
    required this.plan,
    required this.items,
    required this.mealsById,
  });

  final WeeklyPlan plan;

  /// Items ordered by slot: breakfast, then lunch, then dinner.
  final List<WeeklyPlanItem> items;

  /// The meal for every item, including archived meals so an old confirmed
  /// plan still resolves to a real name.
  final Map<String, MealVariant> mealsById;

  /// The meal in [item], or null if its row has since been deleted.
  MealVariant? mealFor(WeeklyPlanItem item) => mealsById[item.mealVariantId];

  /// How many slots of [type] this plan holds, for slot labelling.
  int countOfType(MealType type) =>
      items.where((item) => item.mealType == type).length;
}

/// Raised when a planning operation is asked for something impossible.
class PlanningException implements Exception {
  const PlanningException(this.message);

  final String message;

  @override
  String toString() => 'PlanningException: $message';
}

/// All reads and writes for weekly plans, plus the V1 recommendation engine.
///
/// Owns every statement that touches `weekly_plans` and `weekly_plan_items`.
/// The scoring rules themselves live in [PlanScoring] as pure functions;
/// this class is the part that needs a database and a clock.
///
/// ## Draft versus confirmed
///
/// Generating produces a **draft**. A draft is disposable: regenerating
/// replaces that week's items in the same weekly-plan row, and nothing about
/// the meal library changes. Only [confirmPlan] writes planning counters —
/// `last_planned_at` and `times_planned` — because only a confirmed plan means
/// the household actually intends to eat those meals. This is what keeps
/// "I pressed regenerate six times" from poisoning next week's
/// recommendations.
///
/// Confirming is idempotent: a plan already confirmed is returned unchanged
/// rather than incrementing its meals a second time.
class PlanningService {
  PlanningService(this._databaseService, this._mealService, {Random? random})
    : _random = random ?? Random();

  static const String _plansTable = 'weekly_plans';
  static const String _itemsTable = 'weekly_plan_items';

  final DatabaseService _databaseService;
  final MealService _mealService;

  /// Supplies the small tie-breaking jitter. Tests inject a seeded [Random]
  /// to make generation reproducible.
  final Random _random;

  Future<Database> get _db => _databaseService.database;

  // ------------------------------------------------------------ generation

  /// Builds and saves a draft plan for the week containing [now].
  ///
  /// `week_start` is the identity of a weekly plan. Pressing "Plan this week"
  /// repeatedly updates the same draft row and replaces its items; it never
  /// inserts a second plan for the same calendar week. If that week is already
  /// confirmed, generation leaves it alone and returns the existing plan.
  Future<PlanGenerationResult> generateWeeklyPlan(
    AppSettings settings, {
    DateTime? now,
    DateTime? weekStart,
  }) async {
    final timestamp = (now ?? DateTime.now()).toUtc();
    final start = weekStart ?? PrepDates.weekStartFor(timestamp);

    if (settings.isEmpty) {
      return const PlanGenerationResult(
        outcome: PlanGenerationOutcome.noMealsRequested,
      );
    }

    // Load the library once per type rather than per slot.
    final library = <MealType, List<MealVariant>>{
      for (final type in MealType.values)
        type: await _mealService.getMealsByType(type),
    };

    if (library.values.every((meals) => meals.isEmpty)) {
      return const PlanGenerationResult(
        outcome: PlanGenerationOutcome.emptyLibrary,
      );
    }

    final existing = await getPlanForWeek(start);
    if (existing?.isConfirmed ?? false) {
      return PlanGenerationResult(
        outcome: PlanGenerationOutcome.generated,
        plan: existing,
        items: await getPlanItems(existing!.id),
      );
    }

    final plan =
        existing ??
        WeeklyPlan(
          id: PrepIds.newId(),
          weekStart: start,
          status: PlanStatus.draft,
          createdAt: timestamp,
          updatedAt: timestamp,
        );

    final placed = <({MealVariant meal, MealType mealType})>[];
    final items = <WeeklyPlanItem>[];
    final shortages = <PlanShortage>[];

    for (final type in MealType.values) {
      final requested = settings.countFor(type);
      if (requested == 0) continue;

      final candidates = library[type]!;
      var filled = 0;
      for (var slotIndex = 0; slotIndex < requested; slotIndex++) {
        final choice = PlanScoring.selectBest(
          candidates: candidates,
          context: SlotContext.of(placed, proteinScope: type),
          now: timestamp,
          random: _random,
        );
        if (choice == null) break; // No meals of this type at all.
        placed.add((meal: choice, mealType: type));
        items.add(
          WeeklyPlanItem(
            id: PrepIds.newId(),
            weeklyPlanId: plan.id,
            mealVariantId: choice.id,
            mealType: type,
            slotIndex: slotIndex,
          ),
        );
        filled++;
      }

      if (filled < requested || candidates.length < requested) {
        shortages.add(
          PlanShortage(
            mealType: type,
            requested: requested,
            available: candidates.length,
            filled: filled,
          ),
        );
      }
    }

    final db = await _db;
    await db.transaction((txn) async {
      final stamp = PrepDates.toIso(timestamp);
      if (existing == null) {
        await txn.insert(_plansTable, plan.toMap());
      } else {
        await txn.update(
          _plansTable,
          {
            'status': PlanStatus.draft.value,
            'updated_at': stamp,
            'confirmed_at': null,
          },
          where: 'id = ?',
          whereArgs: [plan.id],
        );
        await txn.delete(
          _itemsTable,
          where: 'weekly_plan_id = ?',
          whereArgs: [plan.id],
        );
        await txn.delete(
          'shopping_items',
          where: 'weekly_plan_id = ? AND is_manual = 0',
          whereArgs: [plan.id],
        );
      }
      for (final item in items) {
        await txn.insert(_itemsTable, item.toMap());
      }
    });

    return PlanGenerationResult(
      outcome: shortages.isEmpty
          ? PlanGenerationOutcome.generated
          : PlanGenerationOutcome.generatedWithShortages,
      plan: plan.copyWith(status: PlanStatus.draft, updatedAt: timestamp),
      items: items,
      shortages: shortages,
    );
  }

  // ----------------------------------------------------------------- reads

  /// A plan with its items and meals resolved, or null if [planId] is unknown.
  Future<WeeklyPlanDetail?> getPlanWithItems(String planId) async {
    final plan = await getPlan(planId);
    if (plan == null) return null;
    final items = await getPlanItems(planId);
    final meals = <String, MealVariant>{};
    for (final id in items.map((item) => item.mealVariantId).toSet()) {
      final meal = await _mealService.getMealVariant(id);
      if (meal != null) meals[id] = meal;
    }
    return WeeklyPlanDetail(plan: plan, items: items, mealsById: meals);
  }

  /// One plan by id, or null.
  Future<WeeklyPlan?> getPlan(String planId) async {
    final db = await _db;
    final rows = await db.query(
      _plansTable,
      where: 'id = ?',
      whereArgs: [planId],
      limit: 1,
    );
    return rows.isEmpty ? null : WeeklyPlan.fromMap(rows.first);
  }

  /// The one plan for [weekStart], or null when that week has not been
  /// planned yet.
  Future<WeeklyPlan?> getPlanForWeek(DateTime weekStart) async {
    final db = await _db;
    final rows = await db.query(
      _plansTable,
      where: 'week_start = ?',
      whereArgs: [PrepDates.toIso(weekStart)],
      limit: 1,
    );
    return rows.isEmpty ? null : WeeklyPlan.fromMap(rows.first);
  }

  /// The items of one plan, ordered by slot.
  Future<List<WeeklyPlanItem>> getPlanItems(String planId) async {
    final db = await _db;
    final rows = await db.query(
      _itemsTable,
      where: 'weekly_plan_id = ?',
      whereArgs: [planId],
    );
    return rows.map(WeeklyPlanItem.fromMap).toList()
      ..sort((a, b) => a.slot.compareTo(b.slot));
  }

  /// Confirmed previous weeks, newest first. This is the Plan History screen.
  Future<List<WeeklyPlan>> getPlanHistory({
    bool includeDrafts = false,
    DateTime? now,
  }) async {
    final db = await _db;
    final currentWeek = PrepDates.toIso(
      PrepDates.weekStartFor((now ?? DateTime.now()).toUtc()),
    );
    final rows = await db.query(
      _plansTable,
      where: includeDrafts ? null : 'status = ? AND week_start < ?',
      whereArgs: includeDrafts
          ? null
          : [PlanStatus.confirmed.value, currentWeek],
      orderBy: 'week_start DESC, updated_at DESC',
    );
    return rows.map(WeeklyPlan.fromMap).toList();
  }

  /// Confirmed plan history with each plan's items and meals resolved.
  ///
  /// History stores stable plan item references, not a snapshot of display
  /// names. Editing a meal's current name will therefore update the name shown
  /// here, while archiving keeps the row available so older plans stay
  /// readable.
  Future<List<WeeklyPlanDetail>> getPlanHistoryDetails({DateTime? now}) async {
    final plans = await getPlanHistory(now: now);
    final details = <WeeklyPlanDetail>[];
    for (final plan in plans) {
      final detail = await getPlanWithItems(plan.id);
      if (detail != null) details.add(detail);
    }
    return details;
  }

  /// The current draft for the week containing [now], if one exists.
  Future<WeeklyPlan?> getCurrentDraft({DateTime? now}) async {
    final start = PrepDates.weekStartFor((now ?? DateTime.now()).toUtc());
    final db = await _db;
    final rows = await db.query(
      _plansTable,
      where: 'week_start = ? AND status = ?',
      whereArgs: [PrepDates.toIso(start), PlanStatus.draft.value],
      orderBy: 'created_at DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : WeeklyPlan.fromMap(rows.first);
  }

  /// This week's plan in any state, if one exists.
  Future<WeeklyPlan?> getCurrentPlan({DateTime? now}) {
    final start = PrepDates.weekStartFor((now ?? DateTime.now()).toUtc());
    return getPlanForWeek(start);
  }

  // ----------------------------------------------------------------- swaps

  /// Alternatives for one slot, ranked the way the planner would rank them.
  ///
  /// Excludes the meal currently in the slot — the household is asking for
  /// something else — and scores the rest against the *other* slots only, so
  /// the meal being replaced does not compete with its own alternatives.
  Future<List<MealVariant>> getSwapCandidates(
    String planItemId, {
    DateTime? now,
  }) async {
    final item = await _requireItem(planItemId);
    final candidates = await _mealService.getMealsByType(item.mealType);
    final context = await _contextExcluding(item);
    return PlanScoring.rank(
      candidates: candidates.where((meal) => meal.id != item.mealVariantId),
      context: context,
      now: (now ?? DateTime.now()).toUtc(),
      random: _random,
    );
  }

  /// Replaces the meal in one slot, leaving every other slot untouched.
  ///
  /// Pass [replacementMealVariantId] for an explicit pick from the swap
  /// sheet, or omit it to let the planner choose the next-best alternative.
  /// Returns the updated item, or throws [PlanningException] when the
  /// replacement is the wrong meal type or no alternative exists.
  Future<WeeklyPlanItem> swapMeal(
    String planItemId, {
    String? replacementMealVariantId,
    DateTime? now,
  }) async {
    final item = await _requireItem(planItemId);
    final plan = await getPlan(item.weeklyPlanId);
    if (plan == null) {
      throw PlanningException('Plan ${item.weeklyPlanId} no longer exists.');
    }
    final MealVariant replacement;
    if (replacementMealVariantId != null) {
      final meal = await _mealService.getMealVariant(replacementMealVariantId);
      if (meal == null || meal.isArchived) {
        throw PlanningException(
          'Meal $replacementMealVariantId is not in the library.',
        );
      }
      final family = await _mealService.getMealFamily(meal.mealFamilyId);
      if (family == null || family.mealType != item.mealType) {
        throw PlanningException(
          '${meal.name} is not a ${item.mealType.value} meal.',
        );
      }
      replacement = meal;
    } else {
      final candidates = await getSwapCandidates(planItemId, now: now);
      if (candidates.isEmpty) {
        throw PlanningException(
          'No other ${item.mealType.value} meal is available to swap in.',
        );
      }
      replacement = candidates.first;
    }

    final updated = item.copyWith(mealVariantId: replacement.id);
    final db = await _db;
    final timestamp = (now ?? DateTime.now()).toUtc();
    final stamp = PrepDates.toIso(timestamp);
    await db.transaction((txn) async {
      await txn.update(
        _itemsTable,
        {'meal_variant_id': updated.mealVariantId},
        where: 'id = ?',
        whereArgs: [updated.id],
      );
      await txn.update(
        _plansTable,
        {'updated_at': stamp},
        where: 'id = ?',
        whereArgs: [plan.id],
      );

      if (plan.isConfirmed) {
        final otherItems = (await txn.query(
          _itemsTable,
          where: 'weekly_plan_id = ? AND id != ?',
          whereArgs: [plan.id, item.id],
        )).map(WeeklyPlanItem.fromMap).toList();
        final oldMealStillUsed = otherItems.any(
          (other) => other.mealVariantId == item.mealVariantId,
        );
        final newMealAlreadyUsed = otherItems.any(
          (other) => other.mealVariantId == replacement.id,
        );

        if (!oldMealStillUsed) {
          await txn.rawUpdate(
            '''
            UPDATE meal_variants
            SET times_planned = CASE
                  WHEN times_planned > 0 THEN times_planned - 1
                  ELSE 0
                END,
                updated_at = ?
            WHERE id = ?
            ''',
            [stamp, item.mealVariantId],
          );
        }
        if (!newMealAlreadyUsed) {
          await txn.rawUpdate(
            '''
            UPDATE meal_variants
            SET times_planned = times_planned + 1,
                last_planned_at = ?,
                updated_at = ?
            WHERE id = ?
            ''',
            [stamp, stamp, replacement.id],
          );
        }
        await txn.delete(
          'shopping_items',
          where: 'weekly_plan_id = ? AND is_manual = 0',
          whereArgs: [plan.id],
        );
      }
    });
    return updated;
  }

  /// Updates the manual estimate for the main prep session.
  ///
  /// This is deliberately independent from the sum of meal cook times:
  /// overlapping oven time, shared components and cook-later meals mean the
  /// household owns this estimate until PrepPick has explicit scheduling
  /// logic.
  Future<WeeklyPlan> updatePrepSessionEstimate(
    String planId, {
    int? estimatedPrepMinutes,
    DateTime? now,
  }) async {
    final plan = await getPlan(planId);
    if (plan == null) throw PlanningException('Plan $planId does not exist.');

    final timestamp = (now ?? DateTime.now()).toUtc();
    final minutes = estimatedPrepMinutes == null || estimatedPrepMinutes <= 0
        ? null
        : estimatedPrepMinutes;
    final db = await _db;
    await db.update(
      _plansTable,
      {
        'estimated_prep_minutes': minutes,
        'updated_at': PrepDates.toIso(timestamp),
      },
      where: 'id = ?',
      whereArgs: [planId],
    );
    return (await getPlan(planId))!;
  }

  /// Updates when a single planned meal will be cooked for this week.
  ///
  /// The timing belongs to `weekly_plan_items`, not to the meal variant, so
  /// the same Fish + Rice row can be main prep this week and cook-later next
  /// week without either plan rewriting the other.
  Future<WeeklyPlanItem> updatePlanItemTiming(
    String planItemId, {
    required PrepTiming prepTiming,
    DateTime? plannedCookDate,
    DateTime? now,
  }) async {
    final item = await _requireItem(planItemId);
    final plan = await getPlan(item.weeklyPlanId);
    if (plan == null) {
      throw PlanningException('Plan ${item.weeklyPlanId} no longer exists.');
    }

    final timestamp = (now ?? DateTime.now()).toUtc();
    final cookDate = prepTiming == PrepTiming.later ? plannedCookDate : null;
    final db = await _db;
    await db.transaction((txn) async {
      await txn.update(
        _itemsTable,
        {
          'prep_timing': prepTiming.value,
          'planned_cook_date': PrepDates.toIsoOrNull(cookDate),
        },
        where: 'id = ?',
        whereArgs: [planItemId],
      );
      await txn.update(
        _plansTable,
        {'updated_at': PrepDates.toIso(timestamp)},
        where: 'id = ?',
        whereArgs: [plan.id],
      );
    });
    return _requireItem(planItemId);
  }

  // ------------------------------------------------------------- confirming

  /// Confirms [planId] and writes the history the planner learns from.
  ///
  /// In one transaction: the plan becomes confirmed with a `confirmed_at`
  /// stamp, and every meal it uses has `last_planned_at` set and
  /// `times_planned` incremented — once per confirmation, even when the same
  /// meal fills two slots, because the household planned it once this week.
  ///
  /// Confirming an already-confirmed plan is a no-op that returns the plan
  /// unchanged, so a double tap or a retry cannot double-count.
  Future<WeeklyPlan> confirmPlan(String planId, {DateTime? now}) async {
    final plan = await getPlan(planId);
    if (plan == null) throw PlanningException('Plan $planId does not exist.');
    if (plan.isConfirmed) return plan;

    final items = await getPlanItems(planId);
    if (items.isEmpty) {
      throw PlanningException('Plan $planId has no meals to confirm.');
    }

    final timestamp = (now ?? DateTime.now()).toUtc();
    final stamp = PrepDates.toIso(timestamp);
    final confirmed = plan.copyWith(
      status: PlanStatus.confirmed,
      updatedAt: timestamp,
      confirmedAt: timestamp,
    );

    final db = await _db;
    await db.transaction((txn) async {
      final updated = await txn.update(
        _plansTable,
        {
          'status': PlanStatus.confirmed.value,
          'updated_at': stamp,
          'confirmed_at': stamp,
        },
        // Re-check the status inside the transaction so two concurrent
        // confirmations cannot both increment.
        where: 'id = ? AND status = ?',
        whereArgs: [planId, PlanStatus.draft.value],
      );
      if (updated == 0) return;

      for (final mealId in items.map((item) => item.mealVariantId).toSet()) {
        await txn.rawUpdate(
          '''
          UPDATE meal_variants
          SET times_planned = times_planned + 1,
              last_planned_at = ?,
              updated_at = ?
          WHERE id = ?
          ''',
          [stamp, stamp, mealId],
        );
      }
    });

    // Another confirmation may have won the race; return what is stored.
    return await getPlan(planId) ?? confirmed;
  }

  /// Deletes a draft and its items. Confirmed plans are protected.
  Future<void> deleteDraft(String planId) async {
    final db = await _db;
    final deleted = await db.delete(
      _plansTable,
      where: 'id = ? AND status = ?',
      whereArgs: [planId, PlanStatus.draft.value],
    );
    if (deleted == 0) {
      throw PlanningException('Plan $planId is not a deletable draft.');
    }
  }

  // --------------------------------------------------------------- helpers

  Future<WeeklyPlanItem> _requireItem(String planItemId) async {
    final db = await _db;
    final rows = await db.query(
      _itemsTable,
      where: 'id = ?',
      whereArgs: [planItemId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw PlanningException('Plan item $planItemId does not exist.');
    }
    return WeeklyPlanItem.fromMap(rows.first);
  }

  /// The variety context of a plan, ignoring [item]'s own slot.
  Future<SlotContext> _contextExcluding(WeeklyPlanItem item) async {
    final items = await getPlanItems(item.weeklyPlanId);
    final placed = <({MealVariant meal, MealType mealType})>[];
    for (final other in items) {
      if (other.id == item.id) continue;
      final meal = await _mealService.getMealVariant(other.mealVariantId);
      if (meal != null) placed.add((meal: meal, mealType: other.mealType));
    }
    return SlotContext.of(placed, proteinScope: item.mealType);
  }
}
