import 'package:flutter/material.dart';
import 'package:flutter/services.dart' as services;
import 'package:provider/provider.dart';

import '../providers/planner_provider.dart';
import '../services/share_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import 'share_options_sheet.dart';

/// Header action for sharing the plan currently held by [PlannerProvider].
class ShareMealPlanButton extends StatefulWidget {
  const ShareMealPlanButton({super.key});

  @override
  State<ShareMealPlanButton> createState() => _ShareMealPlanButtonState();
}

class _ShareMealPlanButtonState extends State<ShareMealPlanButton> {
  bool _isSharing = false;

  Future<void> _share() async {
    final planner = context.read<PlannerProvider>();
    if (planner.currentPlan == null || planner.items.isEmpty || _isSharing) {
      return;
    }

    final option = await ShareOptionsSheet.show(
      context,
      title: 'Share meal plan',
    );
    if (!mounted || option == null) return;

    setState(() => _isSharing = true);
    try {
      final share = const ShareService();
      if (option == ShareOption.message) {
        await share.shareText(
          subject: 'PrepPick meal plan',
          text: share.mealPlanMessage(
            weekStart: planner.weekStart,
            items: planner.items,
            mealFor: planner.mealFor,
          ),
        );
      } else {
        await share.shareMealPlanPdf(
          weekStart: planner.weekStart,
          items: planner.items,
          mealFor: planner.mealFor,
        );
      }
    } catch (error, stackTrace) {
      debugPrint('PrepPick meal-plan share failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is services.MissingPluginException
                  ? 'Sharing needs a full app restart after installing the update.'
                  : 'Could not prepare the meal plan. Try again.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canShare = context.select<PlannerProvider, bool>(
      (planner) => planner.currentPlan != null && planner.items.isNotEmpty,
    );
    return IconButton(
      key: const Key('shareMealPlanButton'),
      onPressed: canShare && !_isSharing ? _share : null,
      icon: const Icon(AppIcons.shareRounded, semanticLabel: 'Share meal plan'),
      color: AppColors.textSecondary,
      tooltip: 'Share meal plan',
    );
  }
}
