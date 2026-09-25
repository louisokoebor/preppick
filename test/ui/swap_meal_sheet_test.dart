import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:preppick/models/models.dart';
import 'package:preppick/providers/planner_provider.dart';
import 'package:preppick/theme/app_theme.dart';
import 'package:preppick/ui/planner/swap_meal_sheet.dart';
import 'package:preppick/widgets/meal_card_compact.dart';
import 'package:preppick/widgets/prep_filter_chip.dart';

import 'fake_planner_provider.dart';

void main() {
  late FakePlannerProvider planner;

  /// What [SwapMealSheet.show] resolved to, recorded by the host button.
  bool? result;

  final target = fakeItem(
    id: 'd1',
    mealType: MealType.dinner,
    mealVariantId: 'meal-current',
  );

  /// Three dinner alternatives, two of them chicken.
  List<MealVariant> dinnerCandidates() => [
    fakeMeal(id: 'meal-1', name: 'Fried Rice', protein: 'Chicken'),
    fakeMeal(id: 'meal-2', name: 'Jollof Rice', protein: 'Turkey'),
    fakeMeal(id: 'meal-3', name: 'Chicken Wraps', protein: 'Chicken'),
  ];

  /// Pumps a host screen with a button that opens the sheet, so the sheet is
  /// exercised through its real [SwapMealSheet.show] entry point.
  Future<void> pumpSheet(
    WidgetTester tester, {
    WeeklyPlanItem? item,
    int totalOfType = 2,
    String? currentMealName = 'Lou Lou Spaghetti',
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ChangeNotifierProvider<PlannerProvider>.value(
        value: planner,
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await SwapMealSheet.show(
                    context,
                    item: item ?? target,
                    totalOfType: totalOfType,
                    currentMealName: currentMealName,
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  setUp(() {
    planner = FakePlannerProvider()..candidates = dinnerCandidates();
    result = null;
  });

  testWidgets('lists the alternatives the planner offered, in order', (
    tester,
  ) async {
    await pumpSheet(tester);

    expect(planner.calls, ['candidates:d1']);
    expect(find.byType(MealCardCompact), findsNWidgets(3));
    // The candidate list is already ranked and already excludes the meal in
    // the slot, so the sheet must not show it.
    expect(find.text('Lou Lou Spaghetti', skipOffstage: false), findsNothing);
    expect(find.textContaining('Swap Dinner 1'), findsOneWidget);
  });

  testWidgets('search matches meal names case-insensitively', (tester) async {
    await pumpSheet(tester);

    await tester.enterText(find.byType(TextField), 'jollof');
    await tester.pumpAndSettle();

    expect(find.text('Jollof Rice'), findsOneWidget);
    expect(find.byType(MealCardCompact), findsOneWidget);
  });

  testWidgets('search also matches the protein line', (tester) async {
    await pumpSheet(tester);

    await tester.enterText(find.byType(TextField), 'TURKEY');
    await tester.pumpAndSettle();

    expect(find.byType(MealCardCompact), findsOneWidget);
    expect(find.text('Jollof Rice'), findsOneWidget);
  });

  testWidgets('a search matching nothing says so without emptying the list '
      'permanently', (tester) async {
    await pumpSheet(tester);

    await tester.enterText(find.byType(TextField), 'sushi');
    await tester.pumpAndSettle();
    expect(find.byType(MealCardCompact), findsNothing);
    expect(find.text('No meals match your search.'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();
    expect(find.byType(MealCardCompact), findsNWidgets(3));
  });

  testWidgets('protein chips narrow the list and only offer real proteins', (
    tester,
  ) async {
    await pumpSheet(tester);

    // All, Chicken, Turkey — nothing else.
    expect(find.byType(PrepFilterChip), findsNWidgets(3));

    await tester.tap(find.widgetWithText(PrepFilterChip, 'Turkey'));
    await tester.pumpAndSettle();

    expect(find.byType(MealCardCompact), findsOneWidget);
    expect(find.text('Jollof Rice'), findsOneWidget);
  });

  testWidgets('selecting a meal swaps that slot and closes the sheet', (
    tester,
  ) async {
    await pumpSheet(tester);

    await tester.tap(find.text('Chicken Wraps'));
    await tester.pumpAndSettle();

    expect(planner.calls, ['candidates:d1', 'swap:d1:meal-3']);
    expect(find.byType(SwapMealSheet), findsNothing);
    // The sheet resolves to true so the caller can tell a swap from a
    // dismissal. `result` is captured by the host button's callback, which
    // has completed by the time the sheet has settled closed.
    expect(result, isTrue);
  });

  testWidgets('a failed swap keeps the sheet open and explains why', (
    tester,
  ) async {
    planner.nextResult = false;
    await pumpSheet(tester);

    await tester.tap(find.text('Fried Rice'));
    await tester.pumpAndSettle();

    expect(find.byType(SwapMealSheet), findsOneWidget);
    expect(find.textContaining('Could not swap in Fried Rice'), findsOneWidget);
  });

  testWidgets('an empty candidate list points at the library, not a search', (
    tester,
  ) async {
    planner.candidates = const [];
    await pumpSheet(tester);

    expect(find.byType(MealCardCompact), findsNothing);
    expect(find.byType(PrepFilterChip), findsNothing);
    expect(
      find.textContaining('no other dinner meal to swap in'),
      findsOneWidget,
    );
  });

  testWidgets('cards are inert while a swap is already running', (
    tester,
  ) async {
    planner.swapping = true;
    await pumpSheet(tester);

    await tester.tap(find.text('Fried Rice'));
    await tester.pumpAndSettle();

    expect(planner.calls, ['candidates:d1']);
    expect(find.byType(SwapMealSheet), findsOneWidget);
  });
}
