import 'package:flutter/foundation.dart';

import '../models/models.dart';
import '../services/shopping_service.dart';

/// Owns the shopping-list state for one week.
///
/// Coordinates [ShoppingService] and holds nothing it could ask for again:
/// no aggregation, no unit arithmetic, no SQL. What lives here is the state a
/// screen needs between taps — the loaded lines, which category filter is
/// selected, and whether a write is in flight.
///
/// ## Writes land immediately
///
/// Every mutation is persisted the moment it happens rather than batched
/// behind a save button. Shopping is done standing in an aisle: the app can
/// be backgrounded, killed by the OS or dropped on the floor at any point,
/// and a tick that only existed in memory would be a tick the household loses
/// after paying for the item. [toggleItem] therefore updates the row in
/// memory optimistically *and* writes, reverting only if the write fails — so
/// the checkbox responds at finger speed while the database stays the truth.
///
/// ## Generation is a one-time repair, not a page load
///
/// [openForPlan] reads the saved list and only generates when there is
/// nothing saved at all. Regenerating on every open would be wasteful and,
/// worse, would rebuild lines while someone is halfway through shopping.
/// [regenerate] exists for the deliberate case, after the plan's meals
/// changed.
class ShoppingProvider extends ChangeNotifier {
  ShoppingProvider(this._service);

  final ShoppingService _service;

  String? _planId;
  List<ShoppingItem> _items = const [];
  String? _categoryFilter;
  bool _isLoading = false;
  bool _isGenerating = false;
  bool _isWriting = false;
  bool _hasLoaded = false;
  bool _isDisposed = false;
  Object? _error;

  /// The plan whose list is loaded, or null before the first open.
  String? get planId => _planId;

  /// Every line of the loaded list, in shopping order, filter ignored.
  List<ShoppingItem> get items => _items;

  /// The selected category, or null for "All".
  String? get categoryFilter => _categoryFilter;

  /// True while the saved list is being read.
  bool get isLoading => _isLoading;

  /// True while the list is being built from the plan.
  bool get isGenerating => _isGenerating;

  /// True while a tick, edit, add or delete is being written.
  bool get isWriting => _isWriting;

  /// True once an open has completed, successfully or not.
  bool get hasLoaded => _hasLoaded;

  /// The last failure, or null. Cleared when the next operation starts.
  Object? get error => _error;

  /// True when a load or generate failed and there is nothing to show.
  bool get hasError => _error != null && _items.isEmpty;

  /// True when the list loaded cleanly and holds nothing. Distinct from
  /// [hasError]: an empty list is a state to explain, not a failure.
  bool get isEmpty => _hasLoaded && _error == null && _items.isEmpty;

  /// How many lines are ticked off, across the whole list.
  ///
  /// This and the getters below derive from [items] rather than the backing
  /// field, so a subclass that supplies its own lines — the widget tests' fake
  /// — gets consistent grouping and counts for free.
  int get checkedCount => items.where((item) => item.isChecked).length;

  /// How many lines there are in total.
  int get totalCount => items.length;

  /// True when every line is ticked and there is at least one.
  bool get isComplete => items.isNotEmpty && checkedCount == totalCount;

  /// Categories present in the loaded list, in shopping order. Drives the
  /// filter row, which never offers a category that would show nothing.
  List<String> get availableCategories {
    final present = items.map((item) => item.category).toSet();
    return [
      ...ShoppingService.categoryOrder.where(present.contains),
      ...present
          .where((c) => !ShoppingService.categoryOrder.contains(c))
          .toList()
        ..sort(),
    ];
  }

  /// The list as category sections, honouring [categoryFilter].
  ///
  /// Grouped here from the already-loaded lines rather than re-queried, so
  /// tapping a filter chip never touches the database.
  List<ShoppingCategoryGroup> get groups {
    final byCategory = <String, List<ShoppingItem>>{};
    for (final item in items) {
      if (_categoryFilter != null && item.category != _categoryFilter) {
        continue;
      }
      byCategory.putIfAbsent(item.category, () => []).add(item);
    }
    return [
      for (final category in availableCategories)
        if (byCategory[category] != null)
          ShoppingCategoryGroup(
            category: category,
            items: byCategory[category]!,
          ),
    ];
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

  /// Shows the list for [planId], building it the first time.
  ///
  /// Reads what is saved and generates only when nothing is. Opening the
  /// screen repeatedly is therefore free and, crucially, non-destructive:
  /// progress made in the shop survives every reopen.
  Future<void> openForPlan(String planId) async {
    if (_isLoading || _isGenerating) return;
    // A different week is a different list; drop the old one rather than let
    // it flash on screen under the new plan's header.
    if (planId != _planId) {
      _items = const [];
      _categoryFilter = null;
      _hasLoaded = false;
    }
    _planId = planId;
    _isLoading = true;
    _error = null;
    _safeNotify();

    try {
      var loaded = await _service.loadShoppingList(planId);
      if (loaded.isEmpty) {
        _isGenerating = true;
        _safeNotify();
        loaded = await _service.generateFromPlan(planId);
      }
      _items = loaded;
    } catch (error) {
      _error = error;
    } finally {
      _isLoading = false;
      _isGenerating = false;
      _hasLoaded = true;
      _safeNotify();
    }
  }

  /// Re-reads the saved list without generating anything.
  Future<void> reload() async {
    final planId = _planId;
    if (planId == null || _isLoading) return;
    _isLoading = true;
    _error = null;
    _safeNotify();

    try {
      _items = await _service.loadShoppingList(planId);
    } catch (error) {
      _error = error;
    } finally {
      _isLoading = false;
      _hasLoaded = true;
      _safeNotify();
    }
  }

  /// Rebuilds the generated lines from the plan's meals.
  ///
  /// For after the plan changed. Ticks on surviving lines are kept by the
  /// service, and manual lines are untouched.
  Future<bool> regenerate() async {
    final planId = _planId;
    if (planId == null || _isGenerating) return false;
    _isGenerating = true;
    _error = null;
    _safeNotify();

    try {
      _items = await _service.generateFromPlan(planId);
      return true;
    } catch (error) {
      _error = error;
      return false;
    } finally {
      _isGenerating = false;
      _hasLoaded = true;
      _safeNotify();
    }
  }

  /// Narrows the visible sections to one category, or clears the filter.
  void setCategoryFilter(String? category) {
    if (_categoryFilter == category) return;
    _categoryFilter = category;
    notifyListeners();
  }

  /// Ticks or unticks one line, writing straight through.
  ///
  /// The in-memory row flips first so the checkbox does not lag the finger,
  /// and is put back if the write fails — a tick that did not persist must
  /// not keep looking like one that did.
  Future<bool> toggleItem(String id, {bool? isChecked}) async {
    final index = _items.indexWhere((item) => item.id == id);
    if (index == -1) return false;

    final previous = _items[index];
    final next = isChecked ?? !previous.isChecked;
    if (next == previous.isChecked) return true;

    _replaceAt(index, previous.copyWith(isChecked: next));
    _error = null;
    _safeNotify();

    try {
      await _service.toggleItem(id, isChecked: next);
      return true;
    } catch (error) {
      _error = error;
      final current = _items.indexWhere((item) => item.id == id);
      if (current != -1) _replaceAt(current, previous);
      _safeNotify();
      return false;
    }
  }

  /// Unticks everything, for starting a fresh shop on the same list.
  Future<bool> clearChecked() async {
    final planId = _planId;
    if (planId == null || checkedCount == 0) return false;
    return _write(() async {
      await _service.clearChecked(planId);
      _items = await _service.loadShoppingList(planId);
    });
  }

  /// Adds a line the household typed in.
  ///
  /// [quantity] stays null when they did not give one; nothing is inferred
  /// from the name.
  Future<bool> addItem({
    required String name,
    double? quantity,
    String? unit,
    String? category,
  }) async {
    final planId = _planId;
    if (planId == null) return false;
    return _write(() async {
      await _service.addManualItem(
        planId: planId,
        name: name,
        quantity: quantity,
        unit: unit,
        category: category,
      );
      // Re-read rather than appending: the new line has to land in shopping
      // order, which the service owns.
      _items = await _service.loadShoppingList(planId);
    });
  }

  /// Edits a manual line. Generated lines are rejected by the service.
  Future<bool> updateItem(
    String id, {
    String? name,
    double? quantity,
    bool clearQuantity = false,
    String? unit,
    bool clearUnit = false,
    String? category,
  }) async {
    final planId = _planId;
    if (planId == null) return false;
    return _write(() async {
      await _service.updateItem(
        id,
        name: name,
        quantity: quantity,
        clearQuantity: clearQuantity,
        unit: unit,
        clearUnit: clearUnit,
        category: category,
      );
      _items = await _service.loadShoppingList(planId);
    });
  }

  /// Removes a manual line.
  Future<bool> deleteItem(String id) async {
    final planId = _planId;
    if (planId == null) return false;
    return _write(() async {
      await _service.deleteManualItem(id);
      _items = await _service.loadShoppingList(planId);
    });
  }

  /// Forgets the loaded list. Nothing stored is touched.
  void clear() {
    if (_planId == null && _items.isEmpty && _error == null) return;
    _planId = null;
    _items = const [];
    _categoryFilter = null;
    _hasLoaded = false;
    _error = null;
    notifyListeners();
  }

  void _replaceAt(int index, ShoppingItem item) {
    final next = [..._items];
    next[index] = item;
    _items = next;
  }

  /// Runs a write that reloads the list, recording failure as state.
  Future<bool> _write(Future<void> Function() action) async {
    if (_isWriting) return false;
    _isWriting = true;
    _error = null;
    _safeNotify();

    try {
      await action();
      return true;
    } catch (error) {
      _error = error;
      return false;
    } finally {
      _isWriting = false;
      _hasLoaded = true;
      _safeNotify();
    }
  }
}
