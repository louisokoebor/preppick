import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../providers/planner_provider.dart';
import '../../services/planning_service.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../../utils/duration_format.dart';
import '../../utils/error_messages.dart';
import '../../utils/week_range_format.dart';
import '../../widgets/prep_loading.dart';
import '../../widgets/category_badge.dart';
import '../../widgets/prep_button.dart';
import '../../widgets/bottom_navigation.dart';
import '../../widgets/prep_header.dart';
import '../shell/prep_shell_screen.dart';

/// Plan History: previous confirmed weeks, newest first.
class PlanHistoryScreen extends StatefulWidget {
  const PlanHistoryScreen({super.key, this.onOpenPlan});

  /// Overrides the detail interaction in tests. Defaults to a read-only sheet.
  final ValueChanged<WeeklyPlanDetail>? onOpenPlan;

  @override
  State<PlanHistoryScreen> createState() => _PlanHistoryScreenState();
}

class _PlanHistoryScreenState extends State<PlanHistoryScreen>
    with PrepShellTabAware<PlanHistoryScreen> {
  @override
  PrepTab get shellTab => PrepTab.history;

  // Re-read on every visit, not once: the tab stays alive in the shell while
  // weeks are confirmed behind it, and a stale history is a wrong one.
  @override
  void onTabBecameVisible() {
    final planner = context.read<PlannerProvider>();
    if (!planner.isLoadingHistory) planner.loadPlanHistory();
  }

  void _openDetail(WeeklyPlanDetail detail) {
    final onOpenPlan = widget.onOpenPlan;
    if (onOpenPlan != null) {
      onOpenPlan(detail);
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.backgroundSurface,
      builder: (_) => _PlanHistoryDetailSheet(detail: detail),
    );
  }

  @override
  Widget build(BuildContext context) {
    final planner = context.watch<PlannerProvider>();

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            PrepHeader(
              title: 'Plan history',
              subtitle: 'Your previous meal plans.',
              onBack: Navigator.of(context).canPop()
                  ? () => Navigator.of(context).pop()
                  : null,
              trailing: IconButton(
                onPressed: planner.isLoadingHistory
                    ? null
                    : () => context.read<PlannerProvider>().loadPlanHistory(),
                icon: const Icon(
                  AppIcons.refreshRounded,
                  semanticLabel: 'Refresh history',
                ),
                tooltip: 'Refresh history',
                color: AppColors.textSecondary,
              ),
            ),
            Expanded(child: _body(planner)),
          ],
        ),
      ),
    );
  }

  Widget _body(PlannerProvider planner) {
    if (planner.isLoadingHistory && planner.history.isEmpty) {
      return const PrepLoading(message: 'Loading your past weeks');
    }
    if (planner.historyError != null) {
      return _HistoryNotice(
        key: const Key('planHistoryError'),
        message: PrepErrorMessages.forError(
          planner.historyError,
          fallback: 'Something went wrong loading your plan history.',
        )!,
        actionLabel: 'Try again',
        onAction: () => context.read<PlannerProvider>().loadPlanHistory(),
      );
    }
    if (planner.history.isEmpty) {
      return const _HistoryNotice(
        message:
            'Confirmed weeks will appear here after you plan and confirm a '
            'shopping list.',
      );
    }

    return RefreshIndicator(
      onRefresh: () => context.read<PlannerProvider>().loadPlanHistory(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.sm,
          AppSpacing.xl,
          AppSpacing.lg,
        ),
        children: [
          for (final detail in planner.history) ...[
            _HistoryEntry(detail: detail, onTap: () => _openDetail(detail)),
            const SizedBox(height: AppSpacing.md),
          ],
        ],
      ),
    );
  }
}

class _HistoryEntry extends StatelessWidget {
  const _HistoryEntry({required this.detail, required this.onTap});

  final WeeklyPlanDetail detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final meals = detail.items
        .map((item) => detail.mealFor(item)?.name ?? 'Meal unavailable')
        .join(', ');

    return Material(
      color: AppColors.backgroundSurface,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      PrepWeekRange.label(detail.plan.weekStart),
                      style: AppTypography.titleLarge,
                    ),
                  ),
                  const Icon(
                    AppIcons.chevronRightRounded,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                detail.items.length == 1
                    ? '1 meal'
                    : '${detail.items.length} meals',
                style: AppTypography.labelMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                meals,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlanHistoryDetailSheet extends StatelessWidget {
  const _PlanHistoryDetailSheet({required this.detail});

  final WeeklyPlanDetail detail;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.xl,
          right: AppSpacing.xl,
          top: AppSpacing.xl,
          bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    PrepWeekRange.label(detail.plan.weekStart),
                    style: AppTypography.headingH2,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(
                    AppIcons.closeRounded,
                    semanticLabel: 'Close',
                  ),
                  tooltip: 'Close',
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Prep session: ${PrepDurationFormat.optionalMinutes(detail.plan.estimatedPrepMinutes) ?? 'Not set'}',
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: detail.items.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: AppSpacing.md),
                itemBuilder: (context, index) {
                  final item = detail.items[index];
                  final meal = detail.mealFor(item);
                  return _HistoryMealRow(
                    slotLabel: item.slot.label(
                      totalOfType: detail.countOfType(item.mealType),
                    ),
                    mealType: item.mealType,
                    mealName: meal?.name ?? 'Meal unavailable',
                    protein: meal?.protein,
                    estimatedMinutes: meal?.estimatedMinutes,
                    prepTiming: item.prepTiming,
                    plannedCookDate: item.plannedCookDate,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryMealRow extends StatelessWidget {
  const _HistoryMealRow({
    required this.slotLabel,
    required this.mealType,
    required this.mealName,
    this.protein,
    this.estimatedMinutes,
    this.prepTiming = PrepTiming.mainPrep,
    this.plannedCookDate,
  });

  final String slotLabel;
  final MealType mealType;
  final String mealName;
  final String? protein;
  final int? estimatedMinutes;
  final PrepTiming prepTiming;
  final DateTime? plannedCookDate;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.borderSubtle),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CategoryBadge(mealType: mealType, label: slotLabel),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(mealName, style: AppTypography.titleMedium),
                if ((protein?.trim().isNotEmpty) ?? false) ...[
                  const SizedBox(height: 2),
                  Text(
                    protein!,
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.xs),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  children: [
                    Text(
                      PrepDurationFormat.approximate(estimatedMinutes),
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    Text(
                      _timingLabel,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String get _timingLabel {
    if (prepTiming == PrepTiming.mainPrep) return 'Main prep';
    final date = plannedCookDate;
    if (date == null) return 'Cook later';
    return 'Cook later · ${DateFormat('EEEE').format(date)}';
  }
}

class _HistoryNotice extends StatelessWidget {
  const _HistoryNotice({
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
    // Scrollable rather than a bare centred Column: on a 568-tall phone at a
    // 1.5 text scale the message and its action are taller than the space
    // left between the header and the nav bar, and an empty state that
    // overflows is the one screen state nobody can work around.
    return SingleChildScrollView(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                message,
                textAlign: TextAlign.center,
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: AppSpacing.lg),
                PrepButton(
                  label: actionLabel!,
                  variant: PrepButtonVariant.tertiary,
                  isFullWidth: false,
                  onPressed: onAction,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
