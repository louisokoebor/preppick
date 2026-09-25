import 'package:uuid/uuid.dart';

/// Generates the UUID string primary keys PrepPick uses everywhere.
///
/// Every table keys on a UUID rather than an auto-increment integer, so a row
/// created offline on one device keeps its identity when sync arrives and two
/// devices can never mint the same id.
class PrepIds {
  const PrepIds._();

  static const Uuid _uuid = Uuid();

  /// A new random (v4) id.
  static String newId() => _uuid.v4();
}
