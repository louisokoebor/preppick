import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../utils/week_range_format.dart';

/// One previous week on the Past Shopping Lists screen: the week, how big
/// the list was, and how much of it was ticked off.
class ShoppingWeekCard extends StatelessWidget {
  const ShoppingWeekCard({
    super.key,
    required this.weekStart,
    required this.itemCount,
    required this.checkedCount,
    required this.onTap,
  });

  final DateTime weekStart;
  final int itemCount;
  final int checkedCount;
  final VoidCallback onTap;

  String get _itemsLabel => itemCount == 1 ? '1 item' : '$itemCount items';

  String get _tickedLabel {
    if (checkedCount == 0) return 'Nothing ticked off';
    if (checkedCount == itemCount) return 'All ticked off';
    return '$checkedCount ticked off';
  }

  @override
  Widget build(BuildContext context) {
    final label = PrepWeekRange.label(weekStart);

    return Semantics(
      button: true,
      label: '$label, $_itemsLabel, $_tickedLabel',
      child: ExcludeSemantics(
        child: Material(
          color: AppColors.backgroundSurface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.categoryShopping,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: const Icon(
                      AppIcons.shoppingBasketOutlined,
                      size: 20,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(label, style: AppTypography.titleMedium),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          '$_itemsLabel · $_tickedLabel',
                          style: AppTypography.labelMedium.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    AppIcons.chevronRightRounded,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
