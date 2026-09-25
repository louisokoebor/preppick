import 'dart:convert';

import '../models/models.dart';
import '../utils/id_utils.dart';
import 'ai_import_client.dart';
import 'database_service.dart';
import 'import_line_classifier.dart';
import 'meal_service.dart';

/// Conservative, local-only import logic for pasted meal history.
///
/// V1 treats parsed text as review candidates, not trusted data. It only
/// extracts candidate names and writes confirmed meals to the library; it never
/// creates ingredients, quantities or inferred meal types.
class ImportService {
  ImportService(
    this._mealService, [
    DatabaseService? databaseService,
    AiImportClient? aiImportClient,
  ]) : _databaseService = databaseService,
       _aiImportClient = aiImportClient;

  final MealService _mealService;
  final DatabaseService? _databaseService;
  final AiImportClient? _aiImportClient;

  bool get supportsStaging => _databaseService != null;
  bool get supportsAiInterpretation => _aiImportClient?.isConfigured ?? false;

  Future<ImportProposal> interpretWithAi({
    required ImportParseResult parsed,
    required List<ImportLibraryEntry> existingLibrary,
  }) {
    final client = _aiImportClient;
    if (client == null || !client.isConfigured) {
      throw const AiImportException(
        code: 'not_configured',
        userMessage: 'AI meal import is not configured on this build.',
      );
    }
    return client.interpret(
      sourceText: parsed.sourceText,
      sourceLines: parsed.sourceLines,
      existingLibrary: existingLibrary,
    );
  }

  static final RegExp _collapsedWhitespace = RegExp(r'\s+');

  ImportParseResult parse(String sourceText) {
    final candidates = <ImportedMealCandidate>[];
    final duplicateCounts = <String, int>{};
    final sourceLines = <ImportSourceLine>[];
    final rawLines = sourceText.split(RegExp(r'\r?\n'));

    for (var index = 0; index < rawLines.length; index++) {
      final rawLine = rawLines[index];
      final classification = ImportLineClassifier.classify(rawLine);
      final sourceLine = ImportSourceLine(
        id: PrepIds.newId(),
        batchId: '',
        sequence: index + 1,
        originalText: rawLine,
        lineType: classification.type,
        heading: classification.heading,
        classificationNote: classification.note,
      );
      sourceLines.add(sourceLine);
      if (classification.type != ImportLineType.meal) continue;

      final original = rawLine.trim();
      final name = ImportLineClassifier.cleanLine(original);
      if (name.isEmpty) continue;

      final key = normaliseMealName(name);
      duplicateCounts[key] = (duplicateCounts[key] ?? 0) + 1;
      candidates.add(
        ImportedMealCandidate(
          id: PrepIds.newId(),
          name: name,
          originalText: original,
          sourceLineIds: [sourceLine.id],
          isAmbiguous: _looksAmbiguous(name),
        ),
      );
    }

    return ImportParseResult(
      sourceText: sourceText,
      candidates: [
        for (final candidate in candidates)
          candidate.copyWith(
            duplicateKey:
                duplicateCounts[normaliseMealName(candidate.name)]! > 1
                ? normaliseMealName(candidate.name)
                : null,
          ),
      ],
      sourceLines: sourceLines,
    );
  }

  /// Persists a parsed paste without touching the live meal library.
  ///
  /// This is the seam used by the later AI and review stages: source text,
  /// source lines and proposals exist as a recoverable batch before commit.
  Future<ImportBatch> stageParsedImport(ImportParseResult result) async {
    final databaseService = _databaseService;
    if (databaseService == null) {
      throw StateError('Import staging requires a DatabaseService');
    }

    final db = await databaseService.database;
    final timestamp = DateTime.now().toUtc();
    final batch = ImportBatch(
      id: PrepIds.newId(),
      sourceType: ImportSourceType.paste,
      rawText: result.sourceText,
      status: ImportBatchStatus.readyForReview,
      schemaVersion: 1,
      createdAt: timestamp,
      updatedAt: timestamp,
    );
    final sourceLines = [
      for (final line in result.sourceLines) line.copyWith(batchId: batch.id),
    ];
    final sourceLineById = {for (final line in sourceLines) line.id: line};

    await db.transaction((txn) async {
      await txn.insert('import_batches', batch.toMap());
      for (final line in sourceLines) {
        await txn.insert('import_source_lines', line.toMap());
      }
      for (final candidate in result.candidates) {
        final staged = candidate.copyWith(
          batchId: batch.id,
          status: candidate.isAmbiguous
              ? ImportCandidateStatus.needsReview
              : ImportCandidateStatus.proposed,
        );
        await txn.insert('import_candidates', _candidateMap(staged, timestamp));
        for (final sourceLineId in staged.sourceLineIds) {
          final sourceLine = sourceLineById[sourceLineId];
          await txn.insert(
            'import_candidate_sources',
            ImportCandidateSource(
              candidateId: staged.id,
              sourceLineId: sourceLineId,
              sourceText: sourceLine?.originalText,
            ).toMap(),
          );
        }
      }
    });

    return batch;
  }

  /// Restores the newest unfinished import so a process restart does not
  /// discard the household's pasted notes or review candidates.
  Future<StagedImport?> loadLatestDraft() async {
    final databaseService = _databaseService;
    if (databaseService == null) return null;

    final db = await databaseService.database;
    final batchRows = await db.query(
      'import_batches',
      where: 'status IN (?, ?, ?, ?)',
      whereArgs: [
        ImportBatchStatus.draft.value,
        ImportBatchStatus.processing.value,
        ImportBatchStatus.readyForReview.value,
        ImportBatchStatus.partiallyReviewed.value,
      ],
      orderBy: 'updated_at DESC',
      limit: 1,
    );
    if (batchRows.isEmpty) return null;

    final batch = ImportBatch.fromMap(batchRows.single);
    final sourceRows = await db.query(
      'import_source_lines',
      where: 'batch_id = ?',
      whereArgs: [batch.id],
      orderBy: 'sequence ASC',
    );
    final sourceLines = sourceRows.map(ImportSourceLine.fromMap).toList();
    final candidateRows = await db.query(
      'import_candidates',
      where: 'batch_id = ?',
      whereArgs: [batch.id],
      orderBy: 'created_at ASC',
    );
    final candidates = <ImportedMealCandidate>[];
    for (final row in candidateRows) {
      final sourceRowsForCandidate = await db.query(
        'import_candidate_sources',
        columns: ['source_line_id'],
        where: 'candidate_id = ?',
        whereArgs: [row['id']],
      );
      candidates.add(
        _candidateFromMap(
          row,
          sourceRowsForCandidate
              .map((source) => source['source_line_id']! as String)
              .toList(),
        ),
      );
    }
    return StagedImport(
      batch: batch,
      sourceLines: sourceLines,
      candidates: candidates,
    );
  }

  Future<void> updateStagedCandidate(ImportedMealCandidate candidate) async {
    final databaseService = _databaseService;
    final batchId = candidate.batchId;
    if (databaseService == null || batchId == null) return;

    final timestamp = DateTime.now().toUtc();
    final db = await databaseService.database;
    await db.update(
      'import_candidates',
      {
        'proposal_json': jsonEncode(_candidateProposal(candidate)),
        'status': ImportCandidateStatus.edited.value,
        'matched_existing_id': candidate.matchedExistingId,
        'confidence_band': candidate.confidenceBand?.value,
        'review_note': candidate.reviewNote,
        'updated_at': timestamp.toIso8601String(),
      },
      where: 'id = ? AND batch_id = ?',
      whereArgs: [candidate.id, batchId],
    );
    await updateBatchStatus(batchId, ImportBatchStatus.partiallyReviewed);
  }

  Future<void> updateBatchStatus(
    String batchId,
    ImportBatchStatus status,
  ) async {
    final databaseService = _databaseService;
    if (databaseService == null) return;
    final db = await databaseService.database;
    await db.update(
      'import_batches',
      {
        'status': status.value,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [batchId],
    );
  }

  Future<void> cancelBatch(String batchId) =>
      updateBatchStatus(batchId, ImportBatchStatus.cancelled);

  /// Confirms selected, typed candidates into the meal library.
  ///
  /// Exact normalised repeats in the same reviewed batch are imported once and
  /// linked back to every matching candidate. Already-confirmed candidates are
  /// skipped so repeated confirmation cannot duplicate the same batch.
  Future<ImportConfirmationResult> confirmCandidates(
    List<ImportedMealCandidate> candidates,
  ) async {
    final importedByKey = <String, String>{};
    final updated = <ImportedMealCandidate>[];
    var createdCount = 0;

    for (final candidate in candidates) {
      final type = candidate.mealType;
      if (!candidate.isIncluded || type == null || candidate.isConfirmed) {
        updated.add(candidate);
        continue;
      }

      final key = '${normaliseMealName(candidate.name)}|${type.value}';
      final existingMealId = importedByKey[key];
      if (existingMealId != null) {
        updated.add(candidate.copyWith(importedMealId: existingMealId));
        continue;
      }

      final meal = await _mealService.addMeal(
        familyName: candidate.name,
        mealType: type,
      );
      importedByKey[key] = meal.id;
      createdCount++;
      updated.add(candidate.copyWith(importedMealId: meal.id));
    }

    return ImportConfirmationResult(
      candidates: updated,
      createdCount: createdCount,
    );
  }

  static String normaliseMealName(String name) =>
      name.trim().replaceAll(_collapsedWhitespace, ' ').toLowerCase();

  static bool _looksAmbiguous(String name) {
    final lower = name.toLowerCase();
    if (RegExp(
      r'^(mon|tue|wed|thu|fri|sat|sun)(day)?\s*[:\-]',
    ).hasMatch(lower)) {
      return true;
    }
    if (RegExp(r'^\d{1,2}[\/.-]\d{1,2}').hasMatch(lower)) return true;
    if (RegExp(r'^rice\s+(?:and|with|\+)\s+fish$').hasMatch(lower)) {
      return true;
    }
    return false;
  }

  static Map<String, Object?> _candidateMap(
    ImportedMealCandidate candidate,
    DateTime timestamp,
  ) => {
    'id': candidate.id,
    'batch_id': candidate.batchId,
    'entity_type': ImportCandidateEntityType.variant.value,
    'proposal_json': jsonEncode(_candidateProposal(candidate)),
    'status': candidate.status.value,
    'matched_existing_id': candidate.matchedExistingId,
    'confidence_band': candidate.confidenceBand?.value,
    'review_note': candidate.reviewNote,
    'created_at': timestamp.toIso8601String(),
    'updated_at': timestamp.toIso8601String(),
  };

  static Map<String, Object?> _candidateProposal(
    ImportedMealCandidate candidate,
  ) => {
    'name': candidate.name,
    'original_text': candidate.originalText,
    'meal_type': candidate.mealType?.value,
    'is_included': candidate.isIncluded,
    'duplicate_key': candidate.duplicateKey,
    'is_ambiguous': candidate.isAmbiguous,
    'imported_meal_id': candidate.importedMealId,
  };

  static ImportedMealCandidate _candidateFromMap(
    Map<String, Object?> row,
    List<String> sourceLineIds,
  ) {
    final proposal =
        jsonDecode(row['proposal_json']! as String) as Map<String, dynamic>;
    final mealTypeValue = proposal['meal_type'] as String?;
    final statusValue = row['status']! as String;
    final confidenceValue = row['confidence_band'] as String?;
    return ImportedMealCandidate(
      id: row['id']! as String,
      name: proposal['name'] as String? ?? '',
      originalText: proposal['original_text'] as String? ?? '',
      mealType: mealTypeValue == null
          ? null
          : MealType.fromValue(mealTypeValue),
      isIncluded: proposal['is_included'] as bool? ?? true,
      duplicateKey: proposal['duplicate_key'] as String?,
      isAmbiguous: proposal['is_ambiguous'] as bool? ?? false,
      importedMealId: proposal['imported_meal_id'] as String?,
      batchId: row['batch_id']! as String,
      sourceLineIds: sourceLineIds,
      status: ImportCandidateStatus.values.firstWhere(
        (status) => status.value == statusValue,
        orElse: () => ImportCandidateStatus.proposed,
      ),
      matchedExistingId: row['matched_existing_id'] as String?,
      confidenceBand: confidenceValue == null
          ? null
          : ImportConfidenceBand.values.firstWhere(
              (band) => band.value == confidenceValue,
              orElse: () => ImportConfidenceBand.low,
            ),
      reviewNote: row['review_note'] as String?,
    );
  }
}

class StagedImport {
  const StagedImport({
    required this.batch,
    required this.sourceLines,
    required this.candidates,
  });

  final ImportBatch batch;
  final List<ImportSourceLine> sourceLines;
  final List<ImportedMealCandidate> candidates;
}

class ImportConfirmationResult {
  const ImportConfirmationResult({
    required this.candidates,
    required this.createdCount,
  });

  final List<ImportedMealCandidate> candidates;
  final int createdCount;
}
