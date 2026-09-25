import 'dart:convert';
import 'dart:io';

import '../models/models.dart';

class ImportHttpResponse {
  const ImportHttpResponse({required this.statusCode, required this.body});

  final int statusCode;
  final String body;
}

abstract interface class ImportHttpTransport {
  Future<ImportHttpResponse> post(
    Uri uri, {
    required Map<String, String> headers,
    required String body,
  });
}

/// Small production transport with no Flutter-side OpenAI dependency.
class IoImportHttpTransport implements ImportHttpTransport {
  const IoImportHttpTransport();

  @override
  Future<ImportHttpResponse> post(
    Uri uri, {
    required Map<String, String> headers,
    required String body,
  }) async {
    final client = HttpClient();
    try {
      final request = await client.postUrl(uri);
      headers.forEach(request.headers.set);
      request.headers.contentType = ContentType.json;
      request.write(body);
      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();
      return ImportHttpResponse(
        statusCode: response.statusCode,
        body: responseBody,
      );
    } finally {
      client.close(force: true);
    }
  }
}

class AiImportException implements Exception {
  const AiImportException({
    required this.code,
    required this.userMessage,
    this.statusCode,
  });

  final String code;
  final String userMessage;
  final int? statusCode;

  @override
  String toString() => 'AiImportException($code): $userMessage';
}

/// Calls the deployed Supabase function. The OpenAI key never enters this
/// class or the Flutter process.
class AiImportClient {
  AiImportClient({
    required this.endpoint,
    this.supabaseAnonKey = '',
    ImportHttpTransport? transport,
  }) : _transport = transport ?? const IoImportHttpTransport();

  static const defaultEndpoint =
      'https://datyjewdppvmxlkmrvwj.supabase.co/functions/v1/import-meals';
  static const _environmentEndpoint = String.fromEnvironment(
    'PREPPICK_IMPORT_FUNCTION_URL',
  );
  static const _environmentAnonKey = String.fromEnvironment(
    'PREPPICK_SUPABASE_ANON_KEY',
  );

  factory AiImportClient.fromEnvironment({ImportHttpTransport? transport}) {
    return AiImportClient(
      endpoint: _environmentEndpoint.isEmpty
          ? defaultEndpoint
          : _environmentEndpoint,
      supabaseAnonKey: _environmentAnonKey,
      transport: transport,
    );
  }

  final String endpoint;
  final String supabaseAnonKey;
  final ImportHttpTransport _transport;

  bool get isConfigured => supabaseAnonKey.trim().isNotEmpty;

  Future<ImportProposal> interpret({
    required String sourceText,
    required List<ImportSourceLine> sourceLines,
    required List<ImportLibraryEntry> existingLibrary,
  }) async {
    if (endpoint.trim().isEmpty) {
      throw const AiImportException(
        code: 'missing_endpoint',
        userMessage: 'Meal import is not configured yet.',
      );
    }
    if (sourceText.trim().isEmpty) {
      throw const AiImportException(
        code: 'empty_source',
        userMessage: 'Paste at least one meal before importing.',
      );
    }

    final headers = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    };
    if (supabaseAnonKey.trim().isNotEmpty) {
      headers['apikey'] = supabaseAnonKey;
      headers['Authorization'] = 'Bearer $supabaseAnonKey';
    }

    final response = await _transport.post(
      Uri.parse(endpoint),
      headers: headers,
      body: jsonEncode({
        'source_text': sourceText,
        'source_lines': [
          for (final line in sourceLines)
            {'id': line.id, 'text': line.originalText},
        ],
        'existing_library': [
          for (final entry in existingLibrary) entry.toJson(),
        ],
      }),
    );

    final decoded = _decodeObject(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _exceptionFromError(decoded, response.statusCode);
    }
    _validateProposalEnvelope(decoded, sourceLines);
    try {
      return ImportProposal.fromJson(decoded);
    } on FormatException {
      throw const AiImportException(
        code: 'invalid_proposal',
        userMessage: 'The import service returned an invalid proposal.',
      );
    }
  }

  static Map<String, dynamic> _decodeObject(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {
      // Normalised below so the UI never receives a JSON parser exception.
    }
    throw const AiImportException(
      code: 'malformed_response',
      userMessage: 'The import service returned an invalid response.',
    );
  }

  static AiImportException _exceptionFromError(
    Map<String, dynamic> body,
    int statusCode,
  ) {
    final error = body['error'];
    if (error is Map<String, dynamic>) {
      final code = error['code'] as String? ?? 'upstream_error';
      final message = error['message'] as String?;
      return AiImportException(
        code: code,
        statusCode: statusCode,
        userMessage: message == null || message.isEmpty
            ? 'The import service could not complete the request.'
            : message,
      );
    }
    return AiImportException(
      code: 'upstream_error',
      statusCode: statusCode,
      userMessage: 'The import service could not complete the request.',
    );
  }

  static void _validateProposalEnvelope(
    Map<String, dynamic> body,
    List<ImportSourceLine> sourceLines,
  ) {
    if (body['schema_version'] != '1' ||
        body['families'] is! List ||
        body['unresolved'] is! List) {
      throw const AiImportException(
        code: 'invalid_proposal',
        userMessage: 'The import service returned an unsupported proposal.',
      );
    }
    final sourceIds = sourceLines.map((line) => line.id).toSet();
    for (final family in body['families'] as List<dynamic>) {
      if (family is! Map<String, dynamic> || family['variants'] is! List) {
        throw const AiImportException(
          code: 'invalid_proposal',
          userMessage: 'The import service returned an invalid proposal.',
        );
      }
      for (final variant in family['variants'] as List<dynamic>) {
        if (variant is! Map<String, dynamic>) {
          throw const AiImportException(
            code: 'invalid_proposal',
            userMessage: 'The import service returned an invalid proposal.',
          );
        }
        _validateSourceIds(variant['source_line_ids'], sourceIds);
      }
    }
    for (final unresolved in body['unresolved'] as List<dynamic>) {
      if (unresolved is! Map<String, dynamic>) {
        throw const AiImportException(
          code: 'invalid_proposal',
          userMessage: 'The import service returned an invalid proposal.',
        );
      }
      _validateSourceIds(unresolved['source_line_ids'], sourceIds);
    }
  }

  static void _validateSourceIds(Object? value, Set<String> sourceIds) {
    if (value is! List ||
        value.isEmpty ||
        value.any((id) => id is! String || !sourceIds.contains(id))) {
      throw const AiImportException(
        code: 'invalid_evidence',
        userMessage: 'The import service returned unsupported source evidence.',
      );
    }
  }
}
