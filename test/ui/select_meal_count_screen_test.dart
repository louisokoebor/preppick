import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:preppick/models/models.dart';
import 'package:preppick/providers/settings_provider.dart';
import 'package:preppick/services/settings_service.dart';
import 'package:preppick/theme/app_theme.dart';
import 'package:preppick/ui/planner/select_meal_count_screen.dart';

/// An in-memory stand-in for [SettingsService].
///
/// These tests are about the screen, not about SQLite — which
/// `settings_service_test.dart` covers directly. A real database is also
/// actively unhelpful here: file I/O completes on the real event loop, which
/// the widget tester's fake clock never advances, so the screen would sit on
/// its loading spinner forever. This fake resolves in a microtask, so a plain
/// `pump` is enough.
class _FakeSettingsService implements SettingsService {
  AppSettings? _stored;

  /// What a restart would read back.
  AppSettings? get stored => _stored;

  /// Puts values in storage as a previous session would have left them.
  void seed(AppSettings settings) => _stored = settings;

  @override
  Future<AppSettings> getSettings() async => _stored ?? AppSettings.defaults;

  @override
  Future<bool> hasSavedMealCounts() async => _stored != null;

  @override
  Future<AppSettings> saveSettings(AppSettings settings) async =>
      _stored = settings.copyWith();

  @override
  Future<void> clearSettings() async => _stored = null;
}

// Each stepper is labelled with its card's heading, so the tooltip addresses
// one category unambiguously.
Finder _plus(String heading) => find.byTooltip('Increase $heading');
Finder _minus(String heading) => find.byTooltip('Decrease $heading');

void main() {
  late _FakeSettingsService service;
  late SettingsProvider provider;

  // Set when a test has chosen its own viewport, so `pumpScreen` does not
  // overwrite it with the default tall one.
  var viewConfigured = false;

  setUp(() {
    service = _FakeSettingsService();
    provider = SettingsProvider(service);
    viewConfigured = false;
  });

  tearDown(() => provider.dispose());

  // The screen shows a CircularProgressIndicator while loading and while
  // saving, and that animation never stops, so `pumpAndSettle` would spin
  // forever. Pumping a few frames instead lets the post-frame load and the
  // fake's futures complete without waiting on an endless animation.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// Gives the test a viewport tall enough to show the whole page at once.
  ///
  /// The default 800x600 surface cuts the list off below the dinner card, and
  /// a ListView does not build children that are off-screen, so anything past
  /// the fold is simply not in the tree to find.
  void useView(WidgetTester tester, Size size, double pixelRatio) {
    viewConfigured = true;
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = pixelRatio;
    addTearDown(tester.view.reset);
  }

  /// The default surface for these tests.
  ///
  /// The three cards do not fit the 800x600 default, and a ListView neither
  /// builds nor accepts taps on children past the fold, so every test gets a
  /// viewport tall enough to show the whole page at once.
  void useTallView(WidgetTester tester) {
    if (viewConfigured) return;
    useView(tester, const Size(800, 2400), 2.0);
  }

  Future<void> pumpScreen(
    WidgetTester tester, {
    VoidCallback? onContinue,
  }) async {
    useTallView(tester);
    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsProvider>.value(
        value: provider,
        child: MaterialApp(
          theme: AppTheme.light,
          home: SelectMealCountScreen(onContinue: onContinue),
        ),
      ),
    );
    await settle(tester);
  }

  testWidgets('renders a card per meal type', (tester) async {
    await pumpScreen(tester);

    expect(find.text('Breakfast Options'), findsOneWidget);
    expect(find.text('Lunch Options'), findsOneWidget);
    expect(find.text('Dinner Options'), findsOneWidget);
    expect(find.text('How many dinners?'), findsOneWidget);
    expect(find.text('Continue to plan'), findsOneWidget);
  });

  testWidgets('reflects provider values after load', (tester) async {
    service.seed(
      const AppSettings(breakfastCount: 0, lunchCount: 3, dinnerCount: 5),
    );

    await pumpScreen(tester);

    expect(find.text('0'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
  });

  testWidgets('plus increments the matching category only', (tester) async {
    service.seed(
      const AppSettings(breakfastCount: 1, lunchCount: 1, dinnerCount: 2),
    );
    await pumpScreen(tester);

    await tester.tap(_plus('Dinner Options'));
    await tester.pump();

    expect(provider.settings.dinnerCount, 3);
    expect(provider.settings.lunchCount, 1);
    expect(provider.settings.breakfastCount, 1);
  });

  testWidgets('minus decrements', (tester) async {
    service.seed(const AppSettings(dinnerCount: 2));
    await pumpScreen(tester);

    await tester.tap(_minus('Dinner Options'));
    await tester.pump();

    expect(provider.settings.dinnerCount, 1);
  });

  testWidgets('minus is ineffective at zero', (tester) async {
    service.seed(const AppSettings(breakfastCount: 0));
    await pumpScreen(tester);

    await tester.tap(_minus('Breakfast Options'));
    await tester.pump();

    expect(provider.settings.breakfastCount, 0);
  });

  testWidgets('plus stops at the documented maximum', (tester) async {
    service.seed(const AppSettings(lunchCount: AppSettings.maxCount));
    await pumpScreen(tester);

    await tester.tap(_plus('Lunch Options'));
    await tester.pump();

    expect(provider.settings.lunchCount, AppSettings.maxCount);
  });

  testWidgets('Continue saves before calling back', (tester) async {
    var continued = false;
    await pumpScreen(tester, onContinue: () => continued = true);

    await tester.tap(_plus('Dinner Options'));
    await tester.pump();
    await tester.tap(find.text('Continue to plan'));
    await settle(tester);

    expect(continued, isTrue);
    // Persisted, not just held in the provider.
    expect(service.stored?.dinnerCount, 3);
    expect(provider.hasUnsavedChanges, isFalse);
  });

  testWidgets('values restore on a fresh screen after a save', (tester) async {
    await pumpScreen(tester);
    await tester.tap(_plus('Lunch Options'));
    await tester.pump();
    await tester.tap(find.text('Continue to plan'));
    await settle(tester);

    // A new provider over the same storage, as a restart would produce.
    // The empty tree in between forces a fresh State, so the screen loads
    // again rather than reusing the element already on screen.
    provider.dispose();
    provider = SettingsProvider(service);
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpScreen(tester);

    expect(provider.settings.lunchCount, 2);
    expect(find.text('2'), findsWidgets);
  });

  testWidgets('explains that a plan needs at least one meal when all are zero', (
    tester,
  ) async {
    service.seed(
      const AppSettings(breakfastCount: 0, lunchCount: 0, dinnerCount: 0),
    );
    await pumpScreen(tester);

    expect(
      find.text('Add at least one meal before generating a plan.'),
      findsOneWidget,
    );
    // Zero is still a saveable answer; the screen explains rather than blocks.
    final button = tester.widget<TextButton>(
      find.ancestor(
        of: find.text('Continue to plan'),
        matching: find.byType(TextButton),
      ),
    );
    expect(button.onPressed, isNotNull);
  });

  testWidgets('hides the notice as soon as a meal is added', (tester) async {
    service.seed(
      const AppSettings(breakfastCount: 0, lunchCount: 0, dinnerCount: 0),
    );
    await pumpScreen(tester);

    await tester.tap(_plus('Lunch Options'));
    await tester.pump();

    expect(
      find.text('Add at least one meal before generating a plan.'),
      findsNothing,
    );
  });

  testWidgets('all zeros save and reload without crashing', (tester) async {
    await pumpScreen(tester);
    provider.updateMealCounts(breakfast: 0, lunch: 0, dinner: 0);
    await tester.pump();

    await tester.tap(find.text('Continue to plan'));
    await settle(tester);

    expect(tester.takeException(), isNull);
    expect(service.stored?.isEmpty, isTrue);
  });

  testWidgets('lays out without overflow at a large text scale', (
    tester,
  ) async {
    useView(tester, const Size(1080, 1920), 3.0);
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await pumpScreen(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Continue to plan'), findsOneWidget);
  });
}
