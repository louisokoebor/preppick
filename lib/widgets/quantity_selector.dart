import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// The PrepPick stepper: a minus button, the value, and a plus button in a
/// bordered pill.
///
/// Matches the "Meal Quantity Selector" component in Figma: the plus is the
/// solid primary action and the minus is a muted secondary, because adding a
/// meal is the common move and removing one is the correction.
///
/// The bounds are enforced here rather than by the caller: at [min] the minus
/// button is disabled and at [max] the plus button is, so neither callback can
/// ever fire with an out-of-range value. That matters because 0 is a valid
/// meal count, and "minus at zero does nothing" must be visible, not silent.
/// The design does not draw a disabled state, so the two are given the
/// flattest treatment in the palette that still reads as "not available".
class QuantitySelector extends StatelessWidget {
  const QuantitySelector({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 99,
    this.semanticLabel,
  }) : assert(min <= max, 'min must not exceed max');

  final int value;

  /// Called with the new value. Null disables the whole control.
  final ValueChanged<int>? onChanged;
  final int min;
  final int max;

  /// What is being counted, e.g. "Breakfast". Read out by screen readers
  /// alongside the value, since the bare number means nothing on its own.
  final String? semanticLabel;

  /// Diameter of the drawn circle for each step button, per the Figma
  /// component.
  static const double buttonSize = 32;

  /// The tap target around that circle. Figma draws a 32 circle, which is
  /// under any practical minimum for a thumb; the circle keeps its size and
  /// the hit area is grown around it instead, so the control matches the
  /// design and is still reliably tappable.
  static const double tapTargetSize = 44;

  bool get _canDecrement => onChanged != null && value > min;
  bool get _canIncrement => onChanged != null && value < max;

  @override
  Widget build(BuildContext context) {
    final label = semanticLabel;

    return Semantics(
      container: true,
      label: label,
      value: '$value',
      // Lets assistive tech step the value without hunting for the buttons.
      increasedValue: _canIncrement ? '${value + 1}' : null,
      decreasedValue: _canDecrement ? '${value - 1}' : null,
      onIncrease: _canIncrement ? () => onChanged!(value + 1) : null,
      onDecrease: _canDecrement ? () => onChanged!(value - 1) : null,
      child: Container(
        // The 44 tap targets already supply most of the inset the 8 padding
        // gave the 32 circles, so the pill keeps its drawn 48 height.
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: 2,
        ),
        decoration: BoxDecoration(
          color: AppColors.backgroundSurface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.borderSubtle),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _StepButton(
              // U+2212 minus sign, as drawn in Figma — not a hyphen.
              glyph: '−',
              tooltip: label == null ? 'Decrease' : 'Decrease $label',
              isPrimary: false,
              onPressed: _canDecrement ? () => onChanged!(value - 1) : null,
            ),
            ConstrainedBox(
              // Wide enough that 0 and 10 do not shift the buttons around,
              // but free to grow when text is scaled up.
              constraints: const BoxConstraints(minWidth: 24),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                // The number is already announced as this control's semantic
                // value; letting the Text speak too reads it out twice.
                child: ExcludeSemantics(
                  child: Text(
                    '$value',
                    textAlign: TextAlign.center,
                    style: AppTypography.titleMedium,
                  ),
                ),
              ),
            ),
            _StepButton(
              glyph: '+',
              tooltip: label == null ? 'Increase' : 'Increase $label',
              isPrimary: true,
              onPressed: _canIncrement ? () => onChanged!(value + 1) : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// One circular step button. Private: the stepper is the public unit.
class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.glyph,
    required this.tooltip,
    required this.isPrimary,
    required this.onPressed,
  });

  final String glyph;
  final String tooltip;

  /// The plus button is solid green; the minus is muted.
  final bool isPrimary;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;

    final background = switch ((isPrimary, enabled)) {
      (true, true) => AppColors.actionPrimary,
      (false, true) => AppColors.backgroundMuted,
      (_, false) => AppColors.borderSubtle,
    };
    final foreground = switch ((isPrimary, enabled)) {
      (true, true) => AppColors.textInverse,
      (false, true) => AppColors.textSecondary,
      (_, false) => AppColors.textTertiary,
    };

    return ExcludeSemantics(
      child: Tooltip(
        message: tooltip,
        // The tap target is the outer box; the circle drawn inside it is the
        // Figma size. Splitting the two is what lets the control stay on
        // design without shrinking the hit area to 32 square.
        child: SizedBox(
          height: QuantitySelector.tapTargetSize,
          width: QuantitySelector.tapTargetSize,
          child: Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            child: InkWell(
              onTap: onPressed,
              customBorder: const CircleBorder(),
              child: Center(
                child: Container(
                  height: QuantitySelector.buttonSize,
                  width: QuantitySelector.buttonSize,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: background,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    glyph,
                    style: AppTypography.labelMedium.copyWith(
                      color: foreground,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
