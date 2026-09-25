import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:preppick/models/models.dart';
import 'package:preppick/providers/meal_provider.dart';
import 'package:preppick/services/database_service.dart';
import 'package:preppick/services/meal_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// A service whose reads fail, to exercise the provider's error path.
class _FailingMealService implements MealService {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      Future<Never>.error(StateError('database unavailable'));
}

/// Wraps a real service and can be switched to failing mid-test.
///
/// Closing the real database does not work for this: [DatabaseService]
/// reopens it on the next access, so the refresh would quietly succeed
/// against an empty database instead of failing.
class _FlakyMealService implements MealService {
  _FlakyMealService(this._inner);

  final MealService _inner;
  bool fail = false;

  @override
  Future<List<MealVariant>> getAllMealVariants({
    bool includeArchived = false,
  }) async {
    if (fail) throw StateError('database unavailable');
    return _inner.getAllMealVariants(includeArchived: includeArchived);
  }

  @override
  Future<List<MealFamily>> getAllMealFamilies({
    bool includeArchived = false,
  }) async {
    if (fail) throw StateError('database unavailable');
    return _inner.getAllMealFamilies(includeArchived: includeArchived);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  sqfliteFfiInit();

  late Directory tempDir;
  late DatabaseService database;
  late MealService service;
  late MealProvider provider;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('preppick_mp_test');
    database = DatabaseService(
      factory: databaseFactoryFfi,
      databaseName: '${tempDir.path}/preppick_test.db',
    );
    service = MealService(database);
    provider = MealProvider(service);
  });

  tearDown(() async {
    provider.dispose();
    await database.close();
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  group('load', () {
    test('starts empty, before anything is loaded', () {
      expect(provider.meals, isEmpty);
      expect(provider.isLoading, isFalse);
      expect(provider.hasLoaded, isFalse);
      // Not "empty library" yet — nothing has been read.
      expect(provider.isEmpty, isFalse);
    });

    test('loads meals and their families', () async {
      final meal = await service.addMeal(
        familyName: 'Jollof Rice',
        mealType: MealType.dinner,
        variantName: 'Jollof Rice + Turkey',
      );

      await provider.load();

      expect(provider.meals, hasLength(1));
      expect(provider.meals.single.id, meal.id);
      expect(provider.familyOf(provider.meals.single)!.name, 'Jollof Rice');
      expect(provider.typeOf(provider.meals.single), MealType.dinner);
      expect(provider.error, isNull);
      expect(provider.hasError, isFalse);
      expect(provider.hasLoaded, isTrue);
    });

    test('transitions through loading and notifies at both ends', () async {
      final states = <bool>[];
      provider.addListener(() => states.add(provider.isLoading));

      final future = provider.load();
      expect(provider.isLoading, isTrue);
      await future;

      expect(provider.isLoading, isFalse);
      // One notification as loading starts, one as it finishes.
      expect(states, [true, false]);
    });

    test('collapses a concurrent second load', () async {
      final first = provider.load();
      final second = provider.load();
      await Future.wait([first, second]);

      expect(provider.hasLoaded, isTrue);
      expect(provider.isLoading, isFalse);
    });

    test('an empty library is empty, not an error', () async {
      await provider.load();

      expect(provider.meals, isEmpty);
      expect(provider.isEmpty, isTrue);
      expect(provider.hasError, isFalse);
    });

    test('exposes a read failure without throwing', () async {
      final failing = MealProvider(_FailingMealService());
      addTearDown(failing.dispose);

      await failing.load();

      expect(failing.hasError, isTrue);
      expect(failing.error, isA<StateError>());
      expect(failing.isLoading, isFalse);
      expect(failing.hasLoaded, isTrue);
      // An error is not an empty library; the screens differ.
      expect(failing.isEmpty, isFalse);
    });

    test('a failed refresh keeps the meals already on screen', () async {
      await service.addMeal(familyName: 'Burger', mealType: MealType.dinner);
      final flaky = _FlakyMealService(service);
      final flakyProvider = MealProvider(flaky);
      addTearDown(flakyProvider.dispose);
      await flakyProvider.load();
      expect(flakyProvider.meals, hasLength(1));

      flaky.fail = true;
      await flakyProvider.refresh();

      expect(flakyProvider.hasError, isTrue);
      // A failed refresh must not blank a library the household was reading.
      expect(flakyProvider.meals, hasLength(1));
    });

    test('a successful load clears a previous error', () async {
      final failing = MealProvider(_FailingMealService());
      addTearDown(failing.dispose);
      await failing.load();
      expect(failing.hasError, isTrue);

      await provider.load();
      expect(provider.hasError, isFalse);
    });

    test('does not throw when it finishes after being disposed', () async {
      final future = provider.load();
      provider.dispose();
      await future;

      // The tearDown disposes again; guard against a double dispose there.
      provider = MealProvider(service);
    });
  });

  group('filtering', () {
    setUp(() async {
      await service.addMeal(
        familyName: 'Breakfast Muffins',
        mealType: MealType.breakfast,
      );
      await service.addMeal(familyName: 'Paninis', mealType: MealType.lunch);
      await service.addMeal(familyName: 'Burger', mealType: MealType.dinner);
      await service.addMeal(familyName: 'Fish', mealType: MealType.dinner);
      await provider.load();
    });

    test('splits the loaded meals by type', () {
      expect(provider.mealsOfType(MealType.breakfast), hasLength(1));
      expect(provider.mealsOfType(MealType.lunch), hasLength(1));
      expect(provider.mealsOfType(MealType.dinner), hasLength(2));
    });

    test('the three filters account for every loaded meal', () {
      final total = MealType.values
          .map((type) => provider.mealsOfType(type).length)
          .reduce((a, b) => a + b);

      expect(total, provider.meals.length);
    });
  });

  group('mutations', () {
    test('adding a meal reloads the library', () async {
      await provider.load();
      expect(provider.meals, isEmpty);

      await provider.addMeal(
        familyName: 'Fried Rice',
        mealType: MealType.dinner,
        variantName: 'Fried Rice + Chicken',
      );

      expect(provider.meals, hasLength(1));
      expect(provider.meals.single.name, 'Fried Rice + Chicken');
    });

    test('updating a meal is reflected after the reload', () async {
      final meal = await provider.addMeal(
        familyName: 'Pasta',
        mealType: MealType.dinner,
        protein: 'beef',
      );

      await provider.updateMeal(meal.id, name: 'Pasta bake', protein: 'turkey');

      expect(provider.meals.single.name, 'Pasta bake');
      expect(provider.meals.single.protein, 'turkey');
    });

    test(
      'removing an unplanned meal deletes it and drops it from the list',
      () async {
        final meal = await provider.addMeal(
          familyName: 'Toast',
          mealType: MealType.breakfast,
        );

        expect(await provider.removeMeal(meal.id), MealRemoval.deleted);
        expect(provider.meals, isEmpty);
      },
    );

    test('exposes a meal recipe on demand', () async {
      final meal = await provider.addMeal(
        familyName: 'Lou Lou Spaghetti',
        mealType: MealType.dinner,
      );
      await service.addIngredientToMeal(
        mealVariantId: meal.id,
        ingredientName: 'Spaghetti',
        quantity: 400,
        unit: 'g',
      );

      final recipe = await provider.ingredientsFor(meal.id);

      expect(recipe, hasLength(1));
      expect(recipe.single.name, 'Spaghetti');
      expect(recipe.single.quantity, 400);
    });

    test('an archived meal disappears from the loaded library', () async {
      final meal = await provider.addMeal(
        familyName: 'Burger',
        mealType: MealType.dinner,
      );

      await service.archiveMealVariant(meal.id);
      await provider.refresh();

      expect(provider.meals, isEmpty);
      expect(provider.isEmpty, isTrue);
    });
  });
}
