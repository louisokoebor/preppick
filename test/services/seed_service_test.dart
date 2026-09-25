import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:preppick/models/models.dart';
import 'package:preppick/services/database_service.dart';
import 'package:preppick/services/seed_data.dart';
import 'package:preppick/services/seed_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late Directory tempDir;
  late DatabaseService database;
  late SeedService seed;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('preppick_seed_test');
    database = DatabaseService(
      factory: databaseFactoryFfi,
      databaseName: '${tempDir.path}/preppick_test.db',
    );
    seed = SeedService(database);
  });

  tearDown(() async {
    await database.close();
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  Future<int> countOf(String table) async {
    final db = await database.database;
    final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM $table');
    return (rows.single['c']! as num).toInt();
  }

  group('seedIfEmpty', () {
    test('inserts the demo library on an empty database', () async {
      expect(await seed.hasMeals(), isFalse);

      expect(await seed.seedIfEmpty(), isTrue);

      expect(await countOf('meal_families'), SeedData.families.length);
      expect(
        await countOf('meal_variants'),
        SeedData.families.fold<int>(0, (sum, f) => sum + f.variants.length),
      );
      expect(await countOf('ingredients'), SeedData.ingredients.length);
      expect(await countOf('meal_ingredients'), greaterThan(0));
      expect(await seed.hasMeals(), isTrue);
    });

    test('records the seed version in settings', () async {
      await seed.seedIfEmpty();

      final db = await database.database;
      final rows = await db.query(
        'settings',
        where: 'key = ?',
        whereArgs: [SeedService.seededSettingKey],
      );
      expect(rows, hasLength(1));
      expect(rows.single['value'], startsWith('${SeedService.seedVersion}@'));
    });

    test('a second seed does not duplicate anything', () async {
      await seed.seedIfEmpty();
      final before = {
        for (final table in DatabaseService.tableNames)
          table: await countOf(table),
      };

      expect(await seed.seedIfEmpty(), isFalse);

      for (final entry in before.entries) {
        expect(await countOf(entry.key), entry.value, reason: entry.key);
      }
    });

    test('skips seeding when the household already has a meal', () async {
      final db = await database.database;
      final now = DateTime.utc(2026, 2, 1);
      await db.insert(
        'meal_families',
        MealFamily(
          id: 'household-family',
          name: 'Sunday Roast',
          mealType: MealType.dinner,
          createdAt: now,
          updatedAt: now,
        ).toMap(),
      );
      await db.insert(
        'meal_variants',
        MealVariant(
          id: 'household-variant',
          mealFamilyId: 'household-family',
          name: 'Sunday Roast + Chicken',
          createdAt: now,
          updatedAt: now,
        ).toMap(),
      );

      expect(await seed.seedIfEmpty(), isFalse);
      expect(await countOf('meal_variants'), 1);
      expect(await countOf('meal_families'), 1);
    });

    test(
      'a forced re-seed onto seeded rows still inserts no duplicates',
      () async {
        await seed.seedIfEmpty();
        final before = await countOf('meal_ingredients');

        // Bypass the emptiness guard the way a buggy caller would, to prove the
        // deterministic ids and INSERT OR IGNORE hold on their own.
        final db = await database.database;
        await db.delete(
          'meal_variants',
          where: "id = ?",
          whereArgs: [SeedService.variantId('Paninis')],
        );
        expect(await seed.seedIfEmpty(), isFalse);

        await db.delete('meal_variants');
        expect(await seed.seedIfEmpty(), isTrue);

        expect(await countOf('ingredients'), SeedData.ingredients.length);
        expect(await countOf('meal_families'), SeedData.families.length);
        expect(await countOf('meal_ingredients'), before);
      },
    );
  });

  group('seeded data shape', () {
    setUp(() async => seed.seedIfEmpty());

    test('every variant points at a real family', () async {
      final db = await database.database;
      final orphans = await db.rawQuery('''
        SELECT v.id FROM meal_variants v
        LEFT JOIN meal_families f ON f.id = v.meal_family_id
        WHERE f.id IS NULL
      ''');
      expect(orphans, isEmpty);
    });

    test('every recipe line points at a real ingredient', () async {
      final db = await database.database;
      final orphans = await db.rawQuery('''
        SELECT mi.id FROM meal_ingredients mi
        LEFT JOIN ingredients i ON i.id = mi.ingredient_id
        WHERE i.id IS NULL
      ''');
      expect(orphans, isEmpty);
    });

    test('a seeded meal can return its ingredients', () async {
      final db = await database.database;
      final rows = await db.rawQuery(
        '''
        SELECT i.name, i.category, mi.quantity, mi.unit
        FROM meal_ingredients mi
        JOIN ingredients i ON i.id = mi.ingredient_id
        WHERE mi.meal_variant_id = ?
        ''',
        [SeedService.variantId('Lou Lou Spaghetti + Chicken')],
      );

      expect(rows, isNotEmpty);
      final names = rows.map((row) => row['name']).toList();
      expect(names, contains('Spaghetti'));
      expect(names, contains('Chicken breast'));
    });

    test('ingredient names are unique once normalised', () async {
      final keys = SeedData.ingredients
          .map((i) => SeedService.normaliseIngredientName(i.name))
          .toList();
      expect(keys.toSet(), hasLength(keys.length));
    });

    test('meals sharing an ingredient share one ingredient id', () async {
      final db = await database.database;
      final rows = await db.rawQuery('''
        SELECT DISTINCT mi.ingredient_id, mi.unit
        FROM meal_ingredients mi
        JOIN ingredients i ON i.id = mi.ingredient_id
        WHERE i.name = 'Chicken breast'
        ''');

      // Same id and same unit in both meals, so the shopping list can merge.
      expect(rows, hasLength(1));
      expect(rows.single['unit'], 'g');

      final lines = await db.rawQuery(
        '''
        SELECT mi.quantity FROM meal_ingredients mi
        WHERE mi.ingredient_id = ?
        ''',
        [rows.single['ingredient_id']],
      );
      expect(lines, hasLength(2));
      expect(lines.map((row) => row['quantity']).toSet(), {500.0, 750.0});
    });

    test('unmeasured ingredients keep a null quantity', () async {
      final db = await database.database;
      final rows = await db.rawQuery('''
        SELECT mi.quantity, mi.unit, mi.base_servings
        FROM meal_ingredients mi
        JOIN ingredients i ON i.id = mi.ingredient_id
        WHERE i.name = 'Olive oil'
        ''');

      expect(rows, isNotEmpty);
      for (final row in rows) {
        expect(row['quantity'], isNull);
        expect(row['unit'], isNull);
        expect(row['base_servings'], isNull);
      }
    });

    test('the same ingredient can appear in two units, unmerged', () async {
      final db = await database.database;
      final rows = await db.rawQuery('''
        SELECT mi.unit FROM meal_ingredients mi
        JOIN ingredients i ON i.id = mi.ingredient_id
        WHERE i.name = 'Tomatoes'
        ''');
      expect(rows.map((row) => row['unit']).toSet(), {'unit', 'g'});
    });

    test('covers several shopping categories', () async {
      final db = await database.database;
      final rows = await db.rawQuery(
        'SELECT DISTINCT category FROM ingredients',
      );
      final categories = rows.map((row) => row['category']).toSet();

      expect(
        categories,
        containsAll(<String>[
          IngredientCategory.produce,
          IngredientCategory.protein,
          IngredientCategory.pantry,
          IngredientCategory.chilled,
          IngredientCategory.frozen,
          IngredientCategory.household,
          IngredientCategory.specialist,
        ]),
      );
    });

    test('covers every meal type', () async {
      final db = await database.database;
      final rows = await db.rawQuery(
        'SELECT DISTINCT meal_type FROM meal_families',
      );
      expect(
        rows.map((row) => row['meal_type']).toSet(),
        MealType.values.map((type) => type.value).toSet(),
      );
    });

    test('seeded rows are all identifiable as demo data', () async {
      final db = await database.database;
      for (final table in const [
        'meal_families',
        'meal_variants',
        'ingredients',
        'meal_ingredients',
      ]) {
        final rows = await db.rawQuery(
          "SELECT id FROM $table WHERE id NOT LIKE '${SeedService.idPrefix}-%'",
        );
        expect(rows, isEmpty, reason: table);
      }
    });
  });

  test('removeSeedData clears the demo library', () async {
    await seed.seedIfEmpty();

    await seed.removeSeedData();

    expect(await countOf('meal_variants'), 0);
    expect(await countOf('meal_families'), 0);
    expect(await countOf('ingredients'), 0);
    expect(await countOf('meal_ingredients'), 0);
    expect(await seed.hasMeals(), isFalse);
  });
}
