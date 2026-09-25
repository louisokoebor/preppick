import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:preppick/app/app.dart';
import 'package:preppick/app/routes.dart';
import 'package:preppick/models/models.dart';
import 'package:preppick/services/database_service.dart';
import 'package:preppick/services/seed_service.dart';
import 'package:preppick/services/settings_service.dart';
import 'package:preppick/theme/app_theme.dart';
import 'package:preppick/ui/shopping/add_shopping_item_sheet.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The Phase 18 device and accessibility matrix.
///
/// These are deliberately whole-app tests rather than widget tests: the
/// failures this phase is about — a footer pushed off a short screen, a label
/// that stops fitting at 1.5, a tap target that was only ever big enough on a
/// wide viewport — appear when real screens are composed, not when a widget
/// is pumped on its own at 800x600.
void main() {
  sqfliteFfiInit();

  /// The viewports PrepPick claims to support, in physical pixels.
  ///
  /// The small phone is the one that matters: at 320x568 logical there is
  /// very little height left once the header, the bottom bar and a footer
  /// button have taken theirs.
  const viewports = <String, ({Size size, double dpr})>{
    'small phone (iPhone SE, 320x568)': (size: Size(640, 1136), dpr: 2.0),
    'modern iPhone (390x844)': (size: Size(1170, 2532), dpr: 3.0),
    'Android phone (412x915)': (size: Size(1236, 2745), dpr: 3.0),
  };

  DatabaseService testDatabase() {
    final database = DatabaseService(
      factory: databaseFactoryFfi,
      databaseName: inMemoryDatabasePath,
    );
    addTearDown(database.close);
    return database;
  }

  Future<void> primeDatabase(
    WidgetTester tester,
    DatabaseService database,
  ) async {
    await tester.runAsync(() async {
      await database.database;
      await SeedService(database).seedIfEmpty(now: DateTime.utc(2026, 3, 1));
      await SettingsService(database).saveSettings(AppSettings.defaults);
    });
  }

  Future<void> settleApp(WidgetTester tester) async {
    for (var i = 0; i < 40; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> pumpAt(
    WidgetTester tester, {
    required Size size,
    required double dpr,
    double textScale = 1.0,
    String? initialRoute,
  }) async {
    final database = testDatabase();
    await primeDatabase(tester, database);

    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = dpr;
    addTearDown(tester.view.reset);

    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(
      PrepPickApp(databaseService: database, initialRoute: initialRoute),
    );
    await settleApp(tester);
  }

  /// Every route the household walks through in the core weekly loop.
  const primaryRoutes = <String, String>{
    AppRoutes.selectMealCount: 'Plan your week',
    AppRoutes.plan: 'Plan this week',
    AppRoutes.mealLibrary: 'Meal library',
    AppRoutes.shoppingList: 'Shopping list',
    AppRoutes.planHistory: 'Plan history',
  };

  group('device matrix', () {
    for (final entry in viewports.entries) {
      for (final route in primaryRoutes.entries) {
        testWidgets('${entry.key} fits ${route.key}', (tester) async {
          await pumpAt(
            tester,
            size: entry.value.size,
            dpr: entry.value.dpr,
            initialRoute: route.key,
          );

          // A RenderFlex overflow surfaces as an exception here, which is
          // exactly the failure mode a short viewport produces.
          expect(tester.takeException(), isNull);
          expect(find.text(route.value), findsWidgets);
        });
      }
    }
  });

  group('text scale', () {
    // 1.3 and 1.5 are the accessibility sizes people actually use daily;
    // beyond that the app should stay functional, which the smoke test's 2.0
    // case covers.
    for (final scale in <double>[1.3, 1.5]) {
      for (final route in primaryRoutes.entries) {
        testWidgets('${route.key} stays usable at ${scale}x on a small phone', (
          tester,
        ) async {
          await pumpAt(
            tester,
            size: viewports.values.first.size,
            dpr: viewports.values.first.dpr,
            textScale: scale,
            initialRoute: route.key,
          );

          expect(find.text(route.value), findsWidgets);
        });
      }
    }

    testWidgets('the bottom bar still reaches every tab at 1.5x', (
      tester,
    ) async {
      await pumpAt(
        tester,
        size: viewports.values.first.size,
        dpr: viewports.values.first.dpr,
        textScale: 1.5,
        initialRoute: AppRoutes.plan,
      );

      // Scaled-up labels must not push the bar's own targets off screen or
      // out of reach: the tabs are the only way between the core screens.
      for (final label in ['Plan', 'Meals', 'Shopping', 'History']) {
        expect(find.bySemanticsLabel(label), findsOneWidget);
      }

      await tester.tap(find.bySemanticsLabel('Meals'));
      await settleApp(tester);
      expect(find.text('Meal library'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('bottom sheets', () {
    testWidgets('the add-item sheet keeps its action clear of the keyboard', (
      tester,
    ) async {
      tester.view.physicalSize = viewports.values.first.size;
      tester.view.devicePixelRatio = viewports.values.first.dpr;
      addTearDown(tester.view.reset);
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => AddShoppingItemSheet.show(context),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Add to list'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // With a keyboard-sized bottom inset the sheet has to lift its action
      // clear rather than leave it under the keys.
      const keyboard = 300.0;
      tester.view.viewInsets = FakeViewPadding(
        bottom: keyboard * viewports.values.first.dpr,
      );
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final screenHeight =
          viewports.values.first.size.height / viewports.values.first.dpr;
      expect(
        tester.getRect(find.text('Add to list')).bottom,
        lessThanOrEqualTo(screenHeight - keyboard),
      );
    });
  });

  group('semantics', () {
    testWidgets('the primary action on each core screen is a named button', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpAt(
        tester,
        size: viewports.values.last.size,
        dpr: viewports.values.last.dpr,
        initialRoute: AppRoutes.plan,
      );

      expect(
        tester.getSemantics(find.bySemanticsLabel('Generate my plan').last),
        matchesSemantics(
          label: 'Generate my plan',
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
        ),
      );
      handle.dispose();
    });

    testWidgets('icon-only header controls carry labels, not just tooltips', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpAt(
        tester,
        size: viewports.values.last.size,
        dpr: viewports.values.last.dpr,
        initialRoute: AppRoutes.mealLibrary,
      );

      // A tooltip is exposed as a semantics tooltip, which is not reliably
      // announced for a control that has no visible text of its own.
      expect(find.bySemanticsLabel('Import history'), findsOneWidget);
      // Two: the header icon and the footer button. Both lead to the same
      // place, so sharing a name is correct — what matters is that the
      // icon-only one has a name at all.
      expect(find.bySemanticsLabel('Add meal'), findsNWidgets(2));
      handle.dispose();
    });
  });
}
