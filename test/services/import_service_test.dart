import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:preppick/models/models.dart';
import 'package:preppick/services/database_service.dart';
import 'package:preppick/services/import_service.dart';
import 'package:preppick/services/meal_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late Directory tempDir;
  late DatabaseService database;
  late MealService mealService;
  late ImportService service;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('preppick_import_test');
    database = DatabaseService(
      factory: databaseFactoryFfi,
      databaseName: '${tempDir.path}/preppick_test.db',
    );
    mealService = MealService(database);
    service = ImportService(mealService, database);
  });

  tearDown(() async {
    await database.close();
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  test('blank lines are ignored', () {
    final result = service.parse('\n\nFried Rice\n   \nPaninis\n');

    expect(result.candidates.map((c) => c.name), ['Fried Rice', 'Paninis']);
  });

  test('bullet symbols and numbering are stripped', () {
    final result = service.parse('- Jollof Rice\n• Paninis\n3. Burgers');

    expect(result.candidates.map((c) => c.name), [
      'Jollof Rice',
      'Paninis',
      'Burgers',
    ]);
  });

  test('repeated exact and case-insensitive names are identified', () {
    final result = service.parse('Fried Rice\nfried rice\nPaninis');

    final friedRice = result.candidates.take(2).toList();
    expect(friedRice.every((candidate) => candidate.isDuplicate), isTrue);
    expect(friedRice.first.duplicateKey, friedRice.last.duplicateKey);
    expect(result.candidates.last.isDuplicate, isFalse);
  });

  test('original source text is preserved', () {
    const source = '  - Lou Lou Spaghetti + Chicken\nPaninis';

    final result = service.parse(source);

    expect(result.sourceText, source);
    expect(
      result.candidates.first.originalText,
      '- Lou Lou Spaghetti + Chicken',
    );
  });

  test('confirming imported meals does not fabricate ingredients', () async {
    final candidate = ImportedMealCandidate(
      id: 'candidate-1',
      name: 'Chicken Curry 500g rice',
      originalText: 'Chicken Curry 500g rice',
      mealType: MealType.dinner,
    );

    final result = await service.confirmCandidates([candidate]);
    final mealId = result.candidates.single.importedMealId!;

    expect(await mealService.getIngredientsForMeal(mealId), isEmpty);
  });

  test('ambiguous lines remain candidates and are flagged, not guessed', () {
    final result = service.parse('Monday: Pasta + Mince');

    expect(result.candidates, hasLength(1));
    expect(result.candidates.single.name, 'Monday: Pasta + Mince');
    expect(result.candidates.single.isAmbiguous, isTrue);
    expect(result.candidates.single.mealType, isNull);
  });

  test(
    'reconfirming the same reviewed candidates does not duplicate them',
    () async {
      final first = ImportedMealCandidate(
        id: 'candidate-1',
        name: 'Fried Rice',
        originalText: 'Fried Rice',
        mealType: MealType.dinner,
      );

      final once = await service.confirmCandidates([first]);
      final twice = await service.confirmCandidates(once.candidates);

      expect(once.createdCount, 1);
      expect(twice.createdCount, 0);
      expect(await mealService.getAllMealVariants(), hasLength(1));
    },
  );

  test('safe exact repeats in one batch are written once', () async {
    final candidates = [
      ImportedMealCandidate(
        id: 'candidate-1',
        name: 'Fried Rice',
        originalText: 'Fried Rice',
        mealType: MealType.dinner,
      ),
      ImportedMealCandidate(
        id: 'candidate-2',
        name: 'fried rice',
        originalText: 'fried rice',
        mealType: MealType.dinner,
      ),
    ];

    final result = await service.confirmCandidates(candidates);

    expect(result.createdCount, 1);
    expect(result.candidates.first.importedMealId, isNotNull);
    expect(
      result.candidates.last.importedMealId,
      result.candidates.first.importedMealId,
    );
    expect(await mealService.getAllMealVariants(), hasLength(1));
  });

  test(
    'stages raw text, source lines and candidates without live meals',
    () async {
      final parsed = service.parse(
        '- Lou Lou spag and fish\n\nMonday: Pasta\nDish soap',
      );

      final batch = await service.stageParsedImport(parsed);
      final restored = await service.loadLatestDraft();

      expect(batch.status, ImportBatchStatus.readyForReview);
      expect(restored, isNotNull);
      expect(restored!.batch.id, batch.id);
      expect(restored.batch.rawText, parsed.sourceText);
      expect(restored.sourceLines, hasLength(4));
      expect(restored.candidates, hasLength(3));
      expect(
        restored.candidates.every((candidate) => candidate.batchId == batch.id),
        isTrue,
      );
      expect(restored.candidates.first.sourceLineIds, hasLength(1));
      expect(restored.candidates[1].status, ImportCandidateStatus.needsReview);
      expect(await mealService.getAllMealVariants(), isEmpty);
    },
  );

  test('staged candidate edits survive reload', () async {
    final parsed = service.parse('Old dinner');
    final batch = await service.stageParsedImport(parsed);
    final candidate = parsed.candidates.single.copyWith(
      batchId: batch.id,
      name: 'New dinner',
      mealType: MealType.dinner,
    );

    await service.updateStagedCandidate(candidate);
    final restored = await service.loadLatestDraft();

    expect(restored!.candidates.single.name, 'New dinner');
    expect(restored.candidates.single.mealType, MealType.dinner);
    expect(restored.candidates.single.status, ImportCandidateStatus.edited);
    expect(restored.batch.status, ImportBatchStatus.partiallyReviewed);
  });
}
