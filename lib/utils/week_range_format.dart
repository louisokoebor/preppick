import 'package:intl/intl.dart';

/// How a past week is named on history screens: "Mon 14 - Sun 20 Jul", or
/// "Mon 28 Jul - Sun 3 Aug" when the week crosses a month.
///
/// Formatted from the calendar date alone. Plans store a UTC week start, and
/// converting it to local time first would slide the label a day for
/// households either side of UTC.
class PrepWeekRange {
  const PrepWeekRange._();

  static String label(DateTime weekStart) {
    final start = DateTime(weekStart.year, weekStart.month, weekStart.day);
    final end = start.add(const Duration(days: 6));
    final day = DateFormat('EEE d');
    final dayMonth = DateFormat('EEE d MMM');
    final startLabel = start.month == end.month
        ? day.format(start)
        : dayMonth.format(start);
    return '$startLabel - ${dayMonth.format(end)}';
  }
}
