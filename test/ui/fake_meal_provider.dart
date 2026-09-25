import 'package:preppick/models/models.dart';
import 'package:preppick/providers/meal_provider.dart';
import 'package:preppick/services/database_service.dart';
import 'package:preppick/services/meal_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// A [MealProvider] whose state the test sets directly.
///
/// The library screen depends on the provider, not on the service, so these
/// widget tests drive the provider and leave SQLite to `meal_service_test`
/// and `meal_provider_test`. A real database is also actively unhelpful
/// here: its I/O completes on the real event loop, which the widget tester's
/// fake clock never advances, so the screen would sit on its spinner
/// forever.
final DatabaseService _unusedDatabase = DatabaseService(
  factory: databaseFactoryFfi,
  databaseName: ':unused:',
);

class FakeMealProvider extends MealProvider {
  FakeMealProvider() : super(MealService(_unusedDatabase));

  /// Calls recorded, in order: 'load' or 'refresh'.
  final List<String> calls = [];

  List<MealVariant> loadedMeals = const [];
  Map<String, MealFamily> families = const {};
  bool loading = false;
  bool loaded = true;
  Object? failure;

  @override
  List<MealVariant> get meals => loadedMeals;

  @override
  Map<String, MealFamily> get familyById => families;

  @override
  bool get isLoading => loading;

  @override
  bool get hasLoaded => loaded;

  @override
  Object? get error => failure;

  @override
  Future<void> load() async {
    calls.add('load');
  }

  @override
  Future<void> refresh() async {
    calls.add('refresh');
  }
}

/// A family plus one variant in it, so a test can describe a library in one
/// line instead of wiring ids by hand.
({MealFamily family, MealVariant variant}) fakeLibraryMeal({
  required String id,
  required String name,
  required MealType mealType,
  String? familyName,
  String? protein,
}) {
  final now = DateTime.utc(2026, 3, 1);
  final familyId = 'family-$id';
  return (
    family: MealFamily(
      id: familyId,
      name: familyName ?? name,
      mealType: mealType,
      createdAt: now,
      updatedAt: now,
    ),
    variant: MealVariant(
      id: id,
      mealFamilyId: familyId,
      name: name,
      protein: protein,
      createdAt: now,
      updatedAt: now,
    ),
  );
}
