import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:preppick/models/models.dart';
import 'package:preppick/services/database_service.dart';
import 'package:preppick/services/settings_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late Directory tempDir;
  late DatabaseService database;
  late SettingsService service;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('preppick_settings_test');
    database = DatabaseService(
      factory: databaseFactoryFfi,
      databaseName: '${tempDir.path}/preppick_test.db',
    );
    service = SettingsService(database);
  });

  tearDown(() async {
    await database.close();
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  group('getSettings', () {
    test('returns the documented defaults on a first run', () async {
      final settings = await service.getSettings();

      expect(settings, AppSettings.defaults);
      expect(settings.breakfastCount, 1);
      expect(settings.lunchCount, 1);
      expect(settings.dinnerCount, 2);
    });

    test('falls back per key when only some keys are stored', () async {
      final db = await database.database;
      await db.insert('settings', {
        'key': SettingsService.lunchKey,
        'value': '4',
      });

      final settings = await service.getSettings();

      expect(settings.lunchCount, 4);
      // Untouched keys keep their defaults rather than collapsing to zero.
      expect(settings.breakfastCount, AppSettings.defaults.breakfastCount);
      expect(settings.dinnerCount, AppSettings.defaults.dinnerCount);
    });

    test('clamps values written outside the allowed range', () async {
      final db = await database.database;
      await db.insert('settings', {
        'key': SettingsService.dinnerKey,
        'value': '99',
      });
      await db.insert('settings', {
        'key': SettingsService.breakfastKey,
        'value': '-3',
      });

      final settings = await service.getSettings();

      expect(settings.dinnerCount, AppSettings.maxCount);
      expect(settings.breakfastCount, AppSettings.minCount);
    });

    test('falls back to the default for an unparsable value', () async {
      final db = await database.database;
      await db.insert('settings', {
        'key': SettingsService.dinnerKey,
        'value': 'not a number',
      });

      final settings = await service.getSettings();

      expect(settings.dinnerCount, AppSettings.defaults.dinnerCount);
    });

    test('ignores settings rows belonging to other features', () async {
      final db = await database.database;
      await db.insert('settings', {'key': 'demo_seed_version', 'value': '1'});

      expect(await service.getSettings(), AppSettings.defaults);
    });
  });

  group('saveSettings', () {
    test('persists new values and reloads them', () async {
      const wanted = AppSettings(
        breakfastCount: 0,
        lunchCount: 3,
        dinnerCount: 5,
      );

      final written = await service.saveSettings(wanted);

      expect(written, wanted);
      expect(await service.getSettings(), wanted);
    });

    test('accepts zero in every category', () async {
      const none = AppSettings(
        breakfastCount: 0,
        lunchCount: 0,
        dinnerCount: 0,
      );

      await service.saveSettings(none);
      final reloaded = await service.getSettings();

      expect(reloaded, none);
      expect(reloaded.isEmpty, isTrue);
    });

    test('clamps out-of-range values instead of rejecting them', () async {
      final written = await service.saveSettings(
        const AppSettings(breakfastCount: -1, lunchCount: 50, dinnerCount: 2),
      );

      expect(written.breakfastCount, AppSettings.minCount);
      expect(written.lunchCount, AppSettings.maxCount);
      expect(written.dinnerCount, 2);
      // What was returned is exactly what was stored.
      expect(await service.getSettings(), written);
    });

    test('overwrites rather than accumulating rows', () async {
      await service.saveSettings(const AppSettings(lunchCount: 2));
      await service.saveSettings(const AppSettings(lunchCount: 6));

      final db = await database.database;
      final rows = await db.query(
        'settings',
        where: 'key = ?',
        whereArgs: [SettingsService.lunchKey],
      );

      expect(rows, hasLength(1));
      expect((await service.getSettings()).lunchCount, 6);
    });

    test('survives closing and reopening the database', () async {
      const wanted = AppSettings(
        breakfastCount: 0,
        lunchCount: 1,
        dinnerCount: 2,
      );
      await service.saveSettings(wanted);
      await database.close();

      expect(await service.getSettings(), wanted);
    });
  });

  test('clearSettings returns the next read to defaults', () async {
    await service.saveSettings(const AppSettings(lunchCount: 7));
    await service.clearSettings();

    expect(await service.getSettings(), AppSettings.defaults);
  });
}
