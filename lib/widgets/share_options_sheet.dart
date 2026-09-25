import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

enum ShareOption { message, pdf }

/// The small choice sheet shared by the shopping list and meal plan.
class ShareOptionsSheet {
  const ShareOptionsSheet._();

  static Future<ShareOption?> show(
    BuildContext context, {
    required String title,
  }) {
    return showModalBottomSheet<ShareOption>(
      context: context,
      showDragHandle: true,
      backgroundColor: AppColors.backgroundSurface,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            0,
            AppSpacing.xl,
            AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTypography.headingH3),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Choose how you want to send it.',
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(AppIcons.contentCopyRounded),
                title: const Text('Share as message'),
                subtitle: const Text('Send a simple checklist in any app.'),
                onTap: () => Navigator.of(context).pop(ShareOption.message),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(AppIcons.fileTextRounded),
                title: const Text('Share / save PDF'),
                subtitle: const Text('Send it or save it to your device.'),
                onTap: () => Navigator.of(context).pop(ShareOption.pdf),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
