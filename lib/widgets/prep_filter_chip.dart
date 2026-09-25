import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// A single selectable filter pill.
///
/// Named with the Prep prefix to avoid colliding with Flutter's own
/// [FilterChip], and hand-rolled rather than themed from it so the selected
/// state uses the PrepPick action palette exactly.
class PrepFilterChip extends StatelessWidget {
  const PrepFilterChip({
    super.key,
    required this.label,
    required this.isSelected,
    required this.onSelected,
  });

  final String label;
  final bool isSelected;
  final VoidCallback? onSelected;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: isSelected,
      child: Material(
        color: isSelected
            ? AppColors.actionSecondary
            : AppColors.backgroundSurface,
        borderRadius: BorderRadius.circular(AppRadius.full),
        child: InkWell(
          onTap: onSelected,
          borderRadius: BorderRadius.circular(AppRadius.full),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.full),
              // Selection is not left to hue: the border darkens and
              // thickens and the label gains weight, so the chosen chip is
              // still obvious to someone who cannot separate the green fill
              // from the white one.
              border: Border.all(
                color: isSelected
                    ? AppColors.actionPrimary
                    : AppColors.borderSubtle,
                width: isSelected ? 1.5 : 1,
              ),
            ),
            child: Center(
              child: Text(
                label,
                style: AppTypography.labelLarge.copyWith(
                  color: isSelected
                      ? AppColors.actionPrimaryPressed
                      : AppColors.textSecondary,
                  fontWeight: isSelected ? FontWeight.w700 : null,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
