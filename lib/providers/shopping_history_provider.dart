import 'package:flutter/foundation.dart';

import '../models/models.dart';
import '../services/shopping_service.dart';

/// Owns the state for looking back at previous weeks' shopping lists.
///
/// Deliberately separate from [ShoppingProvider]. That provider holds the
/// list the Shopping tab is shopping from, and every tap on it writes; opening
/// an old week in it would swap the tab's list out from under the household
/// and send the next tick to the wrong week. This one is read-only, so a past
/// list can be browsed without any risk to the current one.
class ShoppingHistoryProvider extends ChangeNotifier {
  ShoppingHistoryProvider(this._service, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final ShoppingService _service;
  final DateTime Function() _clock;

  List<ShoppingListSummary> _summaries = const [];
  bool _isLoading = false;
  bool _hasLoaded = false;
  Object? _error;

  String? _weekPlanId;
  SavedShoppingList? _week;
  bool _isLoadingWeek = false;
  Object? _weekError;

  bool _isDisposed = false;

  /// Previous weeks with a saved list, newest first.
  List<ShoppingListSummary> get summaries => _summaries;

  /// True while the list of past weeks is being read.
  bool get isLoading => _isLoading;

  /// True once [loadHistory] has completed at least once.
  bool get hasLoaded => _hasLoaded;

  /// The last failure loading past weeks, or null.
  Object? get error => _error;

  /// The plan whose list [openWeek] last asked for.
  String? get weekPlanId => _weekPlanId;

  /// The opened week's saved list, or null while loading, on failure, or
  /// when the plan no longer exists.
  SavedShoppingList? get week => _week;

  /// True while one week's list is being read.
  bool get isLoadingWeek => _isLoadingWeek;

  /// The last failure opening a week, or null.
  Object? get weekError => _weekError;

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }

  void _safeNotify() {
    if (_isDisposed) return;
    notifyListeners();
  }

  /// Reads the past weeks. Called on every visit, since a week confirmed in
  /// the meantime may have rolled into the past.
  Future<void> loadHistory() async {
    if (_isLoading) return;
    _isLoading = true;
    _error = null;
    _safeNotify();
    try {
      _summaries = await _service.getShoppingHistory(now: _clock());
    } catch (error) {
      _error = error;
    } finally {
      _isLoading = false;
      _hasLoaded = true;
      _safeNotify();
    }
  }

  /// Reads the saved list for [planId]. Never generates one.
  Future<void> openWeek(String planId) async {
    if (planId != _weekPlanId) {
      // Drop the previous week straight away, so its lines are never shown
      // under this week's heading while the new ones load.
      _week = null;
    }
    _weekPlanId = planId;
    _isLoadingWeek = true;
    _weekError = null;
    _safeNotify();
    try {
      final week = await _service.getSavedShoppingList(planId);
      // A newer open won the race; its result is the one to keep.
      if (_weekPlanId != planId) return;
      _week = week;
    } catch (error) {
      if (_weekPlanId != planId) return;
      _weekError = error;
    } finally {
      if (_weekPlanId == planId) {
        _isLoadingWeek = false;
        _safeNotify();
      }
    }
  }
}
