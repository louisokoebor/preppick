import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../providers/planner_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../../widgets/prep_loading.dart';
import '../../widgets/meal_card_compact.dart';
import '../../widgets/prep_button.dart';
import '../../widgets/prep_filter_chip.dart';
import '../../widgets/prep_search_input.dart';

/// Swap Meal: the picker for replacing the meal in exactly one slot.
///
/// A modal bottom sheet rather than a route, because it is an edit to the
/// screen behind it and not a place the household navigates to — the plan
/// stays visible underneath, which is what makes it obvious that only one
/// slot is changing.
///
/// The candidate list comes from [PlannerProvider.swapCandidates], so it is
/// already restricted to the slot's meal type, already excludes the meal
/// sitting in the slot, and is already ranked by the same scoring the planner
/// used. This sheet adds only presentation: a search box and protein chips
/// that narrow that list. It never re-ranks and never regenerates.
///
/// Selecting a meal calls [PlannerProvider.swapMeal] with an explicit
/// replacement, which rewrites one `weekly_plan_items` row. Every other slot
/// keeps its id and its meal, and nothing touches `times_planned` — a draft
/// is not history, so swapping around in one costs the household nothing.
class SwapMealSheet extends StatefulWidget {
  const SwapMealSheet({
    super.key,
    required this.item,
    required this.totalOfType,
    this.currentMealName,
  });

  /// The plan item being replaced. Only this one changes.
  final WeeklyPlanItem item;

  /// How many slots of this meal type the week holds, for the title.
  final int totalOfType;

  /// The meal in the slot right now, named in the subtitle so the household
  /// can see what they are replacing.
  final String? currentMealName;

  /// Opens the sheet and resolves to true once a swap has been made.
  ///
  /// The provider is passed down explicitly: the sheet is built by the root
  /// navigator, whose context may sit above the one holding the planner.
  static Future<bool?> show(
    BuildContext context, {
    required WeeklyPlanItem item,
    required int totalOfType,
    String? currentMealName,
  }) {
    final planner = context.read<PlannerProvider>();
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.backgroundApp,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.xxl),
        ),
      ),
      builder: (sheetContext) => ChangeNotifierProvider<PlannerProvider>.value(
        value: planner,
        child: SwapMealSheet(
          item: item,
          totalOfType: totalOfType,
          currentMealName: currentMealName,
        ),
      ),
    );
  }

  @override
  State<SwapMealSheet> createState() => _SwapMealSheetState();
}

class _SwapMealSheetState extends State<SwapMealSheet> {
  final TextEditingController _search = TextEditingController();

  List<MealVariant> _candidates = const [];
  bool _isLoading = true;

  /// True when the candidate load itself failed. Kept apart from an empty
  /// result: "your library has no other dinner" and "we could not read your
  /// library" look identical on screen and mean opposite things, and only one
  /// of them is worth offering a retry for.
  bool _hasError = false;

  /// The selected protein chip, or null for "All".
  String? _protein;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final planner = context.read<PlannerProvider>();
    setState(() {
      _isLoading = true;
      _hasError = false;
    });
    final candidates = await planner.swapCandidates(widget.item.id);
    if (!mounted) return;
    setState(() {
      _candidates = candidates;
      // The provider returns an empty list on failure and records the reason,
      // so an error is only an error when it actually produced nothing.
      _hasError = candidates.isEmpty && planner.error != null;
      _isLoading = false;
    });
  }

  /// The proteins worth offering as chips: only those actually present in the
  /// candidates, so the row never advertises a filter that matches nothing.
  List<String> get _proteins {
    final seen = <String, String>{};
    for (final meal in _candidates) {
      final protein = meal.protein?.trim();
      if (protein == null || protein.isEmpty) continue;
      seen.putIfAbsent(protein.toLowerCase(), () => protein);
    }
    final proteins = seen.values.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return proteins;
  }

  /// Candidates narrowed by the query and the protein chip, in ranked order.
  ///
  /// Search is case-insensitive and matches the meal name or its protein, so
  /// typing "chicken" finds both "Chicken Wraps" and a spaghetti whose only
  /// mention of chicken is its protein line.
  List<MealVariant> get _visible {
    final query = _search.text.trim().toLowerCase();
    final protein = _protein?.toLowerCase();
    return _candidates.where((meal) {
      final mealProtein = meal.protein?.trim().toLowerCase();
      if (protein != null && mealProtein != protein) return false;
      if (query.isEmpty) return true;
      return meal.name.toLowerCase().contains(query) ||
          (mealProtein?.contains(query) ?? false);
    }).toList();
  }

  Future<void> _select(MealVariant meal) async {
    final planner = context.read<PlannerProvider>();
    // The cards disable themselves while a swap runs; this catches the tap
    // that lands in the frame before that takes effect.
    if (planner.isBusy) return;

    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final swapped = await planner.swapMeal(
      widget.item.id,
      replacementMealVariantId: meal.id,
    );
    if (!mounted) return;

    if (swapped) {
      navigator.pop(true);
      return;
    }
    messenger.showSnackBar(
      SnackBar(content: Text('Could not swap in ${meal.name}. Try again.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final planner = context.watch<PlannerProvider>();
    final visible = _visible;
    final label = widget.item.slot.label(totalOfType: widget.totalOfType);

    return SafeArea(
      top: false,
      child: Padding(
        // Lifts the sheet clear of the keyboard while searching.
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: FractionallySizedBox(
          heightFactor: 0.85,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _SheetGrabber(),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  0,
                  AppSpacing.xl,
                  AppSpacing.md,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Swap $label', style: AppTypography.headingH3),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      widget.currentMealName == null
                          ? 'Pick another meal for this slot.'
                          : 'Replacing ${widget.currentMealName}. Nothing '
                                'else in your week changes.',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    PrepSearchInput(
                      controller: _search,
                      hintText: 'Search meals',
                      onChanged: (_) => setState(() {}),
                    ),
                  ],
                ),
              ),
              if (_proteins.isNotEmpty)
                // Self-sizing rather than a fixed 40-high strip: at an
                // increased text scale the chips grow past 40 and a fixed
                // box clips them.
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xl,
                  ),
                  child: Row(
                    children: [
                      PrepFilterChip(
                        label: 'All',
                        isSelected: _protein == null,
                        onSelected: () => setState(() => _protein = null),
                      ),
                      for (final protein in _proteins) ...[
                        const SizedBox(width: AppSpacing.sm),
                        PrepFilterChip(
                          label: protein,
                          isSelected: _protein == protein,
                          onSelected: () => setState(() => _protein = protein),
                        ),
                      ],
                    ],
                  ),
                ),
              Expanded(
                child: _isLoading
                    ? const PrepLoading(
                        message: 'Finding meals you could swap in',
                      )
                    : _hasError
                    ? _SwapErrorState(onRetry: _load)
                    : visible.isEmpty
                    ? _SwapEmptyState(
                        hasCandidates: _candidates.isNotEmpty,
                        mealType: widget.item.mealType,
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.xl,
                          AppSpacing.md,
                          AppSpacing.xl,
                          AppSpacing.xl,
                        ),
                        itemCount: visible.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: AppSpacing.sm),
                        itemBuilder: (context, index) {
                          final meal = visible[index];
                          return MealCardCompact(
                            meal: meal,
                            mealType: widget.item.mealType,
                            onTap: planner.isBusy ? null : () => _select(meal),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The drag handle at the top of the sheet.
class _SheetGrabber extends StatelessWidget {
  const _SheetGrabber();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Center(
        child: Container(
          height: 4,
          width: 40,
          decoration: BoxDecoration(
            color: AppColors.borderDefault,
            borderRadius: BorderRadius.circular(AppRadius.full),
          ),
        ),
      ),
    );
  }
}

/// The candidate load failed, so the sheet says so and offers the one action
/// that can fix it rather than blaming an empty library.
class _SwapErrorState extends StatelessWidget {
  const _SwapErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Could not load meals to swap in.',
            key: const Key('swapSheetError'),
            textAlign: TextAlign.center,
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.textSecondary,
            ),
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
    );
  }
}

/// Nothing to show: either the library has no other meal of this type, or the
/// search and chips have narrowed it to nothing. The two need different
/// wording — one is a library problem, the other is one tap from being fixed.
class _SwapEmptyState extends StatelessWidget {
  const _SwapEmptyState({required this.hasCandidates, required this.mealType});

  final bool hasCandidates;
  final MealType mealType;

  @override
  Widget build(BuildContext context) {
    final name = switch (mealType) {
      MealType.breakfast => 'breakfast',
      MealType.lunch => 'lunch',
      MealType.dinner => 'dinner',
    };
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: Center(
        child: Text(
          hasCandidates
              ? 'No meals match your search.'
              : 'Your library has no other $name meal to swap in yet.',
          textAlign: TextAlign.center,
          style: AppTypography.bodyMedium.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
