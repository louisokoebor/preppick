import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:preppick/models/models.dart';
import 'package:preppick/providers/meal_provider.dart';
import 'package:preppick/theme/app_theme.dart';
import 'package:preppick/ui/meals/meal_library_screen.dart';
import 'package:preppick/widgets/meal_card_library.dart';
import 'package:preppick/widgets/prep_filter_chip.dart';

import 'fake_meal_provider.dart';

void main() {
  late FakeMealProvider meals;

  /// Meal ids the screen reported as opened, in order.
  late List<String> opened;

  /// How many times Add Meal was asked for.
  late int addTaps;

  /// A small library covering every category, with two variants of one
  /// family so the family line and the search across it are exercised.
  void giveLibrary() {
    final entries = [
      fakeLibraryMeal(
        id: 'm1',
        name: 'Breakfast Muffins',
        mealType: MealType.breakfast,
      ),
      fakeLibraryMeal(
        id: 'm2',
        name: 'Paninis',
        mealType: MealType.lunch,
        protein: 'Ham',
      ),
      fakeLibraryMeal(
        id: 'm3',
        name: 'Lou Lou Spaghetti + Chicken',
        familyName: 'Lou Lou Spaghetti',
        mealType: MealType.dinner,
        protein: 'Chicken',
      ),
      fakeLibraryMeal(
        id: 'm4',
        name: 'Lou Lou Spaghetti + Turkey',
        familyName: 'Lou Lou Spaghetti',
        mealType: MealType.dinner,
        protein: 'Turkey',
      ),
    ];
    meals
      ..loadedMeals = [for (final entry in entries) entry.variant]
      ..families = {for (final entry in entries) entry.family.id: entry.family};
  }

  Future<void> pumpLibrary(WidgetTester tester, {bool settle = true}) async {
    // A tall, roomy phone so the whole chip row and a four-meal library fit
    // on screen at once: these tests are about which meals survive a filter,
    // not about scrolling to reach them.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ChangeNotifierProvider<MealProvider>.value(
        value: meals,
        child: MaterialApp(
          theme: AppTheme.light,
          home: MealLibraryScreen(
            onOpenMeal: opened.add,
            onAddMeal: () => addTaps++,
          ),
        ),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  /// Types into the search box and settles.
  Future<void> search(WidgetTester tester, String query) async {
    await tester.enterText(find.byType(TextField), query);
    await tester.pumpAndSettle();
  }

  /// Taps a category chip by its label.
  Future<void> tapChip(WidgetTester tester, String label) async {
    await tester.tap(
      find.descendant(
        of: find.byType(PrepFilterChip),
        matching: find.text(label),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The meal names currently rendered as cards, in order.
  List<String> visibleMeals(WidgetTester tester) => tester
      .widgetList<MealCardLibrary>(find.byType(MealCardLibrary))
      .map((card) => card.meal.name)
      .toList();

  setUp(() {
    meals = FakeMealProvider();
    opened = [];
    addTaps = 0;
  });

  testWidgets('All shows every loaded meal, with the library count', (
    tester,
  ) async {
    giveLibrary();
    await pumpLibrary(tester);

    expect(visibleMeals(tester), [
      'Breakfast Muffins',
      'Paninis',
      'Lou Lou Spaghetti + Chicken',
      'Lou Lou Spaghetti + Turkey',
    ]);
    // Unfiltered, so the count is the size of the library and not an "x of y".
    expect(find.text('4 meals'), findsOneWidget);
  });

  testWidgets('each category chip shows only that category', (tester) async {
    giveLibrary();
    await pumpLibrary(tester);

    await tapChip(tester, 'Breakfast');
    expect(visibleMeals(tester), ['Breakfast Muffins']);

    await tapChip(tester, 'Lunch');
    expect(visibleMeals(tester), ['Paninis']);

    await tapChip(tester, 'Dinner');
    expect(visibleMeals(tester), [
      'Lou Lou Spaghetti + Chicken',
      'Lou Lou Spaghetti + Turkey',
    ]);
    // Filtered, so the count says how much is being hidden.
    expect(find.text('2 of 4 meals'), findsOneWidget);

    await tapChip(tester, 'All');
    expect(visibleMeals(tester), hasLength(4));
  });

  testWidgets('search matches meal names case-insensitively', (tester) async {
    giveLibrary();
    await pumpLibrary(tester);

    await search(tester, 'PANINI');
    expect(visibleMeals(tester), ['Paninis']);

    await search(tester, 'spaghetti');
    expect(visibleMeals(tester), hasLength(2));
  });

  testWidgets('search and a category filter narrow together', (tester) async {
    giveLibrary();
    await pumpLibrary(tester);

    await tapChip(tester, 'Dinner');
    await search(tester, 'turkey');

    // "turkey" alone would still be a dinner, but the point is that the chip
    // stayed applied while the query narrowed inside it.
    expect(visibleMeals(tester), ['Lou Lou Spaghetti + Turkey']);
    expect(find.text('1 of 4 meals'), findsOneWidget);

    await search(tester, 'muffins');
    // Breakfast Muffins matches the query but not the dinner chip, so the two
    // filters are combined rather than one replacing the other.
    expect(visibleMeals(tester), isEmpty);
    expect(find.text('No meals match'), findsOneWidget);
  });

  testWidgets('clearing the search restores the list', (tester) async {
    giveLibrary();
    await pumpLibrary(tester);

    await search(tester, 'paninis');
    expect(visibleMeals(tester), hasLength(1));

    await search(tester, '');
    expect(visibleMeals(tester), hasLength(4));
    expect(find.text('4 meals'), findsOneWidget);
  });

  testWidgets('Clear filters resets both the query and the chip', (
    tester,
  ) async {
    giveLibrary();
    await pumpLibrary(tester);

    await tapChip(tester, 'Breakfast');
    await search(tester, 'spaghetti');
    expect(find.text('No meals match'), findsOneWidget);

    await tester.tap(find.text('Clear filters'));
    await tester.pumpAndSettle();

    expect(visibleMeals(tester), hasLength(4));
    expect(find.text('4 meals'), findsOneWidget);
  });

  testWidgets('tapping a card opens that meal by id', (tester) async {
    giveLibrary();
    await pumpLibrary(tester);

    await tester.tap(find.text('Lou Lou Spaghetti + Turkey'));
    await tester.pumpAndSettle();

    expect(opened, ['m4']);
  });

  testWidgets('an empty library offers to add a first meal', (tester) async {
    await pumpLibrary(tester);

    expect(find.byType(MealCardLibrary), findsNothing);
    expect(find.text('No meals yet'), findsOneWidget);
    // The empty library is a different problem from an empty search, and says
    // so rather than telling someone to change a filter they never set.
    expect(find.text('No meals match'), findsNothing);

    await tester.tap(find.text('Add your first meal'));
    await tester.pumpAndSettle();
    expect(addTaps, 1);
  });

  testWidgets('the Add Meal button is always available', (tester) async {
    giveLibrary();
    await pumpLibrary(tester);

    await tester.tap(find.text('Add meal'));
    await tester.pumpAndSettle();

    expect(addTaps, 1);
  });

  testWidgets('a first load shows a spinner instead of an empty state', (
    tester,
  ) async {
    meals
      ..loading = true
      ..loaded = false;
    // pump rather than pumpLibrary: the spinner animates forever, so
    // pumpAndSettle would never return.
    await pumpLibrary(tester, settle: false);

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('No meals yet'), findsNothing);
  });

  testWidgets('a failed load offers a retry', (tester) async {
    meals.failure = Exception('no database');
    await pumpLibrary(tester);

    expect(find.text('Could not open your library'), findsOneWidget);

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(meals.calls, contains('refresh'));
  });

  testWidgets('long meal names stay on the card without overflowing', (
    tester,
  ) async {
    final long = fakeLibraryMeal(
      id: 'm9',
      name:
          "Mum's Sunday jollof rice with the crispy bits from the bottom of "
          'the pot and extra plantain on the side',
      mealType: MealType.dinner,
      protein: 'Chicken thighs, bone in',
    );
    meals
      ..loadedMeals = [long.variant]
      ..families = {long.family.id: long.family};

    await pumpLibrary(tester);

    // pumpAndSettle throws on an overflow, so reaching here already proves
    // the card holds; the card is asserted present so the test cannot pass
    // by rendering nothing at all.
    expect(find.byType(MealCardLibrary), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
