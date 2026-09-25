class ImportProposal {
  const ImportProposal({
    required this.schemaVersion,
    required this.families,
    required this.unresolved,
  });

  factory ImportProposal.fromJson(Map<String, dynamic> json) {
    if (json['schema_version'] != '1' ||
        json['families'] is! List ||
        json['unresolved'] is! List) {
      throw const FormatException('Unsupported import proposal');
    }
    return ImportProposal(
      schemaVersion: json['schema_version'] as String,
      families: [
        for (final family in json['families'] as List<dynamic>)
          ImportFamilyProposal.fromJson(family),
      ],
      unresolved: [
        for (final unresolved in json['unresolved'] as List<dynamic>)
          ImportUnresolvedProposal.fromJson(unresolved),
      ],
    );
  }

  final String schemaVersion;
  final List<ImportFamilyProposal> families;
  final List<ImportUnresolvedProposal> unresolved;
}

class ImportFamilyProposal {
  const ImportFamilyProposal({
    required this.tempId,
    required this.preferredName,
    required this.aliases,
    required this.variants,
  });

  factory ImportFamilyProposal.fromJson(Object? value) {
    if (value is! Map<String, dynamic> || value['variants'] is! List) {
      throw const FormatException('Invalid family proposal');
    }
    return ImportFamilyProposal(
      tempId: _requiredString(value['temp_id']),
      preferredName: _requiredString(value['preferred_name']),
      aliases: _stringList(value['aliases']),
      variants: [
        for (final variant in value['variants'] as List<dynamic>)
          ImportVariantProposal.fromJson(variant),
      ],
    );
  }

  final String tempId;
  final String preferredName;
  final List<String> aliases;
  final List<ImportVariantProposal> variants;
}

class ImportVariantProposal {
  const ImportVariantProposal({
    required this.tempId,
    required this.displayName,
    required this.componentNames,
    required this.mealSlot,
    required this.sourceLineIds,
    required this.confidenceBand,
    required this.needsReviewReason,
  });

  factory ImportVariantProposal.fromJson(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Invalid variant proposal');
    }
    final slot = value['meal_slot'];
    if (slot != null && slot is! String) {
      throw const FormatException('Invalid meal slot');
    }
    final confidence = _requiredString(value['confidence_band']);
    if (!{'high', 'medium', 'low'}.contains(confidence)) {
      throw const FormatException('Invalid confidence band');
    }
    final reviewReason = value['needs_review_reason'];
    if (reviewReason != null && reviewReason is! String) {
      throw const FormatException('Invalid review reason');
    }
    return ImportVariantProposal(
      tempId: _requiredString(value['temp_id']),
      displayName: _requiredString(value['display_name']),
      componentNames: _stringList(value['component_names']),
      mealSlot: slot as String?,
      sourceLineIds: _stringList(value['source_line_ids']),
      confidenceBand: confidence,
      needsReviewReason: reviewReason as String?,
    );
  }

  final String tempId;
  final String displayName;
  final List<String> componentNames;
  final String? mealSlot;
  final List<String> sourceLineIds;
  final String confidenceBand;
  final String? needsReviewReason;
}

class ImportUnresolvedProposal {
  const ImportUnresolvedProposal({
    required this.sourceLineIds,
    required this.originalText,
    required this.reason,
  });

  factory ImportUnresolvedProposal.fromJson(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Invalid unresolved proposal');
    }
    return ImportUnresolvedProposal(
      sourceLineIds: _stringList(value['source_line_ids']),
      originalText: _requiredString(value['original_text']),
      reason: _requiredString(value['reason']),
    );
  }

  final List<String> sourceLineIds;
  final String originalText;
  final String reason;
}

String _requiredString(Object? value) {
  if (value is! String || value.trim().isEmpty) {
    throw const FormatException('Expected a non-empty string');
  }
  return value.trim();
}

List<String> _stringList(Object? value) {
  if (value is! List || value.any((item) => item is! String)) {
    throw const FormatException('Expected a string array');
  }
  return [for (final item in value) _requiredString(item)];
}
