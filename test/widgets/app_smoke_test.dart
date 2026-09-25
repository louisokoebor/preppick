import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:preppick/app/app.dart';
import 'package:preppick/app/routes.dart';
import 'package:preppick/models/models.dart';
import 'package:preppick/services/database_service.dart';
import 'package:preppick/services/seed_service.dart';
import 'package:preppick/services/settings_service.dart';
import 'package:preppick/widgets/meal_card_library.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  DatabaseService testDatabase() {
    final database = DatabaseService(
      factory: databaseFactoryFfi,
      databaseName: inMemoryDatabasePath,
    );
    addTearDown(() async {
      await database.close();
    });
    return database;
  }

  Future<void> primeDatabase(
    WidgetTester tester,
    DatabaseService database, {
    bool savedSettings = false,
    bool seedMeals = false,
  }) async {
    await tester.runAsync(() async {
      await database.database;
      if (seedMeals) {
        await SeedService(database).seedIfEmpty(now: DateTime.utc(2026, 3, 1));
      }
      if (savedSettings) {
        await SettingsService(database).saveSettings(AppSettings.defaults);
      }
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

  Future<void> pumpApp(
    WidgetTester tester,
    DatabaseService database, {
    String? initialRoute,
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      PrepPickApp(databaseService: database, initialRoute: initialRoute),
    );
    await settleApp(tester);
  }

  testWidgets('first run opens Select Meal Count', (tester) async {
    final database = testDatabase();

    await pumpApp(tester, database);

    expect(find.text('Plan your week'), findsOneWidget);
    expect(find.text('Continue to plan'), findsOneWidget);
    expect(find.text('Getting your week ready.'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('returning user restores Plan as the normal entry screen', (
    tester,
  ) async {
    final database = testDatabase();
    await primeDatabase(tester, database, savedSettings: true);

    await pumpApp(tester, database);

    expect(find.text('Plan this week'), findsWidgets);
    expect(
      find.text('Select the week to build a plan from meals you already love.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('bottom nav changes destination', (tester) async {
    final database = testDatabase();
    await primeDatabase(tester, database, savedSettings: true, seedMeals: true);
    await pumpApp(tester, database);

    await tester.tap(find.bySemanticsLabel('Meals'));
    await settleApp(tester);

    expect(find.text('Meal library'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('History'));
    await settleApp(tester);

    expect(find.text('Plan history'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'the Shopping tab shows the list for a week confirmed behind it',
    (tester) async {
      // The shell builds every tab at startup, so Shopping is alive — and
      // empty — while the week is still being planned. It has to catch up when
      // the shopper actually opens it.
      final database = testDatabase();
      await primeDatabase(
        tester,
        database,
        savedSettings: true,
        seedMeals: true,
      );
      await pumpApp(tester, database);

      await tester.tap(find.text('Generate my plan'));
      await settleApp(tester);
      await tester.tap(find.text('Confirm plan').last);
      await settleApp(tester);

      await tester.tap(find.bySemanticsLabel('Shopping'));
      await settleApp(tester);

      expect(find.text('Shopping list'), findsWidgets);
      expect(
        find.text('Nothing in this aisle. Choose All to see the whole list.'),
        findsNothing,
      );
      expect(find.text('Add an item'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('deep route to valid meal detail works', (tester) async {
    final database = testDatabase();
    await primeDatabase(tester, database, savedSettings: true, seedMeals: true);

    await pumpApp(
      tester,
      database,
      initialRoute: AppRoutes.mealDetailPath(SeedService.variantId('Paninis')),
    );

    expect(find.text('Paninis'), findsWidgets);
    expect(find.text('Ingredients'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('invalid meal ID produces a controlled error state', (
    tester,
  ) async {
    final database = testDatabase();
    await primeDatabase(tester, database, savedSettings: true, seedMeals: true);

    await pumpApp(
      tester,
      database,
      initialRoute: AppRoutes.mealDetailPath('missing-meal'),
    );

    expect(find.text('Meal not found'), findsOneWidget);
    expect(find.text('This meal is no longer available.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('back navigation from detail and import returns to library', (
    tester,
  ) async {
    final database = testDatabase();
    await primeDatabase(tester, database, savedSettings: true, seedMeals: true);
    await pumpApp(tester, database, initialRoute: AppRoutes.mealLibrary);

    await tester.enterText(find.byType(TextField), 'Paninis');
    await settleApp(tester);
    await tester.tap(find.byType(MealCardLibrary).first);
    await settleApp(tester);
    expect(find.text('Ingredients'), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await settleApp(tester);
    expect(find.text('Meal library'), findsOneWidget);

    await tester.tap(find.byTooltip('Import history'));
    await settleApp(tester);
    expect(find.text('Import history'), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await settleApp(tester);
    expect(find.text('Meal library'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('startup shell survives a large text scale', (tester) async {
    final database = testDatabase();

    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(PrepPickApp(databaseService: database));
    await settleApp(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Plan your week'), findsOneWidget);
  });
}
