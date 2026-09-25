import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Owns the SQLite database: opening it, creating the schema and running
/// migrations. Nothing above this layer should contain SQL.
///
/// ## Relational behaviour
///
/// Deletion rules are chosen deliberately so a confirmed plan can never be
/// corrupted by later library edits:
///
/// * `meal_variants.meal_family_id` → RESTRICT. A family with variants cannot
///   be deleted; archive it instead.
/// * `meal_ingredients.meal_variant_id` → CASCADE. Recipe lines are owned by
///   the variant and have no meaning without it.
/// * `meal_ingredients.ingredient_id` → RESTRICT. An ingredient still used by
///   a recipe cannot be deleted.
/// * `weekly_plan_items.weekly_plan_id` → CASCADE. Items are owned by the plan.
/// * `weekly_plan_items.meal_variant_id` → RESTRICT. This is what protects
///   plan history: a planned meal cannot be deleted out from under it.
/// * `shopping_items.weekly_plan_id` → CASCADE. The list is owned by the plan.
/// * `shopping_items.ingredient_id` → SET NULL. Shopping lines carry their own
///   name and quantity, so the line survives the ingredient going away.
///
/// Because meals are RESTRICTed once planned, meal deletion in PrepPick is a
/// soft archive: `meal_families.archived_at` and `meal_variants.archived_at`
/// are stamped instead of rows being removed. Archived meals are hidden from
/// the library and never planned, while historic plans keep resolving.
class DatabaseService {
  /// Creates the service. Tests pass their own [factory] and [databaseName]
  /// to work against a temporary or in-memory database.
  DatabaseService({DatabaseFactory? factory, String? databaseName})
    : _factory = factory ?? databaseFactory,
      _databaseName = databaseName ?? defaultDatabaseName;

  static const String defaultDatabaseName = 'preppick.db';

  /// Bump this and add a migration in [_onUpgrade] for any schema change.
  static const int schemaVersion = 4;

  final DatabaseFactory _factory;
  final String _databaseName;

  Database? _database;
  Future<Database>? _opening;

  /// The open database, opening it on first use.
  Future<Database> get database async {
    final existing = _database;
    if (existing != null && existing.isOpen) return existing;
    // Guard against concurrent callers each triggering an open.
    return _opening ??= _open().whenComplete(() => _opening = null);
  }

  Future<Database> _open() async {
    final path = await resolvePath();
    final database = await _factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onConfigure: _onConfigure,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      ),
    );
    return _database = database;
  }

  /// Full path of the database file.
  Future<String> resolvePath() async {
    if (_databaseName == inMemoryDatabasePath) return _databaseName;
    if (p.isAbsolute(_databaseName)) return _databaseName;
    return p.join(await _factory.getDatabasesPath(), _databaseName);
  }

  Future<void> _onConfigure(Database db) async {
    // sqflite opens with foreign keys off; PrepPick relies on them.
    await db.execute('PRAGMA foreign_keys = ON');
  }

  Future<void> _onCreate(Database db, int version) async {
    final batch = db.batch();
    for (final statement in _createStatements) {
      batch.execute(statement);
    }
    await batch.commit(noResult: true);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) await _migrateWeeklyPlansUniqueWeek(db);
    if (oldVersion < 3) await _migratePlanAndMealTiming(db);
    if (oldVersion < 4) await _migrateImportStaging(db);
  }

  Future<void> _migrateImportStaging(Database db) async {
    for (final statement in _importStagingStatements) {
      final safeStatement = statement
          .replaceFirst('CREATE TABLE ', 'CREATE TABLE IF NOT EXISTS ')
          .replaceFirst('CREATE INDEX ', 'CREATE INDEX IF NOT EXISTS ');
      await db.execute(safeStatement);
    }
  }

  Future<void> _migratePlanAndMealTiming(Database db) async {
    await _addColumnIfMissing(
      db,
      'meal_variants',
      'estimated_minutes',
      'INTEGER',
    );
    await _addColumnIfMissing(
      db,
      'weekly_plans',
      'estimated_prep_minutes',
      'INTEGER',
    );
    await _addColumnIfMissing(
      db,
      'weekly_plan_items',
      'prep_timing',
      "TEXT NOT NULL DEFAULT 'mainPrep'",
    );
    await _addColumnIfMissing(
      db,
      'weekly_plan_items',
      'planned_cook_date',
      'TEXT',
    );
  }

  Future<void> _addColumnIfMissing(
    Database db,
    String table,
    String column,
    String definition,
  ) async {
    final existingTables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
      [table],
    );
    if (existingTables.isEmpty) return;

    final columns = await db.rawQuery('PRAGMA table_info($table)');
    final columnNames = columns.map((row) => row['name'] as String).toSet();
    if (columnNames.contains(column)) return;
    await db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
  }

  Future<void> _migrateWeeklyPlansUniqueWeek(Database db) async {
    final columns = await db.rawQuery('PRAGMA table_info(weekly_plans)');
    final columnNames = columns.map((row) => row['name'] as String).toSet();
    if (!columnNames.contains('updated_at')) {
      await db.execute('ALTER TABLE weekly_plans ADD COLUMN updated_at TEXT');
      await db.execute('''
        UPDATE weekly_plans
        SET updated_at = COALESCE(confirmed_at, created_at, week_start)
        ''');
    }

    final rows = await db.query('weekly_plans');
    final idsToDelete = _duplicateWeeklyPlanIdsToDelete(rows);
    for (final id in idsToDelete) {
      await db.delete('weekly_plans', where: 'id = ?', whereArgs: [id]);
    }

    await db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_weekly_plans_week_start_unique
      ON weekly_plans (week_start)
      ''');
  }

  static List<String> _duplicateWeeklyPlanIdsToDelete(
    List<Map<String, Object?>> rows,
  ) {
    final byWeek = <String, List<Map<String, Object?>>>{};
    for (final row in rows) {
      final weekStart = row['week_start']! as String;
      byWeek.putIfAbsent(weekStart, () => []).add(row);
    }

    final ids = <String>[];
    for (final plans in byWeek.values) {
      if (plans.length < 2) continue;
      plans.sort(_compareWeeklyPlansToKeepFirst);
      ids.addAll(plans.skip(1).map((row) => row['id']! as String));
    }
    return ids;
  }

  static int _compareWeeklyPlansToKeepFirst(
    Map<String, Object?> a,
    Map<String, Object?> b,
  ) {
    final confirmedCompare = _isConfirmed(b).compareTo(_isConfirmed(a));
    if (confirmedCompare != 0) return confirmedCompare;
    return _latestPlanStamp(b).compareTo(_latestPlanStamp(a));
  }

  static int _isConfirmed(Map<String, Object?> row) =>
      row['status'] == 'confirmed' ? 1 : 0;

  static String _latestPlanStamp(Map<String, Object?> row) =>
      (row['updated_at'] ?? row['confirmed_at'] ?? row['created_at'] ?? '')
          as String;

  /// Closes the database so it can be reopened cleanly.
  Future<void> close() async {
    final database = _database;
    _database = null;
    if (database != null && database.isOpen) await database.close();
  }

  /// Deletes the database file entirely.
  ///
  /// Development and test helper only — this is never exposed in the UI.
  Future<void> deleteDatabaseForTesting() async {
    await close();
    await _factory.deleteDatabase(await resolvePath());
  }

  /// Empties every table while leaving the schema in place.
  ///
  /// Development and test helper only.
  Future<void> clearAllTablesForTesting() async {
    final db = await database;
    await db.transaction((txn) async {
      for (final table in tableNames.reversed) {
        await txn.delete(table);
      }
    });
  }

  /// Every table in the schema, in dependency order.
  static const List<String> tableNames = [
    'meal_families',
    'meal_variants',
    'ingredients',
    'meal_ingredients',
    'meal_components',
    'variant_components',
    'meal_aliases',
    'weekly_plans',
    'weekly_plan_items',
    'shopping_items',
    'settings',
    'import_batches',
    'import_source_lines',
    'import_candidates',
    'import_candidate_sources',
  ];

  static const List<String> _createStatements = [
    '''
    CREATE TABLE meal_families (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      meal_type TEXT NOT NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      archived_at TEXT
    )
    ''',
    '''
    CREATE TABLE meal_variants (
      id TEXT PRIMARY KEY,
      meal_family_id TEXT NOT NULL,
      name TEXT NOT NULL,
      protein TEXT,
      estimated_minutes INTEGER,
      last_planned_at TEXT,
      times_planned INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      archived_at TEXT,
      FOREIGN KEY (meal_family_id) REFERENCES meal_families (id)
        ON DELETE RESTRICT
    )
    ''',
    'CREATE INDEX idx_meal_variants_family ON meal_variants (meal_family_id)',
    '''
    CREATE TABLE ingredients (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      category TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
    ''',
    '''
    CREATE TABLE meal_ingredients (
      id TEXT PRIMARY KEY,
      meal_variant_id TEXT NOT NULL,
      ingredient_id TEXT NOT NULL,
      quantity REAL,
      unit TEXT,
      base_servings INTEGER,
      FOREIGN KEY (meal_variant_id) REFERENCES meal_variants (id)
        ON DELETE CASCADE,
      FOREIGN KEY (ingredient_id) REFERENCES ingredients (id)
        ON DELETE RESTRICT
    )
    ''',
    '''
    CREATE INDEX idx_meal_ingredients_variant
      ON meal_ingredients (meal_variant_id)
    ''',
    '''
    CREATE TABLE weekly_plans (
      id TEXT PRIMARY KEY,
      week_start TEXT NOT NULL UNIQUE,
      status TEXT NOT NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      estimated_prep_minutes INTEGER,
      confirmed_at TEXT
    )
    ''',
    '''
    CREATE TABLE weekly_plan_items (
      id TEXT PRIMARY KEY,
      weekly_plan_id TEXT NOT NULL,
      meal_variant_id TEXT NOT NULL,
      meal_type TEXT NOT NULL,
      slot_index INTEGER NOT NULL,
      prep_timing TEXT NOT NULL DEFAULT 'mainPrep',
      planned_cook_date TEXT,
      FOREIGN KEY (weekly_plan_id) REFERENCES weekly_plans (id)
        ON DELETE CASCADE,
      FOREIGN KEY (meal_variant_id) REFERENCES meal_variants (id)
        ON DELETE RESTRICT,
      UNIQUE (weekly_plan_id, meal_type, slot_index)
    )
    ''',
    '''
    CREATE TABLE shopping_items (
      id TEXT PRIMARY KEY,
      weekly_plan_id TEXT NOT NULL,
      ingredient_id TEXT,
      name TEXT NOT NULL,
      quantity REAL,
      unit TEXT,
      category TEXT NOT NULL,
      is_checked INTEGER NOT NULL DEFAULT 0,
      is_manual INTEGER NOT NULL DEFAULT 0,
      FOREIGN KEY (weekly_plan_id) REFERENCES weekly_plans (id)
        ON DELETE CASCADE,
      FOREIGN KEY (ingredient_id) REFERENCES ingredients (id)
        ON DELETE SET NULL
    )
    ''',
    '''
    CREATE INDEX idx_shopping_items_plan ON shopping_items (weekly_plan_id)
    ''',
    '''
    CREATE TABLE settings (
      key TEXT PRIMARY KEY,
      value TEXT
    )
    ''',
    ..._importStagingStatements,
  ];

  static const List<String> _importStagingStatements = [
    '''
    CREATE TABLE meal_components (
      id TEXT PRIMARY KEY,
      display_name TEXT NOT NULL,
      normalized_key TEXT NOT NULL,
      notes TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
    ''',
    'CREATE INDEX idx_meal_components_normalized ON meal_components (normalized_key)',
    '''
    CREATE TABLE variant_components (
      variant_id TEXT NOT NULL,
      component_id TEXT NOT NULL,
      role TEXT,
      PRIMARY KEY (variant_id, component_id),
      FOREIGN KEY (variant_id) REFERENCES meal_variants (id)
        ON DELETE CASCADE,
      FOREIGN KEY (component_id) REFERENCES meal_components (id)
        ON DELETE RESTRICT
    )
    ''',
    '''
    CREATE TABLE meal_aliases (
      id TEXT PRIMARY KEY,
      variant_id TEXT,
      family_id TEXT,
      raw_label TEXT NOT NULL,
      normalized_label TEXT NOT NULL,
      source TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      CHECK ((variant_id IS NOT NULL AND family_id IS NULL)
        OR (variant_id IS NULL AND family_id IS NOT NULL)),
      FOREIGN KEY (variant_id) REFERENCES meal_variants (id)
        ON DELETE CASCADE,
      FOREIGN KEY (family_id) REFERENCES meal_families (id)
        ON DELETE CASCADE
    )
    ''',
    'CREATE INDEX idx_meal_aliases_normalized ON meal_aliases (normalized_label)',
    '''
    CREATE TABLE import_batches (
      id TEXT PRIMARY KEY,
      source_type TEXT NOT NULL,
      source_filename TEXT,
      raw_text TEXT NOT NULL,
      status TEXT NOT NULL,
      schema_version INTEGER NOT NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
    ''',
    '''
    CREATE TABLE import_source_lines (
      id TEXT PRIMARY KEY,
      batch_id TEXT NOT NULL,
      sequence INTEGER NOT NULL,
      original_text TEXT NOT NULL,
      heading TEXT,
      inferred_slot TEXT,
      original_week TEXT,
      FOREIGN KEY (batch_id) REFERENCES import_batches (id)
        ON DELETE CASCADE,
      UNIQUE (batch_id, sequence)
    )
    ''',
    '''
    CREATE TABLE import_candidates (
      id TEXT PRIMARY KEY,
      batch_id TEXT NOT NULL,
      entity_type TEXT NOT NULL,
      proposal_json TEXT NOT NULL,
      status TEXT NOT NULL,
      matched_existing_id TEXT,
      confidence_band TEXT,
      review_note TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      FOREIGN KEY (batch_id) REFERENCES import_batches (id)
        ON DELETE CASCADE
    )
    ''',
    'CREATE INDEX idx_import_candidates_batch ON import_candidates (batch_id)',
    '''
    CREATE TABLE import_candidate_sources (
      candidate_id TEXT NOT NULL,
      source_line_id TEXT NOT NULL,
      source_text TEXT,
      location_hint TEXT,
      PRIMARY KEY (candidate_id, source_line_id),
      FOREIGN KEY (candidate_id) REFERENCES import_candidates (id)
        ON DELETE CASCADE,
      FOREIGN KEY (source_line_id) REFERENCES import_source_lines (id)
        ON DELETE CASCADE
    )
    ''',
  ];
}
