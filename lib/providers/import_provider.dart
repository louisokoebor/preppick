import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/models.dart';
import '../services/ai_import_client.dart';
import '../services/import_matching_service.dart';
import '../services/import_service.dart';
import '../utils/error_messages.dart';

/// Owns the import flow's in-memory state.
///
/// The pasted source text and review candidates intentionally survive
/// navigation between the import and review screens. They are cleared only when
/// a new source is parsed or the caller explicitly starts over.
class ImportProvider extends ChangeNotifier {
  ImportProvider(this._service);

  final ImportService _service;
  static const _matcher = ImportMatchingService();

  String _sourceText = '';
  List<ImportedMealCandidate> _candidates = const [];
  bool _isParsing = false;
  bool _isConfirming = false;
  Object? _error;
  int _createdCount = 0;
  String? _batchId;
  List<ImportSourceLine> _sourceLines = const [];
  ImportProposal? _aiProposal;
  List<ImportMatch> _aiMatches = const [];
  bool _isInterpretingAi = false;

  String get sourceText => _sourceText;
  List<ImportedMealCandidate> get candidates => _candidates;
  bool get isParsing => _isParsing;
  bool get isConfirming => _isConfirming;
  Object? get error => _error;
  int get createdCount => _createdCount;
  String? get batchId => _batchId;
  bool get supportsAiInterpretation => _service.supportsAiInterpretation;
  bool get isInterpretingAi => _isInterpretingAi;
  ImportProposal? get aiProposal => _aiProposal;
  List<ImportMatch> get aiMatches => _aiMatches;

  /// Restores the newest unfinished staged import after an app restart.
  Future<void> restoreDraft() async {
    final staged = await _service.loadLatestDraft();
    if (staged == null) return;
    _batchId = staged.batch.id;
    _sourceText = staged.batch.rawText;
    _candidates = staged.candidates;
    _sourceLines = staged.sourceLines;
    notifyListeners();
  }

  List<ImportedMealCandidate> get includedCandidates =>
      _candidates.where((candidate) => candidate.isIncluded).toList();

  bool get canContinue => _sourceText.trim().isNotEmpty;
  bool get hasCandidates => _candidates.isNotEmpty;
  bool get hasConfirmableCandidates => _candidates.any((c) => c.canConfirm);
  bool get hasSelectedCandidateWithoutType =>
      _candidates.any((c) => c.isIncluded && c.mealType == null);
  bool get canConfirm =>
      !_isConfirming &&
      includedCandidates.isNotEmpty &&
      !hasSelectedCandidateWithoutType &&
      hasConfirmableCandidates;

  void updateSourceText(String value) {
    _sourceText = value;
    if (value.trim().isNotEmpty && _error is BlankImportException) {
      _error = null;
    }
    notifyListeners();
  }

  Future<bool> parseSource() async {
    if (_sourceText.trim().isEmpty) {
      _error = const BlankImportException();
      notifyListeners();
      return false;
    }

    _isParsing = true;
    _error = null;
    notifyListeners();

    try {
      final result = _service.parse(_sourceText);
      _sourceText = result.sourceText;
      _candidates = result.candidates;
      _sourceLines = result.sourceLines;
      _createdCount = 0;
      _aiProposal = null;
      _aiMatches = const [];
      if (_service.supportsStaging) {
        final batch = await _service.stageParsedImport(result);
        _batchId = batch.id;
        _candidates = [
          for (final candidate in _candidates)
            candidate.copyWith(
              batchId: batch.id,
              status: candidate.isAmbiguous
                  ? ImportCandidateStatus.needsReview
                  : ImportCandidateStatus.proposed,
            ),
        ];
        _sourceLines = [
          for (final line in result.sourceLines)
            line.copyWith(batchId: batch.id),
        ];
      }
      return true;
    } catch (error) {
      _error = error;
      return false;
    } finally {
      _isParsing = false;
      notifyListeners();
    }
  }

  /// Sends the staged source to the secure server-side interpreter, then
  /// applies only review metadata to the local candidates. No meal-library
  /// records are created here; that still requires [confirmImport].
  Future<bool> interpretWithAi(List<ImportLibraryEntry> existingLibrary) async {
    if (!supportsAiInterpretation || _sourceText.trim().isEmpty) {
      _error = const AiImportException(
        code: 'not_configured',
        userMessage: 'AI meal import is not configured on this build.',
      );
      notifyListeners();
      return false;
    }

    _isInterpretingAi = true;
    _error = null;
    notifyListeners();
    try {
      final parsed = ImportParseResult(
        sourceText: _sourceText,
        candidates: _candidates,
        sourceLines: _sourceLines,
      );
      final proposal = await _service.interpretWithAi(
        parsed: parsed,
        existingLibrary: existingLibrary,
      );
      final matches = _matcher.matchProposal(proposal, existingLibrary);
      _aiProposal = proposal;
      _aiMatches = matches;
      _candidates = _withDuplicateFlags(
        _applyProposal(_candidates, proposal, matches),
      );
      if (_service.supportsStaging) {
        await Future.wait([
          for (final candidate in _candidates)
            _service.updateStagedCandidate(candidate),
        ]);
      }
      return true;
    } catch (error) {
      _error = error;
      return false;
    } finally {
      _isInterpretingAi = false;
      notifyListeners();
    }
  }

  void includeCandidate(String id, bool isIncluded) {
    _replaceCandidate(id, (candidate) {
      return candidate.copyWith(isIncluded: isIncluded);
    });
  }

  void renameCandidate(String id, String name) {
    _candidates = [
      for (final candidate in _candidates)
        candidate.id == id
            ? candidate.copyWith(
                name: name.trim(),
                status: candidate.isConfirmed
                    ? candidate.status
                    : ImportCandidateStatus.edited,
              )
            : candidate,
    ];
    _candidates = _withDuplicateFlags(_candidates);
    _persistCandidate(id);
    notifyListeners();
  }

  void assignMealType(String id, MealType? mealType) {
    _replaceCandidate(id, (candidate) {
      return candidate.copyWith(
        mealType: mealType,
        clearMealType: mealType == null,
      );
    });
  }

  Future<int> confirmImport() async {
    if (includedCandidates.isEmpty) {
      _error = const EmptyImportSelectionException();
      notifyListeners();
      return 0;
    }
    if (hasSelectedCandidateWithoutType) {
      _error = const MissingImportMealTypeException();
      notifyListeners();
      return 0;
    }

    _isConfirming = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _service.confirmCandidates(_candidates);
      _candidates = result.candidates;
      _createdCount += result.createdCount;
      return result.createdCount;
    } catch (error) {
      _error = error;
      return 0;
    } finally {
      _isConfirming = false;
      notifyListeners();
    }
  }

  void reset() {
    _sourceText = '';
    _candidates = const [];
    _sourceLines = const [];
    _isParsing = false;
    _isConfirming = false;
    _error = null;
    _createdCount = 0;
    _aiProposal = null;
    _aiMatches = const [];
    final batchId = _batchId;
    if (batchId != null) unawaited(_service.cancelBatch(batchId));
    _batchId = null;
    notifyListeners();
  }

  void _replaceCandidate(
    String id,
    ImportedMealCandidate Function(ImportedMealCandidate candidate) replace,
  ) {
    _candidates = [
      for (final candidate in _candidates)
        candidate.id == id
            ? replace(candidate).copyWith(
                status: candidate.isConfirmed
                    ? candidate.status
                    : ImportCandidateStatus.edited,
              )
            : candidate,
    ];
    _persistCandidate(id);
    notifyListeners();
  }

  static List<ImportedMealCandidate> _applyProposal(
    List<ImportedMealCandidate> candidates,
    ImportProposal proposal,
    List<ImportMatch> matches,
  ) {
    final variants = [
      for (final family in proposal.families)
        for (final variant in family.variants)
          (family: family, variant: variant),
    ];
    final matchByVariant = {
      for (final match in matches) match.variantTempId: match,
    };
    final unresolvedByLine = <String, ImportUnresolvedProposal>{
      for (final unresolved in proposal.unresolved)
        for (final lineId in unresolved.sourceLineIds) lineId: unresolved,
    };

    return [
      for (final candidate in candidates)
        _applyProposalToCandidate(
          candidate,
          variants,
          matchByVariant,
          unresolvedByLine,
        ),
    ];
  }

  static ImportedMealCandidate _applyProposalToCandidate(
    ImportedMealCandidate candidate,
    List<({ImportFamilyProposal family, ImportVariantProposal variant})>
    variants,
    Map<String, ImportMatch> matchByVariant,
    Map<String, ImportUnresolvedProposal> unresolvedByLine,
  ) {
    final matched = variants.where(
      (entry) =>
          entry.variant.sourceLineIds.any(candidate.sourceLineIds.contains),
    );
    final entry = matched.isEmpty ? null : matched.first;
    if (entry != null) {
      final match = matchByVariant[entry.variant.tempId];
      final notes = <String>[
        'AI grouped this under ${entry.family.preferredName}.',
        if (entry.variant.mealSlot != null)
          'Suggested type: ${entry.variant.mealSlot}.',
        if (entry.variant.needsReviewReason != null)
          entry.variant.needsReviewReason!,
        if (match?.reason != null) match!.reason!,
      ];
      return candidate.copyWith(
        name: entry.variant.displayName,
        status: ImportCandidateStatus.needsReview,
        matchedExistingId: match?.existingVariantId,
        confidenceBand: _confidenceBand(entry.variant.confidenceBand),
        reviewNote: notes.join(' '),
      );
    }

    ImportUnresolvedProposal? unresolved;
    for (final lineId in candidate.sourceLineIds) {
      final candidateUnresolved = unresolvedByLine[lineId];
      if (candidateUnresolved != null) {
        unresolved = candidateUnresolved;
        break;
      }
    }
    if (unresolved == null) return candidate;
    return candidate.copyWith(
      status: ImportCandidateStatus.needsReview,
      confidenceBand: ImportConfidenceBand.low,
      reviewNote: 'AI could not resolve this line: ${unresolved.reason}',
    );
  }

  static ImportConfidenceBand _confidenceBand(String value) =>
      ImportConfidenceBand.values.firstWhere(
        (band) => band.value == value,
        orElse: () => ImportConfidenceBand.low,
      );

  void _persistCandidate(String id) {
    for (final candidate in _candidates) {
      if (candidate.id == id) {
        unawaited(_service.updateStagedCandidate(candidate));
        return;
      }
    }
  }

  static List<ImportedMealCandidate> _withDuplicateFlags(
    List<ImportedMealCandidate> candidates,
  ) {
    final counts = <String, int>{};
    for (final candidate in candidates) {
      final key = ImportService.normaliseMealName(candidate.name);
      counts[key] = (counts[key] ?? 0) + 1;
    }
    return [
      for (final candidate in candidates)
        candidate.copyWith(
          duplicateKey:
              counts[ImportService.normaliseMealName(candidate.name)]! > 1
              ? ImportService.normaliseMealName(candidate.name)
              : null,
          clearDuplicateKey:
              counts[ImportService.normaliseMealName(candidate.name)]! <= 1,
        ),
    ];
  }
}

/// The three failures below are the household's own mistakes, not the app's,
/// so each carries copy meant to be shown as-is. Everything else the import
/// can throw — a failed write, most obviously — is internal and reaches the
/// screen as the generic message instead.
class BlankImportException implements PrepUserFacingException {
  const BlankImportException();

  @override
  String get userMessage => 'Paste at least one meal before continuing.';

  @override
  String toString() => 'BlankImportException: $userMessage';
}

class EmptyImportSelectionException implements PrepUserFacingException {
  const EmptyImportSelectionException();

  @override
  String get userMessage => 'Select at least one meal to import.';

  @override
  String toString() => 'EmptyImportSelectionException: $userMessage';
}

class MissingImportMealTypeException implements PrepUserFacingException {
  const MissingImportMealTypeException();

  @override
  String get userMessage => 'Assign a meal type to each selected meal.';

  @override
  String toString() => 'MissingImportMealTypeException: $userMessage';
}
