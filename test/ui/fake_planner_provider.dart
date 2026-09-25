import 'package:preppick/models/models.dart';
import 'package:preppick/providers/planner_provider.dart';
import 'package:preppick/services/database_service.dart';
import 'package:preppick/services/meal_service.dart';
import 'package:preppick/services/planning_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// A [PlannerProvider] whose state the test sets directly.
///
/// The planner screens depend on the provider, not on the service, so the
/// widget tests drive the provider and leave SQLite to
/// `planning_service_test.dart` and `planner_provider_test.dart`. A real
/// database is also actively unhelpful here: its I/O completes on the real
/// event loop, which the widget tester's fake clock never advances, so the
/// screen would sit on its spinner forever.
///
/// Every operation is a no-op that records the call and returns
/// [nextResult], so a test can assert both *what* the screen asked for and
/// how many times it asked.
final DatabaseService _unusedDatabase = DatabaseService(
  factory: databaseFactoryFfi,
  databaseName: ':unused:',
);

class FakePlannerProvider extends PlannerProvider {
  FakePlannerProvider({DateTime? now})
    : _now = now ?? DateTime.utc(2026, 3, 16),
      super(
        // Never touched: every method that would reach it is overridden, so
        // no database is ever opened. The factory is named explicitly only
        // because DatabaseService resolves the global one at construction,
        // and in a test process there is no global one to resolve.
        PlanningService(_unusedDatabase, MealService(_unusedDatabase)),
      );

  final DateTime _now;

  /// Calls recorded, in order: 'generate', 'confirm', 'history',
  /// `candidates:<itemId>`, or `swap:<itemId>` (with `:<mealId>` appended for
  /// an explicit pick).
  final List<String> calls = [];

  /// What the next mutating call returns.
  bool nextResult = true;

  // --- state the test sets ------------------------------------------------

  List<WeeklyPlanItem> plannedItems = const [];
  Map<String, MealVariant> meals = const {};
  List<WeeklyPlanDetail> historyDetails = const [];
  bool confirmed = false;
  int? prepMinutes;
  bool generating = false;
  bool confirming = false;
  bool swapping = false;
  bool loadingHistory = false;
  bool loadedHistory = true;
  String? message;
  bool libraryEmpty = false;
  Object? failure;
  Object? historyFailure;

  /// What [swapCandidates] returns, in ranked order.
  List<MealVariant> candidates = const [];

  /// Makes the next call leave the provider busy, as a slow write would.
  void beginGenerating() {
    generating = true;
    notifyListeners();
  }

  // --- overridden state ---------------------------------------------------

  @override
  DateTime get weekStart => _now;

  @override
  List<WeeklyPlanItem> get items => plannedItems;

  @override
  bool get hasPlan => plannedItems.isNotEmpty;

  @override
  WeeklyPlan? get currentPlan => plannedItems.isEmpty
      ? null
      : WeeklyPlan(
          id: 'plan-1',
          weekStart: _now,
          status: confirmed ? PlanStatus.confirmed : PlanStatus.draft,
          estimatedPrepMinutes: prepMinutes,
          createdAt: DateTime.utc(2026, 3, 1),
        );

  @override
  bool get isConfirmed => confirmed;

  @override
  bool get isGenerating => generating;

  @override
  bool get isConfirming => confirming;

  @override
  bool get isSwapping => swapping;

  @override
  bool get isBusy => generating || confirming || swapping;

  @override
  bool get hasLoaded => true;

  @override
  List<WeeklyPlanDetail> get history => historyDetails;

  @override
  bool get isLoadingHistory => loadingHistory;

  @override
  bool get hasLoadedHistory => loadedHistory;

  @override
  Object? get error => failure;

  @override
  Object? get historyError => historyFailure;

  @override
  String? get shortageMessage => message;

  @override
  bool get needsMeals => libraryEmpty;

  @override
  MealVariant? mealFor(WeeklyPlanItem item) => meals[item.mealVariantId];

  @override
  int countOfType(MealType type) =>
      plannedItems.where((item) => item.mealType == type).length;

  // --- overridden operations ---------------------------------------------

  @override
  Future<void> loadCurrentDraft() async {}

  @override
  Future<void> loadPlanHistory() async {
    calls.add('history');
    loadedHistory = true;
    notifyListeners();
  }

  @override
  Future<bool> generatePlan(AppSettings settings) async {
    calls.add('generate');
    // Mirrors the real provider: a call that arrives mid-operation is dropped.
    if (isBusy) return false;
    return nextResult;
  }

  @override
  Future<bool> confirmPlan() async {
    calls.add('confirm');
    if (isBusy) return false;
    confirmed = nextResult;
    notifyListeners();
    return nextResult;
  }

  @override
  Future<List<MealVariant>> swapCandidates(String planItemId) async {
    calls.add('candidates:$planItemId');
    return candidates;
  }

  @override
  Future<bool> swapMeal(
    String planItemId, {
    String? replacementMealVariantId,
  }) async {
    calls.add(
      replacementMealVariantId == null
          ? 'swap:$planItemId'
          : 'swap:$planItemId:$replacementMealVariantId',
    );
    if (isBusy) return false;
    return nextResult;
  }

  @override
  Future<bool> updatePrepSessionEstimate(int? estimatedPrepMinutes) async {
    calls.add('prep-estimate:${estimatedPrepMinutes ?? 'clear'}');
    prepMinutes = estimatedPrepMinutes;
    notifyListeners();
    return nextResult;
  }

  @override
  Future<bool> updatePlanItemTiming(
    String planItemId, {
    required PrepTiming prepTiming,
    DateTime? plannedCookDate,
  }) async {
    calls.add('timing:$planItemId:${prepTiming.value}');
    plannedItems = [
      for (final item in plannedItems)
        item.id == planItemId
            ? item.copyWith(
                prepTiming: prepTiming,
                plannedCookDate: plannedCookDate,
                clearPlannedCookDate: plannedCookDate == null,
              )
            : item,
    ];
    notifyListeners();
    return nextResult;
  }

  /// How many times [name] was called.
  int countOf(String name) => calls.where((call) => call == name).length;
}

/// Builds a plan item without a database.
WeeklyPlanItem fakeItem({
  required String id,
  required MealType mealType,
  int slotIndex = 0,
  String? mealVariantId,
}) => WeeklyPlanItem(
  id: id,
  weeklyPlanId: 'plan-1',
  mealVariantId: mealVariantId ?? 'meal-$id',
  mealType: mealType,
  slotIndex: slotIndex,
);

/// Builds a meal without a database.
MealVariant fakeMeal({
  required String id,
  required String name,
  String? protein,
  String family = 'family-1',
}) {
  final now = DateTime.utc(2026, 1, 1);
  return MealVariant(
    id: id,
    mealFamilyId: family,
    name: name,
    protein: protein,
    createdAt: now,
    updatedAt: now,
  );
}
