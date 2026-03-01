/// In-memory consent service — non-persistent implementation.
///
/// Stores consent records in a map. No persistence across restarts.
/// All purposes start as UNKNOWN (Jidoka: effectively denied).
///
/// Production replacement: SQLiteConsentService (same interface,
/// persistent backing store, audit log table).
library;

import '../models/consent_record.dart';
import 'consent_service.dart';

class InMemoryConsentService implements ConsentService {
  final Map<ConsentPurpose, ConsentRecord> _records = {};

  @override
  Future<ConsentRecord> getConsent(ConsentPurpose purpose) async {
    return _records[purpose] ?? ConsentRecord.unknown(purpose: purpose);
  }

  @override
  Future<List<ConsentRecord>> getAllConsents() async {
    // Return a record for every purpose — unknown if not explicitly set.
    return ConsentPurpose.values.map((purpose) {
      return _records[purpose] ?? ConsentRecord.unknown(purpose: purpose);
    }).toList();
  }

  @override
  Future<ConsentRecord> grant(
    ConsentPurpose purpose,
    Jurisdiction jurisdiction,
  ) async {
    final record = ConsentRecord(
      purpose: purpose,
      status: ConsentStatus.granted,
      jurisdiction: jurisdiction,
      updatedAt: DateTime.now(),
    );
    _records[purpose] = record;
    return record;
  }

  @override
  Future<ConsentRecord> revoke(ConsentPurpose purpose) async {
    // Preserve the jurisdiction from the previous record if it exists.
    final previous = _records[purpose];
    final record = ConsentRecord(
      purpose: purpose,
      status: ConsentStatus.denied,
      jurisdiction: previous?.jurisdiction ?? Jurisdiction.gdpr,
      updatedAt: DateTime.now(),
    );
    _records[purpose] = record;
    return record;
  }

  @override
  Future<void> dispose() async {
    _records.clear();
  }
}
