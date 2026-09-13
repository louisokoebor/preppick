import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:preppick/theme/app_colors.dart';
import 'package:preppick/theme/app_radius.dart';
import 'package:preppick/theme/app_spacing.dart';
import 'package:preppick/theme/app_theme.dart';
import 'package:preppick/theme/app_typography.dart';

void main() {
  group('AppColors', () {
    test('background tokens match Figma', () {
      expect(AppColors.backgroundApp, const Color(0xFFF8F7F3));
      expect(AppColors.backgroundSurface, const Color(0xFFFFFFFF));
      expect(AppColors.backgroundMuted, const Color(0xFFF0F1EE));
    });

    test('text tokens match Figma', () {
      expect(AppColors.textPrimary, const Color(0xFF171A16));
      expect(AppColors.textSecondary, const Color(0xFF6E746D));
      expect(AppColors.textTertiary, const Color(0xFFB9BDB7));
      expect(AppColors.textInverse, const Color(0xFFFFFFFF));
    });

    test('border tokens match Figma', () {
      expect(AppColors.borderDefault, const Color(0xFFB9BDB7));
      expect(AppColors.borderSubtle, const Color(0xFFF0F1EE));
    });

    test('action tokens match Figma', () {
      expect(AppColors.actionPrimary, const Color(0xFF1E9A5A));
      expect(AppColors.actionPrimaryHover, const Color(0xFF36A86D));
      expect(AppColors.actionPrimaryPressed, const Color(0xFF147A45));
      expect(AppColors.actionSecondary, const Color(0xFFE6F4EC));
    });

    test('category tokens match Figma', () {
      expect(AppColors.categoryBreakfast, const Color(0xFFFFF0DC));
      expect(AppColors.categoryLunch, const Color(0xFFE6F4EC));
      expect(AppColors.categoryDinner, const Color(0xFFEFECFF));
      expect(AppColors.categoryShopping, const Color(0xFFFDEBE8));
    });

    test('state tokens match Figma', () {
      expect(AppColors.stateWarning, const Color(0xFFE99A43));
      expect(AppColors.stateError, const Color(0xFFD96555));
    });
  });

  test('AppSpacing exposes the full scale', () {
    expect(
      [
        AppSpacing.xs,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.xl,
        AppSpacing.xxl,
        AppSpacing.xxxl,
        AppSpacing.huge,
        AppSpacing.giant,
      ],
      [4, 8, 12, 16, 20, 24, 32, 40, 48],
    );
  });

  test('AppRadius exposes the full scale', () {
    expect(
      [
        AppRadius.sm,
        AppRadius.md,
        AppRadius.lg,
        AppRadius.xl,
        AppRadius.xxl,
        AppRadius.full,
      ],
      [8, 12, 16, 20, 24, 999],
    );
  });

  group('AppTypography', () {
    test('display large is 32/38 semibold', () {
      expect(AppTypography.displayLarge.fontSize, 32);
      expect(AppTypography.displayLarge.height, 38 / 32);
      expect(AppTypography.displayLarge.fontWeight, FontWeight.w600);
    });

    test('body medium is 14/20 regular', () {
      expect(AppTypography.bodyMedium.fontSize, 14);
      expect(AppTypography.bodyMedium.height, 20 / 14);
      expect(AppTypography.bodyMedium.fontWeight, FontWeight.w400);
    });

    test('caption is 11/16 regular', () {
      expect(AppTypography.caption.fontSize, 11);
      expect(AppTypography.caption.height, 16 / 11);
      expect(AppTypography.caption.fontWeight, FontWeight.w400);
    });

    test('label large is 14/20 medium', () {
      expect(AppTypography.labelLarge.fontSize, 14);
      expect(AppTypography.labelLarge.fontWeight, FontWeight.w500);
    });

    test('no font family is substituted until DM Sans is bundled', () {
      expect(AppTypography.fontFamily, isNull);
    });
  });

  group('AppTheme', () {
    test('wires tokens into ThemeData', () {
      final theme = AppTheme.light;
      expect(theme.scaffoldBackgroundColor, AppColors.backgroundApp);
      expect(theme.colorScheme.primary, AppColors.actionPrimary);
      expect(theme.colorScheme.error, AppColors.stateError);
      expect(theme.textTheme.bodyMedium?.fontSize, 14);
    });

    testWidgets('MaterialApp builds with AppTheme', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(body: Text('token smoke test')),
        ),
      );

      expect(find.text('token smoke test'), findsOneWidget);
    });
  });
}
