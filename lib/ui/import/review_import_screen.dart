import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/routes.dart';
import '../../models/models.dart';
import '../../providers/import_provider.dart';
import '../../providers/meal_provider.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../../utils/error_messages.dart';
import '../../widgets/category_badge.dart';
import '../../widgets/prep_button.dart';
import '../../widgets/prep_header.dart';

class ReviewImportScreen extends StatelessWidget {
  const ReviewImportScreen({super.key, this.onConfirmed});

  final VoidCallback? onConfirmed;

  Future<void> _confirm(BuildContext context) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final importProvider = context.read<ImportProvider>();
    final created = await importProvider.confirmImport();
    if (!context.mounted) return;
    if (created > 0) {
      await context.read<MealProvider>().refresh();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Imported $created ${created == 1 ? 'meal' : 'meals'}'),
        ),
      );
      final onConfirmed = this.onConfirmed;
      if (onConfirmed != null) onConfirmed();
    } else if (!importProvider.hasConfirmableCandidates) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This import has already been confirmed.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ImportProvider>();
    final selectedCount = provider.includedCandidates.length;
    final error = PrepErrorMessages.forError(
      provider.error,
      fallback: 'Your meals could not be saved. Please try again.',
    );

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            PrepHeader(
              title: 'Review import',
              subtitle:
                  'Check each detected meal before saving it to your library.',
              onBack: () => Navigator.of(context).pop(),
            ),
            Expanded(
              child: provider.hasCandidates
                  ? ListView.separated(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.xl,
                        0,
                        AppSpacing.xl,
                        AppSpacing.xxl,
                      ),
                      itemCount: provider.candidates.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: AppSpacing.md),
                      itemBuilder: (context, index) {
                        final candidate = provider.candidates[index];
                        return _CandidateCard(candidate: candidate);
                      },
                    )
                  : _NoCandidates(
                      onPasteAgain: () => Navigator.of(context).pop(),
                    ),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  0,
                  AppSpacing.xl,
                  AppSpacing.sm,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    error,
                    key: const Key('reviewImportErrorText'),
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.stateError,
                    ),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.sm,
                AppSpacing.xl,
                AppSpacing.xl,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '$selectedCount selected',
                    style: AppTypography.labelMedium.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  if (provider.hasSelectedCandidateWithoutType)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.xs),
                      child: Text(
                        'Assign a meal type to every selected meal.',
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.stateWarning,
                        ),
                      ),
                    ),
                  const SizedBox(height: AppSpacing.md),
                  PrepButton(
                    label: 'Confirm import',
                    icon: AppIcons.checkRounded,
                    isBusy: provider.isConfirming,
                    onPressed: provider.canConfirm
                        ? () => _confirm(context)
                        : null,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  PrepButton(
                    label: 'Back to paste',
                    variant: PrepButtonVariant.tertiary,
                    onPressed: provider.isConfirming
                        ? null
                        : () {
                            final navigator = Navigator.of(context);
                            if (navigator.canPop()) {
                              navigator.pop();
                            } else {
                              navigator.pushReplacementNamed(
                                AppRoutes.importHistory,
                              );
                            }
                          },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CandidateCard extends StatelessWidget {
  const _CandidateCard({required this.candidate});

  final ImportedMealCandidate candidate;

  @override
  Widget build(BuildContext context) {
    final provider = context.read<ImportProvider>();
    final isDisabled = candidate.isConfirmed;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.backgroundSurface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CheckboxListTile(
              key: Key('includeCandidate-${candidate.id}'),
              value: candidate.isIncluded,
              onChanged: isDisabled
                  ? null
                  : (value) =>
                        provider.includeCandidate(candidate.id, value ?? false),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(
                candidate.isIncluded ? 'Include' : 'Excluded',
                style: AppTypography.labelLarge,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextFormField(
              key: Key('candidateName-${candidate.id}'),
              initialValue: candidate.name,
              enabled: !isDisabled && candidate.isIncluded,
              decoration: _decoration('Meal name'),
              textCapitalization: TextCapitalization.words,
              onChanged: (value) =>
                  provider.renameCandidate(candidate.id, value),
            ),
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<MealType>(
              key: Key('candidateMealType-${candidate.id}'),
              initialValue: candidate.mealType,
              decoration: _decoration('Meal type'),
              hint: const Text('Choose type'),
              items: [
                for (final type in MealType.values)
                  DropdownMenuItem(
                    value: type,
                    child: Row(
                      children: [
                        Icon(CategoryBadge.iconFor(type), size: 18),
                        const SizedBox(width: AppSpacing.sm),
                        Text(CategoryBadge.nameFor(type)),
                      ],
                    ),
                  ),
              ],
              onChanged: isDisabled || !candidate.isIncluded
                  ? null
                  : (type) => provider.assignMealType(candidate.id, type),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Source: ${candidate.originalText}',
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            if (candidate.isDuplicate || candidate.isAmbiguous || isDisabled)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    if (candidate.isDuplicate)
                      const _ReviewFlag(
                        label: 'Repeated name',
                        icon: AppIcons.contentCopyRounded,
                      ),
                    if (candidate.isAmbiguous)
                      const _ReviewFlag(
                        label: 'Needs review',
                        icon: AppIcons.infoOutlineRounded,
                      ),
                    if (isDisabled)
                      const _ReviewFlag(
                        label: 'Imported',
                        icon: AppIcons.checkCircleOutlineRounded,
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  InputDecoration _decoration(String label) => InputDecoration(
    labelText: label,
    filled: true,
    fillColor: AppColors.backgroundApp,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.md),
      borderSide: const BorderSide(color: AppColors.borderSubtle),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.md),
      borderSide: const BorderSide(color: AppColors.borderSubtle),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.md),
      borderSide: const BorderSide(color: AppColors.actionPrimary),
    ),
  );
}

class _ReviewFlag extends StatelessWidget {
  const _ReviewFlag({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.backgroundMuted,
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.textSecondary),
          const SizedBox(width: AppSpacing.xs),
          Text(
            label,
            style: AppTypography.labelMedium.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _NoCandidates extends StatelessWidget {
  const _NoCandidates({required this.onPasteAgain});

  final VoidCallback onPasteAgain;

  @override
  Widget build(BuildContext context) {
    // Scrollable rather than a bare centred Column: on a 568-tall phone at a
    // 1.5 text scale the message and its action are taller than the space
    // left between the header and the nav bar, and an empty state that
    // overflows is the one screen state nobody can work around.
    return SingleChildScrollView(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                AppIcons.playlistRemoveRounded,
                size: 40,
                color: AppColors.textTertiary,
              ),
              const SizedBox(height: AppSpacing.md),
              Text('No meals detected', style: AppTypography.titleLarge),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Try pasting one meal per line.',
                textAlign: TextAlign.center,
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              PrepButton(
                label: 'Paste again',
                variant: PrepButtonVariant.secondary,
                onPressed: onPasteAgain,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
