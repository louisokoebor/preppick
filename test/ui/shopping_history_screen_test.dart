import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:preppick/app/routes.dart';
import 'package:preppick/models/models.dart';
import 'package:preppick/providers/planner_provider.dart';
import 'package:preppick/providers/shopping_history_provider.dart';
import 'package:preppick/providers/shopping_provider.dart';
import 'package:preppick/services/shopping_service.dart';
import 'package:preppick/theme/app_theme.dart';
import 'package:preppick/ui/shopping/shopping_history_screen.dart';
import 'package:preppick/ui/shopping/shopping_list_screen.dart';
import 'package:preppick/ui/shopping/shopping_week_screen.dart';
import 'package:preppick/widgets/shopping_item_tile.dart';
import 'package:preppick/widgets/shopping_week_card.dart';

import 'fake_planner_provider.dart';
import 'fake_shopping_history_provider.dart';
import 'fake_shopping_provider.dart';

void main() {
  late FakeShoppingHistoryProvider history;

  final older = DateTime.utc(2026, 3, 2);
  final newer = DateTime.utc(2026, 3, 9);

  setUp(() => history = FakeShoppingHistoryProvider());

  Future<void> pump(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider<ShoppingHistoryProvider>.value(
        value: history,
        child: MaterialApp(theme: AppTheme.light, home: home),
      ),
    );
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  group('Past shopping lists', () {
    testWidgets('loads on open and draws one card per past week', (
      tester,
    ) async {
      history.past = [
        ShoppingListSummary(
          plan: fakePastPlan('new', newer),
          itemCount: 12,
          checkedCount: 12,
        ),
        ShoppingListSummary(
          plan: fakePastPlan('old', older),
          itemCount: 1,
          checkedCount: 0,
        ),
      ];
      await pump(tester, const ShoppingHistoryScreen());

      expect(history.calls, contains('load'));
      expect(find.byType(ShoppingWeekCard), findsNWidgets(2));
      expect(find.text('Mon 9 - Sun 15 Mar'), findsOneWidget);
      expect(find.text('12 items · All ticked off'), findsOneWidget);
      expect(find.text('1 item · Nothing ticked off'), findsOneWidget);
    });

    testWidgets('tapping a card opens that week', (tester) async {
      final opened = <String>[];
      history.past = [
        ShoppingListSummary(
          plan: fakePastPlan('old', older),
          itemCount: 3,
          checkedCount: 2,
        ),
      ];
      await pump(
        tester,
        ShoppingHistoryScreen(onOpenWeek: (s) => opened.add(s.plan.id)),
      );

      await tester.tap(find.byType(ShoppingWeekCard));
      expect(opened, ['old']);
    });

    testWidgets('explains an empty history', (tester) async {
      await pump(tester, const ShoppingHistoryScreen());
      expect(find.byType(ShoppingWeekCard), findsNothing);
      expect(find.textContaining('Past weeks appear here'), findsOneWidget);
    });

    testWidgets('offers a retry when loading fails', (tester) async {
      history.failure = Exception('boom');
      await pump(tester, const ShoppingHistoryScreen());
      await tester.tap(find.text('Try again'));
      expect(history.countOf('load'), 2);
    });
  });

  group('One past week', () {
    SavedShoppingList savedWeek() => SavedShoppingList(
      plan: fakePastPlan('old', older),
      groups: [
        ShoppingCategoryGroup(
          category: IngredientCategory.produce,
          items: [
            fakeLine(
              id: 'a',
              name: 'Onions',
              category: IngredientCategory.produce,
              isChecked: true,
            ),
            fakeLine(
              id: 'b',
              name: 'Garlic',
              category: IngredientCategory.produce,
            ),
          ],
        ),
        ShoppingCategoryGroup(
          category: IngredientCategory.household,
          items: [
            fakeLine(
              id: 'c',
              name: 'Bin bags',
              category: IngredientCategory.household,
              isManual: true,
            ),
          ],
        ),
      ],
    );

    testWidgets('shows the week’s saved lines under its dates', (tester) async {
      history.weeks = {'old': savedWeek()};
      await pump(tester, const ShoppingWeekScreen(planId: 'old'));

      expect(history.calls, ['open:old']);
      expect(find.text('Mon 2 - Sun 8 Mar'), findsOneWidget);
      expect(find.text('3 items, 1 ticked off.'), findsOneWidget);
      expect(find.byType(ShoppingItemTile), findsNWidgets(3));
    });

    testWidgets('is read-only: no ticking and no deleting', (tester) async {
      history.weeks = {'old': savedWeek()};
      await pump(tester, const ShoppingWeekScreen(planId: 'old'));

      for (final tile in tester.widgetList<ShoppingItemTile>(
        find.byType(ShoppingItemTile),
      )) {
        expect(tile.onToggle, isNull);
        expect(tile.onDelete, isNull);
      }
      expect(find.text('Add an item'), findsNothing);
    });

    testWidgets('says so when no list was saved', (tester) async {
      history.weeks = {
        'old': SavedShoppingList(plan: fakePastPlan('old', older), groups: []),
      };
      await pump(tester, const ShoppingWeekScreen(planId: 'old'));
      expect(
        find.text('No shopping list was saved for this week.'),
        findsOneWidget,
      );
    });

    testWidgets('says so when the plan no longer exists', (tester) async {
      await pump(tester, const ShoppingWeekScreen(planId: 'gone'));
      expect(find.text('This week could not be found.'), findsOneWidget);
    });
  });

  group('Shopping list history icon', () {
    Future<void> pumpList(WidgetTester tester, {VoidCallback? onOpen}) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<PlannerProvider>.value(
              value: FakePlannerProvider(),
            ),
            ChangeNotifierProvider<ShoppingProvider>.value(
              value: FakeShoppingProvider(),
            ),
            ChangeNotifierProvider<ShoppingHistoryProvider>.value(
              value: history,
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: ShoppingListScreen(onOpenHistory: onOpen),
            routes: {
              AppRoutes.shoppingHistory: (_) => const ShoppingHistoryScreen(),
            },
          ),
        ),
      );
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    }

    testWidgets('is shown even before a week is confirmed', (tester) async {
      var taps = 0;
      await pumpList(tester, onOpen: () => taps++);

      await tester.tap(find.byTooltip('Past shopping lists'));
      expect(taps, 1);
    });

    testWidgets('opens Past shopping lists by default', (tester) async {
      await pumpList(tester);

      await tester.tap(find.byTooltip('Past shopping lists'));
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(find.byType(ShoppingHistoryScreen), findsOneWidget);
    });
  });
}
