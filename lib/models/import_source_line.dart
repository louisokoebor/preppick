/// One original line from an import source, retained for review evidence.
class ImportSourceLine {
  const ImportSourceLine({
    required this.id,
    required this.batchId,
    required this.sequence,
    required this.originalText,
    this.heading,
    this.inferredSlot,
    this.originalWeek,
  });

  factory ImportSourceLine.fromMap(Map<String, Object?> map) =>
      ImportSourceLine(
        id: map['id']! as String,
        batchId: map['batch_id']! as String,
        sequence: (map['sequence']! as num).toInt(),
        originalText: map['original_text']! as String,
        heading: map['heading'] as String?,
        inferredSlot: map['inferred_slot'] as String?,
        originalWeek: map['original_week'] as String?,
      );

  final String id;
  final String batchId;
  final int sequence;
  final String originalText;
  final String? heading;
  final String? inferredSlot;
  final String? originalWeek;

  ImportSourceLine copyWith({String? batchId}) => ImportSourceLine(
    id: id,
    batchId: batchId ?? this.batchId,
    sequence: sequence,
    originalText: originalText,
    heading: heading,
    inferredSlot: inferredSlot,
    originalWeek: originalWeek,
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'batch_id': batchId,
    'sequence': sequence,
    'original_text': originalText,
    'heading': heading,
    'inferred_slot': inferredSlot,
    'original_week': originalWeek,
  };
}
