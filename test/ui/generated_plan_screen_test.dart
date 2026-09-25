import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:preppick/models/models.dart';
import 'package:preppick/providers/planner_provider.dart';
import 'package:preppick/providers/settings_provider.dart';
import 'package:preppick/services/settings_service.dart';
import 'package:preppick/theme/app_theme.dart';
import 'package:preppick/ui/planner/generated_plan_screen.dart';
import 'package:preppick/ui/planner/swap_meal_sheet.dart';
import 'package:preppick/widgets/meal_slot_card.dart';

import 'fake_planner_provider.dart';

/// In-memory stand-in for [SettingsService]; Regenerate reads the counts from
/// it, nothing else on this screen does.
class _FakeSettingsService implements SettingsService {
  @override
  Future<AppSettings> getSettings() async => AppSettings.defaults;

  @override
  Future<bool> hasSavedMealCounts() async => true;

  @override
  Future<AppSettings> saveSettings(AppSettings settings) async => settings;

  @override
  Future<void> clearSettings() async {}
}

void main() {
  late FakePlannerProvider planner;
  late SettingsProvider settings;

  /// A plan of one breakfast and two dinners.
  void seedPlan() {
    planner
      ..plannedItems = [
        fakeItem(id: 'b1', mealType: MealType.breakfast),
        fakeItem(id: 'd1', mealType: MealType.dinner),
        fakeItem(id: 'd2', mealType: MealType.dinner, slotIndex: 1),
      ]
      ..meals = {
        'meal-b1': fakeMeal(id: 'meal-b1', name: 'Breakfast Muffins'),
        'meal-d1': fakeMeal(
          id: 'meal-d1',
          name: 'Lou Lou Spaghetti',
          protein: 'Chicken',
        ),
        'meal-d2': fakeMeal(id: 'meal-d2', name: 'Jollof Rice'),
      };
  }

  Future<void> pumpScreen(
    WidgetTester tester, {
    VoidCallback? onConfirmed,
    void Function(WeeklyPlanItem)? onSwapRequested,
  }) async {
    tester.view.physicalSize = const Size(1080, 4200);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    settings = SettingsProvider(_FakeSettingsService());
    await settings.load();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsProvider>.value(value: settings),
          ChangeNotifierProvider<PlannerProvider>.value(value: planner),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: GeneratedPlanScreen(
            onConfirmed: onConfirmed,
            onSwapRequested: onSwapRequested,
          ),
        ),
      ),
    );
    // A few frames rather than pumpAndSettle: a busy action shows a spinner,
    // whose animation never ends.
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  setUp(() => planner = FakePlannerProvider());

  tearDown(() {
    planner.dispose();
    settings.dispose();
  });

  testWidgets('renders one card per planned item, with its meal', (
    tester,
  ) async {
    seedPlan();
    await pumpScreen(tester);

    expect(find.byType(MealSlotCard), findsNWidgets(3));
    expect(find.text('Breakfast Muffins'), findsOneWidget);
    expect(find.text('Lou Lou Spaghetti'), findsOneWidget);
    expect(find.text('Jollof Rice'), findsOneWidget);
    // The protein line appears only where a meal records one — PrepPick does
    // not invent it.
    expect(find.text('Chicken'), findsOneWidget);
    expect(find.text('DINNER 2'), findsOneWidget);
    expect(find.text('BREAKFAST'), findsOneWidget);
  });

  testWidgets('Confirm plan is primary and Regenerate secondary', (
    tester,
  ) async {
    seedPlan();
    await pumpScreen(tester);

    expect(find.text('Confirm plan'), findsOneWidget);
    expect(find.text('Regenerate'), findsOneWidget);
  });

  testWidgets('confirming asks the provider exactly once', (tester) async {
    seedPlan();
    await pumpScreen(tester, onConfirmed: () {});

    await tester.tap(find.text('Confirm plan'));
    await tester.pump();

    expect(planner.countOf('confirm'), 1);
  });

  testWidgets('a confirmation in flight swallows a second tap', (tester) async {
    seedPlan();
    await pumpScreen(tester, onConfirmed: () {});

    planner.confirming = true;
    await tester.pump();

    await tester.tap(find.byType(GeneratedPlanScreen), warnIfMissed: false);
    await tester.pump();

    expect(planner.countOf('confirm'), 0);
  });

  testWidgets('a confirmed plan moves on toward the shopping list', (
    tester,
  ) async {
    seedPlan();
    var navigated = 0;
    await pumpScreen(tester, onConfirmed: () => navigated++);

    await tester.tap(find.text('Confirm plan'));
    await tester.pump();

    expect(navigated, 1);
    // The screen now reflects a confirmed plan: no more editing, and the way
    // on is the shopping list.
    expect(find.text('Edit plan'), findsOneWidget);
    expect(find.text('View shopping list'), findsOneWidget);
    expect(find.text('Regenerate'), findsNothing);
    expect(find.byTooltip('Swap Breakfast'), findsNothing);
  });

  testWidgets('a confirmed plan exposes swaps only while editing', (
    tester,
  ) async {
    seedPlan();
    planner.confirmed = true;
    await pumpScreen(tester);

    expect(find.text('Edit plan'), findsOneWidget);
    expect(find.byTooltip('Swap Breakfast'), findsNothing);

    await tester.tap(find.text('Edit plan'));
    await tester.pump();

    expect(find.text('Done editing'), findsOneWidget);
    expect(find.byTooltip('Swap Breakfast'), findsOneWidget);
    expect(find.byTooltip('Swap Dinner 1'), findsOneWidget);
    expect(find.byTooltip('Swap Dinner 2'), findsOneWidget);
  });

  testWidgets('a failed confirmation stays put and says so', (tester) async {
    seedPlan();
    var navigated = 0;
    planner.nextResult = false;
    await pumpScreen(tester, onConfirmed: () => navigated++);

    await tester.tap(find.text('Confirm plan'));
    await tester.pump();

    expect(navigated, 0);
    expect(find.textContaining('Could not confirm'), findsOneWidget);
    expect(find.text('Confirm plan'), findsOneWidget);
  });

  testWidgets('regenerating leaves the plan a draft', (tester) async {
    seedPlan();
    await pumpScreen(tester);

    await tester.tap(find.text('Regenerate'));
    await tester.pump();

    expect(planner.countOf('generate'), 1);
    expect(planner.isConfirmed, isFalse);
    expect(find.text('Confirm plan'), findsOneWidget);
  });

  testWidgets('regenerating is blocked while another write runs', (
    tester,
  ) async {
    seedPlan();
    await pumpScreen(tester);

    planner.confirming = true;
    await tester.pump();

    await tester.tap(find.text('Regenerate'), warnIfMissed: false);
    await tester.pump();

    expect(planner.countOf('generate'), 0);
  });

  testWidgets('Swap addresses one slot only', (tester) async {
    seedPlan();
    final swapped = <String>[];
    await pumpScreen(tester, onSwapRequested: (item) => swapped.add(item.id));

    // The second dinner's Swap, to prove the card passes its own item.
    await tester.tap(find.byTooltip('Swap Dinner 2'));
    await tester.pump();

    expect(swapped, ['d2']);
  });

  testWidgets('Swap opens the swap sheet for that slot by default', (
    tester,
  ) async {
    seedPlan();
    planner.candidates = [fakeMeal(id: 'meal-b2', name: 'Overnight Oats')];
    await pumpScreen(tester);

    await tester.tap(find.byTooltip('Swap Breakfast'));
    await tester.pumpAndSettle();

    expect(find.byType(SwapMealSheet), findsOneWidget);
    // The sheet asked for this slot's alternatives, and nothing was swapped
    // merely by opening it.
    expect(planner.calls, ['candidates:b1']);
  });

  testWidgets('picking a meal in the sheet swaps only that slot', (
    tester,
  ) async {
    seedPlan();
    planner.candidates = [fakeMeal(id: 'meal-b2', name: 'Overnight Oats')];
    await pumpScreen(tester);

    await tester.tap(find.byTooltip('Swap Breakfast'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Overnight Oats'));
    await tester.pumpAndSettle();

    expect(find.byType(SwapMealSheet), findsNothing);
    expect(planner.calls, ['candidates:b1', 'swap:b1:meal-b2']);
  });

  testWidgets('an empty plan disables confirming and says what to do', (
    tester,
  ) async {
    await pumpScreen(tester);

    expect(find.byType(MealSlotCard), findsNothing);
    expect(find.textContaining('no meals yet'), findsOneWidget);

    await tester.tap(find.text('Confirm plan'), warnIfMissed: false);
    await tester.pump();
    expect(planner.countOf('confirm'), 0);
  });

  testWidgets('a shortage is explained on the generated plan too', (
    tester,
  ) async {
    seedPlan();
    planner.message = 'You asked for 3 dinners but your library has 2.';
    await pumpScreen(tester);

    expect(find.textContaining('You asked for 3 dinners'), findsOneWidget);
  });
}
