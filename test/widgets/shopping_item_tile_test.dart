import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:preppick/models/models.dart';
import 'package:preppick/theme/app_icons.dart';
import 'package:preppick/theme/app_colors.dart';
import 'package:preppick/theme/app_theme.dart';
import 'package:preppick/widgets/shopping_item_tile.dart';

ShoppingItem item({
  String name = 'Chicken breast',
  double? quantity,
  String? unit,
  bool isChecked = false,
  bool isManual = false,
}) => ShoppingItem(
  id: 'item-1',
  weeklyPlanId: 'plan-1',
  name: name,
  quantity: quantity,
  unit: unit,
  category: IngredientCategory.protein,
  isChecked: isChecked,
  isManual: isManual,
);

void main() {
  Future<void> pumpTile(
    WidgetTester tester,
    ShoppingItem value, {
    VoidCallback? onToggle,
    VoidCallback? onDelete,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: ShoppingItemTile(
            item: value,
            onToggle: onToggle,
            onDelete: onDelete,
          ),
        ),
      ),
    );
  }

  /// The style the tile drew the item's name in.
  TextStyle nameStyle(WidgetTester tester, String name) =>
      tester.widget<Text>(find.text(name)).style!;

  testWidgets('shows the name and a known quantity', (tester) async {
    await pumpTile(tester, item(quantity: 1.25, unit: 'kg'));

    expect(find.text('Chicken breast'), findsOneWidget);
    expect(find.text('1.25 kg'), findsOneWidget);
  });

  testWidgets('shows an unknown quantity as nothing, never "0"', (
    tester,
  ) async {
    await pumpTile(tester, item());

    expect(find.text('Chicken breast'), findsOneWidget);
    expect(find.text('0'), findsNothing);
    expect(find.textContaining('0 '), findsNothing);
    // The row is the name and nothing else.
    expect(find.byType(Text), findsOneWidget);
  });

  testWidgets('writes a count with no unit', (tester) async {
    await pumpTile(tester, item(name: 'Onions', quantity: 3));

    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('tapping anywhere on the row toggles it', (tester) async {
    var taps = 0;
    await pumpTile(tester, item(), onToggle: () => taps++);

    await tester.tap(find.text('Chicken breast'));
    expect(taps, 1);

    // The far end of the row is a target too, not just the tick box.
    await tester.tapAt(tester.getCenter(find.byType(ShoppingItemTile)));
    expect(taps, 2);
  });

  testWidgets('a checked row is struck through and dimmed', (tester) async {
    await pumpTile(tester, item(quantity: 500, unit: 'g', isChecked: true));

    final name = nameStyle(tester, 'Chicken breast');
    expect(name.decoration, TextDecoration.lineThrough);
    // Dimmed to secondary, not tertiary: tertiary is under 2:1 on the card
    // and a ticked line still has to be readable.
    expect(name.color, AppColors.textSecondary);

    final quantity = nameStyle(tester, '500 g');
    expect(quantity.decoration, TextDecoration.lineThrough);

    // The tick itself appears only when checked.
    expect(find.byIcon(AppIcons.checkRounded), findsOneWidget);
  });

  testWidgets('an unchecked row has no strike-through and no tick', (
    tester,
  ) async {
    await pumpTile(tester, item(quantity: 500, unit: 'g'));

    expect(nameStyle(tester, 'Chicken breast').decoration, isNull);
    expect(nameStyle(tester, 'Chicken breast').color, AppColors.textPrimary);
    expect(find.byIcon(AppIcons.checkRounded), findsNothing);
  });

  testWidgets('offers delete only when a handler is given', (tester) async {
    await pumpTile(tester, item(isManual: true));
    expect(find.byIcon(AppIcons.closeRounded), findsNothing);

    var deleted = 0;
    await pumpTile(tester, item(isManual: true), onDelete: () => deleted++);
    await tester.tap(find.byIcon(AppIcons.closeRounded));
    expect(deleted, 1);
  });

  testWidgets('announces its checked state to assistive tech', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpTile(
      tester,
      item(quantity: 500, unit: 'g', isChecked: true),
      onToggle: () {},
    );

    expect(
      tester.getSemantics(
        find.descendant(
          of: find.byType(ShoppingItemTile),
          matching: find.bySemanticsLabel('Chicken breast, 500 g'),
        ),
      ),
      matchesSemantics(
        label: 'Chicken breast, 500 g',
        hasCheckedState: true,
        isChecked: true,
        hasEnabledState: true,
        isEnabled: true,
      ),
    );
    handle.dispose();
  });

  testWidgets('keeps the delete button reachable by assistive tech', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpTile(
      tester,
      item(isManual: true),
      onToggle: () {},
      onDelete: () {},
    );

    // The row's own semantics must not swallow the delete affordance:
    // wrapping the whole tile in one ExcludeSemantics would leave manual
    // items impossible to remove without sight.
    expect(find.bySemanticsLabel('Remove Chicken breast'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('gives the delete button a usable tap target', (tester) async {
    await pumpTile(tester, item(isManual: true), onDelete: () {});

    final size = tester.getSize(find.byType(IconButton));
    expect(size.width, greaterThanOrEqualTo(40));
    expect(size.height, greaterThanOrEqualTo(40));
  });
}
