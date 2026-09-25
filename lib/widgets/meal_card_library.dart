import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme/app_icons.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../utils/duration_format.dart';
import 'category_badge.dart';

/// A meal as it appears in the Meal Library.
///
/// Heavier than [MealCardCompact] because this card is the meal's entry in
/// the household's own collection rather than an option being offered: it
/// names the family the variant belongs to, so "Lou Lou Spaghetti + Chicken"
/// and "+ Turkey" read as two versions of one meal instead of two unrelated
/// rows, and it carries the category badge so the list stays readable when
/// the "All" filter mixes breakfasts with dinners.
///
/// Long names wrap to two lines and then ellipsize rather than overflowing —
/// households name meals after whole sentences ("Mum's Sunday jollof with the
/// crispy bits"), and a card that clips or throws on one is worse than one
/// that trails off.
class MealCardLibrary extends StatelessWidget {
  const MealCardLibrary({
    super.key,
    required this.meal,
    required this.mealType,
    this.familyName,
    this.onTap,
  });

  final MealVariant meal;

  /// Drives the category badge and tint.
  final MealType mealType;

  /// The family this variant belongs to. Hidden when it is null or when it
  /// simply repeats the variant name, which is the case for meals that have
  /// only one version.
  final String? familyName;

  final VoidCallback? onTap;

  bool get _hasProtein => (meal.protein?.trim().isNotEmpty) ?? false;
  bool get _hasTime => meal.estimatedMinutes != null;

  bool get _showsFamily {
    final family = familyName?.trim();
    if (family == null || family.isEmpty) return false;
    return family.toLowerCase() != meal.name.trim().toLowerCase();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: onTap != null,
      child: Material(
        color: AppColors.backgroundSurface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: AppColors.borderSubtle),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 44,
                  width: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: CategoryBadge.colorFor(mealType),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Icon(
                    CategoryBadge.iconFor(mealType),
                    size: 20,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        meal.name,
                        style: AppTypography.titleMedium,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (_showsFamily) ...[
                        const SizedBox(height: 2),
                        Text(
                          familyName!,
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: AppSpacing.sm),
                      // Wrap rather than Row: the badge and the protein sit
                      // side by side when they fit and stack when the text
                      // scale or a long protein name says otherwise.
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.xs,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          CategoryBadge(mealType: mealType),
                          if (_hasProtein)
                            Text(
                              meal.protein!,
                              style: AppTypography.bodySmall.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          if (_hasTime)
                            Text(
                              PrepDurationFormat.approximate(
                                meal.estimatedMinutes,
                              ),
                              style: AppTypography.bodySmall.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (onTap != null) ...[
                  const SizedBox(width: AppSpacing.sm),
                  const Icon(
                    AppIcons.chevronRightRounded,
                    size: 22,
                    color: AppColors.textTertiary,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
