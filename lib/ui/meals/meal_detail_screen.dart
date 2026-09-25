import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/routes.dart';
import '../../models/models.dart';
import '../../providers/meal_provider.dart';
import '../../services/meal_service.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../../utils/duration_format.dart';
import '../../widgets/prep_loading.dart';
import '../../widgets/category_badge.dart';
import '../../widgets/prep_button.dart';
import '../../widgets/prep_header.dart';

/// Read-only view of one meal in the household library.
class MealDetailScreen extends StatefulWidget {
  const MealDetailScreen({super.key, required this.mealId});

  final String mealId;

  @override
  State<MealDetailScreen> createState() => _MealDetailScreenState();
}

class _MealDetailScreenState extends State<MealDetailScreen> {
  late Future<MealDetail?> _detail;

  @override
  void initState() {
    super.initState();
    _detail = context.read<MealProvider>().getDetail(widget.mealId);
  }

  Future<void> _edit() async {
    final changed = await Navigator.of(
      context,
    ).pushNamed(AppRoutes.editMeal, arguments: widget.mealId);
    if (!mounted) return;
    if (changed == true) {
      setState(() {
        _detail = context.read<MealProvider>().getDetail(widget.mealId);
      });
    }
  }

  Future<void> _remove(MealDetail detail) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove this meal?'),
        content: const Text(
          'This removes the meal from your library. Existing plan history '
          'is kept safely by archiving it when needed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.stateError),
            child: const Text('Delete meal'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      final result = await context.read<MealProvider>().removeMeal(
        detail.meal.id,
      );
      if (!mounted) return;
      final message = result == MealRemoval.archived
          ? 'Meal archived; plan history was kept.'
          : 'Meal deleted.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The meal could not be removed.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: FutureBuilder<MealDetail?>(
          future: _detail,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const PrepLoading(message: 'Loading this meal');
            }
            // A thrown error and a null result are different facts: one is
            // a read that failed and can be retried, the other is a meal that
            // is genuinely gone. Collapsing them tells someone their meal was
            // deleted when the database merely hiccuped.
            if (snapshot.hasError) {
              return _DetailLoadFailed(
                onBack: () => Navigator.of(context).pop(),
                onRetry: () => setState(() {
                  _detail = context.read<MealProvider>().getDetail(
                    widget.mealId,
                  );
                }),
              );
            }
            if (snapshot.data == null) {
              return _MissingMeal(onBack: () => Navigator.of(context).pop());
            }
            return _Content(
              detail: snapshot.data!,
              onBack: () => Navigator.of(context).pop(),
              onEdit: _edit,
              onRemove: () => _remove(snapshot.data!),
            );
          },
        ),
      ),
    );
  }
}

class _Content extends StatelessWidget {
  const _Content({
    required this.detail,
    required this.onBack,
    required this.onEdit,
    required this.onRemove,
  });

  final MealDetail detail;
  final VoidCallback onBack;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final type = detail.family.mealType;
    return Column(
      children: [
        PrepHeader(
          title: detail.meal.name,
          onBack: onBack,
          trailing: IconButton(
            onPressed: onRemove,
            tooltip: 'Delete meal',
            icon: const Icon(
              AppIcons.deleteOutlineRounded,
              semanticLabel: 'Delete meal',
            ),
            color: AppColors.stateError,
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              0,
              AppSpacing.xl,
              AppSpacing.xxl,
            ),
            children: [
              _MealHero(detail: detail),
              const SizedBox(height: AppSpacing.xl),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  CategoryBadge(mealType: type),
                  if (detail.meal.protein?.trim().isNotEmpty ?? false)
                    _InfoPill(label: detail.meal.protein!),
                ],
              ),
              const SizedBox(height: AppSpacing.xxl),
              _CookTimeBlock(minutes: detail.meal.estimatedMinutes),
              const SizedBox(height: AppSpacing.xxl),
              Text('Ingredients', style: AppTypography.headingH2),
              const SizedBox(height: AppSpacing.md),
              if (detail.ingredients.isEmpty)
                const _EmptyIngredients()
              else
                _IngredientList(lines: detail.ingredients),
              const SizedBox(height: AppSpacing.xxl),
              PrepButton(
                label: 'Edit meal',
                icon: AppIcons.editOutlined,
                onPressed: onEdit,
              ),
              const SizedBox(height: AppSpacing.md),
              PrepButton(
                label: 'Delete meal',
                variant: PrepButtonVariant.tertiary,
                onPressed: onRemove,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CookTimeBlock extends StatelessWidget {
  const _CookTimeBlock({required this.minutes});

  final int? minutes;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.lg),
    decoration: BoxDecoration(
      color: AppColors.backgroundSurface,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      border: Border.all(color: AppColors.borderSubtle),
    ),
    child: Row(
      children: [
        const Icon(AppIcons.timerOutlined, color: AppColors.textSecondary),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Estimated cook time', style: AppTypography.labelMedium),
              const SizedBox(height: AppSpacing.xs),
              Text(
                PrepDurationFormat.optionalMinutes(minutes) ?? 'Not set',
                style: AppTypography.titleMedium,
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _MealHero extends StatelessWidget {
  const _MealHero({required this.detail});

  final MealDetail detail;

  @override
  Widget build(BuildContext context) {
    final familyIsDifferent =
        detail.family.name.trim().toLowerCase() !=
        detail.meal.name.trim().toLowerCase();
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: CategoryBadge.colorFor(detail.family.mealType),
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.backgroundSurface.withValues(alpha: .75),
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            child: Icon(
              CategoryBadge.iconFor(detail.family.mealType),
              color: AppColors.textSecondary,
              size: 28,
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Meal family', style: AppTypography.labelMedium),
                const SizedBox(height: AppSpacing.xs),
                Text(detail.family.name, style: AppTypography.titleLarge),
                if (familyIsDifferent) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Variant: ${detail.meal.name}',
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _IngredientList extends StatelessWidget {
  const _IngredientList({required this.lines});

  final List<MealRecipeLine> lines;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.backgroundSurface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        children: [
          for (var index = 0; index < lines.length; index++) ...[
            _IngredientTile(line: lines[index]),
            if (index < lines.length - 1) const Divider(height: 1),
          ],
        ],
      ),
    );
  }
}

class _IngredientTile extends StatelessWidget {
  const _IngredientTile({required this.line});

  final MealRecipeLine line;

  @override
  Widget build(BuildContext context) {
    final amount = line.quantity == null
        ? 'Amount not recorded'
        : '${_formatQuantity(line.quantity!)}${line.unit == null ? '' : ' ${line.unit}'}';
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(line.name, style: AppTypography.bodyLarge)),
          const SizedBox(width: AppSpacing.md),
          Flexible(
            child: Text(
              amount,
              textAlign: TextAlign.right,
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textSecondary,
                // "No quantity recorded" is the useful half of this line, so
                // it is set apart by style rather than by fading it below a
                // readable contrast.
                fontStyle: line.hasQuantity ? null : FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _formatQuantity(double quantity) =>
      quantity == quantity.roundToDouble()
      ? quantity.toInt().toString()
      : quantity.toString();
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.md,
      vertical: AppSpacing.xs,
    ),
    decoration: BoxDecoration(
      color: AppColors.backgroundMuted,
      borderRadius: BorderRadius.circular(AppRadius.full),
    ),
    child: Text(label, style: AppTypography.labelMedium),
  );
}

class _EmptyIngredients extends StatelessWidget {
  const _EmptyIngredients();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.xl),
    decoration: BoxDecoration(
      color: AppColors.backgroundMuted,
      borderRadius: BorderRadius.circular(AppRadius.lg),
    ),
    child: Text(
      'No ingredients added yet.',
      style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary),
    ),
  );
}

/// The read failed. Unlike a missing meal, this is worth retrying in place.
class _DetailLoadFailed extends StatelessWidget {
  const _DetailLoadFailed({required this.onBack, required this.onRetry});

  final VoidCallback onBack;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      PrepHeader(title: 'Meal', onBack: onBack),
      Expanded(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'This meal could not be loaded.',
                  key: const Key('mealDetailError'),
                  style: AppTypography.bodyLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.lg),
                PrepButton(
                  label: 'Try again',
                  variant: PrepButtonVariant.tertiary,
                  isFullWidth: false,
                  onPressed: onRetry,
                ),
              ],
            ),
          ),
        ),
      ),
    ],
  );
}

class _MissingMeal extends StatelessWidget {
  const _MissingMeal({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      PrepHeader(title: 'Meal not found', onBack: onBack),
      Expanded(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            child: Text(
              'This meal is no longer available.',
              style: AppTypography.bodyLarge,
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    ],
  );
}
