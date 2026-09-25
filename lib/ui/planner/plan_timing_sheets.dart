import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../models/models.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../../utils/duration_format.dart';
import '../../widgets/prep_button.dart';

class DurationEditResult {
  const DurationEditResult(this.minutes);

  final int? minutes;
}

Future<DurationEditResult?> showDurationEditorSheet(
  BuildContext context, {
  required String title,
  required String label,
  int? initialMinutes,
}) {
  return showModalBottomSheet<DurationEditResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.backgroundApp,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xxl)),
    ),
    builder: (context) => _DurationEditorSheet(
      title: title,
      label: label,
      initialMinutes: initialMinutes,
    ),
  );
}

class PrepTimingEditResult {
  const PrepTimingEditResult({required this.prepTiming, this.plannedCookDate});

  final PrepTiming prepTiming;
  final DateTime? plannedCookDate;
}

Future<PrepTimingEditResult?> showPrepTimingEditorSheet(
  BuildContext context, {
  required WeeklyPlanItem item,
  required DateTime weekStart,
  String? mealName,
}) {
  return showModalBottomSheet<PrepTimingEditResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.backgroundApp,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xxl)),
    ),
    builder: (context) => _PrepTimingEditorSheet(
      item: item,
      weekStart: weekStart,
      mealName: mealName,
    ),
  );
}

class _DurationEditorSheet extends StatefulWidget {
  const _DurationEditorSheet({
    required this.title,
    required this.label,
    this.initialMinutes,
  });

  final String title;
  final String label;
  final int? initialMinutes;

  @override
  State<_DurationEditorSheet> createState() => _DurationEditorSheetState();
}

class _DurationEditorSheetState extends State<_DurationEditorSheet> {
  late final TextEditingController _minutes = TextEditingController(
    text: widget.initialMinutes?.toString() ?? '',
  );

  @override
  void dispose() {
    _minutes.dispose();
    super.dispose();
  }

  void _save() {
    final text = _minutes.text.trim();
    final minutes = text.isEmpty ? null : int.parse(text);
    Navigator.of(context).pop(DurationEditResult(minutes));
  }

  @override
  Widget build(BuildContext context) {
    final value = int.tryParse(_minutes.text.trim());
    final preview = PrepDurationFormat.optionalMinutes(value);

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.md,
          AppSpacing.xl,
          MediaQuery.of(context).viewInsets.bottom + AppSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.borderDefault,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(widget.title, style: AppTypography.headingH3),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _minutes,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: widget.label,
                hintText: 'Minutes',
                suffixText: preview,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                TextButton(
                  onPressed: () =>
                      Navigator.of(context).pop(const DurationEditResult(null)),
                  child: const Text('Clear'),
                ),
                const Spacer(),
                PrepButton(label: 'Save', isFullWidth: false, onPressed: _save),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PrepTimingEditorSheet extends StatefulWidget {
  const _PrepTimingEditorSheet({
    required this.item,
    required this.weekStart,
    this.mealName,
  });

  final WeeklyPlanItem item;
  final DateTime weekStart;
  final String? mealName;

  @override
  State<_PrepTimingEditorSheet> createState() => _PrepTimingEditorSheetState();
}

class _PrepTimingEditorSheetState extends State<_PrepTimingEditorSheet> {
  late PrepTiming _timing = widget.item.prepTiming;
  late DateTime _cookDate =
      widget.item.plannedCookDate ??
      widget.weekStart.add(const Duration(days: 1));

  List<DateTime> get _weekDays => [
    for (var offset = 0; offset < 7; offset++)
      DateTime.utc(
        widget.weekStart.year,
        widget.weekStart.month,
        widget.weekStart.day + offset,
      ),
  ];

  void _save() {
    Navigator.of(context).pop(
      PrepTimingEditResult(
        prepTiming: _timing,
        plannedCookDate: _timing == PrepTiming.later ? _cookDate : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.md,
          AppSpacing.xl,
          AppSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.borderDefault,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('Prep timing', style: AppTypography.headingH3),
            if (widget.mealName != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                widget.mealName!,
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            SegmentedButton<PrepTiming>(
              segments: const [
                ButtonSegment(
                  value: PrepTiming.mainPrep,
                  icon: Icon(AppIcons.eventAvailableOutlined),
                  label: Text('Main prep'),
                ),
                ButtonSegment(
                  value: PrepTiming.later,
                  icon: Icon(AppIcons.todayOutlined),
                  label: Text('Cook later'),
                ),
              ],
              selected: {_timing},
              onSelectionChanged: (selected) =>
                  setState(() => _timing = selected.single),
            ),
            if (_timing == PrepTiming.later) ...[
              const SizedBox(height: AppSpacing.lg),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final day in _weekDays)
                    ChoiceChip(
                      label: Text(DateFormat('EEE d').format(day)),
                      selected: _sameDate(day, _cookDate),
                      onSelected: (_) => setState(() => _cookDate = day),
                    ),
                ],
              ),
            ],
            const SizedBox(height: AppSpacing.xl),
            PrepButton(label: 'Save timing', onPressed: _save),
          ],
        ),
      ),
    );
  }

  static bool _sameDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
