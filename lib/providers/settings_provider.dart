import 'package:flutter/foundation.dart';

import '../models/models.dart';
import '../services/settings_service.dart';

/// Owns the meal-count state for the Select Meal Count screen.
///
/// The counts live here, not in widget state, because the planner reads them
/// too: the same numbers decide how many slots Plan This Week renders and how
/// many meals [PlanningService] is asked for. Widgets edit through
/// [setCount]/[increment]/[decrement] and persist with [save].
///
/// Edits are held in memory until [save] is called, so leaving the screen
/// without pressing Continue does not change what is stored. [settings] is
/// therefore the working copy; [savedSettings] is what is on disk.
class SettingsProvider extends ChangeNotifier {
  SettingsProvider(this._service);

  final SettingsService _service;

  AppSettings _settings = AppSettings.defaults;
  AppSettings _savedSettings = AppSettings.defaults;
  bool _hasSavedSettings = false;
  bool _isLoading = false;
  bool _isSaving = false;
  bool _hasLoaded = false;
  bool _isDisposed = false;
  Object? _error;
  bool _errorIsFromSave = false;

  /// The working copy the UI edits.
  AppSettings get settings => _settings;

  /// The last values successfully read from or written to storage.
  AppSettings get savedSettings => _savedSettings;

  /// True after meal-count settings have been explicitly persisted at least
  /// once. A missing row is first run; a saved all-zero setting is returning.
  bool get hasSavedSettings => _hasSavedSettings;

  /// True while [load] is in flight.
  bool get isLoading => _isLoading;

  /// True while [save] is in flight.
  bool get isSaving => _isSaving;

  /// True once a load has completed, successfully or not.
  bool get hasLoaded => _hasLoaded;

  /// The last load or save failure, or null. Cleared when either succeeds.
  Object? get error => _error;

  /// True when [error] came from reading, so the steppers are showing
  /// defaults rather than what is stored. A save failure leaves the numbers on
  /// screen correct and only the write undone, and the two need different
  /// copy — this is what lets the screen tell them apart.
  bool get hasLoadError => _error != null && !_errorIsFromSave;

  /// True when [error] came from writing.
  bool get hasSaveError => _error != null && _errorIsFromSave;

  /// True when the working copy differs from what is stored.
  bool get hasUnsavedChanges => _settings != _savedSettings;

  /// True when every count is zero. A plan cannot be generated from this.
  bool get hasNoMeals => _settings.isEmpty;

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }

  /// Notifies unless this provider is gone.
  ///
  /// The screen starts a load from a post-frame callback, so a user who
  /// leaves immediately can dispose this provider while the read is still in
  /// flight. Without this guard that read would notify a dead notifier and
  /// throw on the way out.
  void _safeNotify() {
    if (_isDisposed) return;
    notifyListeners();
  }

  /// Loads stored counts. Safe to call more than once; concurrent calls are
  /// collapsed into the one already running.
  Future<void> load() async {
    if (_isLoading) return;
    _isLoading = true;
    _error = null;
    _errorIsFromSave = false;
    _safeNotify();

    try {
      final hasSaved = await _service.hasSavedMealCounts();
      final loaded = await _service.getSettings();
      _hasSavedSettings = hasSaved;
      _savedSettings = loaded;
      _settings = loaded;
    } catch (error) {
      // Keep the defaults rather than blanking the screen; the UI can show
      // [error] and the user can still choose counts and retry the save.
      _error = error;
    } finally {
      _isLoading = false;
      _hasLoaded = true;
      _safeNotify();
    }
  }

  /// Sets one category's count, clamped to the allowed range.
  void setCount(MealType type, int value) {
    final next = _settings.withCount(type, value);
    if (next == _settings) return;
    _settings = next;
    notifyListeners();
  }

  /// Adds one to a category, stopping at [AppSettings.maxCount].
  void increment(MealType type) => setCount(type, _settings.countFor(type) + 1);

  /// Removes one from a category, stopping at [AppSettings.minCount].
  void decrement(MealType type) => setCount(type, _settings.countFor(type) - 1);

  /// Replaces all three counts at once.
  void updateMealCounts({int? breakfast, int? lunch, int? dinner}) {
    final next = _settings.copyWith(
      breakfastCount: breakfast,
      lunchCount: lunch,
      dinnerCount: dinner,
    );
    if (next == _settings) return;
    _settings = next;
    notifyListeners();
  }

  /// Persists the working copy. Returns true when the write succeeded.
  Future<bool> save() async {
    if (_isSaving) return false;
    _isSaving = true;
    _error = null;
    _errorIsFromSave = false;
    _safeNotify();

    try {
      // The service returns what it actually wrote, which is the clamped
      // value, so the working copy cannot drift from storage.
      final written = await _service.saveSettings(_settings);
      _hasSavedSettings = true;
      _savedSettings = written;
      _settings = written;
      return true;
    } catch (error) {
      _error = error;
      _errorIsFromSave = true;
      return false;
    } finally {
      _isSaving = false;
      _safeNotify();
    }
  }

  /// Throws away unsaved edits.
  void revert() {
    if (_settings == _savedSettings) return;
    _settings = _savedSettings;
    notifyListeners();
  }
}
