import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:preppick/app/app.dart';

void main() {
  testWidgets('PrepPickApp starts without provider lookup errors',
      (tester) async {
    await tester.pumpWidget(const PrepPickApp());
    await tester.pumpAndSettle();

    expect(find.text('PrepPick'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('startup shell survives a large text scale', (tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const PrepPickApp());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
