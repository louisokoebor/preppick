import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:preppick/theme/app_theme.dart';
import 'package:preppick/widgets/prep_button.dart';

Future<void> _pump(
  WidgetTester tester, {
  VoidCallback? onPressed,
  bool isBusy = false,
  PrepButtonVariant variant = PrepButtonVariant.primary,
}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: PrepButton(
          label: 'Continue',
          onPressed: onPressed,
          isBusy: isBusy,
          variant: variant,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('calls onPressed when tapped', (tester) async {
    var taps = 0;
    await _pump(tester, onPressed: () => taps++);

    await tester.tap(find.text('Continue'));

    expect(taps, 1);
  });

  testWidgets('a null callback disables the button', (tester) async {
    await _pump(tester, onPressed: null);

    final button = tester.widget<TextButton>(find.byType(TextButton));

    expect(button.onPressed, isNull);
  });

  testWidgets('a busy button shows a spinner and cannot be tapped', (
    tester,
  ) async {
    var taps = 0;
    await _pump(tester, onPressed: () => taps++, isBusy: true);

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Continue'), findsNothing);

    await tester.tap(find.byType(TextButton), warnIfMissed: false);
    await tester.pump();

    // The point of the busy state: a slow save cannot be fired twice.
    expect(taps, 0);
  });

  testWidgets('keeps its label available to screen readers while busy', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, onPressed: () {}, isBusy: true);

    // The spinner has replaced the label on screen, so the semantic label
    // carries the state instead of the button going quiet.
    expect(
      tester.getSemantics(find.byType(PrepButton)).label,
      'Continue, in progress',
    );

    handle.dispose();
  });

  testWidgets('uses the design system height and radius', (tester) async {
    await _pump(tester, onPressed: () {});

    final size = tester.getSize(find.byType(TextButton));
    expect(size.height, 48);

    final shape =
        tester
                .widget<TextButton>(find.byType(TextButton))
                .style!
                .shape!
                .resolve(const <WidgetState>{})
            as RoundedRectangleBorder;
    expect(shape.borderRadius, BorderRadius.circular(16));
  });

  testWidgets('renders every variant without error', (tester) async {
    for (final variant in PrepButtonVariant.values) {
      await _pump(tester, onPressed: () {}, variant: variant);
      expect(tester.takeException(), isNull);
      expect(find.text('Continue'), findsOneWidget);
    }
  });

  testWidgets('wraps a long label instead of overflowing', (tester) async {
    tester.view.physicalSize = const Size(600, 1200);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: PrepButton(
            label: 'Continue to this week’s generated plan',
            onPressed: null,
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });
}
