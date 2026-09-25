import 'package:flutter_test/flutter_test.dart';
import 'package:preppick/models/models.dart';
import 'package:preppick/services/import_matching_service.dart';

ImportProposal proposal({
  String familyName = 'Lou Lou Spag',
  String displayName = 'Lou Lou Spag + Fish',
}) => ImportProposal(
  schemaVersion: '1',
  families: [
    ImportFamilyProposal(
      tempId: 'family-1',
      preferredName: familyName,
      aliases: const [],
      variants: [
        ImportVariantProposal(
          tempId: 'variant-1',
          displayName: displayName,
          componentNames: const ['Fish'],
          mealSlot: 'dinner',
          sourceLineIds: const ['line-1'],
          confidenceBand: 'high',
          needsReviewReason: null,
        ),
      ],
    ),
  ],
  unresolved: const [],
);

void main() {
  const matcher = ImportMatchingService();

  test('normalizes household abbreviations for exact variant matches', () {
    final matches = matcher.matchProposal(proposal(), const [
      ImportLibraryEntry(
        id: 'variant-1',
        familyId: 'family-1',
        familyName: 'Lou Lou Spaghetti',
        variantName: 'Lou Lou Spaghetti + Fish',
      ),
    ]);

    expect(matches.single.kind, ImportMatchKind.exactVariant);
    expect(matches.single.existingVariantId, 'variant-1');
  });

  test('matches aliases exactly but identifies the alias path', () {
    final matches = matcher.matchProposal(
      proposal(displayName: 'yogurt chicken with rice'),
      const [
        ImportLibraryEntry(
          id: 'variant-1',
          familyId: 'family-1',
          familyName: 'Rice',
          variantName: 'Rice + Yogurt Chicken',
          aliases: ['yogurt chicken with rice'],
        ),
      ],
    );

    expect(matches.single.kind, ImportMatchKind.exactAlias);
    expect(matches.single.existingVariantId, 'variant-1');
  });

  test('family-only matches are never treated as variant merges', () {
    final matches = matcher
        .matchProposal(proposal(displayName: 'Lou Lou Spag + Turkey'), const [
          ImportLibraryEntry(
            id: 'variant-1',
            familyId: 'family-1',
            familyName: 'Lou Lou Spaghetti',
            variantName: 'Lou Lou Spaghetti + Fish',
          ),
        ]);

    expect(matches.single.kind, ImportMatchKind.familyOnly);
    expect(matches.single.existingVariantId, isNull);
    expect(matches.single.existingFamilyId, 'family-1');
  });

  test('plain rice and jollof rice remain distinct families', () {
    final matches = matcher.matchProposal(
      proposal(familyName: 'Jollof Rice', displayName: 'Jollof Rice + Salmon'),
      const [
        ImportLibraryEntry(
          id: 'variant-1',
          familyId: 'family-1',
          familyName: 'Rice',
          variantName: 'Rice + Salmon',
        ),
      ],
    );

    expect(matches.single.kind, ImportMatchKind.noMatch);
  });
}
