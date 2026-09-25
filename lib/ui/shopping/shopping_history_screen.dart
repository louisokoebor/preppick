import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/routes.dart';
import '../../models/models.dart';
import '../../providers/shopping_history_provider.dart';
import '../../theme/app_spacing.dart';
import '../../utils/error_messages.dart';
import '../../widgets/prep_header.dart';
import '../../widgets/prep_loading.dart';
import '../../widgets/shopping_week_card.dart';
import 'shopping_list_parts.dart';

/// Past Shopping Lists: one card per previous week that has a saved list,
/// newest first. Opened from the history icon on the Shopping List.
class ShoppingHistoryScreen extends StatefulWidget {
  const ShoppingHistoryScreen({super.key, this.onOpenWeek});

  /// Overrides opening a week in tests. Defaults to pushing
  /// [AppRoutes.shoppingHistoryWeek] with the plan id.
  final ValueChanged<ShoppingListSummary>? onOpenWeek;

  @override
  State<ShoppingHistoryScreen> createState() => _ShoppingHistoryScreenState();
}

class _ShoppingHistoryScreenState extends State<ShoppingHistoryScreen> {
  @override
  void initState() {
    super.initState();
    // After the frame: loading notifies, which cannot happen mid-build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<ShoppingHistoryProvider>().loadHistory();
    });
  }

  void _openWeek(ShoppingListSummary summary) {
    final onOpenWeek = widget.onOpenWeek;
    if (onOpenWeek != null) {
      onOpenWeek(summary);
      return;
    }
    Navigator.of(
      context,
    ).pushNamed(AppRoutes.shoppingHistoryWeek, arguments: summary.plan.id);
  }

  @override
  Widget build(BuildContext context) {
    final history = context.watch<ShoppingHistoryProvider>();

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            PrepHeader(
              title: 'Past shopping lists',
              subtitle: 'What you bought in previous weeks.',
              onBack: Navigator.of(context).canPop()
                  ? () => Navigator.of(context).pop()
                  : null,
            ),
            Expanded(child: _body(history)),
          ],
        ),
      ),
    );
  }

  Widget _body(ShoppingHistoryProvider history) {
    if (!history.hasLoaded ||
        (history.isLoading && history.summaries.isEmpty)) {
      return const PrepLoading(message: 'Loading your past lists');
    }
    if (history.error != null) {
      return ShoppingNotice(
        message: PrepErrorMessages.forError(
          history.error,
          fallback: 'Something went wrong loading your past lists.',
        )!,
        actionLabel: 'Try again',
        onAction: history.loadHistory,
      );
    }
    if (history.summaries.isEmpty) {
      return const ShoppingNotice(
        message:
            'Past weeks appear here once you have confirmed a week and '
            'shopped from its list.',
      );
    }

    return RefreshIndicator(
      onRefresh: history.loadHistory,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.sm,
          AppSpacing.xl,
          AppSpacing.lg,
        ),
        children: [
          for (final summary in history.summaries) ...[
            ShoppingWeekCard(
              weekStart: summary.weekStart,
              itemCount: summary.itemCount,
              checkedCount: summary.checkedCount,
              onTap: () => _openWeek(summary),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
        ],
      ),
    );
  }
}
