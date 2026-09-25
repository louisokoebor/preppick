import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme/app_icons.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../utils/duration_format.dart';
import 'category_badge.dart';

/// One slot in a week, empty or filled.
///
/// The same card serves Plan This Week and Generated Plan rather than two
/// near-identical widgets, because they are the same slot before and after
/// generation: the empty state is a dashed placeholder, and once [mealName]
/// arrives the card fills in and grows a Swap action. Keeping them one widget
/// is what makes the two screens line up pixel for pixel.
class MealSlotCard extends StatelessWidget {
  const MealSlotCard({
    super.key,
    required this.slot,
    required this.totalOfType,
    this.mealName,
    this.protein,
    this.estimatedMinutes,
    this.prepTiming = PrepTiming.mainPrep,
    this.plannedCookDate,
    this.onSwap,
    this.onEditTiming,
    this.onEditMeal,
    this.isSwapping = false,
  });

  final MealSlot slot;

  /// How many slots of this meal type the week holds. Decides whether the
  /// label is numbered ("Dinner 1") or bare ("Dinner").
  final int totalOfType;

  /// The planned meal, or null for an empty slot.
  final String? mealName;

  /// Optional protein line, shown only when the meal records one. PrepPick
  /// never invents this.
  final String? protein;

  /// Optional meal-level cooking estimate.
  final int? estimatedMinutes;

  /// When this specific plan item will be prepared.
  final PrepTiming prepTiming;

  /// Optional date for cook-later plan items.
  final DateTime? plannedCookDate;

  /// Swap action. Null hides it, either because an empty slot has nothing to
  /// swap or because the plan is being shown read-only.
  final VoidCallback? onSwap;

  /// Opens the prep-timing editor for this plan item.
  final VoidCallback? onEditTiming;

  /// Opens the saved meal editor for the meal in this slot.
  final VoidCallback? onEditMeal;

  /// True while this card's swap is in flight.
  final bool isSwapping;

  bool get isEmpty => mealName == null;

  String get label => slot.label(totalOfType: totalOfType);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: isEmpty ? '$label, not selected yet' : '$label, $mealName',
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: AppColors.backgroundSurface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 64,
                      width: 64,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: CategoryBadge.colorFor(slot.mealType),
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                      ),
                      child: Icon(
                        CategoryBadge.iconFor(slot.mealType),
                        size: 28,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(
                          right: onSwap != null || isSwapping
                              ? AppSpacing.giant
                              : 0,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              label.toUpperCase(),
                              style: AppTypography.caption.copyWith(
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              mealName ?? 'Not selected yet',
                              style: AppTypography.titleMedium,
                            ),
                            if (protein != null &&
                                protein!.trim().isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                protein!,
                                style: AppTypography.bodySmall.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                            if (!isEmpty) ...[
                              const SizedBox(height: AppSpacing.sm),
                              _TimingMetadata(
                                estimatedMinutes: estimatedMinutes,
                                timingLabel: _timingLabel,
                                timingIcon: prepTiming == PrepTiming.mainPrep
                                    ? AppIcons.eventAvailableOutlined
                                    : AppIcons.todayOutlined,
                                onEditTiming: onEditTiming,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                if (onSwap != null || isSwapping)
                  Positioned(
                    top: 0,
                    right: 0,
                    child: _SwapAction(
                      label: label,
                      isSwapping: isSwapping,
                      onSwap: onSwap,
                    ),
                  ),
              ],
            ),
            if (!isEmpty && (onEditTiming != null || onEditMeal != null)) ...[
              const SizedBox(height: AppSpacing.xl),
              const Divider(height: 1, color: AppColors.borderSubtle),
            ],
            if (!isEmpty && (onEditTiming != null || onEditMeal != null))
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.lg),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (onEditTiming != null)
                      Flexible(
                        child: _CardAction(
                          label: 'Change timing',
                          icon: AppIcons.eventAvailableOutlined,
                          onPressed: onEditTiming,
                        ),
                      )
                    else
                      const Spacer(),
                    if (onEditMeal != null)
                      Flexible(child: _EditMealAction(onPressed: onEditMeal)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  String get _timingLabel {
    if (prepTiming == PrepTiming.mainPrep) return 'Main prep';
    final date = plannedCookDate;
    if (date == null) return 'Cook later';
    return 'Cook later · ${_weekdayName(date)}';
  }

  static String _weekdayName(DateTime date) => switch (date.weekday) {
    DateTime.monday => 'Monday',
    DateTime.tuesday => 'Tuesday',
    DateTime.wednesday => 'Wednesday',
    DateTime.thursday => 'Thursday',
    DateTime.friday => 'Friday',
    DateTime.saturday => 'Saturday',
    DateTime.sunday => 'Sunday',
    _ => 'Later',
  };
}

class _TimingMetadata extends StatelessWidget {
  const _TimingMetadata({
    required this.estimatedMinutes,
    required this.timingLabel,
    required this.timingIcon,
    this.onEditTiming,
  });

  final int? estimatedMinutes;
  final String timingLabel;
  final IconData timingIcon;
  final VoidCallback? onEditTiming;

  @override
  Widget build(BuildContext context) {
    final time = Text(
      PrepDurationFormat.optionalMinutes(estimatedMinutes) ?? 'Time not set',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary),
    );
    final timing = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(timingIcon, size: 20, color: AppColors.textSecondary),
        const SizedBox(width: AppSpacing.xs),
        Flexible(
          child: Text(
            timingLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
    );

    return Row(
      children: [
        const Icon(
          AppIcons.timerOutlined,
          size: 20,
          color: AppColors.textSecondary,
        ),
        const SizedBox(width: AppSpacing.xs),
        Flexible(child: time),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          child: Text('·', style: TextStyle(color: AppColors.textSecondary)),
        ),
        if (onEditTiming == null)
          Flexible(child: timing)
        else
          Flexible(
            child: Semantics(
              button: true,
              label: '$timingLabel, Change timing',
              child: InkWell(
                onTap: onEditTiming,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                  child: timing,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _CardAction extends StatelessWidget {
  const _CardAction({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => TextButton.icon(
    onPressed: onPressed,
    icon: Icon(icon, size: 20),
    label: Text(label),
    style: TextButton.styleFrom(
      foregroundColor: AppColors.actionPrimaryPressed,
      textStyle: AppTypography.bodyMedium,
      padding: EdgeInsets.zero,
      minimumSize: const Size(0, 40),
      alignment: Alignment.centerLeft,
    ),
  );
}

class _EditMealAction extends StatelessWidget {
  const _EditMealAction({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => TextButton.icon(
    onPressed: onPressed,
    icon: const Icon(AppIcons.editOutlined, size: 18),
    label: const Text('Edit meal'),
    style: TextButton.styleFrom(
      foregroundColor: AppColors.textSecondary,
      backgroundColor: AppColors.backgroundMuted,
      textStyle: AppTypography.bodyMedium,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      minimumSize: const Size(0, 40),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
    ),
  );
}

/// The per-slot Swap affordance.
///
/// Disabled rather than hidden while a swap runs, so the row does not reflow
/// mid-tap and a second tap cannot start a second swap of the same slot.
class _SwapAction extends StatelessWidget {
  const _SwapAction({
    required this.label,
    required this.isSwapping,
    required this.onSwap,
  });

  final String label;
  final bool isSwapping;
  final VoidCallback? onSwap;

  @override
  Widget build(BuildContext context) {
    if (isSwapping) {
      return Semantics(
        liveRegion: true,
        label: 'Swapping $label',
        child: const SizedBox(
          height: 40,
          width: 40,
          child: Center(
            child: SizedBox(
              height: 18,
              width: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      );
    }
    return IconButton(
      onPressed: onSwap,
      tooltip: 'Swap $label',
      style: IconButton.styleFrom(
        foregroundColor: AppColors.actionPrimaryPressed,
        backgroundColor: AppColors.actionSecondary,
        minimumSize: const Size(48, 48),
        padding: EdgeInsets.zero,
        shape: const CircleBorder(),
      ),
      icon: const Icon(AppIcons.syncRounded, semanticLabel: 'Swap'),
    );
  }
}
