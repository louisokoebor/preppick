import 'package:preppick/models/models.dart';
import 'package:preppick/providers/shopping_provider.dart';
import 'package:preppick/services/database_service.dart';
import 'package:preppick/services/meal_service.dart';
import 'package:preppick/services/planning_service.dart';
import 'package:preppick/services/shopping_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// A [ShoppingProvider] whose list the test sets directly.
///
/// The screen depends on the provider, not on the service, so the widget test
/// drives the provider and leaves SQLite to `shopping_service_test.dart` and
/// `shopping_provider_test.dart`. A real database is also actively unhelpful
/// here: its I/O completes on the real event loop, which the widget tester's
/// fake clock never advances, so the screen would sit on its spinner forever.
final DatabaseService _unusedDatabase = DatabaseService(
  factory: databaseFactoryFfi,
  databaseName: ':unused:',
);

class FakeShoppingProvider extends ShoppingProvider {
  FakeShoppingProvider()
    : super(
        // Never touched: every method that would reach it is overridden.
        ShoppingService(
          _unusedDatabase,
          MealService(_unusedDatabase),
          PlanningService(_unusedDatabase, MealService(_unusedDatabase)),
        ),
      );

  /// Calls recorded, in order: `open:<planId>`, `toggle:<itemId>`,
  /// `add:<name>`, `delete:<itemId>` or 'clearChecked'.
  final List<String> calls = [];

  /// What the next mutating call returns.
  bool nextResult = true;

  // --- state the test sets ------------------------------------------------

  List<ShoppingItem> lines = const [];
  bool loading = false;
  bool generating = false;
  bool writing = false;
  Object? failure;

  /// The line added by the next successful [addItem], if the test wants one
  /// to appear.
  ShoppingItem? nextAddedLine;

  // --- overridden state ---------------------------------------------------

  @override
  List<ShoppingItem> get items => lines;

  @override
  bool get isLoading => loading;

  @override
  bool get isGenerating => generating;

  @override
  bool get isWriting => writing;

  @override
  bool get hasLoaded => true;

  @override
  Object? get error => failure;

  @override
  bool get hasError => failure != null && lines.isEmpty;

  @override
  bool get isEmpty => failure == null && lines.isEmpty;

  // --- overridden operations ---------------------------------------------

  @override
  Future<void> openForPlan(String planId) async {
    calls.add('open:$planId');
  }

  @override
  Future<void> reload() async {
    calls.add('reload');
  }

  @override
  Future<bool> toggleItem(String id, {bool? isChecked}) async {
    calls.add('toggle:$id');
    if (!nextResult) return false;
    final index = lines.indexWhere((item) => item.id == id);
    if (index == -1) return false;
    final next = [...lines];
    next[index] = next[index].copyWith(
      isChecked: isChecked ?? !next[index].isChecked,
    );
    lines = next;
    notifyListeners();
    return true;
  }

  @override
  Future<bool> clearChecked() async {
    calls.add('clearChecked');
    if (!nextResult) return false;
    lines = [for (final item in lines) item.copyWith(isChecked: false)];
    notifyListeners();
    return true;
  }

  @override
  Future<bool> addItem({
    required String name,
    double? quantity,
    String? unit,
    String? category,
  }) async {
    calls.add('add:$name');
    if (!nextResult) return false;
    lines = [
      ...lines,
      nextAddedLine ??
          fakeLine(
            id: 'manual-${lines.length}',
            name: name,
            quantity: quantity,
            unit: unit,
            category: category ?? IngredientCategory.other,
            isManual: true,
          ),
    ];
    notifyListeners();
    return true;
  }

  @override
  Future<bool> deleteItem(String id) async {
    calls.add('delete:$id');
    if (!nextResult) return false;
    lines = lines.where((item) => item.id != id).toList();
    notifyListeners();
    return true;
  }

  /// How many times [name] was called.
  int countOf(String name) => calls.where((call) => call == name).length;
}

/// Builds a shopping line without a database.
ShoppingItem fakeLine({
  required String id,
  required String name,
  String category = IngredientCategory.other,
  double? quantity,
  String? unit,
  bool isChecked = false,
  bool isManual = false,
}) => ShoppingItem(
  id: id,
  weeklyPlanId: 'plan-1',
  ingredientId: isManual ? null : 'ingredient-$id',
  name: name,
  quantity: quantity,
  unit: unit,
  category: category,
  isChecked: isChecked,
  isManual: isManual,
);
