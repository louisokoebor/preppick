import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../providers/settings_provider.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../../utils/error_messages.dart';
import '../../widgets/prep_loading.dart';
import '../../widgets/prep_button.dart';
import '../../widgets/quantity_selector.dart';

/// First screen of the weekly workflow: how many batches of each meal the
/// household wants to prep. Implements the Figma `select-meal-count` frame.
///
/// The counts are owned by [SettingsProvider], not by this widget, because the
/// planner needs the same numbers. Continue saves before navigating, so the
/// values survive a restart.
///
/// The frame's three regions — fixed header, scrolling content, sticky action
/// — are laid out as a Column with the middle region expanded. Nothing is
/// absolutely positioned: every row is free to grow when the user scales text
/// up, and the middle region scrolls rather than overflowing.
class SelectMealCountScreen extends StatefulWidget {
  const SelectMealCountScreen({super.key, this.onContinue});

  /// Called after a successful save. Defaults to popping the screen, which is
  /// replaced by navigation to Plan This Week once that screen exists.
  final VoidCallback? onContinue;

  @override
  State<SelectMealCountScreen> createState() => _SelectMealCountScreenState();
}

class _SelectMealCountScreenState extends State<SelectMealCountScreen> {
  @override
  void initState() {
    super.initState();
    // Load after the first frame: `load` notifies listeners synchronously and
    // notifying during build is an error.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final provider = context.read<SettingsProvider>();
      if (!provider.hasLoaded) provider.load();
    });
  }

  Future<void> _handleContinue() async {
    final provider = context.read<SettingsProvider>();
    final messenger = ScaffoldMessenger.of(context);

    final saved = await provider.save();
    if (!mounted) return;

    if (!saved) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Could not save your meal counts. Please try again.'),
        ),
      );
      return;
    }

    final onContinue = widget.onContinue;
    if (onContinue != null) {
      onContinue();
    } else if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SettingsProvider>();
    final showSpinner = provider.isLoading && !provider.hasLoaded;

    return Scaffold(
      body: SafeArea(
        child: showSpinner
            ? const PrepLoading(message: 'Loading your meal counts')
            : Column(
                children: [
                  const _Header(),
                  Expanded(child: _MealCountList(provider: provider)),
                  _StickyAction(
                    isBusy: provider.isSaving,
                    onPressed: _handleContinue,
                  ),
                ],
              ),
      ),
    );
  }
}

/// Region / Fixed Header.
class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xs,
              vertical: AppSpacing.md,
            ),
            child: Text('Plan your week', style: AppTypography.headingH1),
          ),
          Text(
            'Select how many of each meal you want to prepare this week.',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Scroll / Main Content.
class _MealCountList extends StatelessWidget {
  const _MealCountList({required this.provider});

  final SettingsProvider provider;

  @override
  Widget build(BuildContext context) {
    final settings = provider.settings;
    // Only a read failure gets the inline notice. A failed save already has
    // a snackbar, and repeating it here would leave a stale warning sitting
    // above numbers that are perfectly correct.
    final errorMessage = provider.hasLoadError
        ? PrepErrorMessages.forError(
            provider.error,
            fallback:
                'Your saved meal counts could not be loaded, so these are '
                'the defaults.',
          )
        : null;

    return ListView(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.lg,
      ),
      children: [
        // Above the cards: a failed read means the steppers are showing
        // defaults rather than what was saved, and that is worth knowing
        // before adjusting them.
        if (errorMessage != null) ...[
          _SettingsNotice(
            key: const Key('selectMealCountError'),
            message: errorMessage,
            actionLabel: 'Try again',
            onAction: provider.load,
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        for (final type in MealType.values) ...[
          _MealCountCard(
            mealType: type,
            value: settings.countFor(type),
            onChanged: (value) => provider.setCount(type, value),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        if (provider.hasNoMeals)
          const _SettingsNotice(
            message: 'Add at least one meal before generating a plan.',
          ),
      ],
    );
  }
}

/// Region / Sticky Actions.
class _StickyAction extends StatelessWidget {
  const _StickyAction({required this.isBusy, required this.onPressed});

  final bool isBusy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.backgroundApp,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.sm,
        AppSpacing.xl,
        AppSpacing.md,
      ),
      child: PrepButton(
        // The design's trailing ✦ is drawn as an icon for the same reason the
        // card glyphs are: the app font does not carry it.
        icon: AppIcons.autoAwesome,
        iconAfterLabel: true,
        label: 'Continue to plan',
        isBusy: isBusy,
        onPressed: onPressed,
      ),
    );
  }
}

/// One "Meal Count Card": category header, divider, then the guide text and
/// the stepper.
class _MealCountCard extends StatelessWidget {
  const _MealCountCard({
    required this.mealType,
    required this.value,
    required this.onChanged,
  });

  final MealType mealType;
  final int value;
  final ValueChanged<int> onChanged;

  static const Map<MealType, String> _categories = {
    MealType.breakfast: 'BREAKFAST',
    MealType.lunch: 'LUNCH',
    MealType.dinner: 'DINNER',
  };

  static const Map<MealType, String> _headings = {
    MealType.breakfast: 'Breakfast Options',
    MealType.lunch: 'Lunch Options',
    MealType.dinner: 'Dinner Options',
  };

  static const Map<MealType, String> _guides = {
    MealType.breakfast: 'How many breakfasts?',
    MealType.lunch: 'How many lunches?',
    MealType.dinner: 'How many dinners?',
  };

  static const Map<MealType, Color> _accents = {
    MealType.breakfast: AppColors.categoryBreakfast,
    MealType.lunch: AppColors.categoryLunch,
    MealType.dinner: AppColors.categoryDinner,
  };

  /// Material equivalents of the glyphs the design draws in the accent tile.
  ///
  /// Figma sets those as text (☀ ♨ ☾), but Manrope has no coverage for them,
  /// so in the app they would fall back to whatever the platform supplies —
  /// a colour emoji sun on iOS, a monochrome outline on Android. Icons keep
  /// the same reading identical on both.
  static const Map<MealType, IconData> _icons = {
    MealType.breakfast: AppIcons.wbSunnyOutlined,
    MealType.lunch: AppIcons.ramenDiningOutlined,
    MealType.dinner: AppIcons.nightlightOutlined,
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.backgroundSurface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardHeader(
            category: _categories[mealType]!,
            heading: _headings[mealType]!,
            accent: _accents[mealType]!,
            icon: _icons[mealType]!,
          ),
          const SizedBox(height: AppSpacing.md),
          const Divider(height: 1, color: AppColors.borderSubtle),
          const SizedBox(height: AppSpacing.md),
          // Wrap rather than Row: at large text scales the stepper drops onto
          // its own line instead of squeezing the question to nothing.
          SizedBox(
            width: double.infinity,
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.sm,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 180),
                  child: Text(
                    _guides[mealType]!,
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                QuantitySelector(
                  value: value,
                  min: AppSettings.minCount,
                  max: AppSettings.maxCount,
                  semanticLabel: _headings[mealType],
                  onChanged: onChanged,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CardHeader extends StatelessWidget {
  const _CardHeader({
    required this.category,
    required this.heading,
    required this.accent,
    required this.icon,
  });

  final String category;
  final String heading;
  final Color accent;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          height: 48,
          width: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: accent,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Icon(icon, size: 22, color: AppColors.textSecondary),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                category,
                style: AppTypography.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 2),
              Text(heading, style: AppTypography.titleMedium),
            ],
          ),
        ),
      ],
    );
  }
}

/// Shown when all three counts are zero.
///
/// Not in the Figma frame: Continue still works — the household is allowed to
/// store zeros — but the planner has nothing to generate, so the screen says
/// so here rather than letting the next screen fail.
/// A tinted advisory block: the zero-count guidance, and the load/save
/// failure. Both live in the scroll region rather than in a snackbar so the
/// message is still there when the household comes back to the screen.
class _SettingsNotice extends StatelessWidget {
  const _SettingsNotice({
    super.key,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.categoryShopping,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                AppIcons.infoOutlineRounded,
                size: 20,
                color: AppColors.textPrimary,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: Text(message, style: AppTypography.bodyMedium)),
            ],
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: AppSpacing.md),
            PrepButton(
              label: actionLabel!,
              variant: PrepButtonVariant.tertiary,
              isFullWidth: false,
              onPressed: onAction,
            ),
          ],
        ],
      ),
    );
  }
}
