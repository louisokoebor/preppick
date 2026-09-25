import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_radius.dart';
import 'app_spacing.dart';
import 'app_typography.dart';

/// Development-only gallery of every design token, for eyeballing the build
/// against Figma and for checking text scaling.
///
/// This is deliberately NOT registered in [AppRoutes] and must never be part of
/// final navigation. To view it, temporarily set it as `home:` in MaterialApp.
class ThemePreviewScreen extends StatelessWidget {
  const ThemePreviewScreen({super.key});

  static const _colors = <String, Color>{
    'background/app': AppColors.backgroundApp,
    'background/surface': AppColors.backgroundSurface,
    'background/muted': AppColors.backgroundMuted,
    'text/primary': AppColors.textPrimary,
    'text/secondary': AppColors.textSecondary,
    'text/tertiary': AppColors.textTertiary,
    'text/inverse': AppColors.textInverse,
    'border/default': AppColors.borderDefault,
    'border/subtle': AppColors.borderSubtle,
    'action/primary': AppColors.actionPrimary,
    'action/primary hover': AppColors.actionPrimaryHover,
    'action/primary pressed': AppColors.actionPrimaryPressed,
    'action/secondary': AppColors.actionSecondary,
    'category/breakfast': AppColors.categoryBreakfast,
    'category/lunch': AppColors.categoryLunch,
    'category/dinner': AppColors.categoryDinner,
    'category/shopping': AppColors.categoryShopping,
    'state/warning': AppColors.stateWarning,
    'state/error': AppColors.stateError,
  };

  static const _spacing = <String, double>{
    'xs': AppSpacing.xs,
    'sm': AppSpacing.sm,
    'md': AppSpacing.md,
    'lg': AppSpacing.lg,
    'xl': AppSpacing.xl,
    'xxl': AppSpacing.xxl,
    'xxxl': AppSpacing.xxxl,
    'huge': AppSpacing.huge,
    'giant': AppSpacing.giant,
  };

  static const _radii = <String, double>{
    'sm': AppRadius.sm,
    'md': AppRadius.md,
    'lg': AppRadius.lg,
    'xl': AppRadius.xl,
    'xxl': AppRadius.xxl,
    'full': AppRadius.full,
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Theme preview')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          _section('Typography'),
          ..._typeSpecimens(),
          const SizedBox(height: AppSpacing.xxxl),
          _section('Colour'),
          ..._colors.entries.map(_swatch),
          const SizedBox(height: AppSpacing.xxxl),
          _section('Spacing'),
          ..._spacing.entries.map(_spacingBar),
          const SizedBox(height: AppSpacing.xxxl),
          _section('Radius'),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.md,
            children: _radii.entries.map(_radiusTile).toList(),
          ),
          const SizedBox(height: AppSpacing.xxxl),
          _section('Components'),
          ElevatedButton(onPressed: () {}, child: const Text('Primary action')),
          const SizedBox(height: AppSpacing.md),
          const ElevatedButton(onPressed: null, child: Text('Disabled action')),
          const SizedBox(height: AppSpacing.md),
          const TextField(
            decoration: InputDecoration(hintText: 'Search recipes'),
          ),
          const SizedBox(height: AppSpacing.giant),
        ],
      ),
    );
  }

  Widget _section(String label) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.md),
    child: Text(label, style: AppTypography.headingH2),
  );

  List<Widget> _typeSpecimens() {
    // Listed explicitly so the order matches the Figma type ramp.
    final ramp = <(String, TextStyle)>[
      ('Display Large 32/38', AppTypography.displayLarge),
      ('Heading H1 28/34', AppTypography.headingH1),
      ('Heading H2 24/30', AppTypography.headingH2),
      ('Heading H3 20/26', AppTypography.headingH3),
      ('Title Large 18/24', AppTypography.titleLarge),
      ('Title Medium 16/22', AppTypography.titleMedium),
      ('Body Large 16/24', AppTypography.bodyLarge),
      ('Body Medium 14/20', AppTypography.bodyMedium),
      ('Body Small 12/18', AppTypography.bodySmall),
      ('Label Large 14/20', AppTypography.labelLarge),
      ('Label Medium 12/16', AppTypography.labelMedium),
      ('Caption 11/16', AppTypography.caption),
    ];
    return [
      for (final (label, style) in ramp)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Text(label, style: style),
        ),
    ];
  }

  Widget _swatch(MapEntry<String, Color> entry) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          Container(
            width: AppSpacing.huge,
            height: AppSpacing.huge,
            decoration: BoxDecoration(
              color: entry.value,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: AppColors.borderDefault),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: Text(entry.key, style: AppTypography.bodyMedium)),
          Text(
            '#${entry.value.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
            style: AppTypography.labelMedium.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _spacingBar(MapEntry<String, double> entry) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(
              '${entry.key} · ${entry.value.toInt()}',
              style: AppTypography.labelMedium,
            ),
          ),
          Container(
            width: entry.value,
            height: AppSpacing.lg,
            color: AppColors.actionPrimary,
          ),
        ],
      ),
    );
  }

  Widget _radiusTile(MapEntry<String, double> entry) {
    return Container(
      width: 88,
      height: 64,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.actionSecondary,
        borderRadius: BorderRadius.circular(entry.value),
        border: Border.all(color: AppColors.borderDefault),
      ),
      child: Text(
        '${entry.key} · ${entry.value.toInt()}',
        style: AppTypography.labelMedium,
      ),
    );
  }
}
