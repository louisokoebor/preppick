import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/models.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../../utils/duration_format.dart';
import '../../widgets/meal_slot_card.dart';

class PlanItemSections extends StatelessWidget {
  const PlanItemSections({
    super.key,
    required this.plan,
    required this.items,
    required this.mealFor,
    required this.countOfType,
    this.canEdit = false,
    this.isSwapping = false,
    this.onSwap,
    this.onEditPrepEstimate,
    this.onEditTiming,
    this.onEditMeal,
  });

  final WeeklyPlan plan;
  final List<WeeklyPlanItem> items;
  final MealVariant? Function(WeeklyPlanItem item) mealFor;
  final int Function(MealType type) countOfType;
  final bool canEdit;
  final bool isSwapping;
  final ValueChanged<WeeklyPlanItem>? onSwap;
  final VoidCallback? onEditPrepEstimate;
  final ValueChanged<WeeklyPlanItem>? onEditTiming;
  final ValueChanged<WeeklyPlanItem>? onEditMeal;

  @override
  Widget build(BuildContext context) {
    final mainPrep = items
        .where((item) => item.prepTiming == PrepTiming.mainPrep)
        .toList();
    final later = items
        .where((item) => item.prepTiming == PrepTiming.later)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PrepSummary(
          plan: plan,
          items: mainPrep,
          mealFor: mealFor,
          onEdit: canEdit ? onEditPrepEstimate : null,
        ),
        const SizedBox(height: AppSpacing.md),
        for (final item in mainPrep) ...[
          _PlanMealCard(
            item: item,
            meal: mealFor(item),
            totalOfType: countOfType(item.mealType),
            canEdit: canEdit,
            isSwapping: isSwapping,
            onSwap: onSwap,
            onEditTiming: onEditTiming,
            onEditMeal: onEditMeal,
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        if (later.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          _SectionLabel('COOK LATER'),
          const SizedBox(height: AppSpacing.sm),
          for (final group in _laterGroups(later)) ...[
            Padding(
              padding: const EdgeInsets.only(
                top: AppSpacing.xs,
                bottom: AppSpacing.sm,
              ),
              child: Text(
                group.label,
                style: AppTypography.labelLarge.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            for (final item in group.items) ...[
              _PlanMealCard(
                item: item,
                meal: mealFor(item),
                totalOfType: countOfType(item.mealType),
                canEdit: canEdit,
                isSwapping: isSwapping,
                onSwap: onSwap,
                onEditTiming: onEditTiming,
                onEditMeal: onEditMeal,
              ),
              const SizedBox(height: AppSpacing.md),
            ],
          ],
        ],
      ],
    );
  }

  static List<_LaterGroup> _laterGroups(List<WeeklyPlanItem> items) {
    final sorted = [...items]
      ..sort((a, b) {
        final aDate = a.plannedCookDate;
        final bDate = b.plannedCookDate;
        if (aDate == null && bDate == null) return a.slot.compareTo(b.slot);
        if (aDate == null) return 1;
        if (bDate == null) return -1;
        final byDate = aDate.compareTo(bDate);
        return byDate != 0 ? byDate : a.slot.compareTo(b.slot);
      });

    final groups = <_LaterGroup>[];
    for (final item in sorted) {
      final label = item.plannedCookDate == null
          ? 'Day not set'
          : DateFormat('EEEE').format(item.plannedCookDate!);
      final index = groups.indexWhere((group) => group.label == label);
      if (index == -1) {
        groups.add(_LaterGroup(label, [item]));
      } else {
        groups[index].items.add(item);
      }
    }
    return groups;
  }
}

class _PrepSummary extends StatelessWidget {
  const _PrepSummary({
    required this.plan,
    required this.items,
    required this.mealFor,
    this.onEdit,
  });

  final WeeklyPlan plan;
  final List<WeeklyPlanItem> items;
  final MealVariant? Function(WeeklyPlanItem item) mealFor;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final session = PrepDurationFormat.optionalMinutes(
      plan.estimatedPrepMinutes,
    );
    final recordedMealMinutes = items
        .map((item) => mealFor(item)?.estimatedMinutes)
        .whereType<int>()
        .fold<int>(0, (total, minutes) => total + minutes);
    final unsetCount = items
        .where((item) => mealFor(item)?.estimatedMinutes == null)
        .length;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.backgroundSurface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: _SectionLabel('MAIN PREP')),
              if (onEdit != null)
                TextButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(AppIcons.editOutlined, size: 16),
                  label: const Text('Edit'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: AppColors.actionPrimaryPressed,
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Estimated session: ${session ?? 'Not set'}',
            style: AppTypography.titleMedium,
          ),
          if (recordedMealMinutes > 0 || unsetCount > 0) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              _recordedMealTimeLabel(recordedMealMinutes, unsetCount),
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _recordedMealTimeLabel(int minutes, int unsetCount) {
    final known = minutes > 0
        ? PrepDurationFormat.minutesLabel(minutes)
        : 'None recorded';
    if (unsetCount == 0) return 'Recorded meal times: $known';
    return 'Recorded meal times: $known; $unsetCount unset';
  }
}

class _PlanMealCard extends StatelessWidget {
  const _PlanMealCard({
    required this.item,
    required this.meal,
    required this.totalOfType,
    required this.canEdit,
    required this.isSwapping,
    this.onSwap,
    this.onEditTiming,
    this.onEditMeal,
  });

  final WeeklyPlanItem item;
  final MealVariant? meal;
  final int totalOfType;
  final bool canEdit;
  final bool isSwapping;
  final ValueChanged<WeeklyPlanItem>? onSwap;
  final ValueChanged<WeeklyPlanItem>? onEditTiming;
  final ValueChanged<WeeklyPlanItem>? onEditMeal;

  @override
  Widget build(BuildContext context) => MealSlotCard(
    slot: item.slot,
    totalOfType: totalOfType,
    mealName: meal?.name ?? 'Meal unavailable',
    protein: meal?.protein,
    estimatedMinutes: meal?.estimatedMinutes,
    prepTiming: item.prepTiming,
    plannedCookDate: item.plannedCookDate,
    onSwap: canEdit ? () => onSwap?.call(item) : null,
    onEditTiming: canEdit ? () => onEditTiming?.call(item) : null,
    onEditMeal: canEdit && meal != null ? () => onEditMeal?.call(item) : null,
    isSwapping: isSwapping,
  );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Text(
    label,
    style: AppTypography.caption.copyWith(
      color: AppColors.textSecondary,
      fontWeight: FontWeight.w700,
    ),
  );
}

class _LaterGroup {
  _LaterGroup(this.label, this.items);

  final String label;
  final List<WeeklyPlanItem> items;
}
