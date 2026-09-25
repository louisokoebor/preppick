import 'package:sqflite/sqflite.dart';

import '../models/models.dart';
import 'database_service.dart';

/// Reads and writes the household's meal counts.
///
/// Counts live in the key/value `settings` table, one row per category, so
/// later settings (household size, dietary preferences) can be added without
/// a schema change. This service owns every statement that touches those
/// rows; providers and widgets never see SQL.
///
/// Missing rows are not an error. A first run has no rows at all, and
/// [AppSettings.fromMap] fills each absent key from [AppSettings.defaults],
/// so `getSettings` always returns a usable object. Stored values are clamped
/// to [AppSettings.minCount]..[AppSettings.maxCount] on the way in as well as
/// on the way out, so a value written by an older build is normalised rather
/// than trusted.
class SettingsService {
  SettingsService(this._databaseService);

  static const String _table = 'settings';

  /// Keys this service owns, matching [AppSettings.toMap].
  static const String breakfastKey = 'breakfast_count';
  static const String lunchKey = 'lunch_count';
  static const String dinnerKey = 'dinner_count';

  static const List<String> _mealCountKeys = [
    breakfastKey,
    lunchKey,
    dinnerKey,
  ];

  final DatabaseService _databaseService;

  /// The stored meal counts, falling back to defaults for anything unset.
  Future<AppSettings> getSettings() async {
    final db = await _databaseService.database;
    final rows = await db.query(
      _table,
      columns: ['key', 'value'],
      where: 'key IN (${List.filled(_mealCountKeys.length, '?').join(', ')})',
      whereArgs: _mealCountKeys,
    );

    return AppSettings.fromMap({
      for (final row in rows) row['key']! as String: row['value'],
    });
  }

  /// True once the household has explicitly saved meal counts.
  ///
  /// Demo seed metadata also lives in `settings`, so first-run detection must
  /// look only at the three meal-count keys this service owns.
  Future<bool> hasSavedMealCounts() async {
    final db = await _databaseService.database;
    final rows = await db.query(
      _table,
      columns: ['key'],
      where: 'key IN (${List.filled(_mealCountKeys.length, '?').join(', ')})',
      whereArgs: _mealCountKeys,
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  /// Persists [settings], clamped, replacing any previous values.
  ///
  /// Returns what was actually written, which differs from the argument when
  /// a count had to be clamped. The whole write is one transaction so the
  /// three counts can never be persisted half-updated.
  Future<AppSettings> saveSettings(AppSettings settings) async {
    final clamped = settings.copyWith();
    final db = await _databaseService.database;

    await db.transaction((txn) async {
      for (final entry in clamped.toMap().entries) {
        await txn.insert(_table, {
          'key': entry.key,
          'value': '${entry.value}',
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });

    return clamped;
  }

  /// Removes the stored counts so the next read returns defaults.
  ///
  /// Development and test helper; not exposed in the UI.
  Future<void> clearSettings() async {
    final db = await _databaseService.database;
    await db.delete(
      _table,
      where: 'key IN (${List.filled(_mealCountKeys.length, '?').join(', ')})',
      whereArgs: _mealCountKeys,
    );
  }
}
