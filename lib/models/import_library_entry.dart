/// Compact existing-library record sent to the import interpreter and matcher.
class ImportLibraryEntry {
  const ImportLibraryEntry({
    required this.id,
    required this.familyId,
    required this.familyName,
    required this.variantName,
    this.aliases = const [],
  });

  final String id;
  final String familyId;
  final String familyName;
  final String variantName;
  final List<String> aliases;

  Map<String, Object?> toJson() => {
    'id': id,
    'family_id': familyId,
    'family_name': familyName,
    'variant_name': variantName,
    'aliases': aliases,
  };
}
