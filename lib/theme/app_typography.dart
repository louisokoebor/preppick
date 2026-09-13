import 'package:flutter/material.dart';

import 'app_colors.dart';

/// PrepPick typography tokens.
///
/// The design system uses Manrope. The font is bundled in `assets/fonts` at the
/// three weights this scale uses (400 Regular, 500 Medium, 600 SemiBold), so it
/// renders offline with no network fetch. Every style below reads [fontFamily];
/// no other font is substituted.
class AppTypography {
  const AppTypography._();

  static const String fontFamily = 'Manrope';

  static TextStyle _style({
    required double size,
    required double height,
    required FontWeight weight,
  }) {
    return TextStyle(
      fontFamily: fontFamily,
      fontSize: size,
      // Figma line heights are absolute pixels; Flutter expects a multiplier.
      height: height / size,
      fontWeight: weight,
      color: AppColors.textPrimary,
    );
  }

  static final displayLarge =
      _style(size: 32, height: 38, weight: FontWeight.w600);
  static final headingH1 = _style(size: 28, height: 34, weight: FontWeight.w600);
  static final headingH2 = _style(size: 24, height: 30, weight: FontWeight.w600);
  static final headingH3 = _style(size: 20, height: 26, weight: FontWeight.w600);
  static final titleLarge = _style(size: 18, height: 24, weight: FontWeight.w600);
  static final titleMedium =
      _style(size: 16, height: 22, weight: FontWeight.w600);
  static final bodyLarge = _style(size: 16, height: 24, weight: FontWeight.w400);
  static final bodyMedium = _style(size: 14, height: 20, weight: FontWeight.w400);
  static final bodySmall = _style(size: 12, height: 18, weight: FontWeight.w400);
  static final labelLarge = _style(size: 14, height: 20, weight: FontWeight.w500);
  static final labelMedium =
      _style(size: 12, height: 16, weight: FontWeight.w500);
  static final caption = _style(size: 11, height: 16, weight: FontWeight.w400);

  static TextTheme get textTheme => TextTheme(
        displayLarge: displayLarge,
        headlineLarge: headingH1,
        headlineMedium: headingH2,
        headlineSmall: headingH3,
        titleLarge: titleLarge,
        titleMedium: titleMedium,
        bodyLarge: bodyLarge,
        bodyMedium: bodyMedium,
        bodySmall: bodySmall,
        labelLarge: labelLarge,
        labelMedium: labelMedium,
        labelSmall: caption,
      );
}
