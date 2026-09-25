import 'package:flutter_test/flutter_test.dart';
import 'package:preppick/models/models.dart';

final _created = DateTime.utc(2026, 1, 5, 9, 30);
final _updated = DateTime.utc(2026, 2, 11, 18, 45, 12);

void main() {
  group('MealFamily', () {
    test('round-trips through a map', () {
      final family = MealFamily(
        id: 'family-1',
        name: 'Lou Lou Spaghetti',
        mealType: MealType.dinner,
        createdAt: _created,
        updatedAt: _updated,
      );

      final restored = MealFamily.fromMap(family.toMap());

      expect(restored.id, 'family-1');
      expect(restored.name, 'Lou Lou Spaghetti');
      expect(restored.mealType, MealType.dinner);
      expect(restored.createdAt, _created);
      expect(restored.updatedAt, _updated);
    });

    test('persists the meal type as a stable string, not an index', () {
      final map = MealFamily(
        id: 'family-1',
        name: 'Paninis',
        mealType: MealType.lunch,
        createdAt: _created,
        updatedAt: _updated,
      ).toMap();

      expect(map['meal_type'], 'lunch');
    });

    test('rejects an unknown meal type string', () {
      expect(() => MealType.fromValue('brunch'), throwsArgumentError);
    });
  });

  group('MealVariant', () {
    test('round-trips with every optional value populated', () {
      final lastPlanned = DateTime.utc(2026, 3, 2);
      final variant = MealVariant(
        id: 'variant-1',
        mealFamilyId: 'family-1',
        name: 'Lou Lou Spaghetti + Chicken',
        protein: 'chicken',
        lastPlannedAt: lastPlanned,
        timesPlanned: 4,
        createdAt: _created,
        updatedAt: _updated,
      );

      final restored = MealVariant.fromMap(variant.toMap());

      expect(restored.mealFamilyId, 'family-1');
      expect(restored.name, 'Lou Lou Spaghetti + Chicken');
      expect(restored.protein, 'chicken');
      expect(restored.lastPlannedAt, lastPlanned);
      expect(restored.timesPlanned, 4);
      expect(restored.createdAt, _created);
    });

    test('keeps a null protein and a null lastPlannedAt null', () {
      final variant = MealVariant(
        id: 'variant-2',
        mealFamilyId: 'family-1',
        name: 'Breakfast Muffins',
        createdAt: _created,
        updatedAt: _updated,
      );

      final map = variant.toMap();
      expect(map['protein'], isNull);
      expect(map['last_planned_at'], isNull);

      final restored = MealVariant.fromMap(map);
      expect(restored.protein, isNull);
      expect(restored.lastPlannedAt, isNull);
      expect(restored.timesPlanned, 0);
    });
  });

  group('Ingredient', () {
    test('round-trips through a map', () {
      final ingredient = Ingredient(
        id: 'ing-1',
        name: 'Chicken thighs',
        category: IngredientCategory.protein,
        createdAt: _created,
        updatedAt: _updated,
      );

      final restored = Ingredient.fromMap(ingredient.toMap());

      expect(restored.name, 'Chicken thighs');
      expect(restored.category, 'protein');
      expect(restored.updatedAt, _updated);
    });

    test('keeps a null category null', () {
      final restored = Ingredient.fromMap(
        Ingredient(
          id: 'ing-2',
          name: 'Scotch bonnet',
          createdAt: _created,
          updatedAt: _updated,
        ).toMap(),
      );

      expect(restored.category, isNull);
    });
  });

  group('MealIngredient', () {
    test('round-trips through a map', () {
      const mealIngredient = MealIngredient(
        id: 'mi-1',
        mealVariantId: 'variant-1',
        ingredientId: 'ing-1',
        quantity: 500,
        unit: 'g',
        baseServings: 4,
      );

      final restored = MealIngredient.fromMap(mealIngredient.toMap());

      expect(restored.mealVariantId, 'variant-1');
      expect(restored.ingredientId, 'ing-1');
      expect(restored.quantity, 500);
      expect(restored.unit, 'g');
      expect(restored.baseServings, 4);
    });

    test('leaves an unknown quantity null rather than defaulting it', () {
      const mealIngredient = MealIngredient(
        id: 'mi-2',
        mealVariantId: 'variant-1',
        ingredientId: 'ing-2',
      );

      final map = mealIngredient.toMap();
      expect(map['quantity'], isNull);
      expect(map['unit'], isNull);
      expect(map['base_servings'], isNull);

      final restored = MealIngredient.fromMap(map);
      expect(restored.quantity, isNull);
      expect(restored.unit, isNull);
      expect(restored.baseServings, isNull);
    });

    test('reads an integer quantity from SQLite as a double', () {
      final restored = MealIngredient.fromMap({
        'id': 'mi-3',
        'meal_variant_id': 'variant-1',
        'ingredient_id': 'ing-1',
        'quantity': 2,
        'unit': 'tbsp',
        'base_servings': null,
      });

      expect(restored.quantity, 2.0);
    });
  });

  group('WeeklyPlan', () {
    test('round-trips a draft plan with no confirmation date', () {
      final weekStart = DateTime.utc(2026, 3, 2);
      final plan = WeeklyPlan(
        id: 'plan-1',
        weekStart: weekStart,
        status: PlanStatus.draft,
        createdAt: _created,
      );

      final map = plan.toMap();
      expect(map['status'], 'draft');
      expect(map['confirmed_at'], isNull);

      final restored = WeeklyPlan.fromMap(map);
      expect(restored.weekStart, weekStart);
      expect(restored.status, PlanStatus.draft);
      expect(restored.confirmedAt, isNull);
      expect(restored.isConfirmed, isFalse);
    });

    test('round-trips a confirmed plan', () {
      final confirmedAt = DateTime.utc(2026, 3, 1, 20, 15);
      final restored = WeeklyPlan.fromMap(
        WeeklyPlan(
          id: 'plan-2',
          weekStart: DateTime.utc(2026, 3, 2),
          status: PlanStatus.confirmed,
          createdAt: _created,
          confirmedAt: confirmedAt,
        ).toMap(),
      );

      expect(restored.status, PlanStatus.confirmed);
      expect(restored.confirmedAt, confirmedAt);
      expect(restored.isConfirmed, isTrue);
    });

    test('rejects an unknown status string', () {
      expect(() => PlanStatus.fromValue('archived'), throwsArgumentError);
    });
  });

  group('MealSlot', () {
    test('round-trips through its stable key', () {
      const slot = MealSlot(MealType.dinner, 1);

      expect(slot.key, 'dinner:1');
      expect(MealSlot.fromKey('dinner:1'), slot);
    });

    test('numbers a label only when the week has several of that type', () {
      expect(const MealSlot(MealType.dinner, 0).label(), 'Dinner');
      expect(
        const MealSlot(MealType.dinner, 1).label(totalOfType: 2),
        'Dinner 2',
      );
      expect(const MealSlot(MealType.breakfast, 0).label(), 'Breakfast');
    });

    test('sorts breakfast before lunch before dinner', () {
      final slots = <MealSlot>[
        const MealSlot(MealType.dinner, 1),
        const MealSlot(MealType.breakfast, 0),
        const MealSlot(MealType.dinner, 0),
        const MealSlot(MealType.lunch, 0),
      ]..sort();

      expect(slots.map((slot) => slot.key), [
        'breakfast:0',
        'lunch:0',
        'dinner:0',
        'dinner:1',
      ]);
    });

    test('rejects malformed keys and negative indexes', () {
      expect(() => MealSlot.fromKey('dinner'), throwsArgumentError);
      expect(() => MealSlot.fromKey('dinner:x'), throwsArgumentError);
      expect(
        () => MealSlot(MealType.dinner, -1),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('WeeklyPlanItem', () {
    test('round-trips through a map', () {
      const item = WeeklyPlanItem(
        id: 'item-1',
        weeklyPlanId: 'plan-1',
        mealVariantId: 'variant-1',
        mealType: MealType.dinner,
        slotIndex: 1,
      );

      final map = item.toMap();
      expect(map['meal_type'], 'dinner');
      expect(map['slot_index'], 1);

      final restored = WeeklyPlanItem.fromMap(map);
      expect(restored.weeklyPlanId, 'plan-1');
      expect(restored.mealVariantId, 'variant-1');
      expect(restored.slot, const MealSlot(MealType.dinner, 1));
    });
  });

  group('ShoppingItem', () {
    test('round-trips a generated item', () {
      const item = ShoppingItem(
        id: 'shop-1',
        weeklyPlanId: 'plan-1',
        ingredientId: 'ing-1',
        name: 'Chicken thighs',
        quantity: 1.25,
        unit: 'kg',
        category: IngredientCategory.protein,
      );

      final restored = ShoppingItem.fromMap(item.toMap());

      expect(restored.ingredientId, 'ing-1');
      expect(restored.quantity, 1.25);
      expect(restored.unit, 'kg');
      expect(restored.category, 'protein');
      expect(restored.isChecked, isFalse);
      expect(restored.isManual, isFalse);
    });

    test('converts booleans to and from SQLite integers', () {
      const item = ShoppingItem(
        id: 'shop-2',
        weeklyPlanId: 'plan-1',
        name: 'Kitchen roll',
        category: IngredientCategory.household,
        isChecked: true,
        isManual: true,
      );

      final map = item.toMap();
      expect(map['is_checked'], 1);
      expect(map['is_manual'], 1);

      final restored = ShoppingItem.fromMap(map);
      expect(restored.isChecked, isTrue);
      expect(restored.isManual, isTrue);
    });

    test('keeps a manual item without an ingredient or quantity', () {
      final restored = ShoppingItem.fromMap(
        const ShoppingItem(
          id: 'shop-3',
          weeklyPlanId: 'plan-1',
          name: 'Plantain',
          category: IngredientCategory.produce,
          isManual: true,
        ).toMap(),
      );

      expect(restored.ingredientId, isNull);
      expect(restored.quantity, isNull);
      expect(restored.unit, isNull);
    });
  });

  group('AppSettings', () {
    test('round-trips meal counts', () {
      const settings = AppSettings(
        breakfastCount: 1,
        lunchCount: 3,
        dinnerCount: 2,
      );

      final restored = AppSettings.fromMap(settings.toMap());

      expect(restored, settings);
      expect(restored.totalMeals, 6);
    });

    test('reads counts stored as strings in the key/value table', () {
      final restored = AppSettings.fromMap({
        'breakfast_count': '0',
        'lunch_count': '2',
        'dinner_count': '2',
      });

      expect(
        restored,
        const AppSettings(breakfastCount: 0, lunchCount: 2, dinnerCount: 2),
      );
    });

    test('falls back to the default for each missing key', () {
      // A first run has no stored rows at all, and must land on the product
      // defaults rather than on "no meals this week".
      expect(AppSettings.fromMap(const {}), AppSettings.defaults);
    });

    test('mixes stored values with defaults for absent keys', () {
      expect(
        AppSettings.fromMap(const {'lunch_count': '4'}),
        AppSettings.defaults.copyWith(lunchCount: 4),
      );
    });

    test('clamps values outside the allowed range', () {
      final settings = AppSettings.fromMap(const {
        'breakfast_count': '-2',
        'dinner_count': '99',
      });

      expect(settings.breakfastCount, AppSettings.minCount);
      expect(settings.dinnerCount, AppSettings.maxCount);
    });

    test('copyWith clamps as well, so edits cannot escape the range', () {
      expect(
        AppSettings.defaults.copyWith(lunchCount: 20).lunchCount,
        AppSettings.maxCount,
      );
      expect(
        AppSettings.defaults.copyWith(lunchCount: -4).lunchCount,
        AppSettings.minCount,
      );
    });

    test('countFor and withCount address one category at a time', () {
      final settings = AppSettings.defaults.withCount(MealType.dinner, 5);

      expect(settings.countFor(MealType.dinner), 5);
      expect(
        settings.countFor(MealType.lunch),
        AppSettings.defaults.lunchCount,
      );
    });

    test('isEmpty is true only when nothing is being prepped', () {
      expect(AppSettings.defaults.isEmpty, isFalse);
      expect(
        const AppSettings(
          breakfastCount: 0,
          lunchCount: 0,
          dinnerCount: 0,
        ).isEmpty,
        isTrue,
      );
    });
  });

  group('date persistence', () {
    test('dates are stored as ISO-8601 UTC strings', () {
      final map = MealFamily(
        id: 'family-1',
        name: 'Fried Rice',
        mealType: MealType.dinner,
        createdAt: _created,
        updatedAt: _updated,
      ).toMap();

      expect(map['created_at'], '2026-01-05T09:30:00.000Z');
    });

    test('a local date round-trips to the same instant', () {
      final local = DateTime(2026, 6, 1, 7, 15);
      final restored = MealVariant.fromMap(
        MealVariant(
          id: 'variant-1',
          mealFamilyId: 'family-1',
          name: 'Fried Rice + Chicken',
          lastPlannedAt: local,
          createdAt: local,
          updatedAt: local,
        ).toMap(),
      );

      expect(restored.createdAt.isUtc, isTrue);
      expect(restored.createdAt.isAtSameMomentAs(local), isTrue);
      expect(restored.lastPlannedAt!.isAtSameMomentAs(local), isTrue);
    });
  });
}
