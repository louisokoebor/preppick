import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:preppick/models/models.dart';
import 'package:preppick/services/share_service.dart';

void main() {
  const share = ShareService();
  final weekStart = DateTime.utc(2026, 9, 21);

  final chicken = ShoppingItem(
    id: 'chicken',
    weeklyPlanId: 'plan',
    name: 'Chicken breast',
    category: IngredientCategory.protein,
    quantity: 750,
    unit: 'g',
  );
  final salt = ShoppingItem(
    id: 'salt',
    weeklyPlanId: 'plan',
    name: 'Salt',
    category: IngredientCategory.pantry,
  );
  final breakfast = WeeklyPlanItem(
    id: 'breakfast-slot',
    weeklyPlanId: 'plan',
    mealVariantId: 'muffins',
    mealType: MealType.breakfast,
    slotIndex: 0,
  );
  final dinner = WeeklyPlanItem(
    id: 'dinner-slot',
    weeklyPlanId: 'plan',
    mealVariantId: 'pasta',
    mealType: MealType.dinner,
    slotIndex: 0,
  );

  final meals = {
    'muffins': _meal('muffins', 'Breakfast muffins'),
    'pasta': _meal('pasta', 'Lou Lou spaghetti', protein: 'Chicken'),
  };

  test('formats a shopping list as a checklist grouped by category', () {
    final message = share.shoppingListMessage(
      weekStart: weekStart,
      items: [chicken, salt.copyWith(isChecked: true)],
    );

    expect(message, contains('PrepPick shopping list'));
    expect(message, contains('Protein'));
    expect(message, contains('[ ] Chicken breast - 750 g'));
    expect(message, contains('[x] Salt'));
  });

  test('formats a meal plan in slot order', () {
    final message = share.mealPlanMessage(
      weekStart: weekStart,
      items: [dinner, breakfast],
      mealFor: (item) => meals[item.mealVariantId],
    );

    expect(
      message.indexOf('Breakfast: Breakfast muffins'),
      lessThan(message.indexOf('Dinner: Lou Lou spaghetti')),
    );
  });

  test('creates non-empty PDF bytes for both exports', () async {
    final shoppingPdf = await share.shoppingListPdf(
      weekStart: weekStart,
      items: [chicken, salt],
    );
    final planPdf = await share.mealPlanPdf(
      weekStart: weekStart,
      items: [breakfast, dinner],
      mealFor: (item) => meals[item.mealVariantId],
    );

    expect(shoppingPdf, isA<Uint8List>());
    expect(shoppingPdf, isNotEmpty);
    expect(planPdf, isA<Uint8List>());
    expect(planPdf, isNotEmpty);
    expect(String.fromCharCodes(shoppingPdf.take(4)), '%PDF');
    expect(String.fromCharCodes(planPdf.take(4)), '%PDF');
  });
}

MealVariant _meal(String id, String name, {String? protein}) => MealVariant(
  id: id,
  mealFamilyId: '$id-family',
  name: name,
  protein: protein,
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
);
