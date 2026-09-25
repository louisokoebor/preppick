import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/routes.dart';
import '../../models/models.dart';
import '../../providers/planner_provider.dart';
import '../../providers/settings_provider.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../utils/error_messages.dart';
import '../../widgets/bottom_navigation.dart';
import '../../widgets/prep_button.dart';
import '../../widgets/prep_header.dart';
import '../../widgets/week_range_card.dart';
import 'plan_item_sections.dart';
import 'plan_this_week_screen.dart' show PlanNotice;
import 'plan_timing_sheets.dart';
import 'swap_meal_sheet.dart';
import '../../widgets/share_meal_plan_button.dart';

/// Generated Plan: the week PrepPick chose, before it is committed.
///
/// Confirm is the primary action and Regenerate is deliberately secondary:
/// the product's job is to end the weekly decision, not to invite the
/// household to keep rolling the dice. Swapping a single slot sits on the
/// cards themselves, because that is the precise edit — regenerating replaces
/// the whole week and is the blunt one.
class GeneratedPlanScreen extends StatefulWidget {
  const GeneratedPlanScreen({
    super.key,
    this.onConfirmed,
    this.onOpenMealLibrary,
    this.onSwapRequested,
  });

  /// Called once the plan is confirmed. Defaults to pushing the Shopping List.
  final VoidCallback? onConfirmed;

  /// Called from the shortage message when the library needs more meals.
  final VoidCallback? onOpenMealLibrary;

  /// Overrides how Swap opens. Defaults to the [SwapMealSheet] bottom sheet;
  /// tests pass their own to assert which slot was targeted.
  final void Function(WeeklyPlanItem item)? onSwapRequested;

  @override
  State<GeneratedPlanScreen> createState() => _GeneratedPlanScreenState();
}

class _GeneratedPlanScreenState extends State<GeneratedPlanScreen> {
  bool _isEditingConfirmed = false;

  Future<void> _handleConfirm(BuildContext context) async {
    final planner = context.read<PlannerProvider>();
    // The button disables itself while confirming; this catches the tap that
    // lands in the frame before that takes effect, so a plan is never
    // confirmed twice.
    if (planner.isBusy) return;

    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await planner.confirmPlan();
    if (!context.mounted) return;

    if (!confirmed) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Could not confirm your plan. Please try again.'),
        ),
      );
      return;
    }

    final onConfirmed = widget.onConfirmed;
    if (onConfirmed != null) {
      onConfirmed();
    } else {
      openPrepTab(context, PrepTab.shopping);
    }
  }

  Future<void> _handleRegenerate(BuildContext context) async {
    final planner = context.read<PlannerProvider>();
    if (planner.isBusy) return;
    await planner.regeneratePlan(context.read<SettingsProvider>().settings);
  }

  Future<void> _handleSwap(BuildContext context, WeeklyPlanItem item) async {
    final onSwapRequested = widget.onSwapRequested;
    if (onSwapRequested != null) {
      onSwapRequested(item);
      return;
    }
    final planner = context.read<PlannerProvider>();
    if (planner.isBusy) return;
    // The sheet performs the swap itself and pops true; there is nothing to
    // do here afterwards, because the provider has already notified.
    await SwapMealSheet.show(
      context,
      item: item,
      totalOfType: planner.countOfType(item.mealType),
      currentMealName: planner.mealFor(item)?.name,
    );
  }

  Future<void> _handlePrepEstimate(BuildContext context) async {
    final planner = context.read<PlannerProvider>();
    final result = await showDurationEditorSheet(
      context,
      title: 'Prep session estimate',
      label: 'Estimated prep session',
      initialMinutes: planner.currentPlan?.estimatedPrepMinutes,
    );
    if (!context.mounted || result == null) return;
    final saved = await planner.updatePrepSessionEstimate(result.minutes);
    if (!context.mounted || saved) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not save the prep estimate.')),
    );
  }

  Future<void> _handlePrepTiming(
    BuildContext context,
    WeeklyPlanItem item,
  ) async {
    final planner = context.read<PlannerProvider>();
    final result = await showPrepTimingEditorSheet(
      context,
      item: item,
      weekStart: planner.weekStart,
      mealName: planner.mealFor(item)?.name,
    );
    if (!context.mounted || result == null) return;
    final saved = await planner.updatePlanItemTiming(
      item.id,
      prepTiming: result.prepTiming,
      plannedCookDate: result.plannedCookDate,
    );
    if (!context.mounted || saved) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not save the prep timing.')),
    );
  }

  Future<void> _handleEditMeal(
    BuildContext context,
    WeeklyPlanItem item,
  ) async {
    final planner = context.read<PlannerProvider>();
    final meal = planner.mealFor(item);
    if (meal == null) return;
    await Navigator.of(
      context,
    ).pushNamed(AppRoutes.editMeal, arguments: meal.id);
    if (!context.mounted) return;
    await planner.loadCurrentPlan();
  }

  @override
  Widget build(BuildContext context) {
    final planner = context.watch<PlannerProvider>();
    final items = planner.items;
    final isConfirmed = planner.isConfirmed;
    final canEditPlan = !isConfirmed || _isEditingConfirmed;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            PrepHeader(
              title: 'Your week',
              subtitle: isConfirmed
                  ? 'This week\'s plan is confirmed.'
                  : 'Swap anything that does not fit, then confirm.',
              onBack: Navigator.of(context).canPop()
                  ? () => Navigator.of(context).pop()
                  : null,
              trailing: const ShareMealPlanButton(),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  AppSpacing.sm,
                  AppSpacing.xl,
                  AppSpacing.lg,
                ),
                children: [
                  WeekRangeCard(weekStart: planner.weekStart),
                  const SizedBox(height: AppSpacing.lg),
                  if (planner.currentPlan != null && items.isNotEmpty)
                    PlanItemSections(
                      plan: planner.currentPlan!,
                      items: items,
                      mealFor: planner.mealFor,
                      countOfType: planner.countOfType,
                      canEdit: canEditPlan,
                      isSwapping: planner.isSwapping,
                      onSwap: (item) => _handleSwap(context, item),
                      onEditPrepEstimate: () => _handlePrepEstimate(context),
                      onEditTiming: (item) => _handlePrepTiming(context, item),
                      onEditMeal: (item) => _handleEditMeal(context, item),
                    ),
                  if (items.isEmpty)
                    const PlanNotice(
                      message:
                          'This week has no meals yet. Go back and plan your '
                          'week to see PrepPick’s picks.',
                    ),
                  if (planner.shortageMessage != null)
                    PlanNotice(
                      message: planner.shortageMessage!,
                      actionLabel: 'Go to Meal Library',
                      onAction: widget.onOpenMealLibrary,
                    ),
                  // A failed swap or confirm also shows a snackbar, which is
                  // gone by the time someone looks back at the screen. This
                  // notice is what is still there, so the plan never just
                  // looks like it quietly refused to change.
                  if (planner.error != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    PlanNotice(
                      key: const Key('generatedPlanError'),
                      message: PrepErrorMessages.forError(
                        planner.error,
                        fallback:
                            'Something went wrong with your plan. Please try '
                            'again.',
                      )!,
                    ),
                  ],
                ],
              ),
            ),
            Container(
              color: AppColors.backgroundApp,
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.sm,
                AppSpacing.xl,
                AppSpacing.md,
              ),
              child: Column(
                children: [
                  PrepButton(
                    label: isConfirmed
                        ? _isEditingConfirmed
                              ? 'Done editing'
                              : 'Edit plan'
                        : 'Confirm plan',
                    icon: isConfirmed
                        ? _isEditingConfirmed
                              ? AppIcons.checkRounded
                              : AppIcons.editRounded
                        : null,
                    isBusy: planner.isConfirming,
                    onPressed: items.isEmpty
                        ? null
                        : isConfirmed
                        ? () => setState(
                            () => _isEditingConfirmed = !_isEditingConfirmed,
                          )
                        : () => _handleConfirm(context),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  PrepButton(
                    label: isConfirmed ? 'View shopping list' : 'Regenerate',
                    variant: PrepButtonVariant.tertiary,
                    icon: isConfirmed
                        ? AppIcons.shoppingBasketOutlined
                        : AppIcons.refreshRounded,
                    isBusy: planner.isGenerating,
                    // Disabled while confirming or swapping too: all three
                    // write the same plan.
                    onPressed: planner.isBusy
                        ? null
                        : isConfirmed
                        ? () => _openShoppingList(context)
                        : () => _handleRegenerate(context),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openShoppingList(BuildContext context) {
    final onConfirmed = widget.onConfirmed;
    if (onConfirmed != null) {
      onConfirmed();
    } else {
      openPrepTab(context, PrepTab.shopping);
    }
  }
}
