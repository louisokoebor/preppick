import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:preppick/models/models.dart';
import 'package:preppick/providers/import_provider.dart';
import 'package:preppick/services/ai_import_client.dart';
import 'package:preppick/services/database_service.dart';
import 'package:preppick/services/import_service.dart';
import 'package:preppick/services/meal_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _ProposalTransport implements ImportHttpTransport {
  @override
  Future<ImportHttpResponse> post(
    Uri uri, {
    required Map<String, String> headers,
    required String body,
  }) async {
    final request = jsonDecode(body) as Map<String, dynamic>;
    final lines = request['source_lines'] as List<dynamic>;
    final lineId = (lines.single as Map<String, dynamic>)['id'] as String;
    return ImportHttpResponse(
      statusCode: 200,
      body: jsonEncode({
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
                'source_line_ids': [lineId],
                'confidence_band': 'high',
                'needs_review_reason': null,
              },
            ],
          },
        ],
        'unresolved': [],
      }),
    );
  }
}

void main() {
  sqfliteFfiInit();

  late Directory tempDir;
  late DatabaseService database;
  late ImportProvider provider;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('preppick_import_provider');
    database = DatabaseService(
      factory: databaseFactoryFfi,
      databaseName: '${tempDir.path}/preppick_test.db',
    );
    final client = AiImportClient(
      endpoint: 'https://example.test/import-meals',
      supabaseAnonKey: 'anon-key',
      transport: _ProposalTransport(),
    );
    provider = ImportProvider(
      ImportService(MealService(database), database, client),
    );
  });

  tearDown(() async {
    provider.dispose();
    await database.close();
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  test(
    'AI interpretation stages review metadata without creating a meal',
    () async {
      provider.updateSourceText('Rice and fish');
      expect(await provider.parseSource(), isTrue);

      expect(await provider.interpretWithAi(const []), isTrue);
      expect(provider.aiProposal, isNotNull);
      expect(provider.candidates.single.name, 'Rice + Fish');
      expect(
        provider.candidates.single.status,
        ImportCandidateStatus.needsReview,
      );
      expect(
        provider.candidates.single.confidenceBand,
        ImportConfidenceBand.high,
      );
      expect(await MealService(database).getAllMealVariants(), isEmpty);
    },
  );

  test('the staged AI proposal still requires explicit confirmation', () async {
    provider.updateSourceText('Rice and fish');
    await provider.parseSource();
    await provider.interpretWithAi(const []);

    final candidate = provider.candidates.single;
    provider.assignMealType(candidate.id, MealType.dinner);
    expect(await provider.confirmImport(), 1);
    expect(await MealService(database).getAllMealVariants(), hasLength(1));
  });
}
