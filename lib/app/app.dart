import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/meal_provider.dart';
import '../providers/import_provider.dart';
import '../providers/planner_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/shopping_history_provider.dart';
import '../providers/shopping_provider.dart';
import '../services/database_service.dart';
import '../services/ai_import_client.dart';
import '../services/import_service.dart';
import '../services/meal_service.dart';
import '../services/planning_service.dart';
import '../services/settings_service.dart';
import '../services/shopping_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import '../theme/theme_preview_screen.dart';
import '../ui/history/plan_history_screen.dart';
import '../ui/import/import_history_screen.dart';
import '../ui/import/review_import_screen.dart';
import '../ui/planner/generated_plan_screen.dart';
import '../ui/planner/plan_this_week_screen.dart';
import '../ui/meals/meal_library_screen.dart';
import '../ui/meals/meal_detail_screen.dart';
import '../ui/meals/meal_edit_screen.dart';
import '../ui/planner/select_meal_count_screen.dart';
import '../ui/shell/prep_shell_screen.dart';
import '../ui/shopping/shopping_history_screen.dart';
import '../ui/shopping/shopping_list_screen.dart';
import '../ui/shopping/shopping_week_screen.dart';
import '../widgets/bottom_navigation.dart';
import '../widgets/prep_button.dart';
import 'routes.dart';

/// Root widget. Owns theming, routing and the provider shell.
///
/// Providers are registered here as they are implemented. Services are
/// constructed here too and injected into their provider, so tests can swap
/// in a service backed by a temporary database.
class PrepPickApp extends StatefulWidget {
  const PrepPickApp({super.key, this.databaseService, this.initialRoute});

  /// Overrides the database the app talks to. Tests pass a temporary one;
  /// the real app leaves this null and gets the default on-device database.
  final DatabaseService? databaseService;

  /// Optional boot route for tests and platform deep links. Normal app
  /// startup leaves this null and goes through [AppRoutes.startup].
  final String? initialRoute;

  /// Development-only escape hatch that boots straight into the token gallery
  /// instead of the app. Off by default; flip it by running:
  ///
  ///     flutter run --dart-define=PREVIEW_THEME=true
  ///
  /// The preview is never reachable from real navigation, so this stays out of
  /// the shipped app as long as the define is absent.
  static const bool showThemePreview = bool.fromEnvironment('PREVIEW_THEME');

  @override
  State<PrepPickApp> createState() => _PrepPickAppState();
}

class _PrepPickAppState extends State<PrepPickApp> {
  // Built once, not per build, so every provider keeps talking to the same
  // database connection for the life of the app.
  late final DatabaseService _database =
      widget.databaseService ?? DatabaseService();
  late final SettingsService _settingsService = SettingsService(_database);
  late final MealService _mealService = MealService(_database);
  late final AiImportClient _aiImportClient = AiImportClient.fromEnvironment();
  late final ImportService _importService = ImportService(
    _mealService,
    _database,
    _aiImportClient,
  );
  late final PlanningService _planningService = PlanningService(
    _database,
    _mealService,
  );
  late final ShoppingService _shoppingService = ShoppingService(
    _database,
    _mealService,
    _planningService,
  );

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          // Load immediately so the counts are ready before the first screen
          // that needs them is built.
          create: (_) => SettingsProvider(_settingsService)..load(),
        ),
        ChangeNotifierProvider(
          create: (_) => MealProvider(_mealService)..load(),
        ),
        ChangeNotifierProvider(
          // The import flow preserves pasted text and review edits as the
          // user moves between the paste and review screens.
          create: (_) => ImportProvider(_importService)..restoreDraft(),
        ),
        ChangeNotifierProvider(
          // Not loaded eagerly: reading back this week's draft is only worth
          // a query once a planner screen is actually on screen.
          create: (_) => PlannerProvider(_planningService),
        ),
        ChangeNotifierProvider(
          // Also lazy: the list is built from a confirmed plan, so there is
          // nothing to read until the household reaches the shopping screen.
          create: (_) => ShoppingProvider(_shoppingService),
        ),
        ChangeNotifierProvider(
          // Read-only and kept apart from ShoppingProvider, so browsing an
          // old week never disturbs the list being shopped from.
          create: (_) => ShoppingHistoryProvider(_shoppingService),
        ),
      ],
      child: MaterialApp(
        title: 'PrepPick',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: PrepPickApp.showThemePreview ? const ThemePreviewScreen() : null,
        initialRoute: PrepPickApp.showThemePreview
            ? null
            : widget.initialRoute ?? AppRoutes.startup,
        // Every route goes through _routeFor so the four tab routes resolve
        // to the shell rather than to a bare, bar-less screen.
        onGenerateRoute: _routeFor,
        onGenerateInitialRoutes: PrepPickApp.showThemePreview
            ? null
            : (initialRoute) => [
                _routeFor(
                      RouteSettings(name: widget.initialRoute ?? initialRoute),
                    ) ??
                    _routeFor(const RouteSettings(name: AppRoutes.startup))!,
              ],
      ),
    );
  }

  Map<String, WidgetBuilder> get _routeBuilders => {
    AppRoutes.startup: (_) => const StartupShellScreen(),
    AppRoutes.selectMealCount: (context) => SelectMealCountScreen(
      // From first run this replaces the setup screen with the shell; when
      // opened from inside the Plan tab it just pops back to the plan.
      onContinue: () => Navigator.of(context).canPop()
          ? Navigator.of(context).pop()
          : Navigator.of(context).pushReplacementNamed(AppRoutes.plan),
    ),
    AppRoutes.plan: (context) => PlanThisWeekScreen(
      onEditCounts: () =>
          Navigator.of(context).pushNamed(AppRoutes.selectMealCount),
      onOpenMealLibrary: () => openPrepTab(context, PrepTab.meals),
    ),
    AppRoutes.generatedPlan: (context) => GeneratedPlanScreen(
      onOpenMealLibrary: () => openPrepTab(context, PrepTab.meals),
    ),
    AppRoutes.shoppingList: (_) => const ShoppingListScreen(),
    AppRoutes.shoppingHistory: (_) => const ShoppingHistoryScreen(),
    AppRoutes.shoppingHistoryWeek: (context) =>
        ShoppingWeekScreen(planId: _idArgument(context)),
    AppRoutes.planHistory: (_) => const PlanHistoryScreen(),
    AppRoutes.mealLibrary: (_) => const MealLibraryScreen(),
    AppRoutes.importHistory: (_) => const ImportHistoryScreen(),
    AppRoutes.reviewImport: (_) => const ReviewImportScreen(),
    AppRoutes.mealDetail: (context) =>
        MealDetailScreen(mealId: _idArgument(context)),
    AppRoutes.addMeal: (_) => const MealEditScreen(),
    AppRoutes.editMeal: (context) =>
        MealEditScreen(mealId: _idArgument(context)),
  };

  /// Resolves a route at the root navigator.
  ///
  /// The four tab routes open the shell on that tab, so a deep link or a boot
  /// route lands with the bottom bar in place. Everything else is a plain
  /// screen above the shell.
  Route<dynamic>? _routeFor(RouteSettings settings) {
    final tab = shellTabForRoute(settings.name);
    if (tab != null) {
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) =>
            PrepShellScreen(initialTab: tab, onGenerateRoute: _screenRouteFor),
      );
    }
    return _screenRouteFor(settings);
  }

  /// Resolves a screen route inside a tab. Never returns the shell.
  Route<dynamic>? _screenRouteFor(RouteSettings settings) {
    final builder = _routeBuilders[settings.name];
    if (builder != null) {
      return MaterialPageRoute<void>(settings: settings, builder: builder);
    }
    return _generateRoute(settings);
  }

  Route<dynamic>? _generateRoute(RouteSettings settings) {
    final name = settings.name;
    if (name == null) return null;

    final uri = Uri.tryParse(name);
    if (uri == null) return null;

    if (uri.pathSegments.length == 2 && uri.pathSegments.first == 'meal') {
      final mealId = uri.pathSegments[1].trim();
      if (mealId.isEmpty) return null;
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => MealDetailScreen(mealId: mealId),
      );
    }

    return null;
  }
}

String _idArgument(BuildContext context) {
  final argument = ModalRoute.of(context)?.settings.arguments;
  if (argument is String && argument.trim().isNotEmpty) return argument;
  return '';
}

/// Startup gate: waits for persisted settings, then opens the correct V1
/// entry point without leaving this route on the back stack.
class StartupShellScreen extends StatefulWidget {
  const StartupShellScreen({super.key});

  @override
  State<StartupShellScreen> createState() => _StartupShellScreenState();
}

class _StartupShellScreenState extends State<StartupShellScreen> {
  bool _hasNavigated = false;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();

    if (settings.hasLoaded && settings.error == null && !_hasNavigated) {
      _hasNavigated = true;
      final destination = settings.hasSavedSettings
          ? AppRoutes.plan
          : AppRoutes.selectMealCount;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).pushReplacementNamed(destination);
      });
    }

    if (settings.hasLoaded && settings.error != null) {
      return _StartupError(onRetry: settings.load);
    }

    return const _StartupLoading();
  }
}

class _StartupLoading extends StatelessWidget {
  const _StartupLoading();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        // Scrollable so the column still fits when text is scaled up.
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'PrepPick',
                  textAlign: TextAlign.center,
                  style: textTheme.displayLarge,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Getting your week ready.',
                  textAlign: TextAlign.center,
                  style: textTheme.bodyLarge?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                const Center(child: CircularProgressIndicator()),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StartupError extends StatelessWidget {
  const _StartupError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'PrepPick',
                textAlign: TextAlign.center,
                style: textTheme.displayLarge,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Could not open your saved settings.',
                textAlign: TextAlign.center,
                style: textTheme.bodyLarge?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),
              PrepButton(label: 'Try again', onPressed: onRetry),
            ],
          ),
        ),
      ),
    );
  }
}

/// Stands in for a screen a later phase builds.
///
/// Registered for routes the finished flow already navigates to — confirming
/// a plan goes to the shopping list, a shortage points at the meal library —
/// so those journeys are wired end to end now and only the destination
/// changes later.
class ComingSoonScreen extends StatelessWidget {
  const ComingSoonScreen({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Text(
            '$title is coming next.',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: AppColors.textSecondary),
          ),
        ),
      ),
    );
  }
}
