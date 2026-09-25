import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// The week navigator card at the top of the planner screens: a left chevron,
/// the date range being planned, and a right chevron — e.g.
/// "‹  Mon 14 Jul – Sun 20 Jul  ›".
///
/// Matches the Figma `Card / Week Range` component: a white surface with a
/// 12 radius, 14 vertical padding, and the range centred between the two
/// arrows. There is no "THIS WEEK" caption or trailing meal count on this
/// card — the range itself is all the context it needs.
///
/// Plans are stored with a UTC week start, but this card is read by a person
/// standing in a kitchen, so the range is formatted from the calendar date
/// alone. Converting the stored instant to local time first would slide the
/// label a day either way for households west or east of UTC.
class WeekRangeCard extends StatelessWidget {
  const WeekRangeCard({super.key, required this.weekStart});

  /// Monday of the week being shown.
  final DateTime weekStart;

  /// "Mon 14 Jul – Sun 20 Jul", always carrying the month on both ends so the
  /// full week reads the way the design draws it.
  String get rangeLabel {
    final start = DateTime(weekStart.year, weekStart.month, weekStart.day);
    final end = start.add(const Duration(days: 6));
    final format = DateFormat('EEE d MMM');
    return '${format.format(start)} – ${format.format(end)}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: 14,
      ),
      decoration: BoxDecoration(
        color: AppColors.backgroundSurface,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              rangeLabel,
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
