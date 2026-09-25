import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme/app_icons.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// The small tinted pill naming a meal category.
///
/// The category tints are the one place in the palette that carries meaning
/// rather than structure, so they live here and every screen reads them from
/// this one widget instead of re-deriving the mapping.
class CategoryBadge extends StatelessWidget {
  const CategoryBadge({super.key, required this.mealType, this.label});

  final MealType mealType;

  /// Overrides the category name, e.g. "Dinner 2" for a numbered slot.
  final String? label;

  /// The palette tint for a category.
  static Color colorFor(MealType type) => switch (type) {
    MealType.breakfast => AppColors.categoryBreakfast,
    MealType.lunch => AppColors.categoryLunch,
    MealType.dinner => AppColors.categoryDinner,
  };

  /// The glyph for a category, matching the Select Meal Count cards.
  static IconData iconFor(MealType type) => switch (type) {
    MealType.breakfast => AppIcons.wbSunnyOutlined,
    MealType.lunch => AppIcons.ramenDiningOutlined,
    MealType.dinner => AppIcons.nightlightOutlined,
  };

  /// The display name for a category.
  static String nameFor(MealType type) => switch (type) {
    MealType.breakfast => 'Breakfast',
    MealType.lunch => 'Lunch',
    MealType.dinner => 'Dinner',
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: colorFor(mealType),
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Text(
        (label ?? nameFor(mealType)).toUpperCase(),
        style: AppTypography.labelMedium.copyWith(color: AppColors.textPrimary),
      ),
    );
  }
}
