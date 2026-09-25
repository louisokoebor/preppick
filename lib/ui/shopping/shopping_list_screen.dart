import 'package:flutter/material.dart';
import 'package:flutter/services.dart' as services;
import 'package:provider/provider.dart';

import '../../app/routes.dart';
import '../../models/models.dart';
import '../../providers/planner_provider.dart';
import '../../providers/shopping_provider.dart';
import '../../services/shopping_service.dart';
import '../../services/share_service.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../../utils/category_labels.dart';
import '../../utils/error_messages.dart';
import '../../widgets/prep_loading.dart';
import '../../widgets/bottom_navigation.dart';
import '../shell/prep_shell_screen.dart';
import '../../widgets/prep_button.dart';
import '../../widgets/prep_filter_chip.dart';
import '../../widgets/prep_header.dart';
import 'add_shopping_item_sheet.dart';
import 'shopping_list_parts.dart';
import '../../widgets/share_options_sheet.dart';

/// Shopping List: the confirmed week turned into something to walk a shop
/// with.
///
/// This is the screen the whole product is for. Everything upstream — the
/// counts, the picks, the swaps — exists to produce this list, so it is
/// treated as a destination rather than a receipt: grouped by aisle, ticked
/// off in place, and added to freely.
///
/// ## Every tap is already saved
///
/// There is no save button and no confirm step. A tick writes to SQLite
/// immediately (see [ShoppingProvider.toggleItem]), which is what lets
/// someone close the app in the queue, reopen it in the car park, and find
/// their progress exactly where they left it.
///
/// ## Nothing is hidden
///
/// Ticked lines stay in place, dimmed and struck through, rather than
/// disappearing or sinking to the bottom — a list that rearranges itself
/// under a thumb loses the shopper's place. Lines with no known quantity are
/// shown with no quantity at all, never a fabricated one.
class ShoppingListScreen extends StatefulWidget {
  const ShoppingListScreen({
    super.key,
    this.planId,
    this.onBrowsePlan,
    this.onOpenHistory,
  });

  /// The plan to shop for. Defaults to the plan the [PlannerProvider] holds,
  /// which is how the screen is reached after confirming.
  final String? planId;

  /// Called from the empty state when there is no confirmed plan to shop.
  /// Defaults to pushing Plan This Week.
  final VoidCallback? onBrowsePlan;

  /// Called from the history icon. Defaults to pushing Past Shopping Lists
  /// inside the Shopping tab, so Back returns here.
  final VoidCallback? onOpenHistory;

  @override
  State<ShoppingListScreen> createState() => _ShoppingListScreenState();
}

class _ShoppingListScreenState extends State<ShoppingListScreen>
    with PrepShellTabAware<ShoppingListScreen> {
  bool _isSharing = false;
  @override
  PrepTab get shellTab => PrepTab.shopping;

  // The tab is built at app start, long before a week is confirmed, so the
  // list is opened every time the shopper comes back to it rather than once.
  @override
  void onTabBecameVisible() => _open();

  Future<void> _open() async {
    if (!mounted) return;
    final planner = context.read<PlannerProvider>();
    // Reached directly from the nav bar rather than from a confirmation, so
    // find out what week is in progress first.
    if (widget.planId == null && !planner.hasLoaded) {
      await planner.loadCurrentPlan();
      if (!mounted) return;
    }

    final planId = _planId();
    if (planId == null) return;
    await context.read<ShoppingProvider>().openForPlan(planId);
  }

  /// The plan to shop for, or null when there is not a confirmed one.
  ///
  /// A draft has no shopping list by design: it is still being shuffled, and
  /// a list built from one would be wrong by the next swap.
  String? _planId() {
    if (widget.planId != null) return widget.planId;
    final planner = context.read<PlannerProvider>();
    return planner.isConfirmed ? planner.currentPlan?.id : null;
  }

  Future<void> _toggle(ShoppingItem item) async {
    final shopping = context.read<ShoppingProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final ok = await shopping.toggleItem(item.id);
    if (!mounted || ok) return;
    messenger.showSnackBar(
      SnackBar(content: Text('Could not save ${item.name}. Try again.')),
    );
  }

  Future<void> _addItem() async {
    final shopping = context.read<ShoppingProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final draft = await AddShoppingItemSheet.show(context);
    if (draft == null || !mounted) return;

    final added = await shopping.addItem(
      name: draft.name,
      quantity: draft.quantity,
      unit: draft.unit,
      category: draft.category,
    );
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          added
              ? '${draft.name} added to your list.'
              : 'Could not add ${draft.name}. Try again.',
        ),
      ),
    );
  }

  Future<void> _delete(ShoppingItem item) async {
    final shopping = context.read<ShoppingProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final removed = await shopping.deleteItem(item.id);
    if (!mounted || removed) return;
    messenger.showSnackBar(
      SnackBar(content: Text('Could not remove ${item.name}. Try again.')),
    );
  }

  Future<void> _shareList() async {
    final shopping = context.read<ShoppingProvider>();
    if (shopping.items.isEmpty || _isSharing) return;

    final option = await ShareOptionsSheet.show(
      context,
      title: 'Share shopping list',
    );
    if (!mounted || option == null) return;

    setState(() => _isSharing = true);
    try {
      final weekStart = context.read<PlannerProvider>().weekStart;
      final share = const ShareService();
      if (option == ShareOption.message) {
        await share.shareText(
          subject: 'PrepPick shopping list',
          text: share.shoppingListMessage(
            weekStart: weekStart,
            items: shopping.items,
          ),
        );
      } else {
        await share.shareShoppingListPdf(
          weekStart: weekStart,
          items: shopping.items,
        );
      }
    } catch (error, stackTrace) {
      debugPrint('PrepPick shopping-list share failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is services.MissingPluginException
                  ? 'Sharing needs a full app restart after installing the update.'
                  : 'Could not prepare the shopping list. Try again.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final shopping = context.watch<ShoppingProvider>();
    final planner = context.watch<PlannerProvider>();
    final hasPlan = widget.planId != null || planner.isConfirmed;
    final groups = shopping.groups;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            PrepHeader(
              title: 'Shopping list',
              subtitle: _subtitle(shopping, hasPlan: hasPlan),
              onBack: Navigator.of(context).canPop()
                  ? () => Navigator.of(context).pop()
                  : null,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (shopping.checkedCount > 0)
                    IconButton(
                      onPressed: shopping.isWriting
                          ? null
                          : () =>
                                context.read<ShoppingProvider>().clearChecked(),
                      icon: const Icon(
                        AppIcons.restartAltRounded,
                        semanticLabel: 'Untick everything',
                      ),
                      color: AppColors.textSecondary,
                      tooltip: 'Untick everything',
                    ),
                  // Always offered, even with no confirmed week: that is
                  // exactly when last week's list is most useful.
                  IconButton(
                    onPressed: widget.onOpenHistory ?? _openHistory,
                    icon: const Icon(
                      AppIcons.historyRounded,
                      semanticLabel: 'Past shopping lists',
                    ),
                    color: AppColors.textSecondary,
                    tooltip: 'Past shopping lists',
                  ),
                  IconButton(
                    key: const Key('shareShoppingListButton'),
                    onPressed: _isSharing ? null : _shareList,
                    icon: const Icon(
                      AppIcons.shareRounded,
                      semanticLabel: 'Share shopping list',
                    ),
                    color: AppColors.textSecondary,
                    tooltip: 'Share shopping list',
                  ),
                ],
              ),
            ),
            if (shopping.error != null && shopping.totalCount > 0)
              const _WriteFailureBanner(),
            if (shopping.totalCount > 0)
              _CategoryFilters(
                categories: shopping.availableCategories,
                selected: shopping.categoryFilter,
                onSelected: (category) => context
                    .read<ShoppingProvider>()
                    .setCategoryFilter(category),
              ),
            Expanded(
              child: _body(
                shopping: shopping,
                groups: groups,
                hasPlan: hasPlan,
              ),
            ),
            if (hasPlan && shopping.totalCount > 0)
              Container(
                color: AppColors.backgroundApp,
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  AppSpacing.sm,
                  AppSpacing.xl,
                  AppSpacing.md,
                ),
                child: PrepButton(
                  label: 'Add an item',
                  variant: PrepButtonVariant.tertiary,
                  icon: AppIcons.addRounded,
                  isBusy: shopping.isWriting,
                  onPressed: shopping.isWriting ? null : _addItem,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _body({
    required ShoppingProvider shopping,
    required List<ShoppingCategoryGroup> groups,
    required bool hasPlan,
  }) {
    if (!hasPlan && shopping.totalCount == 0) {
      return ShoppingNotice(
        message:
            'Your shopping list appears once you confirm a week. Plan '
            'your meals and PrepPick will build the list from them.',
        actionLabel: 'Plan this week',
        onAction: widget.onBrowsePlan ?? () => _goToPlan(context),
      );
    }
    if (shopping.isLoading || shopping.isGenerating) {
      return PrepLoading(
        message: shopping.isGenerating
            ? 'Building your shopping list'
            : 'Loading your shopping list',
      );
    }
    if (shopping.hasError) {
      return ShoppingNotice(
        message: PrepErrorMessages.forError(
          shopping.error,
          fallback: 'Something went wrong building your shopping list.',
        )!,
        actionLabel: 'Try again',
        onAction: _open,
      );
    }
    if (shopping.isEmpty) {
      return const ShoppingNotice(
        message:
            'This week’s meals have no ingredients recorded yet. Add '
            'ingredients to your meals, or add items to the list yourself.',
      );
    }
    if (!shopping.hasLoaded) {
      // A confirmed week whose list this screen has not read yet — the tab
      // was alive but out of view while the plan was confirmed. Says so,
      // rather than falling through to a filter message about a list that
      // was never loaded.
      return const PrepLoading(message: 'Loading your shopping list');
    }
    if (groups.isEmpty) {
      // Everything is filtered out — one tap from being fixed, so this says
      // so rather than looking like an empty list.
      return const ShoppingNotice(
        message: 'Nothing in this aisle. Choose All to see the whole list.',
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.md,
        AppSpacing.xl,
        AppSpacing.lg,
      ),
      children: [
        for (final group in groups) ...[
          ShoppingCategorySection(
            group: group,
            onToggle: _toggle,
            onDelete: _delete,
            isBusy: shopping.isWriting,
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
      ],
    );
  }

  /// The line under the title: shopping progress once there is a list, and
  /// what to do next when there is not.
  String _subtitle(ShoppingProvider shopping, {required bool hasPlan}) {
    if (!hasPlan && shopping.totalCount == 0) {
      return 'No confirmed week yet.';
    }
    if (shopping.totalCount == 0) return 'Building your list…';
    if (shopping.isComplete) return 'All done — everything is ticked off.';
    return '${shopping.checkedCount} of ${shopping.totalCount} ticked off.';
  }

  void _openHistory() {
    Navigator.of(context).pushNamed(AppRoutes.shoppingHistory);
  }

  void _goToPlan(BuildContext context) {
    openPrepTab(context, PrepTab.plan);
  }
}

/// A thin strip shown when a change to a list that is already on screen did
/// not save.
///
/// The snackbars cover the moment it happens; this covers everything after —
/// the household needs to know a tick did not stick before they walk away
/// from the shelf, not only in the two seconds the snackbar was up.
class _WriteFailureBanner extends StatelessWidget {
  const _WriteFailureBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('shoppingWriteError'),
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        0,
        AppSpacing.xl,
        AppSpacing.sm,
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.categoryShopping,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Text(
        'Your last change could not be saved. Try it again.',
        style: AppTypography.bodySmall,
      ),
    );
  }
}

/// The aisle filter row.
///
/// Only categories actually present are offered, so the row never advertises
/// a filter that would empty the screen.
class _CategoryFilters extends StatelessWidget {
  const _CategoryFilters({
    required this.categories,
    required this.selected,
    required this.onSelected,
  });

  final List<String> categories;
  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
        children: [
          PrepFilterChip(
            label: 'All',
            isSelected: selected == null,
            onSelected: () => onSelected(null),
          ),
          for (final category in categories) ...[
            const SizedBox(width: AppSpacing.sm),
            PrepFilterChip(
              label: PrepCategoryLabels.labelFor(category),
              isSelected: selected == category,
              onSelected: () => onSelected(category),
            ),
          ],
        ],
      ),
    );
  }
}
