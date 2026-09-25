import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:preppick/models/models.dart';
import 'package:preppick/services/database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Rows used by several tests.
Map<String, Object?> _family(String id, {MealType type = MealType.dinner}) =>
    MealFamily(
      id: id,
      name: 'Lou Lou Spaghetti',
      mealType: type,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    ).toMap();

Map<String, Object?> _variant(String id, String familyId, {String? protein}) =>
    MealVariant(
      id: id,
      mealFamilyId: familyId,
      name: 'Lou Lou Spaghetti + Chicken',
      protein: protein,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    ).toMap();

Map<String, Object?> _ingredient(String id, String name) => Ingredient(
  id: id,
  name: name,
  category: IngredientCategory.protein,
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
).toMap();

Map<String, Object?> _plan(String id, {PlanStatus status = PlanStatus.draft}) =>
    WeeklyPlan(
      id: id,
      weekStart: DateTime.utc(2026, 3, 2),
      status: status,
      createdAt: DateTime.utc(2026, 3, 1),
    ).toMap();

void main() {
  sqfliteFfiInit();

  late Directory tempDir;
  late DatabaseService service;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('preppick_db_test');
    service = DatabaseService(
      factory: databaseFactoryFfi,
      databaseName: '${tempDir.path}/preppick_test.db',
    );
  });

  tearDown(() async {
    await service.close();
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  group('schema', () {
    test('creates the database at the current version', () async {
      final db = await service.database;

      expect(db.isOpen, isTrue);
      expect(await db.getVersion(), DatabaseService.schemaVersion);
    });

    test('creates every expected table', () async {
      final db = await service.database;

      final rows = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      );
      final names = rows.map((row) => row['name']! as String).toSet();

      expect(names, containsAll(DatabaseService.tableNames));
    });

    test('enables foreign keys', () async {
      final db = await service.database;

      final rows = await db.rawQuery('PRAGMA foreign_keys');

      expect(rows.single.values.single, 1);
    });

    test('returns the same instance to concurrent callers', () async {
      final results = await Future.wait([
        service.database,
        service.database,
        service.database,
      ]);

      expect(identical(results[0], results[1]), isTrue);
      expect(identical(results[1], results[2]), isTrue);
    });
  });

  group('meals', () {
    test('inserts and reads a meal family', () async {
      final db = await service.database;

      await db.insert('meal_families', _family('family-1'));
      final rows = await db.query('meal_families');

      final restored = MealFamily.fromMap(rows.single);
      expect(restored.id, 'family-1');
      expect(restored.mealType, MealType.dinner);
      expect(restored.createdAt, DateTime.utc(2026, 1, 1));
      expect(restored.archivedAt, isNull);
    });

    test('inserts and reads a variant referencing its family', () async {
      final db = await service.database;

      await db.insert('meal_families', _family('family-1'));
      await db.insert(
        'meal_variants',
        _variant('variant-1', 'family-1', protein: 'chicken'),
      );

      final rows = await db.query('meal_variants');
      final restored = MealVariant.fromMap(rows.single);

      expect(restored.mealFamilyId, 'family-1');
      expect(restored.protein, 'chicken');
      expect(restored.estimatedMinutes, isNull);
      expect(restored.timesPlanned, 0);
      expect(restored.lastPlannedAt, isNull);
    });

    test('rejects a variant pointing at a missing family', () async {
      final db = await service.database;

      expect(
        () => db.insert('meal_variants', _variant('variant-1', 'nope')),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('keeps a null ingredient quantity null', () async {
      final db = await service.database;

      await db.insert('meal_families', _family('family-1'));
      await db.insert('meal_variants', _variant('variant-1', 'family-1'));
      await db.insert('ingredients', _ingredient('ing-1', 'Scotch bonnet'));
      await db.insert(
        'meal_ingredients',
        const MealIngredient(
          id: 'mi-1',
          mealVariantId: 'variant-1',
          ingredientId: 'ing-1',
        ).toMap(),
      );

      final restored = MealIngredient.fromMap(
        (await db.query('meal_ingredients')).single,
      );

      expect(restored.quantity, isNull);
      expect(restored.unit, isNull);
      expect(restored.baseServings, isNull);
    });

    test('deleting a variant cascades to its recipe lines', () async {
      final db = await service.database;

      await db.insert('meal_families', _family('family-1'));
      await db.insert('meal_variants', _variant('variant-1', 'family-1'));
      await db.insert('ingredients', _ingredient('ing-1', 'Chicken thighs'));
      await db.insert(
        'meal_ingredients',
        const MealIngredient(
          id: 'mi-1',
          mealVariantId: 'variant-1',
          ingredientId: 'ing-1',
          quantity: 500,
          unit: 'g',
        ).toMap(),
      );

      await db.delete(
        'meal_variants',
        where: 'id = ?',
        whereArgs: ['variant-1'],
      );

      expect(await db.query('meal_ingredients'), isEmpty);
    });

    test('an ingredient still used by a recipe cannot be deleted', () async {
      final db = await service.database;

      await db.insert('meal_families', _family('family-1'));
      await db.insert('meal_variants', _variant('variant-1', 'family-1'));
      await db.insert('ingredients', _ingredient('ing-1', 'Chicken thighs'));
      await db.insert(
        'meal_ingredients',
        const MealIngredient(
          id: 'mi-1',
          mealVariantId: 'variant-1',
          ingredientId: 'ing-1',
        ).toMap(),
      );

      expect(
        () => db.delete('ingredients', where: 'id = ?', whereArgs: ['ing-1']),
        throwsA(isA<DatabaseException>()),
      );
    });
  });

  group('plans', () {
    test('persists a plan and its items', () async {
      final db = await service.database;

      await db.insert('meal_families', _family('family-1'));
      await db.insert('meal_variants', _variant('variant-1', 'family-1'));
      await db.insert('weekly_plans', _plan('plan-1'));
      await db.insert(
        'weekly_plan_items',
        const WeeklyPlanItem(
          id: 'item-1',
          weeklyPlanId: 'plan-1',
          mealVariantId: 'variant-1',
          mealType: MealType.dinner,
          slotIndex: 1,
        ).toMap(),
      );

      final plan = WeeklyPlan.fromMap((await db.query('weekly_plans')).single);
      final item = WeeklyPlanItem.fromMap(
        (await db.query('weekly_plan_items')).single,
      );

      expect(plan.weekStart, DateTime.utc(2026, 3, 2));
      expect(plan.status, PlanStatus.draft);
      expect(plan.confirmedAt, isNull);
      expect(plan.updatedAt, DateTime.utc(2026, 3, 1));
      expect(plan.estimatedPrepMinutes, isNull);
      expect(item.slot, const MealSlot(MealType.dinner, 1));
      expect(item.prepTiming, PrepTiming.mainPrep);
      expect(item.plannedCookDate, isNull);
    });

    test('persists plan and meal timing fields', () async {
      final db = await service.database;

      await db.insert('meal_families', _family('family-1'));
      await db.insert(
        'meal_variants',
        MealVariant(
          id: 'variant-1',
          mealFamilyId: 'family-1',
          name: 'Jollof Rice + Turkey',
          estimatedMinutes: 60,
          createdAt: DateTime.utc(2026, 1, 1),
          updatedAt: DateTime.utc(2026, 1, 1),
        ).toMap(),
      );
      await db.insert(
        'weekly_plans',
        WeeklyPlan(
          id: 'plan-1',
          weekStart: DateTime.utc(2026, 3, 2),
          status: PlanStatus.draft,
          estimatedPrepMinutes: 90,
          createdAt: DateTime.utc(2026, 3, 1),
        ).toMap(),
      );
      await db.insert(
        'weekly_plan_items',
        WeeklyPlanItem(
          id: 'item-1',
          weeklyPlanId: 'plan-1',
          mealVariantId: 'variant-1',
          mealType: MealType.dinner,
          slotIndex: 0,
          prepTiming: PrepTiming.later,
          plannedCookDate: DateTime.utc(2026, 3, 3),
        ).toMap(),
      );

      final variant = MealVariant.fromMap(
        (await db.query('meal_variants')).single,
      );
      final plan = WeeklyPlan.fromMap((await db.query('weekly_plans')).single);
      final item = WeeklyPlanItem.fromMap(
        (await db.query('weekly_plan_items')).single,
      );

      expect(variant.estimatedMinutes, 60);
      expect(plan.estimatedPrepMinutes, 90);
      expect(item.prepTiming, PrepTiming.later);
      expect(item.plannedCookDate, DateTime.utc(2026, 3, 3));
    });

    test('week_start is unique', () async {
      final db = await service.database;

      await db.insert('weekly_plans', _plan('plan-1'));

      expect(
        () => db.insert('weekly_plans', _plan('plan-2')),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('a confirmed plan protects the meals it references', () async {
      final db = await service.database;

      await db.insert('meal_families', _family('family-1'));
      await db.insert('meal_variants', _variant('variant-1', 'family-1'));
      await db.insert('weekly_plans', _plan('plan-1'));
      await db.insert(
        'weekly_plan_items',
        const WeeklyPlanItem(
          id: 'item-1',
          weeklyPlanId: 'plan-1',
          mealVariantId: 'variant-1',
          mealType: MealType.dinner,
          slotIndex: 0,
        ).toMap(),
      );

      expect(
        () => db.delete(
          'meal_variants',
          where: 'id = ?',
          whereArgs: ['variant-1'],
        ),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('archiving a planned meal keeps the plan intact', () async {
      final db = await service.database;

      await db.insert('meal_families', _family('family-1'));
      await db.insert('meal_variants', _variant('variant-1', 'family-1'));
      await db.insert('weekly_plans', _plan('plan-1'));
      await db.insert(
        'weekly_plan_items',
        const WeeklyPlanItem(
          id: 'item-1',
          weeklyPlanId: 'plan-1',
          mealVariantId: 'variant-1',
          mealType: MealType.dinner,
          slotIndex: 0,
        ).toMap(),
      );

      await db.update(
        'meal_variants',
        {'archived_at': DateTime.utc(2026, 4, 1).toIso8601String()},
        where: 'id = ?',
        whereArgs: ['variant-1'],
      );

      final variant = MealVariant.fromMap(
        (await db.query('meal_variants')).single,
      );
      expect(variant.isArchived, isTrue);
      expect(await db.query('weekly_plan_items'), hasLength(1));
    });

    test('deleting a plan cascades to items and shopping lines', () async {
      final db = await service.database;

      await db.insert('meal_families', _family('family-1'));
      await db.insert('meal_variants', _variant('variant-1', 'family-1'));
      await db.insert('weekly_plans', _plan('plan-1'));
      await db.insert(
        'weekly_plan_items',
        const WeeklyPlanItem(
          id: 'item-1',
          weeklyPlanId: 'plan-1',
          mealVariantId: 'variant-1',
          mealType: MealType.dinner,
          slotIndex: 0,
        ).toMap(),
      );
      await db.insert(
        'shopping_items',
        const ShoppingItem(
          id: 'shop-1',
          weeklyPlanId: 'plan-1',
          name: 'Chicken thighs',
          category: IngredientCategory.protein,
        ).toMap(),
      );

      await db.delete('weekly_plans', where: 'id = ?', whereArgs: ['plan-1']);

      expect(await db.query('weekly_plan_items'), isEmpty);
      expect(await db.query('shopping_items'), isEmpty);
    });

    test('the same slot cannot be filled twice in one plan', () async {
      final db = await service.database;

      await db.insert('meal_families', _family('family-1'));
      await db.insert('meal_variants', _variant('variant-1', 'family-1'));
      await db.insert('weekly_plans', _plan('plan-1'));
      await db.insert(
        'weekly_plan_items',
        const WeeklyPlanItem(
          id: 'item-1',
          weeklyPlanId: 'plan-1',
          mealVariantId: 'variant-1',
          mealType: MealType.dinner,
          slotIndex: 0,
        ).toMap(),
      );

      expect(
        () => db.insert(
          'weekly_plan_items',
          const WeeklyPlanItem(
            id: 'item-2',
            weeklyPlanId: 'plan-1',
            mealVariantId: 'variant-1',
            mealType: MealType.dinner,
            slotIndex: 0,
          ).toMap(),
        ),
        throwsA(isA<DatabaseException>()),
      );
    });
  });

  group('shopping items', () {
    test('persists the checked state', () async {
      final db = await service.database;

      await db.insert('weekly_plans', _plan('plan-1'));
      await db.insert('ingredients', _ingredient('ing-1', 'Chicken thighs'));
      await db.insert(
        'shopping_items',
        const ShoppingItem(
          id: 'shop-1',
          weeklyPlanId: 'plan-1',
          ingredientId: 'ing-1',
          name: 'Chicken thighs',
          quantity: 1.25,
          unit: 'kg',
          category: IngredientCategory.protein,
        ).toMap(),
      );

      await db.update(
        'shopping_items',
        {'is_checked': 1},
        where: 'id = ?',
        whereArgs: ['shop-1'],
      );

      final item = ShoppingItem.fromMap(
        (await db.query('shopping_items')).single,
      );
      expect(item.isChecked, isTrue);
      expect(item.quantity, 1.25);
    });

    test('deleting an ingredient leaves the shopping line intact', () async {
      final db = await service.database;

      await db.insert('weekly_plans', _plan('plan-1'));
      await db.insert('ingredients', _ingredient('ing-1', 'Chicken thighs'));
      await db.insert(
        'shopping_items',
        const ShoppingItem(
          id: 'shop-1',
          weeklyPlanId: 'plan-1',
          ingredientId: 'ing-1',
          name: 'Chicken thighs',
          category: IngredientCategory.protein,
        ).toMap(),
      );

      await db.delete('ingredients', where: 'id = ?', whereArgs: ['ing-1']);

      final item = ShoppingItem.fromMap(
        (await db.query('shopping_items')).single,
      );
      expect(item.ingredientId, isNull);
      expect(item.name, 'Chicken thighs');
    });

    test('a manual item needs no ingredient', () async {
      final db = await service.database;

      await db.insert('weekly_plans', _plan('plan-1'));
      await db.insert(
        'shopping_items',
        const ShoppingItem(
          id: 'shop-1',
          weeklyPlanId: 'plan-1',
          name: 'Kitchen roll',
          category: IngredientCategory.household,
          isManual: true,
        ).toMap(),
      );

      final item = ShoppingItem.fromMap(
        (await db.query('shopping_items')).single,
      );
      expect(item.isManual, isTrue);
      expect(item.ingredientId, isNull);
    });
  });

  group('settings', () {
    test('persists key/value pairs', () async {
      final db = await service.database;

      for (final entry in const AppSettings(
        breakfastCount: 1,
        lunchCount: 3,
        dinnerCount: 2,
      ).toMap().entries) {
        await db.insert('settings', {
          'key': entry.key,
          'value': '${entry.value}',
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }

      final rows = await db.query('settings');
      final stored = {
        for (final row in rows) row['key']! as String: row['value'],
      };

      expect(
        AppSettings.fromMap(stored),
        const AppSettings(breakfastCount: 1, lunchCount: 3, dinnerCount: 2),
      );
    });
  });

  group('lifecycle', () {
    test('closing and reopening keeps the data', () async {
      final db = await service.database;
      await db.insert('meal_families', _family('family-1'));

      await service.close();
      final reopened = await service.database;

      expect(await reopened.getVersion(), DatabaseService.schemaVersion);
      expect(await reopened.query('meal_families'), hasLength(1));
      final pragma = await reopened.rawQuery('PRAGMA foreign_keys');
      expect(pragma.single.values.single, 1, reason: 'FKs stay on on reopen');
    });

    test('opening twice does not re-run table creation', () async {
      await service.database;
      await service.close();

      // Would throw "table already exists" if onCreate ran a second time.
      expect(await (await service.database).query('meal_families'), isEmpty);
    });

    test(
      'clearAllTablesForTesting empties the data but keeps the schema',
      () async {
        final db = await service.database;
        await db.insert('meal_families', _family('family-1'));

        await service.clearAllTablesForTesting();

        expect(await db.query('meal_families'), isEmpty);
      },
    );

    test(
      'deleteDatabaseForTesting removes the file and recreates it',
      () async {
        final db = await service.database;
        await db.insert('meal_families', _family('family-1'));
        final path = await service.resolvePath();

        await service.deleteDatabaseForTesting();
        expect(File(path).existsSync(), isFalse);

        expect(await (await service.database).query('meal_families'), isEmpty);
      },
    );
  });

  group('migrations', () {
    test('a version-1 database upgrades weekly plans safely', () async {
      final path = '${tempDir.path}/preppick_v1.db';
      final old = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, version) async {
            await db.execute('''
            CREATE TABLE weekly_plans (
              id TEXT PRIMARY KEY,
              week_start TEXT NOT NULL,
              status TEXT NOT NULL,
              created_at TEXT NOT NULL,
              confirmed_at TEXT
            )
            ''');
            await db.execute('''
            CREATE TABLE weekly_plan_items (
              id TEXT PRIMARY KEY,
              weekly_plan_id TEXT NOT NULL,
              meal_variant_id TEXT NOT NULL,
              meal_type TEXT NOT NULL,
              slot_index INTEGER NOT NULL,
              FOREIGN KEY (weekly_plan_id) REFERENCES weekly_plans (id)
                ON DELETE CASCADE
            )
            ''');
          },
        ),
      );
      await old.insert('weekly_plans', {
        'id': 'old-draft',
        'week_start': '2026-03-16T00:00:00.000Z',
        'status': 'draft',
        'created_at': '2026-03-16T09:00:00.000Z',
      });
      await old.insert('weekly_plans', {
        'id': 'old-confirmed',
        'week_start': '2026-03-16T00:00:00.000Z',
        'status': 'confirmed',
        'created_at': '2026-03-16T10:00:00.000Z',
        'confirmed_at': '2026-03-16T11:00:00.000Z',
      });
      await old.insert('weekly_plans', {
        'id': 'newer-confirmed',
        'week_start': '2026-03-16T00:00:00.000Z',
        'status': 'confirmed',
        'created_at': '2026-03-16T12:00:00.000Z',
        'confirmed_at': '2026-03-16T13:00:00.000Z',
      });
      await old.close();

      final upgradedService = DatabaseService(
        factory: databaseFactoryFfi,
        databaseName: path,
      );
      final upgraded = await upgradedService.database;

      expect(await upgraded.getVersion(), DatabaseService.schemaVersion);
      final rows = await upgraded.query('weekly_plans');
      expect(rows, hasLength(1));
      expect(rows.single['id'], 'newer-confirmed');
      expect(rows.single['updated_at'], '2026-03-16T13:00:00.000Z');
      expect(
        () => upgraded.insert('weekly_plans', {
          'id': 'duplicate',
          'week_start': '2026-03-16T00:00:00.000Z',
          'status': 'draft',
          'created_at': '2026-03-17T09:00:00.000Z',
          'updated_at': '2026-03-17T09:00:00.000Z',
        }),
        throwsA(isA<DatabaseException>()),
      );
      await upgradedService.close();
    });
  });
}
