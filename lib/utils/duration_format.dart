/// Human-friendly duration labels for cooking and prep estimates.
class PrepDurationFormat {
  const PrepDurationFormat._();

  static String? optionalMinutes(int? minutes) =>
      minutes == null || minutes <= 0 ? null : minutesLabel(minutes);

  static String minutesLabel(int minutes) {
    final hours = minutes ~/ 60;
    final remaining = minutes % 60;
    if (hours == 0) return '$remaining min';
    if (remaining == 0) return hours == 1 ? '1 hr' : '$hours hr';
    return hours == 1 ? '1 hr $remaining min' : '$hours hr $remaining min';
  }

  static String approximate(int? minutes) {
    final label = optionalMinutes(minutes);
    return label == null ? 'Time not set' : '~$label';
  }
}
