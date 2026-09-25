import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// Visual weight of a [PrepButton].
enum PrepButtonVariant {
  /// Solid green. One per screen — the action the screen exists for.
  primary,

  /// Tinted green on a pale fill. Supporting actions such as Regenerate.
  secondary,

  /// Outlined on the app background. Low-emphasis actions.
  tertiary,
}

/// The PrepPick button.
///
/// Every screen uses this rather than styling an [ElevatedButton] locally, so
/// height, radius and the busy state stay identical across the app. The
/// primary variant matches the Figma "Button" component: 48 high, 16 radius,
/// a Label/Large caption on solid green.
///
/// Passing [isBusy] disables the button and swaps the label for a spinner
/// while keeping the button's width, so a slow save cannot be double-tapped
/// and the layout does not jump.
class PrepButton extends StatelessWidget {
  const PrepButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = PrepButtonVariant.primary,
    this.isBusy = false,
    this.isFullWidth = true,
    this.icon,
    this.iconAfterLabel = false,
  });

  final String label;

  /// Null disables the button.
  final VoidCallback? onPressed;
  final PrepButtonVariant variant;
  final bool isBusy;
  final bool isFullWidth;
  final IconData? icon;

  /// Puts [icon] after the label instead of before it.
  final bool iconAfterLabel;

  /// Button height in the design system. A minimum rather than a fixed
  /// height, so a wrapped label at a large text scale can grow past it.
  static const double _minHeight = 48;

  bool get _isEnabled => onPressed != null && !isBusy;

  @override
  Widget build(BuildContext context) {
    final style = ButtonStyle(
      backgroundColor: WidgetStateProperty.resolveWith(_background),
      foregroundColor: WidgetStateProperty.resolveWith(_foreground),
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      elevation: const WidgetStatePropertyAll(0),
      shadowColor: const WidgetStatePropertyAll(Colors.transparent),
      side: WidgetStateProperty.resolveWith(_side),
      textStyle: WidgetStatePropertyAll(AppTypography.labelLarge),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: 14),
      ),
      // A minimum rather than a fixed height: the label must be allowed to
      // wrap and grow when the user scales text up.
      minimumSize: WidgetStatePropertyAll(
        isFullWidth
            ? const Size(double.infinity, _minHeight)
            : const Size(0, _minHeight),
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
      ),
    );

    return Semantics(
      button: true,
      enabled: _isEnabled,
      // While busy the spinner replaces the label on screen, so the label has
      // to carry the state instead — otherwise the button silently stops
      // responding with no announcement of why.
      liveRegion: isBusy,
      label: isBusy ? '$label, in progress' : label,
      child: ExcludeSemantics(
        child: TextButton(
          onPressed: _isEnabled ? onPressed : null,
          style: style,
          child: isBusy ? _busyIndicator() : _label(),
        ),
      ),
    );
  }

  Widget _label() {
    final text = Flexible(child: Text(label, textAlign: TextAlign.center));
    if (icon == null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [text],
      );
    }
    final glyph = Icon(icon, size: 18);
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: iconAfterLabel
          ? [text, const SizedBox(width: AppSpacing.sm), glyph]
          : [glyph, const SizedBox(width: AppSpacing.sm), text],
    );
  }

  Widget _busyIndicator() => SizedBox(
    height: 20,
    width: 20,
    child: CircularProgressIndicator(
      strokeWidth: 2,
      valueColor: AlwaysStoppedAnimation(_foreground(const <WidgetState>{})),
    ),
  );

  // A busy button is disabled to Flutter but must not *look* disabled: it is
  // mid-action, not unavailable, so it keeps its enabled colours and only the
  // label is replaced by the spinner.
  bool _looksDisabled(Set<WidgetState> states) =>
      !isBusy && states.contains(WidgetState.disabled);

  Color _background(Set<WidgetState> states) {
    if (_looksDisabled(states)) {
      return switch (variant) {
        PrepButtonVariant.primary => AppColors.backgroundMuted,
        PrepButtonVariant.secondary => AppColors.backgroundMuted,
        PrepButtonVariant.tertiary => Colors.transparent,
      };
    }
    final pressed = states.contains(WidgetState.pressed);
    return switch (variant) {
      PrepButtonVariant.primary =>
        pressed ? AppColors.actionPrimaryPressed : AppColors.actionPrimary,
      PrepButtonVariant.secondary => AppColors.actionSecondary,
      PrepButtonVariant.tertiary =>
        pressed ? AppColors.backgroundMuted : Colors.transparent,
    };
  }

  Color _foreground(Set<WidgetState> states) {
    if (_looksDisabled(states)) return AppColors.textTertiary;
    return switch (variant) {
      PrepButtonVariant.primary => AppColors.textInverse,
      PrepButtonVariant.secondary => AppColors.actionPrimaryPressed,
      PrepButtonVariant.tertiary => AppColors.textPrimary,
    };
  }

  BorderSide? _side(Set<WidgetState> states) {
    if (variant != PrepButtonVariant.tertiary) return BorderSide.none;
    return BorderSide(
      color: _looksDisabled(states)
          ? AppColors.borderSubtle
          : AppColors.borderDefault,
    );
  }
}
