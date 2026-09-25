import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:preppick/models/models.dart';
import 'package:preppick/providers/planner_provider.dart';
import 'package:preppick/providers/shopping_provider.dart';
import 'package:preppick/theme/app_theme.dart';
import 'package:preppick/ui/shopping/shopping_list_screen.dart';
import 'package:preppick/widgets/prep_filter_chip.dart';
import 'package:preppick/widgets/shopping_item_tile.dart';

import 'fake_planner_provider.dart';
import 'fake_shopping_provider.dart';

void main() {
  late FakeShoppingProvider shopping;
  late FakePlannerProvider planner;

  setUp(() {
    shopping = FakeShoppingProvider();
    planner = FakePlannerProvider()..confirmed = true;
  });

  /// A week spanning three aisles, including a line whose amount was never
  /// recorded and a manual line.
  void seedList() {
    shopping.lines = [
      fakeLine(
        id: 'p1',
        name: 'Spring onions',
        category: IngredientCategory.produce,
        quantity: 2,
      ),
      fakeLine(
        id: 'pr1',
        name: 'Chicken',
        category: IngredientCategory.protein,
      ),
      fakeLine(
        id: 'pr2',
        name: 'Salmon fillets',
        category: IngredientCategory.protein,
        quantity: 1.25,
        unit: 'kg',
      ),
      fakeLine(
        id: 'pa1',
        name: 'Rice',
        category: IngredientCategory.pantry,
        quantity: 500,
        unit: 'g',
      ),
      fakeLine(
        id: 'm1',
        name: 'Bin bags',
        category: IngredientCategory.household,
        isManual: true,
      ),
    ];
  }

  /// An aisle heading, told apart from the filter chip of the same name by
  /// its weight — the chips are Label/Large, the headings Title/Medium.
  Finder heading(String label) => find.byWidgetPredicate(
    (widget) =>
        widget is Text &&
        widget.data == label &&
        widget.style?.fontWeight == FontWeight.w600,
  );

  Future<void> pumpScreen(
    WidgetTester tester, {
    String? planId = 'plan-1',
    double viewWidth = 1080,
  }) async {
    tester.view.physicalSize = Size(viewWidth, 4200);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<PlannerProvider>.value(value: planner),
          ChangeNotifierProvider<ShoppingProvider>.value(value: shopping),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: ShoppingListScreen(planId: planId),
        ),
      ),
    );
    // A few frames rather than pumpAndSettle: a busy state shows a spinner,
    // whose animation never ends.
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  group('grouping', () {
    testWidgets('renders an aisle heading per category, in shopping order', (
      tester,
    ) async {
      seedList();
      await pumpScreen(tester);

      expect(heading('Produce'), findsOneWidget);
      expect(heading('Protein'), findsOneWidget);
      expect(heading('Pantry'), findsOneWidget);
      expect(heading('Household'), findsOneWidget);

      final labels = ['Produce', 'Protein', 'Pantry', 'Household'];
      final offsets = [
        for (final label in labels) tester.getTopLeft(heading(label)).dy,
      ];
      expect(offsets, orderedEquals([...offsets]..sort()));
    });

    testWidgets('draws every line, unknown quantities included', (
      tester,
    ) async {
      seedList();
      await pumpScreen(tester);

      expect(find.byType(ShoppingItemTile), findsNWidgets(5));
      // The line with no recorded amount is present, and shows no number.
      expect(find.text('Chicken'), findsOneWidget);
      expect(find.text('0'), findsNothing);
      expect(find.text('0 g'), findsNothing);
    });

    testWidgets('formats quantities per line', (tester) async {
      seedList();
      await pumpScreen(tester);

      expect(find.text('2'), findsOneWidget); // count, no unit
      expect(find.text('1.25 kg'), findsOneWidget);
      expect(find.text('500 g'), findsOneWidget);
    });

    testWidgets('shows per-aisle and overall progress', (tester) async {
      seedList();
      shopping.lines = [
        for (final line in shopping.lines)
          line.id == 'pr1' ? line.copyWith(isChecked: true) : line,
      ];
      await pumpScreen(tester);

      expect(find.text('1 of 5 ticked off.'), findsOneWidget);
      expect(find.text('1/2'), findsOneWidget); // protein
      expect(find.text('0/1'), findsNWidgets(3)); // the single-line aisles
    });

    testWidgets('opens the list for its plan on first frame', (tester) async {
      seedList();
      await pumpScreen(tester);

      expect(shopping.calls, ['open:plan-1']);
    });
  });

  group('checking off', () {
    testWidgets('tapping a row toggles it and writes straight away', (
      tester,
    ) async {
      seedList();
      await pumpScreen(tester);

      await tester.tap(find.text('Rice'));
      await tester.pump();

      expect(shopping.calls, contains('toggle:pa1'));
      expect(shopping.items.firstWhere((i) => i.id == 'pa1').isChecked, isTrue);
    });

    testWidgets('the checked style follows the state', (tester) async {
      seedList();
      await pumpScreen(tester);

      expect(tester.widget<Text>(find.text('Rice')).style!.decoration, isNull);

      await tester.tap(find.text('Rice'));
      await tester.pump();

      expect(
        tester.widget<Text>(find.text('Rice')).style!.decoration,
        TextDecoration.lineThrough,
      );
      // Ticked lines stay put rather than vanishing from the list.
      expect(find.byType(ShoppingItemTile), findsNWidgets(5));
      expect(find.text('1 of 5 ticked off.'), findsOneWidget);
    });

    testWidgets('a failed write is reported rather than silently lost', (
      tester,
    ) async {
      seedList();
      shopping.nextResult = false;
      await pumpScreen(tester);

      await tester.tap(find.text('Rice'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Could not save Rice. Try again.'), findsOneWidget);
      expect(tester.widget<Text>(find.text('Rice')).style!.decoration, isNull);
    });

    testWidgets('untick-everything appears only once something is ticked', (
      tester,
    ) async {
      seedList();
      await pumpScreen(tester);
      expect(find.byTooltip('Untick everything'), findsNothing);

      await tester.tap(find.text('Rice'));
      await tester.pump();

      await tester.tap(find.byTooltip('Untick everything'));
      await tester.pump();

      expect(shopping.calls, contains('clearChecked'));
      expect(find.text('0 of 5 ticked off.'), findsOneWidget);
    });
  });

  group('filters', () {
    testWidgets('offers All plus only the aisles present', (tester) async {
      seedList();
      // Wide enough that the horizontal chip row builds every chip rather
      // than lazily stopping at the edge of the viewport.
      await pumpScreen(tester, viewWidth: 3000);

      final labels = tester
          .widgetList<PrepFilterChip>(find.byType(PrepFilterChip))
          .map((chip) => chip.label)
          .toList();
      expect(labels, ['All', 'Produce', 'Protein', 'Pantry', 'Household']);
      // Nothing in the week is frozen, so no chip offers it.
      expect(labels, isNot(contains('Frozen')));
    });

    testWidgets('choosing an aisle limits the visible rows', (tester) async {
      seedList();
      await pumpScreen(tester);

      await tester.tap(find.widgetWithText(PrepFilterChip, 'Protein'));
      await tester.pump();

      expect(find.byType(ShoppingItemTile), findsNWidgets(2));
      expect(find.text('Chicken'), findsOneWidget);
      expect(find.text('Salmon fillets'), findsOneWidget);
      expect(find.text('Rice'), findsNothing);
      // Progress still counts the whole week, not the filtered view.
      expect(find.text('0 of 5 ticked off.'), findsOneWidget);
    });

    testWidgets('All restores the whole list', (tester) async {
      seedList();
      await pumpScreen(tester);

      await tester.tap(find.widgetWithText(PrepFilterChip, 'Protein'));
      await tester.pump();
      await tester.tap(find.widgetWithText(PrepFilterChip, 'All'));
      await tester.pump();

      expect(find.byType(ShoppingItemTile), findsNWidgets(5));
    });
  });

  group('manual items', () {
    testWidgets('adding one creates a row', (tester) async {
      seedList();
      await pumpScreen(tester);

      await tester.tap(find.text('Add an item'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'Coffee');
      await tester.pump();
      await tester.tap(find.text('Add to list'));
      await tester.pumpAndSettle();

      expect(shopping.calls, contains('add:Coffee'));
      expect(find.text('Coffee'), findsOneWidget);
      expect(find.byType(ShoppingItemTile), findsNWidgets(6));
    });

    testWidgets('an added item with no amount shows no quantity', (
      tester,
    ) async {
      seedList();
      await pumpScreen(tester);

      await tester.tap(find.text('Add an item'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Coffee');
      await tester.pump();
      await tester.tap(find.text('Add to list'));
      await tester.pumpAndSettle();

      final coffee = shopping.items.firstWhere((i) => i.name == 'Coffee');
      expect(coffee.quantity, isNull);
      expect(find.text('0'), findsNothing);
    });

    testWidgets('Add to list stays disabled until a name is typed', (
      tester,
    ) async {
      seedList();
      await pumpScreen(tester);

      await tester.tap(find.text('Add an item'));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Add to list'))
            .onPressed,
        isNull,
      );
    });

    testWidgets('only a manual line offers a remove control', (tester) async {
      seedList();
      await pumpScreen(tester);

      // One close button, on the one manual line.
      expect(find.byTooltip('Remove Bin bags'), findsOneWidget);
      expect(find.byTooltip('Remove Rice'), findsNothing);

      await tester.tap(find.byTooltip('Remove Bin bags'));
      await tester.pump();

      expect(shopping.calls, contains('delete:m1'));
      expect(find.text('Bin bags'), findsNothing);
    });
  });

  group('empty and loading states', () {
    testWidgets('shows a spinner while the list is being built', (
      tester,
    ) async {
      shopping.generating = true;
      await pumpScreen(tester);

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(ShoppingItemTile), findsNothing);
    });

    testWidgets('explains an empty list rather than showing a blank screen', (
      tester,
    ) async {
      await pumpScreen(tester);

      expect(find.textContaining('no ingredients recorded'), findsOneWidget);
    });

    testWidgets('points at planning when there is no confirmed week', (
      tester,
    ) async {
      planner.confirmed = false;
      await pumpScreen(tester, planId: null);

      expect(find.textContaining('once you confirm a week'), findsOneWidget);
      expect(find.text('Plan this week'), findsOneWidget);
      // Nothing was opened, because there is nothing to open.
      expect(shopping.calls, isEmpty);
    });

    testWidgets('a load failure offers a retry', (tester) async {
      shopping.failure = Exception('boom');
      await pumpScreen(tester);

      expect(find.textContaining('Something went wrong'), findsOneWidget);

      await tester.tap(find.text('Try again'));
      await tester.pump();

      expect(shopping.countOf('open:plan-1'), 2);
    });

    testWidgets('says so when a filter hides everything', (tester) async {
      seedList();
      await pumpScreen(tester);

      await tester.tap(find.widgetWithText(PrepFilterChip, 'Protein'));
      await tester.pump();
      // Everything in the filtered aisle disappears from the list.
      shopping.lines = shopping.lines
          .where((i) => i.category != IngredientCategory.protein)
          .toList();
      shopping.notifyListeners();
      await tester.pump();

      expect(find.textContaining('Nothing in this aisle'), findsOneWidget);
    });
  });

  testWidgets('survives a large text scale', (tester) async {
    seedList();
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await pumpScreen(tester);

    expect(tester.takeException(), isNull);
  });
}
