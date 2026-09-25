import 'meal_family.dart';
import 'import_source_line.dart';

enum ImportCandidateStatus {
  proposed('proposed'),
  approved('approved'),
  edited('edited'),
  needsReview('needs_review'),
  rejected('rejected'),
  committed('committed');

  const ImportCandidateStatus(this.value);

  final String value;
}

enum ImportCandidateEntityType {
  family('family'),
  variant('variant'),
  component('component'),
  unresolved('unresolved');

  const ImportCandidateEntityType(this.value);

  final String value;
}

enum ImportConfidenceBand {
  high('high'),
  medium('medium'),
  low('low');

  const ImportConfidenceBand(this.value);

  final String value;
}

/// A parsed line from pasted meal history, waiting for human review.
///
/// This is deliberately not a persistent meal model. It can become a
/// [MealVariant] only after the user includes it and assigns a meal type.
class ImportedMealCandidate {
  const ImportedMealCandidate({
    required this.id,
    required this.name,
    required this.originalText,
    this.mealType,
    this.isIncluded = true,
    this.duplicateKey,
    this.isAmbiguous = false,
    this.importedMealId,
    this.batchId,
    this.sourceLineIds = const [],
    this.status = ImportCandidateStatus.proposed,
    this.matchedExistingId,
    this.confidenceBand,
    this.reviewNote,
  });

  final String id;
  final String name;

  /// The exact line this candidate came from, before bullets or numbering
  /// were stripped. Kept visible for review so parsing never becomes opaque.
  final String originalText;

  final MealType? mealType;
  final bool isIncluded;

  /// Non-null when another parsed candidate has the same normalised name.
  final String? duplicateKey;

  /// True when the line contains extra structure the baseline parser refuses
  /// to interpret, such as "Monday: Pasta".
  final bool isAmbiguous;

  /// Set after confirmation. A second confirm skips candidates that already
  /// resolved to a meal, preventing accidental duplicate writes.
  final String? importedMealId;

  /// Set once the candidate has been persisted as part of an import batch.
  final String? batchId;

  /// Source evidence is stored as stable line IDs, never as guessed database
  /// IDs from an AI response.
  final List<String> sourceLineIds;

  final ImportCandidateStatus status;
  final String? matchedExistingId;
  final ImportConfidenceBand? confidenceBand;
  final String? reviewNote;

  bool get isDuplicate => duplicateKey != null;
  bool get isConfirmed => importedMealId != null;
  bool get canConfirm => isIncluded && mealType != null && !isConfirmed;

  ImportedMealCandidate copyWith({
    String? name,
    MealType? mealType,
    bool clearMealType = false,
    bool? isIncluded,
    String? duplicateKey,
    bool clearDuplicateKey = false,
    bool? isAmbiguous,
    String? importedMealId,
    String? batchId,
    List<String>? sourceLineIds,
    ImportCandidateStatus? status,
    String? matchedExistingId,
    bool clearMatchedExistingId = false,
    ImportConfidenceBand? confidenceBand,
    String? reviewNote,
  }) {
    return ImportedMealCandidate(
      id: id,
      name: name ?? this.name,
      originalText: originalText,
      mealType: clearMealType ? null : mealType ?? this.mealType,
      isIncluded: isIncluded ?? this.isIncluded,
      duplicateKey: clearDuplicateKey
          ? null
          : duplicateKey ?? this.duplicateKey,
      isAmbiguous: isAmbiguous ?? this.isAmbiguous,
      importedMealId: importedMealId ?? this.importedMealId,
      batchId: batchId ?? this.batchId,
      sourceLineIds: sourceLineIds ?? this.sourceLineIds,
      status: status ?? this.status,
      matchedExistingId: clearMatchedExistingId
          ? null
          : matchedExistingId ?? this.matchedExistingId,
      confidenceBand: confidenceBand ?? this.confidenceBand,
      reviewNote: reviewNote ?? this.reviewNote,
    );
  }
}

/// The full result of parsing pasted history.
class ImportParseResult {
  const ImportParseResult({
    required this.sourceText,
    required this.candidates,
    this.sourceLines = const [],
  });

  final String sourceText;
  final List<ImportedMealCandidate> candidates;
  final List<ImportSourceLine> sourceLines;
}
