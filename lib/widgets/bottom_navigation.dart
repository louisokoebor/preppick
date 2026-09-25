import 'package:flutter/material.dart';

import '../app/routes.dart';
import '../ui/shell/prep_shell_screen.dart';
import '../theme/app_icons.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

/// The destinations in PrepPick's bottom bar.
enum PrepTab {
  plan('Plan', AppIcons.calendarMonthOutlined),
  meals('Meals', AppIcons.restaurantMenuOutlined),
  shopping('Shopping', AppIcons.shoppingBasketOutlined),
  history('History', AppIcons.historyRounded);

  const PrepTab(this.label, this.icon);

  final String label;
  final IconData icon;
}

extension PrepTabRoute on PrepTab {
  String get routeName => switch (this) {
    PrepTab.plan => AppRoutes.plan,
    PrepTab.meals => AppRoutes.mealLibrary,
    PrepTab.shopping => AppRoutes.shoppingList,
    PrepTab.history => AppRoutes.planHistory,
  };
}

/// Move to a bottom-tab destination.
///
/// Inside the shell this only switches tabs, so the bar stays put and each
/// tab keeps its own history. A screen pumped outside the shell — a test, or
/// a deep link that opened a bare screen — falls back to a plain push.
void openPrepTab(BuildContext context, PrepTab tab) {
  final shell = PrepShellScope.maybeOf(context);
  if (shell != null) {
    shell.selectTab(tab);
    return;
  }

  final routeName = tab.routeName;
  if (ModalRoute.of(context)?.settings.name == routeName) return;
  Navigator.of(context).pushNamed(routeName);
}

/// The app's bottom navigation bar.
///
/// [onSelected] is nullable per tab via [enabledTabs]: the planner screens
/// ship before the Meals, Shopping and History screens exist, and a tab that
/// navigates nowhere is worse than one that visibly cannot be reached yet.
class PrepBottomNavigation extends StatelessWidget {
  const PrepBottomNavigation({
    super.key,
    required this.current,
    this.onSelected,
    this.enabledTabs = const {},
  });

  final PrepTab current;

  /// Called with the chosen tab. Null disables the whole bar.
  final ValueChanged<PrepTab>? onSelected;

  /// Tabs that lead somewhere. The current tab is always enabled.
  final Set<PrepTab> enabledTabs;

  bool _isEnabled(PrepTab tab) =>
      onSelected != null && (tab == current || enabledTabs.contains(tab));

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.backgroundSurface,
        border: Border(top: BorderSide(color: AppColors.borderSubtle)),
      ),
      child: SafeArea(
        top: false,
        // A minimum rather than a fixed height: the labels are capped below
        // but still grow a little with the text scale, and the bar grows with
        // them instead of clipping.
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Row(
            children: [
              for (final tab in PrepTab.values)
                Expanded(
                  child: _NavItem(
                    tab: tab,
                    isCurrent: tab == current,
                    onTap: _isEnabled(tab) && tab != current
                        ? () => onSelected!(tab)
                        : null,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.tab,
    required this.isCurrent,
    required this.onTap,
  });

  final PrepTab tab;
  final bool isCurrent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = isCurrent
        ? AppColors.actionPrimaryPressed
        : onTap == null
        ? AppColors.textTertiary
        : AppColors.textSecondary;

    return Semantics(
      button: true,
      selected: isCurrent,
      label: tab.label,
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onTap,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(tab.icon, size: 22, color: color),
              const SizedBox(height: 2),
              // The bar is a fixed 64 high, so an unbounded accessibility
              // scale would push the label out of it. Capped rather than
              // allowed to grow: the tab labels sit beside icons that already
              // name the destination, and a bar that swallows a third of a
              // small screen costs more than the extra type size gains.
              MediaQuery.withClampedTextScaling(
                maxScaleFactor: 1.3,
                child: Text(
                  tab.label,
                  style: AppTypography.caption.copyWith(color: color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
