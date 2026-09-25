/// Date helpers for persisting dates as ISO-8601 strings.
///
/// SQLite has no date type, so every date in PrepPick is stored as an
/// ISO-8601 string in UTC and read back as a UTC [DateTime].
class PrepDates {
  const PrepDates._();

  /// Serialises [date] to an ISO-8601 UTC string.
  static String toIso(DateTime date) => date.toUtc().toIso8601String();

  /// Serialises a nullable [date], preserving null.
  static String? toIsoOrNull(DateTime? date) =>
      date == null ? null : toIso(date);

  /// Parses an ISO-8601 string into a UTC [DateTime].
  static DateTime fromIso(String value) => DateTime.parse(value).toUtc();

  /// Parses a nullable value, preserving null.
  static DateTime? fromIsoOrNull(Object? value) =>
      value == null ? null : fromIso(value as String);

  /// Midnight (UTC) on the Monday of the week containing [date].
  static DateTime weekStartFor(DateTime date) {
    final local = date.toUtc();
    final monday = local.subtract(Duration(days: local.weekday - 1));
    return DateTime.utc(monday.year, monday.month, monday.day);
  }
}
