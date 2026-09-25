import 'package:sqflite/sqflite.dart';

import '../models/models.dart';
import '../utils/date_utils.dart';
import '../utils/id_utils.dart';
import 'database_service.dart';
import 'meal_service.dart';
import 'planning_service.dart';
import 'quantity_math.dart';

/// Raised when a shopping operation is asked for something impossible.
class ShoppingException implements Exception {
  const ShoppingException(this.message);

  final String message;

  @override
  String toString() => 'ShoppingException: $message';
}

/// One category of a shopping list, ready to draw as a section.
class ShoppingCategoryGroup {
  const ShoppingCategoryGroup({required this.category, required this.items});

  final String category;
  final List<ShoppingItem> items;

  int get checkedCount => items.where((item) => item.isChecked).length;

  bool get isComplete => items.isNotEmpty && checkedCount == items.length;
}

/// A previous week's saved list, read back exactly as it was left.
class SavedShoppingList {
  const SavedShoppingList({required this.plan, required this.groups});

  final WeeklyPlan plan;

  /// The saved lines as category sections, in shopping order.
  final List<ShoppingCategoryGroup> groups;

  int get itemCount =>
      groups.fold(0, (total, group) => total + group.items.length);

  int get checkedCount =>
      groups.fold(0, (total, group) => total + group.checkedCount);

  bool get isEmpty => itemCount == 0;
}

/// The shopping list for one week: generation, aggregation and manual edits.
///
/// Owns every statement that touches `shopping_items`.
///
/// ## Generated versus manual lines
///
/// A generated line is derived from the plan's recipes and is owned by
/// [generateFromPlan]: regenerating rebuilds it, and it cannot be edited or
/// deleted directly — the way to change it is to change the recipe it came
/// from. A manual line is typed by the household, belongs to nobody else, and
/// regeneration never touches it. Keeping the two apart is what makes
/// regeneration safe to run at any time.
///
/// ## Aggregation
///
/// Ingredients are shared rows (see [MealService]), so two meals using
/// chicken point at the same ingredient id and merge without any name
/// guessing. Within one ingredient, contributions are grouped into what can
/// be *safely added* (see [QuantityMath]):
///
/// * amounts on the same metric scale add and convert — 500 g + 750 g is
///   1.25 kg;
/// * amounts sharing an unconvertible unit add within that unit — 2 tbsp +
///   1 tbsp is 3 tbsp;
/// * amounts in units that cannot be reconciled stay on separate lines;
/// * contributions with no recorded quantity form their own line with no
///   quantity at all.
///
/// That last rule is the one that matters most. If chicken appears once as
/// 500 g and once with no amount recorded, the list shows both "Chicken
/// 500 g" and "Chicken" — never "Chicken 500 g" alone, which would quietly
/// understate the week, and never an invented figure for the second meal.
/// Two honest lines beat one confident wrong one.
///
/// A meal filling two slots contributes its ingredients twice, because that
/// is two batches to cook.
class ShoppingService {
  ShoppingService(this._databaseService, this._mealService, this._planning);

  static const String _table = 'shopping_items';

  /// Roughly supermarket order, so the list reads the way a shop is walked.
  static const List<String> categoryOrder = [
    IngredientCategory.produce,
    IngredientCategory.protein,
    IngredientCategory.chilled,
    IngredientCategory.frozen,
    IngredientCategory.pantry,
    IngredientCategory.household,
    IngredientCategory.specialist,
    IngredientCategory.other,
  ];

  final DatabaseService _databaseService;
  final MealService _mealService;
  final PlanningService _planning;

  Future<Database> get _db => _databaseService.database;

  // ------------------------------------------------------------ generation

  /// Builds the generated lines for [planId] from its meals' recipes.
  ///
  /// Only a **confirmed** plan has a shopping list. A draft is still being
  /// shuffled, and a list generated from one would be wrong the moment the
  /// next swap happened; [ShoppingException] is thrown rather than handing
  /// back a list that is about to go stale.
  ///
  /// Safe to call repeatedly. Generated lines are rebuilt in place rather than
  /// appended, so reopening the shopping list can never duplicate a row. A
  /// line that survives the rebuild unchanged keeps its id and its checked
  /// state, so ticking things off and then regenerating does not undo the
  /// shopping already done. Manual lines are not touched.
  Future<List<ShoppingItem>> generateFromPlan(String planId) async {
    final plan = await _planning.getPlan(planId);
    if (plan == null) {
      throw ShoppingException('Plan $planId does not exist.');
    }
    if (!plan.isConfirmed) {
      throw ShoppingException(
        'Plan $planId is still a draft. Confirm it before shopping for it.',
      );
    }

    final items = await _planning.getPlanItems(planId);
    final groups = await _collectContributions(items);

    final existing = await _rows(planId);
    // Previous generated lines, keyed the same way the new ones are, so a
    // line that still exists can be recognised and its state carried over.
    final previous = {
      for (final row in existing.where((row) => !row.isManual))
        _identityOf(row): row,
    };

    final generated = <ShoppingItem>[];
    for (final entry in groups.entries) {
      final group = entry.value;
      final carried = previous[entry.key];
      generated.add(
        ShoppingItem(
          id: carried?.id ?? PrepIds.newId(),
          weeklyPlanId: planId,
          ingredientId: group.ingredient.id,
          name: group.ingredient.name,
          quantity: group.total?.amount,
          unit: group.total?.unit,
          category: ShoppingItem.categoryOr(group.ingredient.category),
          isChecked: carried?.isChecked ?? false,
        ),
      );
    }

    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete(
        _table,
        where: 'weekly_plan_id = ? AND is_manual = 0',
        whereArgs: [planId],
      );
      for (final item in generated) {
        await txn.insert(_table, item.toMap());
      }
    });

    return loadShoppingList(planId);
  }

  // ----------------------------------------------------------------- reads

  /// The saved list for [planId], generated and manual lines together, in
  /// shopping order.
  ///
  /// A pure read: it never generates, so opening the screen twice cannot
  /// create anything. An empty result means nothing has been generated yet.
  Future<List<ShoppingItem>> loadShoppingList(String planId) async {
    final rows = await _rows(planId);
    rows.sort(_byShoppingOrder);
    return rows;
  }

  /// The list for [planId] split into category sections, empty ones dropped.
  Future<List<ShoppingCategoryGroup>> loadGroupedShoppingList(
    String planId,
  ) async {
    final items = await loadShoppingList(planId);
    final byCategory = <String, List<ShoppingItem>>{};
    for (final item in items) {
      byCategory.putIfAbsent(item.category, () => []).add(item);
    }
    return [
      for (final category in _orderedCategories(byCategory.keys))
        ShoppingCategoryGroup(category: category, items: byCategory[category]!),
    ];
  }

  // --------------------------------------------------------------- history

  /// Previous weeks' shopping lists, newest first.
  ///
  /// Only confirmed weeks before the one containing [now] count, matching
  /// [PlanningService.getPlanHistory], and only weeks with at least one saved
  /// line: a week whose list was never built has nothing to look back on.
  Future<List<ShoppingListSummary>> getShoppingHistory({DateTime? now}) async {
    final db = await _db;
    final currentWeek = PrepDates.toIso(
      PrepDates.weekStartFor((now ?? DateTime.now()).toUtc()),
    );
    final rows = await db.rawQuery(
      '''
      SELECT p.*,
        COUNT(s.id) AS item_count,
        COALESCE(SUM(s.is_checked), 0) AS checked_count
      FROM weekly_plans p
      JOIN $_table s ON s.weekly_plan_id = p.id
      WHERE p.status = ? AND p.week_start < ?
      GROUP BY p.id
      ORDER BY p.week_start DESC, p.updated_at DESC
      ''',
      [PlanStatus.confirmed.value, currentWeek],
    );
    return rows.map(ShoppingListSummary.fromMap).toList();
  }

  /// The saved list for [planId] with its plan, or null if the plan is
  /// unknown.
  ///
  /// Strictly a read. Unlike opening the current week, this never generates:
  /// building a missing list now would use today's recipes and present them
  /// as what was bought back then.
  Future<SavedShoppingList?> getSavedShoppingList(String planId) async {
    final plan = await _planning.getPlan(planId);
    if (plan == null) return null;
    return SavedShoppingList(
      plan: plan,
      groups: await loadGroupedShoppingList(planId),
    );
  }

  /// One line by id, or null.
  Future<ShoppingItem?> getItem(String id) async {
    final db = await _db;
    final rows = await db.query(
      _table,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : ShoppingItem.fromMap(rows.first);
  }

  // --------------------------------------------------------------- writing

  /// Flips the checked state of one line and returns it.
  ///
  /// Works on generated and manual lines alike — ticking something off is the
  /// one edit that makes sense for both.
  Future<ShoppingItem> toggleItem(String id, {bool? isChecked}) async {
    final item = await _require(id);
    final next = isChecked ?? !item.isChecked;
    if (next == item.isChecked) return item;

    final db = await _db;
    await db.update(
      _table,
      {'is_checked': next ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
    return item.copyWith(isChecked: next);
  }

  /// Unticks everything on [planId], for starting a fresh shop.
  Future<void> clearChecked(String planId) async {
    final db = await _db;
    await db.update(
      _table,
      {'is_checked': 0},
      where: 'weekly_plan_id = ?',
      whereArgs: [planId],
    );
  }

  /// Adds a line the household typed in themselves.
  ///
  /// Manual lines are free text and are never matched against the ingredient
  /// library: someone adding "bin bags" is not describing a recipe. [quantity]
  /// stays null when they did not give one.
  Future<ShoppingItem> addManualItem({
    required String planId,
    required String name,
    double? quantity,
    String? unit,
    String? category,
  }) async {
    final plan = await _planning.getPlan(planId);
    if (plan == null) {
      throw ShoppingException('Plan $planId does not exist.');
    }
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw const ShoppingException('A shopping item needs a name.');
    }

    final item = ShoppingItem(
      id: PrepIds.newId(),
      weeklyPlanId: planId,
      name: trimmed,
      quantity: quantity,
      unit: QuantityMath.canonicalUnit(unit),
      category: ShoppingItem.categoryOr(category),
      isManual: true,
    );
    final db = await _db;
    await db.insert(_table, item.toMap());
    return item;
  }

  /// Edits a manual line.
  ///
  /// Only manual lines can be edited. A generated line is rebuilt from its
  /// recipe on every regeneration, so an edit to one would silently disappear
  /// later; the honest way to change it is to change the meal's ingredients.
  /// Pass [clearQuantity] to remove an amount rather than replace it —
  /// omitting [quantity] leaves the existing one alone.
  Future<ShoppingItem> updateItem(
    String id, {
    String? name,
    double? quantity,
    bool clearQuantity = false,
    String? unit,
    bool clearUnit = false,
    String? category,
  }) async {
    final item = await _require(id);
    if (!item.isManual) {
      throw ShoppingException(
        'Line $id was generated from the plan. Edit the meal it came from.',
      );
    }

    final trimmed = name?.trim();
    if (trimmed != null && trimmed.isEmpty) {
      throw const ShoppingException('A shopping item needs a name.');
    }

    final updated = ShoppingItem(
      id: item.id,
      weeklyPlanId: item.weeklyPlanId,
      ingredientId: item.ingredientId,
      name: trimmed ?? item.name,
      quantity: clearQuantity ? null : (quantity ?? item.quantity),
      unit: clearUnit ? null : QuantityMath.canonicalUnit(unit ?? item.unit),
      category: category ?? item.category,
      isChecked: item.isChecked,
      isManual: true,
    );

    final db = await _db;
    await db.update(_table, updated.toMap(), where: 'id = ?', whereArgs: [id]);
    return updated;
  }

  /// Removes a manual line.
  ///
  /// Generated lines cannot be deleted — the next regeneration would bring
  /// them straight back, so the delete would read as broken.
  Future<void> deleteManualItem(String id) async {
    final db = await _db;
    final deleted = await db.delete(
      _table,
      where: 'id = ? AND is_manual = 1',
      whereArgs: [id],
    );
    if (deleted == 0) {
      throw ShoppingException('Line $id is not a manual item.');
    }
  }

  // --------------------------------------------------------------- helpers

  Future<List<ShoppingItem>> _rows(String planId) async {
    final db = await _db;
    final rows = await db.query(
      _table,
      where: 'weekly_plan_id = ?',
      whereArgs: [planId],
    );
    return rows.map(ShoppingItem.fromMap).toList();
  }

  Future<ShoppingItem> _require(String id) async {
    final item = await getItem(id);
    if (item == null) {
      throw ShoppingException('Shopping item $id does not exist.');
    }
    return item;
  }

  /// Walks every meal in the plan and buckets its recipe lines into the
  /// groups that can each become one shopping line.
  Future<Map<String, _Contribution>> _collectContributions(
    List<WeeklyPlanItem> items,
  ) async {
    // One read per distinct meal; a meal in two slots contributes twice.
    final recipes = <String, List<MealRecipeLine>>{};
    final groups = <String, _Contribution>{};

    for (final item in items) {
      final recipe = recipes[item.mealVariantId] ??= await _mealService
          .getIngredientsForMeal(item.mealVariantId);
      for (final line in recipe) {
        final key = _keyFor(
          ingredientId: line.ingredient.id,
          quantity: line.quantity,
          unit: line.unit,
        );
        (groups[key] ??= _Contribution(line.ingredient)).add(line);
      }
    }
    return groups;
  }

  /// The identity a generated line keeps across regenerations.
  ///
  /// Derived only from what a saved row already carries, so an existing row
  /// and a freshly computed group produce the same key without storing one.
  static String _keyFor({
    required String ingredientId,
    required double? quantity,
    required String? unit,
  }) => quantity == null
      ? '$ingredientId|unknown'
      : '$ingredientId|${QuantityMath.bucketKey(unit)}';

  static String _identityOf(ShoppingItem row) => _keyFor(
    // A generated row whose ingredient was deleted falls back to its name so
    // it still matches itself rather than duplicating.
    ingredientId:
        row.ingredientId ?? 'name:${Ingredient.normaliseName(row.name)}',
    quantity: row.quantity,
    unit: row.unit,
  );

  static Iterable<String> _orderedCategories(Iterable<String> present) {
    final seen = present.toSet();
    return [
      ...categoryOrder.where(seen.contains),
      // Anything the app has not heard of still gets shown, at the end.
      ...seen.where((c) => !categoryOrder.contains(c)).toList()..sort(),
    ];
  }

  static int _byShoppingOrder(ShoppingItem a, ShoppingItem b) {
    final byCategory = _categoryRank(
      a.category,
    ).compareTo(_categoryRank(b.category));
    if (byCategory != 0) return byCategory;
    final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
    if (byName != 0) return byName;
    // A quantified line reads before its unquantified twin.
    final byKnown = (a.quantity == null ? 1 : 0).compareTo(
      b.quantity == null ? 1 : 0,
    );
    if (byKnown != 0) return byKnown;
    return (a.unit ?? '').compareTo(b.unit ?? '');
  }

  static int _categoryRank(String category) {
    final index = categoryOrder.indexOf(category);
    return index == -1 ? categoryOrder.length : index;
  }
}

/// Everything contributing to one shopping line while it is being built.
class _Contribution {
  _Contribution(this.ingredient);

  final Ingredient ingredient;
  final List<Quantity> parts = [];

  void add(MealRecipeLine line) {
    final quantity = line.quantity;
    if (quantity != null) parts.add(Quantity(quantity, line.unit));
  }

  /// Null when no contribution carried an amount — the line shows no
  /// quantity rather than a made-up one.
  Quantity? get total => QuantityMath.sum(parts);
}
