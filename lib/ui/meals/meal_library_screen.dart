import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/routes.dart';
import '../../models/models.dart';
import '../../providers/meal_provider.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../../utils/error_messages.dart';
import '../../widgets/prep_loading.dart';
import '../../widgets/meal_card_library.dart';
import '../../widgets/prep_button.dart';
import '../../widgets/prep_filter_chip.dart';
import '../../widgets/prep_header.dart';
import '../../widgets/prep_search_input.dart';

/// Meal Library: everything the household has told PrepPick it likes.
///
/// This is the source the planner draws from, so it is also where a "not
/// enough meals" shortage is fixed — both planner screens point here.
///
/// ## The list comes from the provider, never from a query
///
/// [MealProvider] holds the active variants and their families, already
/// ordered by name. This screen only narrows that list: the search box and
/// the category chips filter what is already in memory, so typing or
/// switching a chip never touches SQLite and never reorders anything. That
/// keeps the library in one predictable order however it is being sliced.
///
/// ## Two different kinds of "nothing here"
///
/// An empty library and an empty search look the same and mean opposite
/// things: one needs a meal added, the other needs a word deleted. They get
/// separate states with separate actions, because telling someone to add
/// their first meal when they have forty of them and simply mistyped one is
/// the more annoying of the two mistakes.
class MealLibraryScreen extends StatefulWidget {
  const MealLibraryScreen({super.key, this.onOpenMeal, this.onAddMeal});

  /// Called with the tapped meal's id. Defaults to pushing Meal Detail.
  final ValueChanged<String>? onOpenMeal;

  /// Called from the Add Meal button. Defaults to pushing Add Meal.
  final VoidCallback? onAddMeal;

  @override
  State<MealLibraryScreen> createState() => _MealLibraryScreenState();
}

class _MealLibraryScreenState extends State<MealLibraryScreen> {
  final TextEditingController _search = TextEditingController();

  /// The selected category chip, or null for "All".
  MealType? _type;

  @override
  void initState() {
    super.initState();
    // After the first frame: load() notifies synchronously, and notifying
    // during build is an error.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final meals = context.read<MealProvider>();
      if (!meals.hasLoaded && !meals.isLoading) meals.load();
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _openMeal(String id) async {
    final onOpenMeal = widget.onOpenMeal;
    if (onOpenMeal != null) {
      onOpenMeal(id);
    } else {
      final removedOrChanged = await Navigator.of(
        context,
      ).pushNamed(AppRoutes.mealDetail, arguments: id);
      if (mounted && removedOrChanged == true) {
        await context.read<MealProvider>().refresh();
      }
    }
  }

  Future<void> _addMeal() async {
    final onAddMeal = widget.onAddMeal;
    if (onAddMeal != null) {
      onAddMeal();
    } else {
      final added = await Navigator.of(context).pushNamed(AppRoutes.addMeal);
      if (mounted && added == true) {
        await context.read<MealProvider>().refresh();
      }
    }
  }

  /// The loaded meals narrowed by the chip and the query, in library order.
  ///
  /// Search is case-insensitive and matches the meal name, the family name,
  /// or the protein, so "chicken" finds a meal called Chicken Wraps and a
  /// spaghetti whose only mention of chicken is its protein line.
  List<MealVariant> _visible(MealProvider provider) {
    final query = _search.text.trim().toLowerCase();
    final type = _type;
    return provider.meals.where((meal) {
      if (type != null && provider.typeOf(meal) != type) return false;
      if (query.isEmpty) return true;
      final family = provider.familyOf(meal)?.name.toLowerCase() ?? '';
      final protein = meal.protein?.toLowerCase() ?? '';
      return meal.name.toLowerCase().contains(query) ||
          family.contains(query) ||
          protein.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MealProvider>();
    final visible = _visible(provider);
    final isFiltered = _type != null || _search.text.trim().isNotEmpty;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            PrepHeader(
              title: 'Meal library',
              subtitle: 'The meals PrepPick plans your weeks from.',
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(
                      context,
                    ).pushNamed(AppRoutes.importHistory),
                    icon: const Icon(
                      AppIcons.uploadFileRounded,
                      semanticLabel: 'Import history',
                    ),
                    tooltip: 'Import history',
                    color: AppColors.textSecondary,
                  ),
                  IconButton(
                    onPressed: _addMeal,
                    icon: const Icon(
                      AppIcons.addRounded,
                      semanticLabel: 'Add meal',
                    ),
                    tooltip: 'Add meal',
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),
            // Search, filters and the count scroll with the list rather
            // than sitting in fixed bands above it. Stacked as fixed chrome
            // they cost around 130 logical pixels, which on a 568-tall phone
            // at a 1.5 text scale is more than the screen has left once the
            // header, the footer action and the nav bar have taken theirs.
            Expanded(
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.xl,
                        0,
                        AppSpacing.xl,
                        AppSpacing.md,
                      ),
                      child: PrepSearchInput(
                        controller: _search,
                        hintText: 'Search meals',
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xl,
                      ),
                      child: Row(
                        children: [
                          PrepFilterChip(
                            label: 'All',
                            isSelected: _type == null,
                            onSelected: () => setState(() => _type = null),
                          ),
                          for (final type in MealType.values) ...[
                            const SizedBox(width: AppSpacing.sm),
                            PrepFilterChip(
                              label: _chipLabel(type),
                              isSelected: _type == type,
                              onSelected: () => setState(() => _type = type),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.xl,
                        AppSpacing.md,
                        AppSpacing.xl,
                        0,
                      ),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _summary(
                            visible.length,
                            provider.meals.length,
                            isFiltered,
                          ),
                          style: AppTypography.labelMedium.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ),
                  _Body(
                    provider: provider,
                    visible: visible,
                    isFiltered: isFiltered,
                    onOpenMeal: _openMeal,
                    onAddMeal: _addMeal,
                    onClearFilters: () => setState(() {
                      _search.clear();
                      _type = null;
                    }),
                  ),
                ],
              ),
            ),
            Container(
              color: AppColors.backgroundApp,
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.sm,
                AppSpacing.xl,
                AppSpacing.md,
              ),
              child: PrepButton(
                label: 'Add meal',
                icon: AppIcons.addRounded,
                onPressed: _addMeal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _chipLabel(MealType type) => switch (type) {
    MealType.breakfast => 'Breakfast',
    MealType.lunch => 'Lunch',
    MealType.dinner => 'Dinner',
  };

  /// The count line above the list.
  ///
  /// Unfiltered it is just the size of the library; filtered it says "3 of
  /// 12" so the household can see how much the chips and the query are
  /// hiding rather than wondering where the rest went.
  static String _summary(int visible, int total, bool isFiltered) {
    final noun = total == 1 ? 'meal' : 'meals';
    if (!isFiltered) return '$total $noun';
    return '$visible of $total $noun';
  }
}

/// The list itself, or whichever of the four states stands in for it.
///
/// A sliver rather than a box: it shares one scroll view with the search
/// field, the filter chips and the count line above it, so all four scroll
/// together instead of the list being squeezed into whatever a stack of
/// fixed bands leaves behind.
class _Body extends StatelessWidget {
  const _Body({
    required this.provider,
    required this.visible,
    required this.isFiltered,
    required this.onOpenMeal,
    required this.onAddMeal,
    required this.onClearFilters,
  });

  final MealProvider provider;
  final List<MealVariant> visible;
  final bool isFiltered;
  final ValueChanged<String> onOpenMeal;
  final VoidCallback onAddMeal;
  final VoidCallback onClearFilters;

  @override
  Widget build(BuildContext context) {
    // Only a first load gets the spinner. A refresh keeps the last good list
    // on screen, because blanking a library someone is reading to re-fetch
    // the same rows helps no one.
    if (provider.isLoading && provider.meals.isEmpty) {
      return const _BodyFill(child: PrepLoading(message: 'Loading your meals'));
    }
    if (provider.hasError && provider.meals.isEmpty) {
      return _BodyFill(
        child: _LibraryMessage(
          key: const Key('mealLibraryError'),
          icon: AppIcons.errorOutlineRounded,
          title: 'Could not open your library',
          body: PrepErrorMessages.forError(
            provider.error,
            fallback: 'Something went wrong while loading your meals.',
          )!,
          actionLabel: 'Try again',
          onAction: provider.refresh,
        ),
      );
    }
    if (provider.meals.isEmpty) {
      return _BodyFill(
        child: _LibraryMessage(
          icon: AppIcons.restaurantMenuOutlined,
          title: 'No meals yet',
          body:
              'Add the meals your household already likes and PrepPick will '
              'plan your weeks from them.',
          actionLabel: 'Add your first meal',
          onAction: onAddMeal,
        ),
      );
    }
    if (visible.isEmpty) {
      return _BodyFill(
        child: _LibraryMessage(
          icon: AppIcons.searchOffRounded,
          title: 'No meals match',
          body: 'Try a different search, or clear your filters.',
          actionLabel: isFiltered ? 'Clear filters' : null,
          onAction: isFiltered ? onClearFilters : null,
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.md,
        AppSpacing.xl,
        AppSpacing.lg,
      ),
      sliver: SliverList.separated(
        itemCount: visible.length,
        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
        itemBuilder: (context, index) {
          final meal = visible[index];
          final family = provider.familyOf(meal);
          return MealCardLibrary(
            meal: meal,
            // A meal whose family somehow failed to load still belongs
            // somewhere on screen, so it falls back to dinner's tint rather
            // than being dropped from the household's own library.
            mealType: family?.mealType ?? MealType.dinner,
            familyName: family?.name,
            onTap: () => onOpenMeal(meal.id),
          );
        },
      ),
    );
  }
}

/// Wraps one of the non-list states so it fills the scroll view's remaining
/// space.
///
/// [SliverFillRemaining.hasScrollBody] stays true because every state passed
/// here brings its own scroll view: they must still be readable when a large
/// text scale makes them taller than the space left under the search field
/// and the chips.
class _BodyFill extends StatelessWidget {
  const _BodyFill({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => SliverFillRemaining(child: child);
}

/// A centred icon, headline and line of body text, with an optional action.
/// Shared by the empty, no-results and error states so all three read the
/// same and only their wording differs.
class _LibraryMessage extends StatelessWidget {
  const _LibraryMessage({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: AppSpacing.xxl),
          Icon(icon, size: 40, color: AppColors.textTertiary),
          const SizedBox(height: AppSpacing.lg),
          Text(title, style: AppTypography.titleLarge),
          const SizedBox(height: AppSpacing.sm),
          Text(
            body,
            textAlign: TextAlign.center,
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: AppSpacing.xl),
            PrepButton(
              label: actionLabel!,
              variant: PrepButtonVariant.secondary,
              isFullWidth: false,
              onPressed: onAction,
            ),
          ],
        ],
      ),
    );
  }
}
