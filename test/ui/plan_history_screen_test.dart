import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:preppick/models/models.dart';
import 'package:preppick/providers/planner_provider.dart';
import 'package:preppick/services/planning_service.dart';
import 'package:preppick/theme/app_theme.dart';
import 'package:preppick/ui/history/plan_history_screen.dart';

import 'fake_planner_provider.dart';

void main() {
  late FakePlannerProvider planner;
  late List<String> opened;

  WeeklyPlanDetail detail({
    required String id,
    required DateTime weekStart,
    required List<WeeklyPlanItem> items,
    required Map<String, MealVariant> meals,
  }) {
    final createdAt = weekStart.add(const Duration(hours: 10));
    return WeeklyPlanDetail(
      plan: WeeklyPlan(
        id: id,
        weekStart: weekStart,
        status: PlanStatus.confirmed,
        createdAt: createdAt,
        confirmedAt: createdAt,
      ),
      items: items,
      mealsById: meals,
    );
  }

  WeeklyPlanItem item({
    required String id,
    required String planId,
    required String mealId,
    required MealType mealType,
    int slotIndex = 0,
  }) => WeeklyPlanItem(
    id: id,
    weeklyPlanId: planId,
    mealVariantId: mealId,
    mealType: mealType,
    slotIndex: slotIndex,
  );

  void seedHistory() {
    final newItems = [
      item(
        id: 'new-breakfast',
        planId: 'new-plan',
        mealId: 'muffins',
        mealType: MealType.breakfast,
      ),
      item(
        id: 'new-dinner-1',
        planId: 'new-plan',
        mealId: 'spaghetti',
        mealType: MealType.dinner,
      ),
      item(
        id: 'new-dinner-2',
        planId: 'new-plan',
        mealId: 'jollof',
        mealType: MealType.dinner,
        slotIndex: 1,
      ),
    ];
    final oldItems = [
      item(
        id: 'old-lunch',
        planId: 'old-plan',
        mealId: 'paninis',
        mealType: MealType.lunch,
      ),
    ];

    planner.historyDetails = [
      detail(
        id: 'new-plan',
        weekStart: DateTime.utc(2026, 3, 23),
        items: newItems,
        meals: {
          'muffins': fakeMeal(id: 'muffins', name: 'Breakfast Muffins'),
          'spaghetti': fakeMeal(
            id: 'spaghetti',
            name: 'Lou Lou Spaghetti',
            protein: 'Chicken',
          ),
          'jollof': fakeMeal(id: 'jollof', name: 'Jollof Rice'),
        },
      ),
      detail(
        id: 'old-plan',
        weekStart: DateTime.utc(2026, 3, 16),
        items: oldItems,
        meals: {'paninis': fakeMeal(id: 'paninis', name: 'Paninis')},
      ),
    ];
  }

  Future<void> pumpHistory(
    WidgetTester tester, {
    bool useDefaultDetailSheet = false,
  }) async {
    tester.view.physicalSize = const Size(1080, 2600);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ChangeNotifierProvider<PlannerProvider>.value(
        value: planner,
        child: MaterialApp(
          theme: AppTheme.light,
          home: PlanHistoryScreen(
            onOpenPlan: useDefaultDetailSheet
                ? null
                : (detail) => opened.add(detail.plan.id),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  setUp(() {
    planner = FakePlannerProvider();
    opened = [];
  });

  tearDown(() => planner.dispose());

  testWidgets('lists confirmed plans newest first with their meals', (
    tester,
  ) async {
    seedHistory();
    await pumpHistory(tester);

    expect(find.text('Plan history'), findsOneWidget);
    expect(find.text('Your previous meal plans.'), findsOneWidget);
    expect(find.text('Mon 23 - Sun 29 Mar'), findsOneWidget);
    expect(find.text('Mon 16 - Sun 22 Mar'), findsOneWidget);
    expect(
      find.text('Breakfast Muffins, Lou Lou Spaghetti, Jollof Rice'),
      findsOneWidget,
    );
    expect(find.text('Paninis'), findsOneWidget);
    expect(find.textContaining('Meal names are read'), findsNothing);

    final firstWeekTop = tester.getTopLeft(find.text('Mon 23 - Sun 29 Mar')).dy;
    final secondWeekTop = tester
        .getTopLeft(find.text('Mon 16 - Sun 22 Mar'))
        .dy;
    expect(firstWeekTop, lessThan(secondWeekTop));
  });

  testWidgets('tapping a history entry opens read-only detail', (tester) async {
    seedHistory();
    await pumpHistory(tester, useDefaultDetailSheet: true);

    await tester.tap(find.text('Mon 23 - Sun 29 Mar'));
    await tester.pumpAndSettle();

    expect(find.text('BREAKFAST'), findsOneWidget);
    expect(find.text('DINNER 1'), findsOneWidget);
    expect(find.text('DINNER 2'), findsOneWidget);
    expect(find.text('Lou Lou Spaghetti'), findsWidgets);
    expect(find.text('Chicken'), findsOneWidget);
    expect(find.text('Swap'), findsNothing);
    expect(find.text('Confirm plan'), findsNothing);
  });

  testWidgets('asks the provider to load history on first open', (
    tester,
  ) async {
    planner.loadedHistory = false;
    await pumpHistory(tester);

    expect(planner.countOf('history'), 1);
  });

  testWidgets('shows an empty state before any plan is confirmed', (
    tester,
  ) async {
    await pumpHistory(tester);

    expect(find.textContaining('Confirmed weeks will appear'), findsOneWidget);
  });
}
