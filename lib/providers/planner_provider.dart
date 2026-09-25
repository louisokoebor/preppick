import 'package:flutter/foundation.dart';

import '../models/models.dart';
import '../services/planning_service.dart';
import '../utils/date_utils.dart';

/// Owns the weekly-plan state shared by Plan This Week, Generated Plan and
/// the swap sheet.
///
/// This provider coordinates [PlanningService]; it does not re-implement any
/// of it. No scoring, no slot filling, no SQL: generation, swapping and
/// confirmation all go straight to the service, and what comes back is held
/// here so several screens can read the same plan without each running its
/// own query.
///
/// ## One in-flight operation at a time
///
/// Generating, swapping and confirming all mutate the same draft, so they are
/// guarded by [isBusy]. A second tap while one is running is dropped rather
/// than queued — the buttons disable themselves from the same flag, and this
/// is the backstop for the taps that land in the frame before that happens.
///
/// ## Failures are state, not exceptions
///
/// Every mutating method returns a bool and records the reason in [error] or
/// [shortages] rather than throwing. An empty library and a library too small
/// for the requested counts are ordinary things for a new household to hit,
/// and the screens need to explain them.
class PlannerProvider extends ChangeNotifier {
  PlannerProvider(this._service, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final PlanningService _service;

  /// Supplies "now" for generation and for the week range the screens draw.
  /// Tests inject a fixed clock so the rendered week is predictable.
  final DateTime Function() _clock;

  WeeklyPlanDetail? _detail;
  List<WeeklyPlanDetail> _history = const [];
  List<PlanShortage> _shortages = const [];
  PlanGenerationOutcome? _outcome;
  bool _isGenerating = false;
  bool _isConfirming = false;
  bool _isSwapping = false;
  bool _isLoading = false;
  bool _isLoadingHistory = false;
  bool _hasLoaded = false;
  bool _hasLoadedHistory = false;
  bool _isDisposed = false;
  Object? _error;
  Object? _historyError;

  /// The current plan with its items and meals resolved, or null when nothing
  /// has been generated yet.
  WeeklyPlanDetail? get planDetail => _detail;

  /// Confirmed plans, newest week first, with meal names resolved.
  List<WeeklyPlanDetail> get history => _history;

  /// The current plan, or null.
  WeeklyPlan? get currentPlan => _detail?.plan;

  /// The current plan's items, ordered by slot. Empty when there is no plan.
  List<WeeklyPlanItem> get items => _detail?.items ?? const [];

  /// True once a plan exists to show.
  bool get hasPlan => _detail != null;

  /// True when the current plan has been confirmed.
  bool get isConfirmed => _detail?.plan.isConfirmed ?? false;

  /// True while a generate or regenerate is in flight.
  bool get isGenerating => _isGenerating;

  /// True while a confirmation is in flight.
  bool get isConfirming => _isConfirming;

  /// True while a swap is in flight.
  bool get isSwapping => _isSwapping;

  /// True while an existing plan is being read back.
  bool get isLoading => _isLoading;

  /// True while confirmed plan history is being read back.
  bool get isLoadingHistory => _isLoadingHistory;

  /// True once [loadCurrentPlan] has completed at least once.
  bool get hasLoaded => _hasLoaded;

  /// True once [loadPlanHistory] has completed at least once.
  bool get hasLoadedHistory => _hasLoadedHistory;

  /// True while any operation is running. Screens disable their actions on
  /// this so one slow write cannot be started twice.
  bool get isBusy => _isGenerating || _isConfirming || _isSwapping;

  /// The last failure, or null. Cleared when the next operation starts.
  Object? get error => _error;

  /// The last plan-history failure, or null.
  Object? get historyError => _historyError;

  /// One entry per category the library could not satisfy exactly. Non-empty
  /// only after a generation that ran thin.
  List<PlanShortage> get shortages => _shortages;

  /// How the last generation ended, or null if none has run.
  PlanGenerationOutcome? get lastOutcome => _outcome;

  /// The start of the week the screens are showing — the current plan's week,
  /// or the week containing now when there is no plan yet.
  DateTime get weekStart =>
      _detail?.plan.weekStart ?? PrepDates.weekStartFor(_clock().toUtc());

  /// The meal in [item], or null when its row has since been removed.
  MealVariant? mealFor(WeeklyPlanItem item) => _detail?.mealFor(item);

  /// How many slots of [type] the current plan holds, for slot labelling.
  int countOfType(MealType type) => _detail?.countOfType(type) ?? 0;

  /// A sentence explaining why the plan is not what was asked for, or null
  /// when nothing needs saying.
  ///
  /// Built here rather than in the screen so Plan This Week and Generated
  /// Plan cannot drift apart on the wording, and so the empty-library case —
  /// the one that sends the household to the Meal Library — reads the same
  /// wherever it surfaces.
  String? get shortageMessage {
    if (_outcome == PlanGenerationOutcome.emptyLibrary) {
      return 'Your meal library is empty. Add a few meals your household '
          'already likes, then plan your week.';
    }
    if (_outcome == PlanGenerationOutcome.noMealsRequested) {
      return 'Every meal count is set to zero. Choose how many meals you '
          'want before planning.';
    }
    if (_shortages.isEmpty) return null;

    final parts = _shortages.map(_describeShortage).toList();
    return '${parts.join(' ')} Add more meals to your library for more '
        'variety.';
  }

  /// True when the library holds nothing to plan from, so the screen should
  /// point at the Meal Library rather than offer a retry.
  bool get needsMeals => _outcome == PlanGenerationOutcome.emptyLibrary;

  static String _describeShortage(PlanShortage shortage) {
    final label = switch (shortage.mealType) {
      MealType.breakfast => 'breakfast',
      MealType.lunch => 'lunch',
      MealType.dinner => 'dinner',
    };
    final plural = shortage.requested == 1 ? label : '${label}s';
    if (shortage.isUnfilled) {
      return shortage.available == 0
          ? 'You have no $label meals yet, so '
                '${shortage.requested - shortage.filled} slot'
                '${shortage.requested - shortage.filled == 1 ? '' : 's'} '
                'could not be filled.'
          : 'Only ${shortage.filled} of ${shortage.requested} $plural '
                'could be filled.';
    }
    // Filled, but the library was smaller than the request, so meals repeat.
    return 'You asked for ${shortage.requested} $plural but your library has '
        '${shortage.available}, so some repeat.';
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }

  /// Notifies unless this provider is gone, so a write that finishes after
  /// the screen closes cannot throw on the way out.
  void _safeNotify() {
    if (_isDisposed) return;
    notifyListeners();
  }

  /// Reads back the plan already saved for this week, if there is one.
  ///
  /// Lets Plan This Week reopen on a plan the household generated earlier
  /// or confirmed earlier rather than silently starting over.
  Future<void> loadCurrentPlan() async {
    if (_isLoading) return;
    _isLoading = true;
    _error = null;
    _safeNotify();

    try {
      final plan = await _service.getCurrentPlan(now: _clock());
      if (plan != null) {
        _detail = await _service.getPlanWithItems(plan.id);
      }
    } catch (error) {
      _error = error;
    } finally {
      _isLoading = false;
      _hasLoaded = true;
      _safeNotify();
    }
  }

  /// Backwards-compatible name for callers that have not been updated yet.
  Future<void> loadCurrentDraft() => loadCurrentPlan();

  /// Reads confirmed plans for the Plan History screen.
  ///
  /// These details resolve current meal names from the meal library rather
  /// than storing a name snapshot on the plan item. That keeps archived meals
  /// readable and lets intentional meal-name edits be reflected in history.
  Future<void> loadPlanHistory() async {
    if (_isLoadingHistory) return;
    _isLoadingHistory = true;
    _historyError = null;
    _safeNotify();

    try {
      _history = await _service.getPlanHistoryDetails(now: _clock());
    } catch (error) {
      _historyError = error;
    } finally {
      _isLoadingHistory = false;
      _hasLoadedHistory = true;
      _safeNotify();
    }
  }

  /// Generates a draft plan for this week from [settings].
  ///
  /// Returns true when a plan exists afterwards. False means nothing was
  /// saved and [shortageMessage] explains why — an empty library, or every
  /// count set to zero.
  Future<bool> generatePlan(AppSettings settings) async {
    if (isBusy) return false;
    _isGenerating = true;
    _error = null;
    _shortages = const [];
    _outcome = null;
    _safeNotify();

    try {
      final result = await _service.generateWeeklyPlan(settings, now: _clock());
      _outcome = result.outcome;
      _shortages = result.shortages;
      if (!result.hasPlan) {
        // Nothing was written, so leave any previous plan alone rather than
        // blanking the screen the household is looking at.
        return false;
      }
      _detail = await _service.getPlanWithItems(result.plan!.id);
      return _detail != null;
    } catch (error) {
      _error = error;
      return false;
    } finally {
      _isGenerating = false;
      _hasLoaded = true;
      _safeNotify();
    }
  }

  /// Replaces the current draft's items for the same week.
  ///
  /// Identical to [generatePlan] — the service already updates the week's
  /// draft row — and named separately only so the Generated Plan screen reads
  /// the way the product does. Regenerating is only exposed for drafts.
  Future<bool> regeneratePlan(AppSettings settings) => generatePlan(settings);

  /// The alternatives for one slot, best first, for the swap sheet.
  ///
  /// Returns an empty list on failure and records [error]; the sheet shows an
  /// empty state either way.
  Future<List<MealVariant>> swapCandidates(String planItemId) async {
    // Cleared first so an error left over from an earlier failure cannot make
    // an honestly-empty candidate list look like a broken read. The sheet
    // tells the two apart by whether [error] is set once this returns.
    _error = null;
    try {
      return await _service.getSwapCandidates(planItemId, now: _clock());
    } catch (error) {
      _error = error;
      _safeNotify();
      return const [];
    }
  }

  /// Replaces the meal in one slot, leaving every other slot untouched.
  ///
  /// Pass [replacementMealVariantId] for an explicit pick from the swap
  /// sheet, or omit it to take the planner's next-best alternative.
  Future<bool> swapMeal(
    String planItemId, {
    String? replacementMealVariantId,
  }) async {
    final planId = _detail?.plan.id;
    if (planId == null || isBusy) return false;
    _isSwapping = true;
    _error = null;
    _safeNotify();

    try {
      await _service.swapMeal(
        planItemId,
        replacementMealVariantId: replacementMealVariantId,
        now: _clock(),
      );
      // Re-read rather than patching in place: the swapped-in meal may not be
      // in the cached meal map yet.
      _detail = await _service.getPlanWithItems(planId);
      return true;
    } catch (error) {
      _error = error;
      return false;
    } finally {
      _isSwapping = false;
      _safeNotify();
    }
  }

  /// Saves the manual main-prep session estimate on the current plan.
  Future<bool> updatePrepSessionEstimate(int? estimatedPrepMinutes) async {
    final planId = _detail?.plan.id;
    if (planId == null || isBusy) return false;
    _error = null;
    _safeNotify();

    try {
      await _service.updatePrepSessionEstimate(
        planId,
        estimatedPrepMinutes: estimatedPrepMinutes,
        now: _clock(),
      );
      _detail = await _service.getPlanWithItems(planId);
      if (_hasLoadedHistory) {
        _history = await _service.getPlanHistoryDetails(now: _clock());
      }
      return true;
    } catch (error) {
      _error = error;
      _safeNotify();
      return false;
    }
  }

  /// Saves prep timing for one item, leaving every other planned meal intact.
  Future<bool> updatePlanItemTiming(
    String planItemId, {
    required PrepTiming prepTiming,
    DateTime? plannedCookDate,
  }) async {
    final planId = _detail?.plan.id;
    if (planId == null || isBusy) return false;
    _error = null;
    _safeNotify();

    try {
      await _service.updatePlanItemTiming(
        planItemId,
        prepTiming: prepTiming,
        plannedCookDate: plannedCookDate,
        now: _clock(),
      );
      _detail = await _service.getPlanWithItems(planId);
      if (_hasLoadedHistory) {
        _history = await _service.getPlanHistoryDetails(now: _clock());
      }
      return true;
    } catch (error) {
      _error = error;
      _safeNotify();
      return false;
    }
  }

  /// Confirms the current plan, which is what writes planning history.
  ///
  /// Returns true when the plan is confirmed afterwards — including when it
  /// already was, since the service treats a repeat confirmation as a no-op.
  Future<bool> confirmPlan() async {
    final planId = _detail?.plan.id;
    if (planId == null || isBusy) return false;
    _isConfirming = true;
    _error = null;
    _safeNotify();

    try {
      await _service.confirmPlan(planId);
      _detail = await _service.getPlanWithItems(planId);
      if (_hasLoadedHistory) {
        _history = await _service.getPlanHistoryDetails(now: _clock());
      }
      return _detail?.plan.isConfirmed ?? false;
    } catch (error) {
      _error = error;
      return false;
    } finally {
      _isConfirming = false;
      _safeNotify();
    }
  }

  /// Forgets the plan held in memory. The stored draft is untouched.
  void clear() {
    if (_detail == null && _shortages.isEmpty && _error == null) return;
    _detail = null;
    _shortages = const [];
    _outcome = null;
    _error = null;
    notifyListeners();
  }
}
