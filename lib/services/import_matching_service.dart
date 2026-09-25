import '../models/models.dart';

enum ImportMatchKind { exactVariant, exactAlias, familyOnly, noMatch }

class ImportMatch {
  const ImportMatch({
    required this.familyTempId,
    required this.variantTempId,
    required this.kind,
    this.existingVariantId,
    this.existingFamilyId,
    this.reason,
  });

  final String familyTempId;
  final String variantTempId;
  final ImportMatchKind kind;
  final String? existingVariantId;
  final String? existingFamilyId;
  final String? reason;

  bool get hasExistingVariant => existingVariantId != null;
}

/// Deterministic matching that runs before and after AI interpretation.
///
/// Matching is intentionally conservative: exact normalized labels and
/// aliases are safe merges; family-only matches are suggestions for review,
/// never automatic variant merges.
class ImportMatchingService {
  const ImportMatchingService();

  List<ImportMatch> matchProposal(
    ImportProposal proposal,
    List<ImportLibraryEntry> library,
  ) {
    final matches = <ImportMatch>[];
    for (final family in proposal.families) {
      for (final variant in family.variants) {
        matches.add(_matchVariant(family, variant, library));
      }
    }
    return matches;
  }

  ImportMatch _matchVariant(
    ImportFamilyProposal family,
    ImportVariantProposal variant,
    List<ImportLibraryEntry> library,
  ) {
    final displayKey = normalizeLabel(variant.displayName);
    final familyKey = normalizeLabel(family.preferredName);
    for (final entry in library) {
      if (normalizeLabel(entry.variantName) == displayKey) {
        return ImportMatch(
          familyTempId: family.tempId,
          variantTempId: variant.tempId,
          kind: ImportMatchKind.exactVariant,
          existingVariantId: entry.id,
          existingFamilyId: entry.familyId,
          reason: 'Exact normalized variant match',
        );
      }
      if (entry.aliases.any((alias) => normalizeLabel(alias) == displayKey)) {
        return ImportMatch(
          familyTempId: family.tempId,
          variantTempId: variant.tempId,
          kind: ImportMatchKind.exactAlias,
          existingVariantId: entry.id,
          existingFamilyId: entry.familyId,
          reason: 'Exact normalized alias match',
        );
      }
    }
    final familyMatch = library.where(
      (entry) => normalizeLabel(entry.familyName) == familyKey,
    );
    if (familyMatch.isNotEmpty) {
      return ImportMatch(
        familyTempId: family.tempId,
        variantTempId: variant.tempId,
        kind: ImportMatchKind.familyOnly,
        existingFamilyId: familyMatch.first.familyId,
        reason: 'Existing family found; variant requires review',
      );
    }
    return ImportMatch(
      familyTempId: family.tempId,
      variantTempId: variant.tempId,
      kind: ImportMatchKind.noMatch,
      reason: 'No deterministic library match',
    );
  }

  static String normalizeLabel(String value) {
    var normalized = value.toLowerCase().trim();
    normalized = normalized.replaceAll('&', ' and ');
    normalized = normalized.replaceAll('+', ' and ');
    normalized = normalized.replaceAll(RegExp(r"['’]"), '');
    normalized = normalized.replaceAll(RegExp(r'[^a-z0-9]+'), ' ');
    final words = normalized
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .map(_normalizeAbbreviation)
        .toList();
    return words.join(' ');
  }

  static String _normalizeAbbreviation(String word) => switch (word) {
    'spag' || 'spaghett' => 'spaghetti',
    'chkn' => 'chicken',
    'yog' => 'yogurt',
    _ => word,
  };
}
