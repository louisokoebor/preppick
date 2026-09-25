import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/models.dart';
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

  String _sourceText = '';
  List<ImportedMealCandidate> _candidates = const [];
  bool _isParsing = false;
  bool _isConfirming = false;
  Object? _error;
  int _createdCount = 0;
  String? _batchId;

  String get sourceText => _sourceText;
  List<ImportedMealCandidate> get candidates => _candidates;
  bool get isParsing => _isParsing;
  bool get isConfirming => _isConfirming;
  Object? get error => _error;
  int get createdCount => _createdCount;
  String? get batchId => _batchId;

  /// Restores the newest unfinished staged import after an app restart.
  Future<void> restoreDraft() async {
    final staged = await _service.loadLatestDraft();
    if (staged == null) return;
    _batchId = staged.batch.id;
    _sourceText = staged.batch.rawText;
    _candidates = staged.candidates;
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
      _createdCount = 0;
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

  void includeCandidate(String id, bool isIncluded) {
    _replaceCandidate(id, (candidate) {
      return candidate.copyWith(isIncluded: isIncluded);
    });
  }

  void renameCandidate(String id, String name) {
    _candidates = [
      for (final candidate in _candidates)
        candidate.id == id ? candidate.copyWith(name: name.trim()) : candidate,
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
    _isParsing = false;
    _isConfirming = false;
    _error = null;
    _createdCount = 0;
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
        candidate.id == id ? replace(candidate) : candidate,
    ];
    _persistCandidate(id);
    notifyListeners();
  }

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
