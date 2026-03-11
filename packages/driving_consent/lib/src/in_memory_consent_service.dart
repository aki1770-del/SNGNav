/// In-memory consent service — non-persistent implementation.
///
/// Stores consent records in a map. No persistence across restarts.
/// All purposes start as UNKNOWN (Jidoka: effectively denied).
///
/// For persistent storage, implement [ConsentService] with your
/// preferred backing store (SQLite, Hive, SharedPreferences, etc.).
library;

import 'consent_record.dart';
import 'consent_service.dart';

class InMemoryConsentService implements ConsentService {
  final Map<ConsentPurpose, ConsentRecord> _records = {};

  @override
  Future<ConsentRecord> getConsent(ConsentPurpose purpose) async {
    return _records[purpose] ?? ConsentRecord.unknown(purpose: purpose);
  }

  @override
  Future<List<ConsentRecord>> getAllConsents() async {
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
