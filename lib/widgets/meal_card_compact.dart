import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme/app_icons.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../utils/duration_format.dart';
import 'category_badge.dart';

/// A one-line meal card for pickers and lists.
///
/// Deliberately lighter than [MealSlotCard]: this is a meal being *offered*,
/// not a meal already placed in the week, so it carries only the category
/// glyph, the name, the protein when one is recorded, and a selection tick.
class MealCardCompact extends StatelessWidget {
  const MealCardCompact({
    super.key,
    required this.meal,
    required this.mealType,
    this.isSelected = false,
    this.onTap,
  });

  final MealVariant meal;

  /// Drives the category tint and glyph.
  final MealType mealType;

  final bool isSelected;
  final VoidCallback? onTap;

  bool get _hasProtein => (meal.protein?.trim().isNotEmpty) ?? false;
  bool get _hasTime => meal.estimatedMinutes != null;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: onTap != null,
      selected: isSelected,
      child: Material(
        color: AppColors.backgroundSurface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(
                color: isSelected
                    ? AppColors.actionPrimary
                    : AppColors.borderSubtle,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  height: 36,
                  width: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: CategoryBadge.colorFor(mealType),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Icon(
                    CategoryBadge.iconFor(mealType),
                    size: 18,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(meal.name, style: AppTypography.titleMedium),
                      if (_hasProtein) ...[
                        const SizedBox(height: 2),
                        Text(
                          meal.protein!,
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                      if (_hasTime) ...[
                        const SizedBox(height: 2),
                        Text(
                          PrepDurationFormat.approximate(meal.estimatedMinutes),
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (isSelected)
                  const Icon(
                    AppIcons.checkCircleRounded,
                    size: 22,
                    color: AppColors.actionPrimary,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
