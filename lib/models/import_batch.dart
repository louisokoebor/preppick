import '../utils/date_utils.dart';

/// Where an import batch came from. Paste is the only source supported in
/// Phase 2's first slice; the other values reserve stable database values for
/// later document extractors.
enum ImportSourceType {
  paste('paste'),
  txt('txt'),
  csv('csv'),
  pdf('pdf');

  const ImportSourceType(this.value);

  final String value;

  static ImportSourceType fromValue(String value) =>
      ImportSourceType.values.firstWhere(
        (type) => type.value == value,
        orElse: () => throw ArgumentError.value(
          value,
          'value',
          'Unknown ImportSourceType',
        ),
      );
}

enum ImportBatchStatus {
  draft('draft'),
  processing('processing'),
  readyForReview('ready_for_review'),
  partiallyReviewed('partially_reviewed'),
  committed('committed'),
  failed('failed'),
  cancelled('cancelled');

  const ImportBatchStatus(this.value);

  final String value;

  static ImportBatchStatus fromValue(String value) =>
      ImportBatchStatus.values.firstWhere(
        (status) => status.value == value,
        orElse: () => throw ArgumentError.value(
          value,
          'value',
          'Unknown ImportBatchStatus',
        ),
      );
}

/// A persisted import attempt. It owns the original text and the staged
/// proposals derived from it until the user explicitly confirms them.
class ImportBatch {
  const ImportBatch({
    required this.id,
    required this.sourceType,
    required this.rawText,
    required this.status,
    required this.schemaVersion,
    required this.createdAt,
    required this.updatedAt,
    this.sourceFilename,
  });

  factory ImportBatch.fromMap(Map<String, Object?> map) => ImportBatch(
    id: map['id']! as String,
    sourceType: ImportSourceType.fromValue(map['source_type']! as String),
    sourceFilename: map['source_filename'] as String?,
    rawText: map['raw_text']! as String,
    status: ImportBatchStatus.fromValue(map['status']! as String),
    schemaVersion: (map['schema_version']! as num).toInt(),
    createdAt: PrepDates.fromIso(map['created_at']! as String),
    updatedAt: PrepDates.fromIso(map['updated_at']! as String),
  );

  final String id;
  final ImportSourceType sourceType;
  final String? sourceFilename;
  final String rawText;
  final ImportBatchStatus status;
  final int schemaVersion;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, Object?> toMap() => {
    'id': id,
    'source_type': sourceType.value,
    'source_filename': sourceFilename,
    'raw_text': rawText,
    'status': status.value,
    'schema_version': schemaVersion,
    'created_at': PrepDates.toIso(createdAt),
    'updated_at': PrepDates.toIso(updatedAt),
  };

  ImportBatch copyWith({ImportBatchStatus? status, DateTime? updatedAt}) =>
      ImportBatch(
        id: id,
        sourceType: sourceType,
        sourceFilename: sourceFilename,
        rawText: rawText,
        status: status ?? this.status,
        schemaVersion: schemaVersion,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}
