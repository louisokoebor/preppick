import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:preppick/models/models.dart';
import 'package:preppick/services/ai_import_client.dart';

class _FakeTransport implements ImportHttpTransport {
  _FakeTransport(this.response);

  final ImportHttpResponse response;
  Uri? uri;
  Map<String, String>? headers;
  String? body;

  @override
  Future<ImportHttpResponse> post(
    Uri uri, {
    required Map<String, String> headers,
    required String body,
  }) async {
    this.uri = uri;
    this.headers = headers;
    this.body = body;
    return response;
  }
}

ImportSourceLine sourceLine(String id, String text) => ImportSourceLine(
  id: id,
  batchId: 'batch-1',
  sequence: 1,
  originalText: text,
  lineType: ImportLineType.meal,
);

Map<String, dynamic> validResponse({String sourceId = 'line-1'}) => {
  'schema_version': '1',
  'families': [
    {
      'temp_id': 'family_rice',
      'preferred_name': 'Rice',
      'aliases': [],
      'variants': [
        {
          'temp_id': 'variant_rice_fish',
          'display_name': 'Rice + Fish',
          'component_names': ['Fish'],
          'meal_slot': 'dinner',
          'source_line_ids': [sourceId],
          'confidence_band': 'low',
          'needs_review_reason': 'The rice type is unspecified.',
        },
      ],
    },
  ],
  'unresolved': [],
};

void main() {
  test(
    'sends source lines and library index with Supabase auth headers',
    () async {
      final transport = _FakeTransport(
        ImportHttpResponse(statusCode: 200, body: jsonEncode(validResponse())),
      );
      final client = AiImportClient(
        endpoint: 'https://example.test/import-meals',
        supabaseAnonKey: 'anon-key',
        transport: transport,
      );

      final result = await client.interpret(
        sourceText: 'Rice and fish',
        sourceLines: [sourceLine('line-1', 'Rice and fish')],
        existingLibrary: [
          const ImportLibraryEntry(
            id: 'variant-1',
            familyId: 'family-1',
            familyName: 'Rice',
            variantName: 'Rice + Chicken',
            aliases: ['chicken rice'],
          ),
        ],
      );

      expect(result.schemaVersion, '1');
      expect(transport.uri.toString(), 'https://example.test/import-meals');
      expect(transport.headers!['Authorization'], 'Bearer anon-key');
      final sent = jsonDecode(transport.body!) as Map<String, dynamic>;
      expect(sent['source_lines'], hasLength(1));
      expect(sent['existing_library'], hasLength(1));
    },
  );

  test('turns function errors into AiImportException', () async {
    final client = AiImportClient(
      endpoint: 'https://example.test/import-meals',
      transport: _FakeTransport(
        const ImportHttpResponse(
          statusCode: 504,
          body: '{"error":{"code":"timeout","message":"Try again."}}',
        ),
      ),
    );

    await expectLater(
      client.interpret(
        sourceText: 'Rice and fish',
        sourceLines: [sourceLine('line-1', 'Rice and fish')],
        existingLibrary: const [],
      ),
      throwsA(
        isA<AiImportException>()
            .having((error) => error.code, 'code', 'timeout')
            .having((error) => error.statusCode, 'statusCode', 504),
      ),
    );
  });

  test('rejects proposals that cite unknown source lines', () async {
    final client = AiImportClient(
      endpoint: 'https://example.test/import-meals',
      transport: _FakeTransport(
        ImportHttpResponse(
          statusCode: 200,
          body: jsonEncode(validResponse(sourceId: 'missing-line')),
        ),
      ),
    );

    await expectLater(
      client.interpret(
        sourceText: 'Rice and fish',
        sourceLines: [sourceLine('line-1', 'Rice and fish')],
        existingLibrary: const [],
      ),
      throwsA(isA<AiImportException>()),
    );
  });
}
