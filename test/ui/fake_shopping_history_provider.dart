import 'package:preppick/models/models.dart';
import 'package:preppick/providers/shopping_history_provider.dart';
import 'package:preppick/services/database_service.dart';
import 'package:preppick/services/meal_service.dart';
import 'package:preppick/services/planning_service.dart';
import 'package:preppick/services/shopping_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final DatabaseService _unusedDatabase = DatabaseService(
  factory: databaseFactoryFfi,
  databaseName: ':unused:',
);

/// A [ShoppingHistoryProvider] whose state the test sets directly, for the
/// same reason as `FakeShoppingProvider`: real SQLite I/O never completes
/// under the widget tester's fake clock.
class FakeShoppingHistoryProvider extends ShoppingHistoryProvider {
  FakeShoppingHistoryProvider()
    : super(
        ShoppingService(
          _unusedDatabase,
          MealService(_unusedDatabase),
          PlanningService(_unusedDatabase, MealService(_unusedDatabase)),
        ),
      );

  /// Calls recorded, in order: 'load' or `open:<planId>`.
  final List<String> calls = [];

  List<ShoppingListSummary> past = const [];
  bool loaded = true;
  Object? failure;

  /// Saved lists by plan id, returned by [openWeek].
  Map<String, SavedShoppingList> weeks = const {};
  String? openedId;
  Object? openFailure;

  @override
  List<ShoppingListSummary> get summaries => past;

  @override
  bool get hasLoaded => loaded;

  @override
  bool get isLoading => false;

  @override
  Object? get error => failure;

  @override
  String? get weekPlanId => openedId;

  @override
  SavedShoppingList? get week => weeks[openedId];

  @override
  bool get isLoadingWeek => false;

  @override
  Object? get weekError => openFailure;

  /// How many times [name] was called.
  int countOf(String name) => calls.where((call) => call == name).length;

  @override
  Future<void> loadHistory() async {
    calls.add('load');
  }

  @override
  Future<void> openWeek(String planId) async {
    calls.add('open:$planId');
    openedId = planId;
    notifyListeners();
  }
}

WeeklyPlan fakePastPlan(String id, DateTime weekStart) => WeeklyPlan(
  id: id,
  weekStart: weekStart,
  status: PlanStatus.confirmed,
  createdAt: weekStart,
  confirmedAt: weekStart,
);
