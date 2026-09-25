import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:preppick/theme/app_theme.dart';
import 'package:preppick/theme/theme_preview_screen.dart';

Widget _preview() =>
    MaterialApp(theme: AppTheme.light, home: const ThemePreviewScreen());

void main() {
  testWidgets('token gallery renders every scale without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_preview());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Display Large 32/38'), findsOneWidget);

    // The gallery is a lazy ListView, so the later sections only build once
    // scrolled into view.
    await tester.scrollUntilVisible(find.text('action/primary'), 200);
    expect(find.text('action/primary'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('token gallery stays laid out at 2x text scale', (tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(_preview());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
