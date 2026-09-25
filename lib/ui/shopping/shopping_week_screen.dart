import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/shopping_history_provider.dart';
import '../../services/shopping_service.dart';
import '../../theme/app_spacing.dart';
import '../../utils/error_messages.dart';
import '../../utils/week_range_format.dart';
import '../../widgets/prep_header.dart';
import '../../widgets/prep_loading.dart';
import 'shopping_list_parts.dart';

/// One previous week's shopping list, read-only.
///
/// Drawn with the same aisle sections as the live list, but nothing can be
/// ticked, added or removed: this is a record of what was bought that week,
/// not a list to shop from.
class ShoppingWeekScreen extends StatefulWidget {
  const ShoppingWeekScreen({super.key, required this.planId});

  final String planId;

  @override
  State<ShoppingWeekScreen> createState() => _ShoppingWeekScreenState();
}

class _ShoppingWeekScreenState extends State<ShoppingWeekScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _open());
  }

  void _open() {
    if (!mounted || widget.planId.isEmpty) return;
    context.read<ShoppingHistoryProvider>().openWeek(widget.planId);
  }

  @override
  Widget build(BuildContext context) {
    final history = context.watch<ShoppingHistoryProvider>();
    final week = history.weekPlanId == widget.planId ? history.week : null;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            PrepHeader(
              title: week == null
                  ? 'Shopping list'
                  : PrepWeekRange.label(week.plan.weekStart),
              subtitle: week == null ? null : _subtitle(week),
              onBack: Navigator.of(context).canPop()
                  ? () => Navigator.of(context).pop()
                  : null,
            ),
            Expanded(child: _body(history, week)),
          ],
        ),
      ),
    );
  }

  Widget _body(ShoppingHistoryProvider history, SavedShoppingList? week) {
    final isCurrent = history.weekPlanId == widget.planId;
    if (widget.planId.isEmpty ||
        (isCurrent &&
            !history.isLoadingWeek &&
            week == null &&
            history.weekError == null)) {
      return const ShoppingNotice(message: 'This week could not be found.');
    }
    if (isCurrent && history.weekError != null) {
      return ShoppingNotice(
        message: PrepErrorMessages.forError(
          history.weekError,
          fallback: 'Something went wrong loading this list.',
        )!,
        actionLabel: 'Try again',
        onAction: _open,
      );
    }
    if (week == null) {
      return const PrepLoading(message: 'Loading this week’s list');
    }
    if (week.isEmpty) {
      return const ShoppingNotice(
        message: 'No shopping list was saved for this week.',
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.md,
        AppSpacing.xl,
        AppSpacing.lg,
      ),
      children: [
        for (final group in week.groups) ...[
          ShoppingCategorySection(group: group),
          const SizedBox(height: AppSpacing.lg),
        ],
      ],
    );
  }

  String _subtitle(SavedShoppingList week) {
    final total = week.itemCount;
    final items = total == 1 ? '1 item' : '$total items';
    if (week.checkedCount == total) return '$items, all ticked off.';
    return '$items, ${week.checkedCount} ticked off.';
  }
}
