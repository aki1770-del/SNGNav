/// SQLite consent database — schema, migrations, and helpers.
///
/// Two tables:
///   `consents` — current consent state (one row per purpose)
///   `consent_audit_log` — append-only history of every consent change
///
/// Consent records and append-only audit trail.
library;

import 'package:sqlite3/sqlite3.dart';

/// Opens (or creates) the consent database at [path].
///
/// In-memory for tests: pass `':memory:'`.
/// Production: pass a path from `path_provider`.
Database openConsentDatabase(String path) {
  final db = sqlite3.open(path);
  _migrate(db);
  return db;
}

void _migrate(Database db) {
  // Enable WAL for concurrent reads during UI rendering.
  db.execute('PRAGMA journal_mode = WAL;');

  // Schema version tracking.
  final version = db.select('PRAGMA user_version;').first.values.first as int;

  if (version < 1) {
    db.execute('''
      CREATE TABLE IF NOT EXISTS consents (
        purpose    TEXT PRIMARY KEY,
        status     TEXT NOT NULL,
        jurisdiction TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );
    ''');

    db.execute('''
      CREATE TABLE IF NOT EXISTS consent_audit_log (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        purpose    TEXT NOT NULL,
        status     TEXT NOT NULL,
        jurisdiction TEXT NOT NULL,
        changed_at TEXT NOT NULL
      );
    ''');

    db.execute('PRAGMA user_version = 1;');
  }
}
