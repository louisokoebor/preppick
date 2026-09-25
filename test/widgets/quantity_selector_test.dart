import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:preppick/theme/app_theme.dart';
import 'package:preppick/widgets/quantity_selector.dart';

Future<void> _pump(
  WidgetTester tester, {
  required int value,
  ValueChanged<int>? onChanged,
  int min = 0,
  int max = 7,
}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: QuantitySelector(
          value: value,
          min: min,
          max: max,
          semanticLabel: 'Dinner',
          onChanged: onChanged,
        ),
      ),
    ),
  );
}

// The design draws the steps as glyphs, not icons, so the tooltip is the
// stable handle — it is also what a screen reader user hears.
Finder get _plus => find.byTooltip('Increase Dinner');
Finder get _minus => find.byTooltip('Decrease Dinner');

void main() {
  testWidgets('plus reports one more', (tester) async {
    final changes = <int>[];
    await _pump(tester, value: 2, onChanged: changes.add);

    await tester.tap(_plus);

    expect(changes, [3]);
  });

  testWidgets('minus reports one less', (tester) async {
    final changes = <int>[];
    await _pump(tester, value: 2, onChanged: changes.add);

    await tester.tap(_minus);

    expect(changes, [1]);
  });

  testWidgets('minus is ineffective at the minimum', (tester) async {
    final changes = <int>[];
    await _pump(tester, value: 0, onChanged: changes.add);

    await tester.tap(_minus);

    expect(changes, isEmpty);
  });

  testWidgets('plus is ineffective at the maximum', (tester) async {
    final changes = <int>[];
    await _pump(tester, value: 7, max: 7, onChanged: changes.add);

    await tester.tap(_plus);

    expect(changes, isEmpty);
  });

  testWidgets('a null callback disables both buttons', (tester) async {
    await _pump(tester, value: 3, onChanged: null);

    await tester.tap(_plus);
    await tester.tap(_minus);

    expect(tester.takeException(), isNull);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('exposes label, value and step actions to assistive tech', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, value: 2, onChanged: (_) {});

    expect(
      tester.getSemantics(find.byType(QuantitySelector)),
      matchesSemantics(
        label: 'Dinner',
        value: '2',
        increasedValue: '3',
        decreasedValue: '1',
        hasIncreaseAction: true,
        hasDecreaseAction: true,
      ),
    );

    handle.dispose();
  });

  testWidgets('drops the decrease action at the minimum', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, value: 0, onChanged: (_) {});

    final node = tester.getSemantics(find.byType(QuantitySelector));
    expect(node.increasedValue, '1');
    expect(node.decreasedValue, '');

    handle.dispose();
  });

  testWidgets('renders the value', (tester) async {
    await _pump(tester, value: 5, onChanged: (_) {});
    expect(find.text('5'), findsOneWidget);
  });
}
