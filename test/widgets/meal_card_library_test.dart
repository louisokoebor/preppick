import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:preppick/models/models.dart';
import 'package:preppick/theme/app_icons.dart';
import 'package:preppick/theme/app_theme.dart';
import 'package:preppick/widgets/meal_card_library.dart';

void main() {
  MealVariant meal({required String name, String? protein}) => MealVariant(
    id: 'm1',
    mealFamilyId: 'f1',
    name: name,
    protein: protein,
    createdAt: DateTime.utc(2026, 3, 1),
    updatedAt: DateTime.utc(2026, 3, 1),
  );

  Future<void> pumpCard(
    WidgetTester tester, {
    required MealVariant variant,
    String? familyName,
    VoidCallback? onTap,
    double width = 360,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              child: MealCardLibrary(
                meal: variant,
                mealType: MealType.dinner,
                familyName: familyName,
                onTap: onTap,
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('shows the meal, its family and its protein', (tester) async {
    await pumpCard(
      tester,
      variant: meal(name: 'Lou Lou Spaghetti + Chicken', protein: 'Chicken'),
      familyName: 'Lou Lou Spaghetti',
    );

    expect(find.text('Lou Lou Spaghetti + Chicken'), findsOneWidget);
    expect(find.text('Lou Lou Spaghetti'), findsOneWidget);
    expect(find.text('Chicken'), findsOneWidget);
    expect(find.text('DINNER'), findsOneWidget);
  });

  testWidgets('hides a family line that only repeats the meal name', (
    tester,
  ) async {
    await pumpCard(
      tester,
      variant: meal(name: 'Paninis'),
      familyName: 'paninis',
    );

    // A meal with one version would otherwise show its own name twice.
    expect(find.text('Paninis'), findsOneWidget);
    expect(find.text('paninis'), findsNothing);
  });

  testWidgets('a very long name ellipsizes instead of overflowing', (
    tester,
  ) async {
    await pumpCard(
      tester,
      variant: meal(
        name:
            "Mum's Sunday jollof rice with the crispy bits from the bottom "
            'of the pot and extra plantain',
        protein: 'Chicken thighs, bone in',
      ),
      width: 320,
    );

    expect(tester.takeException(), isNull);
    final name = tester.widget<Text>(find.textContaining("Mum's Sunday"));
    expect(name.maxLines, 2);
    expect(name.overflow, TextOverflow.ellipsis);
  });

  testWidgets('taps report once and a card with no handler is not a button', (
    tester,
  ) async {
    var taps = 0;
    await pumpCard(
      tester,
      variant: meal(name: 'Fried Rice'),
      onTap: () => taps++,
    );
    await tester.tap(find.byType(MealCardLibrary));
    await tester.pumpAndSettle();
    expect(taps, 1);

    await pumpCard(tester, variant: meal(name: 'Fried Rice'));
    // No handler, so no chevron promising somewhere to go.
    expect(find.byIcon(AppIcons.chevronRightRounded), findsNothing);
  });
}
