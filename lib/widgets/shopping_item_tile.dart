import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme/app_icons.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../utils/quantity_format.dart';

/// One row of the shopping list: a check control, the item, and its amount.
///
/// The whole row is the tap target, not just the box. This is used one-handed
/// while pushing a trolley, so the hit area is the full width rather than a
/// 24-pixel square.
///
/// A ticked row is dimmed and struck through rather than removed or moved.
/// Reordering the list under someone's thumb as they shop loses their place,
/// and hiding what is done makes it impossible to check whether something was
/// ticked by accident.
///
/// The ticked state is never carried by colour alone: the box fills and
/// gains a tick glyph, the text is struck through, and the row is announced
/// as a checkbox so assistive tech says "ticked" rather than leaving it to
/// the styling.
///
/// An item with no known quantity shows its name and nothing else. It is
/// never drawn as "0" and never hidden: PrepPick knows the household needs
/// chicken this week and does not know how much, and both halves of that are
/// worth saying.
class ShoppingItemTile extends StatelessWidget {
  const ShoppingItemTile({
    super.key,
    required this.item,
    this.onToggle,
    this.onDelete,
  });

  final ShoppingItem item;

  /// Called when the row is tapped. Null disables the row.
  final VoidCallback? onToggle;

  /// Offers a delete affordance when non-null. Only manual lines get one —
  /// a generated line would come straight back on the next regeneration.
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final isChecked = item.isChecked;
    final quantity = PrepQuantityFormat.label(item.quantity, item.unit);
    // Not textTertiary: at roughly 1.9:1 on the surface it is below any
    // readable threshold, and a ticked line still has to be legible enough to
    // check that nothing was ticked by mistake. The strikethrough and the
    // filled box carry the state; the dimming only supports them.
    final nameColor = isChecked
        ? AppColors.textSecondary
        : AppColors.textPrimary;

    return Material(
      color: AppColors.backgroundSurface,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.xs,
        ),
        child: Row(
          children: [
            // The row and the delete affordance are separate semantic nodes.
            // Wrapping the whole tile in one ExcludeSemantics would hide the
            // delete button from assistive tech entirely, leaving manual
            // items impossible to remove without sight.
            Expanded(
              child: Semantics(
                // Announced as a checkbox rather than a button, so assistive
                // tech says "ticked"/"not ticked" instead of leaving the
                // state to the label.
                checked: isChecked,
                button: false,
                enabled: onToggle != null,
                label: quantity == null ? item.name : '${item.name}, $quantity',
                child: ExcludeSemantics(
                  child: InkWell(
                    onTap: onToggle,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.md,
                      ),
                      child: Row(
                        children: [
                          _CheckBox(
                            isChecked: isChecked,
                            isEnabled: onToggle != null,
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Text(
                              item.name,
                              style: AppTypography.bodyLarge.copyWith(
                                color: nameColor,
                                decoration: isChecked
                                    ? TextDecoration.lineThrough
                                    : null,
                                decorationColor: AppColors.textSecondary,
                              ),
                            ),
                          ),
                          // Nothing is drawn at all when the amount is
                          // unknown; an em dash or a "0" would both read as
                          // information.
                          if (quantity != null) ...[
                            const SizedBox(width: AppSpacing.sm),
                            Text(
                              quantity,
                              style: AppTypography.labelLarge.copyWith(
                                color: AppColors.textSecondary,
                                decoration: isChecked
                                    ? TextDecoration.lineThrough
                                    : null,
                                decorationColor: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (onDelete != null)
              IconButton(
                onPressed: onDelete,
                // The label is on the icon rather than left to the tooltip:
                // a tooltip is exposed as a semantics *tooltip*, which not
                // every screen reader reads out for an icon-only control.
                icon: Icon(
                  AppIcons.closeRounded,
                  size: 18,
                  semanticLabel: 'Remove ${item.name}',
                ),
                color: AppColors.textSecondary,
                tooltip: 'Remove ${item.name}',
                // A 40-square target rather than the Material 48: the row is
                // only 56 tall and a 48 button would crowd the name. Kept
                // well clear of the row's own tap area, which is what a
                // mis-tap here would otherwise hit.
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                padding: EdgeInsets.zero,
              ),
          ],
        ),
      ),
    );
  }
}

/// The tick box. Hand-drawn rather than a [Checkbox] so the filled state uses
/// the PrepPick action green exactly and the size matches the design.
class _CheckBox extends StatelessWidget {
  const _CheckBox({required this.isChecked, required this.isEnabled});

  final bool isChecked;
  final bool isEnabled;

  static const double _size = 24;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _size,
      height: _size,
      decoration: BoxDecoration(
        color: isChecked ? AppColors.actionPrimary : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(
          color: isChecked
              ? AppColors.actionPrimary
              : isEnabled
              ? AppColors.borderDefault
              : AppColors.borderSubtle,
          width: 1.5,
        ),
      ),
      child: isChecked
          ? const Icon(
              AppIcons.checkRounded,
              size: 16,
              color: AppColors.textInverse,
            )
          : null,
    );
  }
}
