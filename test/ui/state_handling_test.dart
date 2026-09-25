import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:preppick/models/models.dart';
import 'package:preppick/providers/import_provider.dart';
import 'package:preppick/providers/meal_provider.dart';
import 'package:preppick/providers/planner_provider.dart';
import 'package:preppick/providers/settings_provider.dart';
import 'package:preppick/providers/shopping_provider.dart';
import 'package:preppick/services/database_service.dart';
import 'package:preppick/services/import_service.dart';
import 'package:preppick/services/meal_service.dart';
import 'package:preppick/services/settings_service.dart';
import 'package:preppick/theme/app_theme.dart';
import 'package:preppick/ui/history/plan_history_screen.dart';
import 'package:preppick/ui/import/import_history_screen.dart';
import 'package:preppick/ui/import/review_import_screen.dart';
import 'package:preppick/ui/meals/meal_library_screen.dart';
import 'package:preppick/ui/planner/generated_plan_screen.dart';
import 'package:preppick/ui/planner/plan_this_week_screen.dart';
import 'package:preppick/ui/planner/select_meal_count_screen.dart';
import 'package:preppick/ui/planner/swap_meal_sheet.dart';
import 'package:preppick/ui/shopping/shopping_list_screen.dart';
import 'package:preppick/utils/error_messages.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'fake_meal_provider.dart';
import 'fake_planner_provider.dart';
import 'fake_shopping_provider.dart';

/// Phase 17: the states a screen shows when things are loading, empty or
/// broken.
///
/// Every failure here is forced through a fake that throws, not through a
/// corrupted database, because the point under test is what the *screen* does
/// with a failure — that it says something a household can act on, offers the
/// action that fixes it where there is one, and never leaves a spinner
/// running after the thing it was waiting for has already failed.
///
/// The recurring assertion is [_expectNoRawException]: services throw text
/// written for a stack trace, and a screen that renders `error.toString()`
/// puts a SQLite statement in front of someone trying to cook dinner.

/// A failure shaped like the ones sqflite actually raises, so a screen that
/// leaks the exception object fails loudly and recognisably.
class _FakeDatabaseException implements Exception {
  const _FakeDatabaseException();

  @override
  String toString() =>
      'DatabaseException(no such table: meal_variants (code 1)) sql '
      "'SELECT * FROM meal_variants'";
}

/// Asserts no part of a raw exception reached the screen.
void _expectNoRawException() {
  for (final fragment in const [
    'DatabaseException',
    'no such table',
    'SELECT',
    'Exception:',
  ]) {
    expect(
      find.textContaining(fragment, findRichText: true),
      findsNothing,
      reason: 'raw exception text "$fragment" must not reach the UI',
    );
  }
}

final DatabaseService _unusedDatabase = DatabaseService(
  factory: databaseFactoryFfi,
  databaseName: ':unused:',
);

/// A settings store whose reads and writes can be made to fail.
class _FailingSettingsService implements SettingsService {
  _FailingSettingsService({this.failGet = false, this.failSave = false});

  bool failGet;
  bool failSave;
  AppSettings _stored = AppSettings.defaults;

  @override
  Future<AppSettings> getSettings() async {
    if (failGet) throw const _FakeDatabaseException();
    return _stored;
  }

  @override
  Future<bool> hasSavedMealCounts() async {
    if (failGet) throw const _FakeDatabaseException();
    return true;
  }

  @override
  Future<AppSettings> saveSettings(AppSettings settings) async {
    if (failSave) throw const _FakeDatabaseException();
    return _stored = settings.copyWith();
  }

  @override
  Future<void> clearSettings() async {}
}

/// A settings store that never completes, for asserting the loading state.
class _HangingSettingsService implements SettingsService {
  final _never = Completer<AppSettings>();

  @override
  Future<AppSettings> getSettings() => _never.future;

  @override
  Future<bool> hasSavedMealCounts() async => true;

  @override
  Future<AppSettings> saveSettings(AppSettings settings) async => settings;

  @override
  Future<void> clearSettings() async {}
}

/// An import whose confirmation write fails, standing in for a full disk.
class _FailingImportService extends ImportService {
  _FailingImportService() : super(MealService(_unusedDatabase));

  @override
  Future<ImportConfirmationResult> confirmCandidates(
    List<ImportedMealCandidate> candidates,
  ) async => throw const _FakeDatabaseException();
}

ImportedMealCandidate _candidate(String name, {MealType? mealType}) =>
    ImportedMealCandidate(
      id: 'candidate-$name',
      name: name,
      originalText: name,
      mealType: mealType,
    );

void main() {
  /// A few frames rather than pumpAndSettle: a loading state shows a spinner,
  /// whose animation never ends.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> pump(WidgetTester tester, Widget home, List<dynamic> providers) {
    tester.view.physicalSize = const Size(1080, 4200);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    return tester.pumpWidget(
      MultiProvider(
        providers: providers.cast(),
        child: MaterialApp(theme: AppTheme.light, home: home),
      ),
    );
  }

  group('Select Meal Count', () {
    testWidgets('a failed read explains itself and offers a retry', (
      tester,
    ) async {
      final service = _FailingSettingsService(failGet: true);
      final provider = SettingsProvider(service);
      addTearDown(provider.dispose);

      await pump(tester, const SelectMealCountScreen(), [
        ChangeNotifierProvider<SettingsProvider>.value(value: provider),
      ]);
      await settle(tester);

      expect(find.byKey(const Key('selectMealCountError')), findsOneWidget);
      expect(find.textContaining('could not be loaded'), findsOneWidget);
      _expectNoRawException();

      // The screen is usable, not stuck: the steppers are on screen and the
      // retry reaches the service again.
      expect(find.byType(CircularProgressIndicator), findsNothing);
      service.failGet = false;
      await tester.tap(find.text('Try again'));
      await settle(tester);
      expect(find.byKey(const Key('selectMealCountError')), findsNothing);
    });

    testWidgets('a failed save warns without claiming the counts are wrong', (
      tester,
    ) async {
      final provider = SettingsProvider(
        _FailingSettingsService(failSave: true),
      );
      addTearDown(provider.dispose);

      await pump(tester, const SelectMealCountScreen(), [
        ChangeNotifierProvider<SettingsProvider>.value(value: provider),
      ]);
      await settle(tester);
      await tester.tap(find.text('Continue to plan'));
      await settle(tester);

      expect(
        find.textContaining('Could not save your meal counts'),
        findsOneWidget,
      );
      // A save failure leaves the numbers on screen correct, so the load
      // notice must stay away.
      expect(find.byKey(const Key('selectMealCountError')), findsNothing);
      _expectNoRawException();
    });

    testWidgets('a read that never returns keeps the spinner, not the form', (
      tester,
    ) async {
      final provider = SettingsProvider(_HangingSettingsService());
      addTearDown(provider.dispose);

      await pump(tester, const SelectMealCountScreen(), [
        ChangeNotifierProvider<SettingsProvider>.value(value: provider),
      ]);
      await settle(tester);

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });

  group('Plan This Week', () {
    late FakePlannerProvider planner;
    late SettingsProvider settings;

    Future<void> pumpScreen(WidgetTester tester) async {
      settings = SettingsProvider(_FailingSettingsService());
      addTearDown(settings.dispose);
      await settings.load();
      await pump(
        tester,
        PlanThisWeekScreen(
          // Supplied so the screen does not navigate by route name, which
          // this harness has no routes for.
          onPlanGenerated: () {},
          onOpenMealLibrary: () {},
        ),
        [
          ChangeNotifierProvider<SettingsProvider>.value(value: settings),
          ChangeNotifierProvider<PlannerProvider>.value(value: planner),
        ],
      );
      await settle(tester);
    }

    setUp(() => planner = FakePlannerProvider());
    tearDown(() => planner.dispose());

    testWidgets('a failed generation shows plain copy and a retry', (
      tester,
    ) async {
      planner.failure = const _FakeDatabaseException();
      await pumpScreen(tester);

      expect(find.byKey(const Key('planThisWeekError')), findsOneWidget);
      expect(
        find.textContaining('Something went wrong while planning your week'),
        findsOneWidget,
      );
      _expectNoRawException();

      // Retry actually re-runs generation rather than only clearing the copy.
      await tester.tap(find.text('Try again'));
      await settle(tester);
      expect(planner.countOf('generate'), 1);
    });

    testWidgets('not enough meals is explained as a library problem', (
      tester,
    ) async {
      planner
        ..message =
            'Your meal library is empty. Add a few meals your household '
            'already likes, then plan your week.'
        ..libraryEmpty = true;
      await pumpScreen(tester);

      expect(find.textContaining('meal library is empty'), findsOneWidget);
      expect(find.text('Go to Meal Library'), findsOneWidget);
    });
  });

  group('Generated Plan', () {
    late FakePlannerProvider planner;
    late SettingsProvider settings;

    setUp(() => planner = FakePlannerProvider());
    tearDown(() => planner.dispose());

    Future<void> pumpScreen(WidgetTester tester) async {
      settings = SettingsProvider(_FailingSettingsService());
      addTearDown(settings.dispose);
      await pump(tester, const GeneratedPlanScreen(), [
        ChangeNotifierProvider<SettingsProvider>.value(value: settings),
        ChangeNotifierProvider<PlannerProvider>.value(value: planner),
      ]);
      await settle(tester);
    }

    testWidgets(
      'a failed confirm leaves a notice behind, not just a snackbar',
      (tester) async {
        planner
          ..plannedItems = [fakeItem(id: 'i1', mealType: MealType.dinner)]
          ..meals = {'meal-i1': fakeMeal(id: 'meal-i1', name: 'Fried Rice')}
          ..nextResult = false;
        await pumpScreen(tester);

        await tester.tap(find.text('Confirm plan'));
        await settle(tester);
        expect(
          find.textContaining('Could not confirm your plan'),
          findsOneWidget,
        );

        // The snackbar goes; the notice is what remains once it does.
        planner.failure = const _FakeDatabaseException();
        planner.notifyListeners();
        await settle(tester);
        expect(find.byKey(const Key('generatedPlanError')), findsOneWidget);
        _expectNoRawException();
      },
    );

    testWidgets('an empty plan disables Confirm and says what to do', (
      tester,
    ) async {
      await pumpScreen(tester);

      expect(find.textContaining('This week has no meals yet'), findsOneWidget);
      final button = tester.widget<InkWell>(
        find
            .ancestor(
              of: find.text('Confirm plan'),
              matching: find.byType(InkWell),
            )
            .first,
      );
      expect(button.onTap, isNull);
    });
  });

  group('Swap Meal sheet', () {
    late FakePlannerProvider planner;

    setUp(() => planner = FakePlannerProvider());
    tearDown(() => planner.dispose());

    Future<void> openSheet(WidgetTester tester) async {
      final item = fakeItem(id: 'i1', mealType: MealType.dinner);
      await pump(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () =>
                    SwapMealSheet.show(context, item: item, totalOfType: 1),
                child: const Text('open'),
              ),
            ),
          ),
        ),
        [ChangeNotifierProvider<PlannerProvider>.value(value: planner)],
      );
      await tester.tap(find.text('open'));
      await settle(tester);
    }

    testWidgets(
      'a failed candidate load is not passed off as an empty library',
      (tester) async {
        // The real provider returns an empty list and records the reason, which
        // is exactly the case the sheet used to misread as "no meals exist".
        planner
          ..candidates = const []
          ..failure = const _FakeDatabaseException();
        await openSheet(tester);

        expect(find.byKey(const Key('swapSheetError')), findsOneWidget);
        expect(
          find.textContaining('Your library has no other'),
          findsNothing,
          reason: 'a read failure must not be reported as an empty library',
        );
        expect(find.byType(CircularProgressIndicator), findsNothing);
        _expectNoRawException();

        // Retry asks again rather than only redrawing.
        await tester.tap(find.text('Try again'));
        await settle(tester);
        expect(planner.countOf('candidates:i1'), 2);
      },
    );

    testWidgets('genuinely having no alternatives reads as a library gap', (
      tester,
    ) async {
      planner.candidates = const [];
      await openSheet(tester);

      expect(find.textContaining('no other dinner meal'), findsOneWidget);
      expect(find.byKey(const Key('swapSheetError')), findsNothing);
    });
  });

  group('Shopping List', () {
    late FakeShoppingProvider shopping;
    late FakePlannerProvider planner;

    setUp(() {
      shopping = FakeShoppingProvider();
      planner = FakePlannerProvider()..confirmed = true;
    });
    tearDown(() {
      shopping.dispose();
      planner.dispose();
    });

    Future<void> pumpScreen(WidgetTester tester) async {
      await pump(tester, const ShoppingListScreen(planId: 'plan-1'), [
        ChangeNotifierProvider<ShoppingProvider>.value(value: shopping),
        ChangeNotifierProvider<PlannerProvider>.value(value: planner),
      ]);
      await settle(tester);
    }

    testWidgets('a failed build offers a retry instead of a spinner', (
      tester,
    ) async {
      shopping.failure = const _FakeDatabaseException();
      await pumpScreen(tester);

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(
        find.textContaining('Something went wrong building your shopping list'),
        findsOneWidget,
      );
      _expectNoRawException();

      shopping.failure = null;
      await tester.tap(find.text('Try again'));
      await settle(tester);
      expect(shopping.countOf('open:plan-1'), greaterThan(1));
    });

    testWidgets('a plan whose meals have no ingredients is not an error', (
      tester,
    ) async {
      await pumpScreen(tester);

      expect(
        find.textContaining('no ingredients recorded yet'),
        findsOneWidget,
      );
      expect(find.textContaining('went wrong'), findsNothing);
    });

    testWidgets(
      'a tick that did not save is still visible after the snackbar',
      (tester) async {
        shopping
          ..lines = [fakeLine(id: 'line-1', name: 'Chicken')]
          ..nextResult = false;
        await pumpScreen(tester);

        await tester.tap(find.text('Chicken'));
        await settle(tester);
        expect(find.textContaining('Could not save Chicken'), findsOneWidget);

        shopping.failure = const _FakeDatabaseException();
        shopping.notifyListeners();
        await settle(tester);
        expect(find.byKey(const Key('shoppingWriteError')), findsOneWidget);
        _expectNoRawException();
      },
    );
  });

  group('Meal Library', () {
    late FakeMealProvider meals;

    setUp(() => meals = FakeMealProvider());
    tearDown(() => meals.dispose());

    Future<void> pumpScreen(WidgetTester tester) async {
      await pump(tester, const MealLibraryScreen(), [
        ChangeNotifierProvider<MealProvider>.value(value: meals),
      ]);
      await settle(tester);
    }

    testWidgets(
      'a failed load is an error with a retry, not an empty library',
      (tester) async {
        meals.failure = const _FakeDatabaseException();
        await pumpScreen(tester);

        expect(find.byKey(const Key('mealLibraryError')), findsOneWidget);
        expect(find.text('No meals yet'), findsNothing);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        _expectNoRawException();

        await tester.tap(find.text('Try again'));
        await settle(tester);
        expect(meals.calls.contains('refresh'), isTrue);
      },
    );

    testWidgets('an empty library asks for a first meal', (tester) async {
      await pumpScreen(tester);

      expect(find.text('No meals yet'), findsOneWidget);
      expect(find.text('Add your first meal'), findsOneWidget);
    });
  });

  group('Plan History', () {
    late FakePlannerProvider planner;

    setUp(() => planner = FakePlannerProvider());
    tearDown(() => planner.dispose());

    Future<void> pumpScreen(WidgetTester tester) async {
      await pump(tester, const PlanHistoryScreen(), [
        ChangeNotifierProvider<PlannerProvider>.value(value: planner),
      ]);
      await settle(tester);
    }

    testWidgets('a failed load explains itself and retries', (tester) async {
      planner.historyFailure = const _FakeDatabaseException();
      await pumpScreen(tester);

      expect(find.byKey(const Key('planHistoryError')), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      _expectNoRawException();

      await tester.tap(find.text('Try again'));
      await settle(tester);
      expect(planner.countOf('history'), greaterThan(0));
    });

    testWidgets('no confirmed weeks yet is an empty state, not a failure', (
      tester,
    ) async {
      await pumpScreen(tester);

      expect(
        find.textContaining('Confirmed weeks will appear here'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('planHistoryError')), findsNothing);
    });
  });

  group('Import', () {
    testWidgets('a blank paste is a validation message, verbatim', (
      tester,
    ) async {
      final provider = ImportProvider(
        ImportService(MealService(_unusedDatabase)),
      );
      addTearDown(provider.dispose);

      await pump(tester, const ImportHistoryScreen(), [
        ChangeNotifierProvider<ImportProvider>.value(value: provider),
      ]);
      await tester.tap(find.text('Continue to review'));
      await settle(tester);

      expect(
        find.text('Paste at least one meal before continuing.'),
        findsOneWidget,
      );
    });

    testWidgets('a failed write shows generic copy, never the SQL', (
      tester,
    ) async {
      final provider = ImportProvider(_FailingImportService());
      addTearDown(provider.dispose);
      provider.updateSourceText('Fried Rice');
      await provider.parseSource();
      for (final candidate in provider.candidates) {
        provider.assignMealType(candidate.id, MealType.dinner);
      }

      final meals = FakeMealProvider();
      addTearDown(meals.dispose);
      await pump(tester, const ReviewImportScreen(), [
        ChangeNotifierProvider<ImportProvider>.value(value: provider),
        ChangeNotifierProvider<MealProvider>.value(value: meals),
      ]);
      await settle(tester);

      await tester.tap(find.text('Confirm import'));
      await settle(tester);

      expect(find.byKey(const Key('reviewImportErrorText')), findsOneWidget);
      expect(
        find.text('Your meals could not be saved. Please try again.'),
        findsOneWidget,
      );
      _expectNoRawException();
    });

    testWidgets('no candidates is an empty state with a way back', (
      tester,
    ) async {
      final provider = ImportProvider(
        ImportService(MealService(_unusedDatabase)),
      );
      addTearDown(provider.dispose);
      final meals = FakeMealProvider();
      addTearDown(meals.dispose);

      await pump(tester, const ReviewImportScreen(), [
        ChangeNotifierProvider<ImportProvider>.value(value: provider),
        ChangeNotifierProvider<MealProvider>.value(value: meals),
      ]);
      await settle(tester);

      expect(find.byType(CircularProgressIndicator), findsNothing);
      _expectNoRawException();
    });
  });

  group('PrepErrorMessages', () {
    test('passes through copy written for the household', () {
      expect(
        PrepErrorMessages.forError(const BlankImportException()),
        'Paste at least one meal before continuing.',
      );
    });

    test('replaces anything internal with the fallback', () {
      expect(
        PrepErrorMessages.forError(const _FakeDatabaseException()),
        PrepErrorMessages.genericMessage,
      );
      expect(
        PrepErrorMessages.forError(
          StateError('boom'),
          fallback: 'Could not load your meals.',
        ),
        'Could not load your meals.',
      );
    });

    test('null stays null so callers can branch on the message', () {
      expect(PrepErrorMessages.forError(null), isNull);
    });
  });

  test('_candidate helper keeps the import fixtures honest', () {
    expect(
      _candidate('Fried Rice', mealType: MealType.dinner).canConfirm,
      isTrue,
    );
    expect(_candidate('Fried Rice').canConfirm, isFalse);
  });
}
