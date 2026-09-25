import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// A centred spinner with a line saying what is being waited for.
///
/// A bare [CircularProgressIndicator] is a blank screen to a screen reader
/// and very nearly one to everybody else: it says something is happening but
/// not what, and PrepPick's waits are meaningfully different — reading the
/// library, generating a week, building a shopping list. The message is
/// required rather than optional so a new screen cannot quietly fall back to
/// an unlabelled spinner.
class PrepLoading extends StatelessWidget {
  const PrepLoading({super.key, required this.message});

  /// What the app is doing, e.g. "Loading your meals".
  final String message;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      // Announced as a live region so assistive tech reads the message when
      // the spinner appears rather than only when it is focused.
      liveRegion: true,
      label: message,
      child: ExcludeSemantics(
        // Scrollable and centred rather than a bare Column: this is shown in
        // route transitions and in short panes, where the box it is given can
        // briefly be only a few pixels tall, and a plain Column overflows
        // there. It also keeps the message readable at a large text scale.
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              // Centred in the space it is given, but never taller than it:
              // in a full pane the spinner sits in the middle, and in a
              // few-pixel box mid-transition it scrolls instead of
              // overflowing.
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight.isFinite
                    ? constraints.maxHeight
                    : 0,
              ),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        height: 28,
                        width: 28,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          valueColor: AlwaysStoppedAnimation(
                            AppColors.actionPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        message,
                        textAlign: TextAlign.center,
                        style: AppTypography.bodyMedium.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
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
