import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/routes.dart';
import '../../models/models.dart';
import '../../providers/planner_provider.dart';
import '../../providers/settings_provider.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../../utils/error_messages.dart';
import '../../widgets/prep_loading.dart';
import '../../widgets/bottom_navigation.dart';
import '../../widgets/meal_slot_card.dart';
import '../../widgets/prep_button.dart';
import '../../widgets/prep_header.dart';
import '../../widgets/share_meal_plan_button.dart';
import '../../widgets/week_range_card.dart';
import 'plan_item_sections.dart';
import 'plan_timing_sheets.dart';
import 'swap_meal_sheet.dart';

/// The slots a week holds for a given set of meal counts, in slot order.
///
/// Derived from [AppSettings] rather than hard-coded, so a household that
/// preps three dinners and no breakfast sees exactly that. This is the same
/// order [PlanningService] fills, which is why the empty cards and the
/// generated cards line up one for one.
List<MealSlot> slotsFor(AppSettings settings) => [
  for (final type in MealType.values)
    for (var index = 0; index < settings.countFor(type); index++)
      MealSlot(type, index),
];

/// Plan This Week: the empty week, ready to be generated.
///
/// Shows one card per slot from the saved meal counts and one primary action.
/// The cards are placeholders — no meal is chosen until "Plan this week" is
/// pressed, because generating on arrival would mean the household never sees
/// the week it asked for before the app fills it in.
class PlanThisWeekScreen extends StatefulWidget {
  const PlanThisWeekScreen({
    super.key,
    this.onPlanGenerated,
    this.onEditCounts,
    this.onOpenMealLibrary,
  });

  /// Called after a plan is generated. Defaults to pushing Generated Plan.
  final VoidCallback? onPlanGenerated;

  /// Called when the household wants to change its meal counts.
  final VoidCallback? onEditCounts;

  /// Called from the shortage message when the library needs more meals.
  final VoidCallback? onOpenMealLibrary;

  @override
  State<PlanThisWeekScreen> createState() => _PlanThisWeekScreenState();
}

class _PlanThisWeekScreenState extends State<PlanThisWeekScreen> {
  bool _isEditingConfirmed = false;

  @override
  void initState() {
    super.initState();
    // After the first frame: both loads notify synchronously, and notifying
    // during build is an error.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final settings = context.read<SettingsProvider>();
      if (!settings.hasLoaded) settings.load();
      final planner = context.read<PlannerProvider>();
      if (!planner.hasLoaded) planner.loadCurrentPlan();
    });
  }

  Future<void> _handlePlan() async {
    final planner = context.read<PlannerProvider>();
    // A tap that lands while generation is already running is dropped by the
    // provider too; this keeps the navigation from running twice.
    if (planner.isBusy) return;

    final settings = context.read<SettingsProvider>().settings;
    final generated = await planner.generatePlan(settings);
    if (!mounted || !generated) return;

    final onPlanGenerated = widget.onPlanGenerated;
    if (onPlanGenerated != null) {
      onPlanGenerated();
    } else {
      Navigator.of(context).pushNamed(AppRoutes.generatedPlan);
    }
  }

  Future<void> _handleRegenerate() async {
    final planner = context.read<PlannerProvider>();
    if (planner.isBusy || planner.isConfirmed) return;
    await planner.regeneratePlan(context.read<SettingsProvider>().settings);
  }

  Future<void> _handleConfirm() async {
    final planner = context.read<PlannerProvider>();
    if (planner.isBusy) return;

    final confirmed = await planner.confirmPlan();
    if (!mounted || !confirmed) return;
    openPrepTab(context, PrepTab.shopping);
  }

  Future<void> _handleSwap(WeeklyPlanItem item) async {
    final planner = context.read<PlannerProvider>();
    if (planner.isBusy) return;
    await SwapMealSheet.show(
      context,
      item: item,
      totalOfType: planner.countOfType(item.mealType),
      currentMealName: planner.mealFor(item)?.name,
    );
  }

  Future<void> _handlePrepEstimate() async {
    final planner = context.read<PlannerProvider>();
    final result = await showDurationEditorSheet(
      context,
      title: 'Prep session estimate',
      label: 'Estimated prep session',
      initialMinutes: planner.currentPlan?.estimatedPrepMinutes,
    );
    if (!mounted || result == null) return;
    final saved = await planner.updatePrepSessionEstimate(result.minutes);
    if (!mounted || saved) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not save the prep estimate.')),
    );
  }

  Future<void> _handlePrepTiming(WeeklyPlanItem item) async {
    final planner = context.read<PlannerProvider>();
    final result = await showPrepTimingEditorSheet(
      context,
      item: item,
      weekStart: planner.weekStart,
      mealName: planner.mealFor(item)?.name,
    );
    if (!mounted || result == null) return;
    final saved = await planner.updatePlanItemTiming(
      item.id,
      prepTiming: result.prepTiming,
      plannedCookDate: result.plannedCookDate,
    );
    if (!mounted || saved) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not save the prep timing.')),
    );
  }

  Future<void> _handleEditMeal(WeeklyPlanItem item) async {
    final planner = context.read<PlannerProvider>();
    final meal = planner.mealFor(item);
    if (meal == null) return;
    await Navigator.of(
      context,
    ).pushNamed(AppRoutes.editMeal, arguments: meal.id);
    if (!mounted) return;
    await planner.loadCurrentPlan();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final planner = context.watch<PlannerProvider>();
    final slots = slotsFor(settings.settings);
    // Only the very first read gets a spinner in place of the slots. Once the
    // counts are known the cards stay put, so a later refresh cannot blank a
    // week the household is already looking at.
    final isFirstLoad =
        (settings.isLoading && !settings.hasLoaded) ||
        (planner.isLoading && !planner.hasLoaded);

    final hasExistingPlan = planner.hasPlan && !isFirstLoad;
    final canEditPlan =
        hasExistingPlan && (!planner.isConfirmed || _isEditingConfirmed);
    final title = hasExistingPlan
        ? planner.isConfirmed
              ? 'This week\'s plan'
              : 'Draft plan'
        : 'Plan this week';
    final subtitle = hasExistingPlan
        ? planner.isConfirmed
              ? 'Confirmed for this week.'
              : 'Swap anything that does not fit, then confirm.'
        : 'Select the week to build a plan from meals you already love.';

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            PrepHeader(
              title: title,
              subtitle: subtitle,
              trailing: const ShareMealPlanButton(),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  AppSpacing.xl,
                  AppSpacing.xl,
                  AppSpacing.lg,
                ),
                children: [
                  WeekRangeCard(weekStart: planner.weekStart),
                  const SizedBox(height: AppSpacing.sm),
                  if (isFirstLoad)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
                      child: PrepLoading(message: 'Loading this week'),
                    )
                  else if (slots.isEmpty)
                    const _NoSlotsNotice()
                  else if (hasExistingPlan)
                    PlanItemSections(
                      plan: planner.currentPlan!,
                      items: planner.items,
                      mealFor: planner.mealFor,
                      countOfType: planner.countOfType,
                      canEdit: canEditPlan,
                      isSwapping: planner.isSwapping,
                      onSwap: _handleSwap,
                      onEditPrepEstimate: _handlePrepEstimate,
                      onEditTiming: _handlePrepTiming,
                      onEditMeal: _handleEditMeal,
                    )
                  else
                    for (final slot in slots) ...[
                      MealSlotCard(
                        slot: slot,
                        totalOfType: settings.settings.countFor(slot.mealType),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                    ],
                  if (planner.shortageMessage != null)
                    PlanNotice(
                      message: planner.shortageMessage!,
                      actionLabel: planner.needsMeals
                          ? 'Go to Meal Library'
                          : null,
                      onAction: planner.needsMeals
                          ? widget.onOpenMealLibrary
                          : null,
                    ),
                  if (planner.error != null)
                    PlanNotice(
                      key: const Key('planThisWeekError'),
                      // The message never comes from the error object: a
                      // failed write throws sqflite's own text, which says
                      // nothing a household can act on.
                      message: PrepErrorMessages.forError(
                        planner.error,
                        fallback:
                            'Something went wrong while planning your week. '
                            'Please try again.',
                      )!,
                      actionLabel: 'Try again',
                      onAction: planner.isBusy ? null : _handlePlan,
                    ),
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
              child: PrepButton(
                label: hasExistingPlan
                    ? planner.isConfirmed
                          ? _isEditingConfirmed
                                ? 'Done editing'
                                : 'Edit plan'
                          : 'Confirm plan'
                    : 'Generate my plan',
                icon: hasExistingPlan
                    ? planner.isConfirmed
                          ? _isEditingConfirmed
                                ? AppIcons.checkRounded
                                : AppIcons.editRounded
                          : AppIcons.checkRounded
                    : AppIcons.autoAwesome,
                iconAfterLabel: !hasExistingPlan,
                isBusy: planner.isGenerating || planner.isConfirming,
                onPressed: slots.isEmpty || isFirstLoad
                    ? null
                    : hasExistingPlan
                    ? planner.isConfirmed
                          ? () => setState(
                              () => _isEditingConfirmed = !_isEditingConfirmed,
                            )
                          : _handleConfirm
                    : _handlePlan,
              ),
            ),
            if (hasExistingPlan)
              Container(
                color: AppColors.backgroundApp,
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  0,
                  AppSpacing.xl,
                  AppSpacing.md,
                ),
                child: PrepButton(
                  label: planner.isConfirmed
                      ? 'View shopping list'
                      : 'Regenerate',
                  variant: PrepButtonVariant.tertiary,
                  icon: planner.isConfirmed
                      ? AppIcons.shoppingBasketOutlined
                      : AppIcons.refreshRounded,
                  isBusy: planner.isGenerating,
                  onPressed: planner.isBusy
                      ? null
                      : planner.isConfirmed
                      ? () => openPrepTab(context, PrepTab.shopping)
                      : _handleRegenerate,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A tinted, optionally actionable message block.
///
/// Shared by both planner screens so a shortage reads identically wherever it
/// appears, and so the action that resolves it — going to the Meal Library —
/// is always one tap away rather than something the household has to work out.
class PlanNotice extends StatelessWidget {
  const PlanNotice({
    super.key,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.categoryShopping,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                AppIcons.infoOutlineRounded,
                size: 20,
                color: AppColors.textPrimary,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: Text(message, style: AppTypography.bodyMedium)),
            ],
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: AppSpacing.md),
            PrepButton(
              label: actionLabel!,
              variant: PrepButtonVariant.tertiary,
              isFullWidth: false,
              onPressed: onAction,
            ),
          ],
        ],
      ),
    );
  }
}

/// Shown when every meal count is zero, so the week has no slots at all.
class _NoSlotsNotice extends StatelessWidget {
  const _NoSlotsNotice();

  @override
  Widget build(BuildContext context) {
    return const PlanNotice(
      message:
          'You have not asked for any meals this week. Change your meal '
          'counts to start planning.',
    );
  }
}
