import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:preppick/models/models.dart';
import 'package:preppick/providers/settings_provider.dart';
import 'package:preppick/services/database_service.dart';
import 'package:preppick/services/settings_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// A service that fails on demand, to exercise the provider's error path.
class _FailingSettingsService implements SettingsService {
  _FailingSettingsService({this.failLoad = false, this.failSave = false});

  final bool failLoad;
  final bool failSave;

  @override
  Future<AppSettings> getSettings() async {
    if (failLoad) throw StateError('load failed');
    return AppSettings.defaults;
  }

  @override
  Future<bool> hasSavedMealCounts() async {
    if (failLoad) throw StateError('load failed');
    return false;
  }

  @override
  Future<AppSettings> saveSettings(AppSettings settings) async {
    if (failSave) throw StateError('save failed');
    return settings.copyWith();
  }

  @override
  Future<void> clearSettings() async {}
}

void main() {
  sqfliteFfiInit();

  late Directory tempDir;
  late DatabaseService database;
  late SettingsService service;
  late SettingsProvider provider;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('preppick_provider_test');
    database = DatabaseService(
      factory: databaseFactoryFfi,
      databaseName: '${tempDir.path}/preppick_test.db',
    );
    service = SettingsService(database);
    provider = SettingsProvider(service);
  });

  tearDown(() async {
    provider.dispose();
    await database.close();
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  group('load', () {
    test('starts on defaults before anything is loaded', () {
      expect(provider.settings, AppSettings.defaults);
      expect(provider.hasLoaded, isFalse);
      expect(provider.isLoading, isFalse);
    });

    test('missing settings produce defaults', () async {
      await provider.load();

      expect(provider.settings, AppSettings.defaults);
      expect(provider.hasLoaded, isTrue);
      expect(provider.error, isNull);
    });

    test('reports loading state and notifies around the read', () async {
      var notifications = 0;
      provider.addListener(() => notifications++);

      final future = provider.load();
      expect(provider.isLoading, isTrue);
      await future;

      expect(provider.isLoading, isFalse);
      // One notification when loading starts, one when it finishes.
      expect(notifications, 2);
    });

    test('reloading returns the saved values', () async {
      await provider.load();
      provider.updateMealCounts(breakfast: 0, lunch: 3, dinner: 4);
      await provider.save();

      final reloaded = SettingsProvider(service);
      addTearDown(reloaded.dispose);
      await reloaded.load();

      expect(reloaded.settings.breakfastCount, 0);
      expect(reloaded.settings.lunchCount, 3);
      expect(reloaded.settings.dinnerCount, 4);
    });

    test('keeps defaults and records the error when the read fails', () async {
      final failing = SettingsProvider(_FailingSettingsService(failLoad: true));
      addTearDown(failing.dispose);

      await failing.load();

      expect(failing.settings, AppSettings.defaults);
      expect(failing.error, isA<StateError>());
      expect(failing.hasLoaded, isTrue);
      expect(failing.isLoading, isFalse);
    });
  });

  group('editing', () {
    setUp(() => provider.load());

    test('increment and decrement move one step', () {
      provider.setCount(MealType.dinner, 2);

      provider.increment(MealType.dinner);
      expect(provider.settings.dinnerCount, 3);

      provider.decrement(MealType.dinner);
      expect(provider.settings.dinnerCount, 2);
    });

    test('decrement stops at zero', () {
      provider.setCount(MealType.breakfast, 0);
      provider.decrement(MealType.breakfast);

      expect(provider.settings.breakfastCount, AppSettings.minCount);
    });

    test('increment stops at the documented maximum', () {
      provider.setCount(MealType.lunch, AppSettings.maxCount);
      provider.increment(MealType.lunch);

      expect(provider.settings.lunchCount, AppSettings.maxCount);
    });

    test('setCount clamps a value beyond the range', () {
      provider.setCount(MealType.dinner, 40);
      expect(provider.settings.dinnerCount, AppSettings.maxCount);

      provider.setCount(MealType.dinner, -5);
      expect(provider.settings.dinnerCount, AppSettings.minCount);
    });

    test('a no-op edit does not notify', () {
      provider.setCount(MealType.lunch, 1);
      var notifications = 0;
      provider.addListener(() => notifications++);

      // Same value, and a decrement already at the floor: neither changes
      // anything, so neither should rebuild the screen.
      provider.setCount(MealType.lunch, 1);
      provider.setCount(MealType.breakfast, 0);
      provider.decrement(MealType.breakfast);
      expect(notifications, 1);

      // Only a real change notifies.
      provider.setCount(MealType.lunch, 2);
      expect(notifications, 2);
    });

    test('edits are not persisted until save is called', () async {
      provider.setCount(MealType.dinner, 6);

      expect(provider.hasUnsavedChanges, isTrue);
      expect(
        (await service.getSettings()).dinnerCount,
        AppSettings.defaults.dinnerCount,
      );
    });

    test('revert throws away unsaved edits', () async {
      provider.setCount(MealType.dinner, 6);
      provider.revert();

      expect(provider.settings, provider.savedSettings);
      expect(provider.hasUnsavedChanges, isFalse);
    });

    test('hasNoMeals is true only when every count is zero', () {
      provider.updateMealCounts(breakfast: 0, lunch: 0, dinner: 0);
      expect(provider.hasNoMeals, isTrue);

      provider.increment(MealType.lunch);
      expect(provider.hasNoMeals, isFalse);
    });
  });

  group('save', () {
    test('persists the working copy and clears the unsaved flag', () async {
      await provider.load();
      provider.updateMealCounts(breakfast: 0, lunch: 2, dinner: 3);

      expect(await provider.save(), isTrue);
      expect(provider.hasUnsavedChanges, isFalse);
      expect(provider.savedSettings, provider.settings);
      expect(await service.getSettings(), provider.settings);
    });

    test('accepts all zeros', () async {
      await provider.load();
      provider.updateMealCounts(breakfast: 0, lunch: 0, dinner: 0);

      expect(await provider.save(), isTrue);
      expect((await service.getSettings()).isEmpty, isTrue);
    });

    test('reports the saving state', () async {
      await provider.load();

      final future = provider.save();
      expect(provider.isSaving, isTrue);
      await future;
      expect(provider.isSaving, isFalse);
    });

    test('returns false and records the error when the write fails', () async {
      final failing = SettingsProvider(_FailingSettingsService(failSave: true));
      addTearDown(failing.dispose);
      await failing.load();
      failing.setCount(MealType.lunch, 4);

      expect(await failing.save(), isFalse);
      expect(failing.error, isA<StateError>());
      // The edit is kept so the user can retry without re-entering it.
      expect(failing.settings.lunchCount, 4);
      expect(failing.isSaving, isFalse);
    });
  });
}
