import 'package:flutter/material.dart';

import '../theme/app_icons.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// The rounded search field used wherever PrepPick filters a list of meals.
///
/// Stateless on purpose: the owning screen holds the controller, because the
/// query is screen state — the swap sheet needs to read it to filter, and the
/// Meal Library will need to keep it across rebuilds.
class PrepSearchInput extends StatelessWidget {
  const PrepSearchInput({
    super.key,
    required this.controller,
    this.hintText = 'Search',
    this.autofocus = false,
    this.onChanged,
  });

  final TextEditingController controller;
  final String hintText;
  final bool autofocus;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        return TextField(
          controller: controller,
          autofocus: autofocus,
          onChanged: onChanged,
          textInputAction: TextInputAction.search,
          style: AppTypography.bodyMedium,
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: AppTypography.bodyMedium.copyWith(
              color: AppColors.textSecondary,
            ),
            prefixIcon: const Icon(
              AppIcons.searchRounded,
              size: 20,
              color: AppColors.textSecondary,
            ),
            // Only offered once there is something to clear, so the field is
            // quiet at rest.
            suffixIcon: value.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(
                      AppIcons.closeRounded,
                      size: 18,
                      semanticLabel: 'Clear search',
                    ),
                    color: AppColors.textSecondary,
                    tooltip: 'Clear search',
                    onPressed: () {
                      controller.clear();
                      onChanged?.call('');
                    },
                  ),
            filled: true,
            fillColor: AppColors.backgroundMuted,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.full),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.full),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.full),
              borderSide: const BorderSide(color: AppColors.actionPrimary),
            ),
          ),
        );
      },
    );
  }
}
