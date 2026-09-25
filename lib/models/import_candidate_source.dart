/// Links a staged proposal to the source evidence that supports it.
class ImportCandidateSource {
  const ImportCandidateSource({
    required this.candidateId,
    required this.sourceLineId,
    this.sourceText,
    this.locationHint,
  });

  final String candidateId;
  final String sourceLineId;
  final String? sourceText;
  final String? locationHint;

  Map<String, Object?> toMap() => {
    'candidate_id': candidateId,
    'source_line_id': sourceLineId,
    'source_text': sourceText,
    'location_hint': locationHint,
  };
}
