import 'package:flutter/material.dart';

import '../theme/app_icons.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// The fixed header region shared by the planner screens: an optional back
/// affordance, a title, and a supporting line.
///
/// A plain widget rather than an [AppBar] because the design's header sits in
/// the page background with page padding, not in a Material surface with its
/// own elevation and toolbar metrics.
class PrepHeader extends StatelessWidget {
  const PrepHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.onBack,
    this.trailing,
  });

  final String title;

  /// Supporting line under the title. Omitted when null.
  final String? subtitle;

  /// Shows a back button when non-null.
  final VoidCallback? onBack;

  /// Optional action drawn at the end of the title row.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.sm,
        AppSpacing.xl,
        AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (onBack != null) ...[
                IconButton(
                  onPressed: onBack,
                  icon: const Icon(
                    AppIcons.arrowBackRounded,
                    semanticLabel: 'Back',
                  ),
                  color: AppColors.textPrimary,
                  tooltip: 'Back',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 40,
                    minHeight: 40,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                  child: Text(title, style: AppTypography.headingH1),
                ),
              ),
              ?trailing,
            ],
          ),
          if (subtitle != null)
            Text(
              subtitle!,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
        ],
      ),
    );
  }
}
