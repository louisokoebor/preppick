import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:preppick/models/models.dart';
import 'package:preppick/providers/planner_provider.dart';
import 'package:preppick/providers/settings_provider.dart';
import 'package:preppick/services/settings_service.dart';
import 'package:preppick/theme/app_theme.dart';
import 'package:preppick/ui/planner/plan_this_week_screen.dart';
import 'package:preppick/widgets/meal_slot_card.dart';

import 'fake_planner_provider.dart';

/// In-memory stand-in for [SettingsService]; see the note in
/// `fake_planner_provider.dart` on why a real database is avoided here.
class _FakeSettingsService implements SettingsService {
  _FakeSettingsService(this._stored);

  AppSettings _stored;

  @override
  Future<AppSettings> getSettings() async => _stored;

  @override
  Future<bool> hasSavedMealCounts() async => true;

  @override
  Future<AppSettings> saveSettings(AppSettings settings) async =>
      _stored = settings.copyWith();

  @override
  Future<void> clearSettings() async {}
}

void main() {
  late FakePlannerProvider planner;
  late SettingsProvider settings;

  Future<void> pumpScreen(
    WidgetTester tester, {
    required AppSettings counts,
    VoidCallback? onPlanGenerated,
    VoidCallback? onOpenMealLibrary,
  }) async {
    tester.view.physicalSize = const Size(1080, 4200);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    settings = SettingsProvider(_FakeSettingsService(counts));
    await settings.load();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsProvider>.value(value: settings),
          ChangeNotifierProvider<PlannerProvider>.value(value: planner),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: PlanThisWeekScreen(
            onPlanGenerated: onPlanGenerated,
            onOpenMealLibrary: onOpenMealLibrary,
          ),
        ),
      ),
    );
    // A few frames rather than pumpAndSettle: a busy state shows a spinner,
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

  testWidgets('renders one slot card per saved meal count', (tester) async {
    await pumpScreen(
      tester,
      counts: const AppSettings(
        breakfastCount: 1,
        lunchCount: 0,
        dinnerCount: 3,
      ),
    );

    expect(find.byType(MealSlotCard), findsNWidgets(4));
    expect(find.text('BREAKFAST'), findsOneWidget);
    // Dinners are numbered because there is more than one; breakfast is not.
    expect(find.text('DINNER 1'), findsOneWidget);
    expect(find.text('DINNER 3'), findsOneWidget);
    expect(find.text('LUNCH'), findsNothing);
  });

  testWidgets('slot count follows a change in settings', (tester) async {
    await pumpScreen(tester, counts: const AppSettings());
    expect(find.byType(MealSlotCard), findsNWidgets(4));

    settings.updateMealCounts(breakfast: 0, lunch: 2, dinner: 2);
    await tester.pump();

    expect(find.byType(MealSlotCard), findsNWidgets(4));
    expect(find.text('BREAKFAST'), findsNothing);
    expect(find.text('LUNCH 1'), findsOneWidget);
  });

  testWidgets('tapping Plan this week asks the provider exactly once', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      counts: const AppSettings(),
      onPlanGenerated: () {},
    );

    await tester.tap(find.text('Generate my plan'));
    await tester.pump();

    expect(planner.countOf('generate'), 1);
  });

  testWidgets('a generation already in flight swallows a second tap', (
    tester,
  ) async {
    await pumpScreen(tester, counts: const AppSettings());

    planner.beginGenerating();
    await tester.pump();

    // The busy button shows a spinner instead of its label and is disabled,
    // so the tap lands on the button but reaches no callback.
    await tester.tap(find.byType(PlanThisWeekScreen), warnIfMissed: false);
    await tester.pump();

    expect(planner.countOf('generate'), 0);
  });

  testWidgets('navigates on a successful generation only', (tester) async {
    var navigated = 0;
    await pumpScreen(
      tester,
      counts: const AppSettings(),
      onPlanGenerated: () => navigated++,
    );

    planner.nextResult = false;
    await tester.tap(find.text('Generate my plan'));
    await tester.pump();
    expect(navigated, 0, reason: 'a failed generation must not navigate');

    planner.nextResult = true;
    await tester.tap(find.text('Generate my plan'));
    await tester.pump();
    expect(navigated, 1);
  });

  testWidgets('an empty library shows the message and a link to the library', (
    tester,
  ) async {
    var openedLibrary = 0;
    planner
      ..message = 'Your meal library is empty. Add a few meals.'
      ..libraryEmpty = true;

    await pumpScreen(
      tester,
      counts: const AppSettings(),
      onOpenMealLibrary: () => openedLibrary++,
    );

    expect(
      find.text('Your meal library is empty. Add a few meals.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Go to Meal Library'));
    await tester.pump();
    expect(openedLibrary, 1);
  });

  testWidgets('a shortage short of an empty library shows no library link', (
    tester,
  ) async {
    planner.message = 'You asked for 3 dinners but your library has 2.';
    await pumpScreen(tester, counts: const AppSettings());

    expect(find.textContaining('You asked for 3 dinners'), findsOneWidget);
    expect(find.text('Go to Meal Library'), findsNothing);
  });

  testWidgets('a failure is reported rather than swallowed', (tester) async {
    planner.failure = StateError('database is gone');
    await pumpScreen(tester, counts: const AppSettings());

    expect(find.textContaining('Something went wrong'), findsOneWidget);
  });

  testWidgets('zero meal counts disable planning and say why', (tester) async {
    await pumpScreen(
      tester,
      counts: const AppSettings(
        breakfastCount: 0,
        lunchCount: 0,
        dinnerCount: 0,
      ),
    );

    expect(find.byType(MealSlotCard), findsNothing);
    expect(find.textContaining('not asked for any meals'), findsOneWidget);

    await tester.tap(find.text('Generate my plan'), warnIfMissed: false);
    await tester.pump();
    expect(planner.countOf('generate'), 0);
  });

  testWidgets('an existing draft shows draft actions instead of empty slots', (
    tester,
  ) async {
    planner
      ..plannedItems = [
        fakeItem(id: 'd1', mealType: MealType.dinner),
        fakeItem(id: 'd2', mealType: MealType.dinner, slotIndex: 1),
      ]
      ..meals = {
        'meal-d1': fakeMeal(id: 'meal-d1', name: 'Jollof Rice'),
        'meal-d2': fakeMeal(id: 'meal-d2', name: 'Fried Rice'),
      };

    await pumpScreen(
      tester,
      counts: const AppSettings(
        breakfastCount: 0,
        lunchCount: 0,
        dinnerCount: 2,
      ),
    );

    expect(find.text('Draft plan'), findsOneWidget);
    expect(find.text('Confirm plan'), findsOneWidget);
    expect(find.text('Regenerate'), findsOneWidget);
    expect(find.text('Plan this week'), findsNothing);
    expect(find.text('Jollof Rice'), findsOneWidget);
  });

  testWidgets('a confirmed current week offers edit, not generate', (
    tester,
  ) async {
    planner
      ..confirmed = true
      ..plannedItems = [fakeItem(id: 'd1', mealType: MealType.dinner)]
      ..meals = {'meal-d1': fakeMeal(id: 'meal-d1', name: 'Jollof Rice')};

    await pumpScreen(
      tester,
      counts: const AppSettings(
        breakfastCount: 0,
        lunchCount: 0,
        dinnerCount: 1,
      ),
    );

    expect(find.text('This week\'s plan'), findsOneWidget);
    expect(find.text('Edit plan'), findsOneWidget);
    expect(find.text('View shopping list'), findsOneWidget);
    expect(find.text('Regenerate'), findsNothing);
    expect(find.text('Plan this week'), findsNothing);
    expect(find.byTooltip('Swap Dinner'), findsNothing);

    await tester.tap(find.text('Edit plan'));
    await tester.pump();

    expect(find.text('Done editing'), findsOneWidget);
    expect(find.byTooltip('Swap Dinner'), findsOneWidget);
  });
}
