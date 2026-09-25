enum ImportLineType {
  blank('blank'),
  meal('meal'),
  heading('heading'),
  shoppingItem('shopping_item'),
  householdItem('household_item');

  const ImportLineType(this.value);

  final String value;

  static ImportLineType fromValue(String value) =>
      ImportLineType.values.firstWhere(
        (type) => type.value == value,
        orElse: () => ImportLineType.meal,
      );
}

/// One original line from an import source, retained for review evidence.
class ImportSourceLine {
  const ImportSourceLine({
    required this.id,
    required this.batchId,
    required this.sequence,
    required this.originalText,
    required this.lineType,
    this.heading,
    this.inferredSlot,
    this.originalWeek,
    this.classificationNote,
  });

  factory ImportSourceLine.fromMap(Map<String, Object?> map) =>
      ImportSourceLine(
        id: map['id']! as String,
        batchId: map['batch_id']! as String,
        sequence: (map['sequence']! as num).toInt(),
        originalText: map['original_text']! as String,
        lineType: ImportLineType.fromValue(map['line_type']! as String),
        heading: map['heading'] as String?,
        inferredSlot: map['inferred_slot'] as String?,
        originalWeek: map['original_week'] as String?,
        classificationNote: map['classification_note'] as String?,
      );

  final String id;
  final String batchId;
  final int sequence;
  final String originalText;
  final ImportLineType lineType;
  final String? heading;
  final String? inferredSlot;
  final String? originalWeek;
  final String? classificationNote;

  ImportSourceLine copyWith({String? batchId}) => ImportSourceLine(
    id: id,
    batchId: batchId ?? this.batchId,
    sequence: sequence,
    originalText: originalText,
    lineType: lineType,
    heading: heading,
    inferredSlot: inferredSlot,
    originalWeek: originalWeek,
    classificationNote: classificationNote,
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'batch_id': batchId,
    'sequence': sequence,
    'original_text': originalText,
    'line_type': lineType.value,
    'heading': heading,
    'inferred_slot': inferredSlot,
    'original_week': originalWeek,
    'classification_note': classificationNote,
  };
}
