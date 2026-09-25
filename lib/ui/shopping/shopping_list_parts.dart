import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../services/shopping_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../../utils/category_labels.dart';
import '../../widgets/prep_button.dart';
import '../../widgets/shopping_item_tile.dart';

/// Pieces shared by the current week's shopping list and the read-only view
/// of a previous week, so both draw an aisle the same way.

/// One aisle: its name, how much of it is done, and its lines.
class ShoppingCategorySection extends StatelessWidget {
  const ShoppingCategorySection({
    super.key,
    required this.group,
    this.onToggle,
    this.onDelete,
    this.isBusy = false,
  });

  final ShoppingCategoryGroup group;

  /// Ticks a line. Null draws the section read-only, as a past week is.
  final void Function(ShoppingItem)? onToggle;

  /// Removes a manual line. Null offers no delete at all.
  final void Function(ShoppingItem)? onDelete;

  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            left: AppSpacing.xs,
            bottom: AppSpacing.sm,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  PrepCategoryLabels.labelFor(group.category),
                  style: AppTypography.titleMedium.copyWith(
                    // A completed aisle is dimmed to secondary, not
                    // tertiary: the count beside it already says 4/4, and the
                    // heading still has to be findable at a glance.
                    color: group.isComplete
                        ? AppColors.textSecondary
                        : AppColors.textPrimary,
                  ),
                ),
              ),
              Text(
                '${group.checkedCount}/${group.items.length}',
                style: AppTypography.labelMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        for (final item in group.items) ...[
          ShoppingItemTile(
            item: item,
            onToggle: onToggle == null ? null : () => onToggle!(item),
            // Only a manual line can be removed. A generated one would come
            // straight back on the next regeneration, so offering a delete
            // would be a lie.
            onDelete: onDelete != null && item.isManual && !isBusy
                ? () => onDelete!(item)
                : null,
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ],
    );
  }
}

/// An explanatory panel for the states where there is no list to draw.
class ShoppingNotice extends StatelessWidget {
  const ShoppingNotice({
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
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Container(
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
                  AppIcons.shoppingBasketOutlined,
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
      ),
    );
  }
}
