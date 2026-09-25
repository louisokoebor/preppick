import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:preppick/models/models.dart';
import 'package:preppick/providers/import_provider.dart';
import 'package:preppick/providers/meal_provider.dart';
import 'package:preppick/services/database_service.dart';
import 'package:preppick/services/import_service.dart';
import 'package:preppick/services/meal_service.dart';
import 'package:preppick/theme/app_theme.dart';
import 'package:preppick/ui/import/import_history_screen.dart';
import 'package:preppick/ui/import/review_import_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'fake_meal_provider.dart';

void main() {
  sqfliteFfiInit();

  late Directory tempDir;
  late DatabaseService database;
  late MealService mealService;
  late ImportProvider importProvider;
  late FakeMealProvider mealProvider;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('preppick_import_ui_test');
    database = DatabaseService(
      factory: databaseFactoryFfi,
      databaseName: '${tempDir.path}/preppick_test.db',
    );
    mealService = MealService(database);
    importProvider = ImportProvider(ImportService(mealService));
    mealProvider = FakeMealProvider();
  });

  tearDown(() async {
    importProvider.dispose();
    mealProvider.dispose();
    await database.close();
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  Future<void> pumpImportScreen(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ImportProvider>.value(value: importProvider),
          ChangeNotifierProvider<MealProvider>.value(value: mealProvider),
        ],
        child: MaterialApp(theme: AppTheme.light, home: child),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> parse(String source) async {
    importProvider.updateSourceText(source);
    final ok = await importProvider.parseSource();
    expect(ok, isTrue);
  }

  Future<void> chooseType(
    WidgetTester tester,
    ImportedMealCandidate candidate,
    String label,
  ) async {
    await tester.tap(find.byKey(Key('candidateMealType-${candidate.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  Future<List<MealVariant>> confirmAndReadMeals(WidgetTester tester) async {
    final meals = await tester.runAsync(() async {
      await importProvider.confirmImport();
      return mealService.getAllMealVariants();
    });
    await tester.pump();
    return meals!;
  }

  testWidgets('blank import cannot continue', (tester) async {
    var continued = false;
    await pumpImportScreen(
      tester,
      ImportHistoryScreen(onContinue: () => continued = true),
    );

    await tester.tap(find.text('Continue to review'));
    await tester.pumpAndSettle();

    expect(continued, isFalse);
    expect(find.byKey(const Key('importErrorText')), findsOneWidget);
  });

  testWidgets('review shows parsed candidates', (tester) async {
    await parse('- Fried Rice\nPaninis');
    await pumpImportScreen(tester, const ReviewImportScreen());

    expect(find.text('Fried Rice'), findsOneWidget);
    expect(find.text('Paninis'), findsOneWidget);
    expect(find.text('2 selected'), findsOneWidget);
  });

  testWidgets('pasted source text is preserved within import flow', (
    tester,
  ) async {
    await pumpImportScreen(tester, const ImportHistoryScreen());

    await tester.enterText(
      find.byKey(const Key('importSourceTextField')),
      'Fried Rice\nPaninis',
    );
    await tester.pump();
    await importProvider.parseSource();

    await pumpImportScreen(tester, const ReviewImportScreen());
    expect(find.text('Fried Rice'), findsOneWidget);

    await pumpImportScreen(tester, const ImportHistoryScreen());
    final textField = tester.widget<TextField>(
      find.byKey(const Key('importSourceTextField')),
    );
    expect(textField.controller!.text, 'Fried Rice\nPaninis');
  });

  testWidgets('exclude removes candidate from confirm set', (tester) async {
    await parse('Fried Rice\nPaninis');
    await pumpImportScreen(tester, const ReviewImportScreen());

    final second = importProvider.candidates.last;
    await tester.tap(find.byKey(Key('includeCandidate-${second.id}')));
    await tester.pumpAndSettle();

    expect(importProvider.candidates.last.isIncluded, isFalse);
    expect(find.text('1 selected'), findsOneWidget);
  });

  testWidgets('rename persists into imported meal', (tester) async {
    await parse('Old Dinner');
    await pumpImportScreen(tester, const ReviewImportScreen());

    final candidate = importProvider.candidates.single;
    await tester.enterText(
      find.byKey(Key('candidateName-${candidate.id}')),
      'New Dinner',
    );
    await tester.pumpAndSettle();
    await chooseType(tester, candidate, 'Dinner');

    expect(importProvider.canConfirm, isTrue);
    final meals = await confirmAndReadMeals(tester);
    expect(meals.single.name, 'New Dinner');
  });

  testWidgets('assigning type persists', (tester) async {
    await parse('Breakfast Muffins');
    await pumpImportScreen(tester, const ReviewImportScreen());

    final candidate = importProvider.candidates.single;
    await chooseType(tester, candidate, 'Breakfast');

    expect(importProvider.canConfirm, isTrue);
    final meals = await confirmAndReadMeals(tester);
    final family = await tester.runAsync(
      () => mealService.getMealFamily(meals.single.mealFamilyId),
    );
    expect(family!.mealType, MealType.breakfast);
  });

  testWidgets('confirm creates library records', (tester) async {
    await parse('Fried Rice\nPaninis');
    await pumpImportScreen(tester, const ReviewImportScreen());

    for (final candidate in importProvider.candidates) {
      await chooseType(tester, candidate, 'Lunch');
    }

    expect(importProvider.canConfirm, isTrue);
    final meals = await confirmAndReadMeals(tester);
    expect(
      meals.map((meal) => meal.name),
      containsAll(['Fried Rice', 'Paninis']),
    );
  });

  testWidgets('confirming once creates expected count', (tester) async {
    await parse('Fried Rice\nfried rice\nJollof Rice');
    await pumpImportScreen(tester, const ReviewImportScreen());

    for (final candidate in importProvider.candidates) {
      await chooseType(tester, candidate, 'Dinner');
    }

    expect(importProvider.canConfirm, isTrue);
    final meals = await confirmAndReadMeals(tester);

    expect(meals, hasLength(2));
    expect(importProvider.createdCount, 2);
  });
}
