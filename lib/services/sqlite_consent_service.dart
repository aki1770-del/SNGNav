/// SQLite-backed consent service — persistent consent with audit trail.
///
/// Implements [ConsentService] with the same 4 methods + dispose.
/// BLoC doesn't know or care whether storage is in-memory or SQLite.
///
/// Two tables:
///   `consents` — current state (upsert on grant/revoke)
///   `consent_audit_log` — append-only audit trail
///
/// Jidoka semantics preserved: getConsent returns [ConsentRecord.unknown]
/// when no row exists. UNKNOWN = DENIED.
///
/// Persistent consent with audit trail.
library;

import 'package:sqlite3/sqlite3.dart';

import '../models/consent_record.dart';
import 'consent_database.dart';
import 'consent_service.dart';

class SqliteConsentService implements ConsentService {
  final Database _db;

  /// Create with an already-opened [Database].
  ///
  /// For production: pass `openConsentDatabase(path)`.
  /// For tests: pass `openConsentDatabase(':memory:')`.
  SqliteConsentService(this._db);

  /// Convenience factory that opens the database at [path].
  factory SqliteConsentService.open(String path) {
    return SqliteConsentService(openConsentDatabase(path));
  }

  @override
  Future<ConsentRecord> getConsent(ConsentPurpose purpose) async {
    final rows = _db.select(
      'SELECT status, jurisdiction, updated_at FROM consents WHERE purpose = ?;',
      [purpose.name],
    );

    if (rows.isEmpty) {
      return ConsentRecord.unknown(purpose: purpose);
    }

    final row = rows.first;
    return ConsentRecord(
      purpose: purpose,
      status: _parseStatus(row['status'] as String),
      jurisdiction: _parseJurisdiction(row['jurisdiction'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }

  @override
  Future<List<ConsentRecord>> getAllConsents() async {
    return Future.wait(
      ConsentPurpose.values.map((purpose) => getConsent(purpose)),
    );
  }

  @override
  Future<ConsentRecord> grant(
    ConsentPurpose purpose,
    Jurisdiction jurisdiction,
  ) async {
    final now = DateTime.now();
    final nowIso = now.toIso8601String();

    _db.execute(
      '''INSERT INTO consents (purpose, status, jurisdiction, updated_at)
         VALUES (?, ?, ?, ?)
         ON CONFLICT(purpose) DO UPDATE SET
           status = excluded.status,
           jurisdiction = excluded.jurisdiction,
           updated_at = excluded.updated_at;''',
      [purpose.name, ConsentStatus.granted.name, jurisdiction.name, nowIso],
    );

    _appendAuditLog(purpose, ConsentStatus.granted, jurisdiction, nowIso);

    return ConsentRecord(
      purpose: purpose,
      status: ConsentStatus.granted,
      jurisdiction: jurisdiction,
      updatedAt: now,
    );
  }

  @override
  Future<ConsentRecord> revoke(ConsentPurpose purpose) async {
    // Preserve jurisdiction from previous record if it exists.
    final previous = await getConsent(purpose);
    final jurisdiction =
        previous.isUnknown ? Jurisdiction.gdpr : previous.jurisdiction;

    final now = DateTime.now();
    final nowIso = now.toIso8601String();

    _db.execute(
      '''INSERT INTO consents (purpose, status, jurisdiction, updated_at)
         VALUES (?, ?, ?, ?)
         ON CONFLICT(purpose) DO UPDATE SET
           status = excluded.status,
           jurisdiction = excluded.jurisdiction,
           updated_at = excluded.updated_at;''',
      [purpose.name, ConsentStatus.denied.name, jurisdiction.name, nowIso],
    );

    _appendAuditLog(purpose, ConsentStatus.denied, jurisdiction, nowIso);

    return ConsentRecord(
      purpose: purpose,
      status: ConsentStatus.denied,
      jurisdiction: jurisdiction,
      updatedAt: now,
    );
  }

  @override
  Future<void> dispose() async {
    _db.dispose();
  }

  // ---------------------------------------------------------------------------
  // Audit log
  // ---------------------------------------------------------------------------

  void _appendAuditLog(
    ConsentPurpose purpose,
    ConsentStatus status,
    Jurisdiction jurisdiction,
    String changedAt,
  ) {
    _db.execute(
      '''INSERT INTO consent_audit_log (purpose, status, jurisdiction, changed_at)
         VALUES (?, ?, ?, ?);''',
      [purpose.name, status.name, jurisdiction.name, changedAt],
    );
  }

  /// Read the audit log — useful for tests and compliance review.
  ///
  /// Returns rows in chronological order (oldest first).
  List<Map<String, dynamic>> readAuditLog() {
    final rows = _db.select(
      'SELECT id, purpose, status, jurisdiction, changed_at '
      'FROM consent_audit_log ORDER BY id ASC;',
    );
    return rows.map((row) {
      return {
        'id': row['id'],
        'purpose': row['purpose'],
        'status': row['status'],
        'jurisdiction': row['jurisdiction'],
        'changed_at': row['changed_at'],
      };
    }).toList();
  }

  // ---------------------------------------------------------------------------
  // Enum parsing helpers
  // ---------------------------------------------------------------------------

  static ConsentStatus _parseStatus(String value) {
    return ConsentStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => ConsentStatus.unknown,
    );
  }

  static Jurisdiction _parseJurisdiction(String value) {
    return Jurisdiction.values.firstWhere(
      (e) => e.name == value,
      orElse: () => Jurisdiction.gdpr,
    );
  }
}
