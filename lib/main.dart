import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app/app.dart';
import 'services/database_service.dart';
import 'services/seed_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Demo data only, and only in debug builds: it gives the planner and
  // shopping flows something to work with before any real meal has been
  // entered. It is skipped the moment the library holds a meal, so it never
  // overwrites the household's own data. Remove this call once import lands.
  if (kDebugMode) {
    final seeded = await SeedService(DatabaseService()).seedIfEmpty();
    if (seeded) debugPrint('PrepPick: demo meal library seeded.');
  }

  runApp(const PrepPickApp());
}
