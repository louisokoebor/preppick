import 'package:flutter/material.dart';

import '../../app/routes.dart';
import '../../widgets/bottom_navigation.dart';

/// The persistent tab shell.
///
/// The bottom bar belongs to the shell, not to the screens. Each tab keeps its
/// own [Navigator], so pushing Meal Detail or Generated Plan stays inside the
/// tab that opened it and the bar never rebuilds or slides with the screen.
class PrepShellScreen extends StatefulWidget {
  const PrepShellScreen({
    super.key,
    required this.initialTab,
    required this.onGenerateRoute,
  });

  /// Tab shown first. Deep links into `/meals`, `/shopping` and `/history`
  /// land here rather than on a bare screen.
  final PrepTab initialTab;

  /// Resolves a screen route inside a tab. This must build the screens
  /// themselves, never the shell, or a tab would nest another shell.
  final RouteFactory onGenerateRoute;

  @override
  State<PrepShellScreen> createState() => _PrepShellScreenState();
}

class _PrepShellScreenState extends State<PrepShellScreen>
    implements PrepShellController {
  static const _tabs = PrepTab.values;

  final Map<PrepTab, GlobalKey<NavigatorState>> _navigatorKeys = {
    for (final tab in _tabs) tab: GlobalKey<NavigatorState>(),
  };

  late PrepTab _current = widget.initialTab;

  @override
  PrepTab get currentTab => _current;

  @override
  void selectTab(PrepTab tab) {
    if (tab == _current) {
      // A second tap on the tab you are already on is the standard "take me
      // back to the top of this section" gesture.
      _navigatorKeys[tab]!.currentState?.popUntil((route) => route.isFirst);
      return;
    }
    setState(() => _current = tab);
  }

  /// Back first unwinds the active tab, then falls back to the Plan tab, and
  /// only leaves the app from an empty Plan tab.
  bool _handlePop() {
    final navigator = _navigatorKeys[_current]!.currentState;
    if (navigator != null && navigator.canPop()) {
      navigator.pop();
      return false;
    }
    if (_current != PrepTab.plan) {
      setState(() => _current = PrepTab.plan);
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return PrepShellScope(
      controller: this,
      currentTab: _current,
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          if (_handlePop()) Navigator.of(context).pop();
        },
        child: Scaffold(
          body: SafeArea(
            bottom: false,
            child: Column(
              children: [
                Expanded(
                  child: IndexedStack(
                    index: _tabs.indexOf(_current),
                    children: [
                      for (final tab in _tabs)
                        // Kept alive by the stack, so switching tabs preserves
                        // each section's scroll position and push history.
                        Navigator(
                          key: _navigatorKeys[tab],
                          onGenerateRoute: widget.onGenerateRoute,
                          // Exactly one route, not the implicit '/'-first
                          // hierarchy Navigator builds from a path.
                          onGenerateInitialRoutes: (navigator, _) => [
                            widget.onGenerateRoute(
                              RouteSettings(name: tab.routeName),
                            )!,
                          ],
                        ),
                    ],
                  ),
                ),
                PrepBottomNavigation(
                  current: _current,
                  enabledTabs: PrepTab.values.toSet(),
                  onSelected: selectTab,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// What a screen inside the shell can ask of it.
abstract class PrepShellController {
  PrepTab get currentTab;

  void selectTab(PrepTab tab);
}

/// Exposes the shell to the screens inside it.
///
/// Absent when a screen is pumped on its own — in a test or behind a deep
/// link — which is why [openPrepTab] falls back to a plain push.
class PrepShellScope extends InheritedWidget {
  const PrepShellScope({
    super.key,
    required this.controller,
    required this.currentTab,
    required super.child,
  });

  final PrepShellController controller;

  /// The tab on screen. Screens depend on this to notice they have just been
  /// brought back into view.
  final PrepTab currentTab;

  static PrepShellScope? _of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PrepShellScope>();

  static PrepShellController? maybeOf(BuildContext context) =>
      _of(context)?.controller;

  /// The visible tab, or null when this screen is not inside the shell.
  static PrepTab? currentTabOf(BuildContext context) =>
      _of(context)?.currentTab;

  @override
  bool updateShouldNotify(PrepShellScope oldWidget) =>
      controller != oldWidget.controller || currentTab != oldWidget.currentTab;
}

/// Runs [onTabBecameVisible] whenever the shell brings this screen's tab back
/// into view, and once on first build.
///
/// Tabs are built together and kept alive by the shell, so a screen that
/// loads only in [State.initState] shows whatever was true at app start — the
/// Shopping tab built before a plan existed would still say so after the week
/// was confirmed. This is the hook that keeps a live tab honest.
mixin PrepShellTabAware<T extends StatefulWidget> on State<T> {
  bool _wasVisible = false;

  /// The tab this screen sits at the root of.
  PrepTab get shellTab;

  void onTabBecameVisible();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final current = PrepShellScope.currentTabOf(context);
    // Outside the shell — a test, or a deep-linked screen — there is no tab
    // to hide behind, so the screen counts as visible from the start.
    final isVisible = current == null || current == shellTab;
    final becameVisible = isVisible && !_wasVisible;
    _wasVisible = isVisible;
    if (!becameVisible) return;

    // After the frame: this runs during build, and the callbacks read
    // providers and touch the database.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) onTabBecameVisible();
    });
  }
}

/// The tab routes the shell owns. Anything else is a screen pushed inside a
/// tab, or a root-level route such as Select Meal Count.
PrepTab? shellTabForRoute(String? routeName) => switch (routeName) {
  AppRoutes.plan => PrepTab.plan,
  AppRoutes.mealLibrary => PrepTab.meals,
  AppRoutes.shoppingList => PrepTab.shopping,
  AppRoutes.planHistory => PrepTab.history,
  _ => null,
};
