import '../utils/date_utils.dart';

/// Lifecycle of a weekly plan.
///
/// Persisted as a stable string, never as an enum index.
enum PlanStatus {
  draft('draft'),
  confirmed('confirmed');

  const PlanStatus(this.value);

  /// Stable value written to SQLite.
  final String value;

  static PlanStatus fromValue(String value) => PlanStatus.values.firstWhere(
    (status) => status.value == value,
    orElse: () =>
        throw ArgumentError.value(value, 'value', 'Unknown PlanStatus'),
  );
}

/// One week of planned meals.
class WeeklyPlan {
  const WeeklyPlan({
    required this.id,
    required this.weekStart,
    required this.status,
    required this.createdAt,
    DateTime? updatedAt,
    this.estimatedPrepMinutes,
    this.confirmedAt,
  }) : updatedAt = updatedAt ?? createdAt;

  factory WeeklyPlan.fromMap(Map<String, Object?> map) => WeeklyPlan(
    id: map['id']! as String,
    weekStart: PrepDates.fromIso(map['week_start']! as String),
    status: PlanStatus.fromValue(map['status']! as String),
    createdAt: PrepDates.fromIso(map['created_at']! as String),
    updatedAt: PrepDates.fromIso(map['updated_at']! as String),
    estimatedPrepMinutes: (map['estimated_prep_minutes'] as num?)?.toInt(),
    confirmedAt: PrepDates.fromIsoOrNull(map['confirmed_at']),
  );

  final String id;
  final DateTime weekStart;
  final PlanStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int? estimatedPrepMinutes;
  final DateTime? confirmedAt;

  bool get isConfirmed => status == PlanStatus.confirmed;

  Map<String, Object?> toMap() => {
    'id': id,
    'week_start': PrepDates.toIso(weekStart),
    'status': status.value,
    'created_at': PrepDates.toIso(createdAt),
    'updated_at': PrepDates.toIso(updatedAt),
    'estimated_prep_minutes': estimatedPrepMinutes,
    'confirmed_at': PrepDates.toIsoOrNull(confirmedAt),
  };

  WeeklyPlan copyWith({
    PlanStatus? status,
    DateTime? updatedAt,
    int? estimatedPrepMinutes,
    DateTime? confirmedAt,
  }) => WeeklyPlan(
    id: id,
    weekStart: weekStart,
    status: status ?? this.status,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    estimatedPrepMinutes: estimatedPrepMinutes ?? this.estimatedPrepMinutes,
    confirmedAt: confirmedAt ?? this.confirmedAt,
  );
}
