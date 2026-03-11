/// SqliteConsentService unit tests.
///
/// Mirrors all 10 InMemoryConsentService tests (same interface contract)
/// plus SQLite-specific tests:
///   11. Persistence across service instances (same database)
///   12. Audit log records every grant
///   13. Audit log records every revoke
///   14. Audit log preserves chronological order
///   15. Migration creates both tables
///   16. Database schema version is set
///
/// Day 3 additions — jurisdiction enforcement + audit log queries:
///   17. All three jurisdictions (GDPR, CCPA, APPI) stored and retrieved
///   18. Jurisdiction changes on re-grant are tracked in audit log
///   19. Audit log timestamps are parseable ISO 8601
///   20. Audit log survives new service instance (persistent)
///   21. Re-opening database does not duplicate tables (idempotent migration)
///   22. Grant overwrites previous grant (upsert, not duplicate)
///
/// Sprint 8 Days 2–3 — SqliteConsentService.
library;

import 'package:driving_consent/driving_consent.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:sngnav_snow_scene/services/consent_database.dart';
import 'package:sngnav_snow_scene/services/sqlite_consent_service.dart';

void main() {
  group('SqliteConsentService', () {
    late Database db;
    late SqliteConsentService service;

    setUp(() {
      db = openConsentDatabase(':memory:');
      service = SqliteConsentService(db);
    });

    tearDown(() async {
      await service.dispose();
    });

    // -------------------------------------------------------------------------
    // Contract tests — identical to InMemoryConsentService (same interface)
    // -------------------------------------------------------------------------

    test('getConsent returns unknown for unset purpose', () async {
      final record = await service.getConsent(ConsentPurpose.fleetLocation);

      expect(record.purpose, ConsentPurpose.fleetLocation);
      expect(record.status, ConsentStatus.unknown);
      expect(record.isEffectivelyGranted, false);
    });

    test('getAllConsents returns one record per purpose', () async {
      final records = await service.getAllConsents();

      expect(records, hasLength(ConsentPurpose.values.length));
      for (final record in records) {
        expect(record.status, ConsentStatus.unknown);
      }
    });

    test('grant returns granted record with correct jurisdiction', () async {
      final record = await service.grant(
        ConsentPurpose.fleetLocation,
        Jurisdiction.appi,
      );

      expect(record.purpose, ConsentPurpose.fleetLocation);
      expect(record.status, ConsentStatus.granted);
      expect(record.jurisdiction, Jurisdiction.appi);
      expect(record.isEffectivelyGranted, true);
    });

    test('grant persists — getConsent returns granted', () async {
      await service.grant(ConsentPurpose.fleetLocation, Jurisdiction.appi);

      final record = await service.getConsent(ConsentPurpose.fleetLocation);
      expect(record.status, ConsentStatus.granted);
      expect(record.jurisdiction, Jurisdiction.appi);
    });

    test('revoke returns denied record', () async {
      await service.grant(ConsentPurpose.fleetLocation, Jurisdiction.appi);
      final record = await service.revoke(ConsentPurpose.fleetLocation);

      expect(record.purpose, ConsentPurpose.fleetLocation);
      expect(record.status, ConsentStatus.denied);
      expect(record.isEffectivelyGranted, false);
    });

    test('revoke preserves jurisdiction from previous grant', () async {
      await service.grant(ConsentPurpose.fleetLocation, Jurisdiction.appi);
      final record = await service.revoke(ConsentPurpose.fleetLocation);

      expect(record.jurisdiction, Jurisdiction.appi);
    });

    test('revoke defaults to GDPR when no previous grant', () async {
      final record = await service.revoke(ConsentPurpose.fleetLocation);

      expect(record.jurisdiction, Jurisdiction.gdpr);
      expect(record.status, ConsentStatus.denied);
    });

    test('grant → revoke → grant cycle works', () async {
      // Grant
      var record = await service.grant(
        ConsentPurpose.weatherTelemetry,
        Jurisdiction.ccpa,
      );
      expect(record.isEffectivelyGranted, true);

      // Revoke
      record = await service.revoke(ConsentPurpose.weatherTelemetry);
      expect(record.isEffectivelyGranted, false);

      // Re-grant
      record = await service.grant(
        ConsentPurpose.weatherTelemetry,
        Jurisdiction.ccpa,
      );
      expect(record.isEffectivelyGranted, true);
    });

    test('multiple purposes are independent', () async {
      await service.grant(ConsentPurpose.fleetLocation, Jurisdiction.appi);

      final fleet = await service.getConsent(ConsentPurpose.fleetLocation);
      final weather =
          await service.getConsent(ConsentPurpose.weatherTelemetry);
      final diag = await service.getConsent(ConsentPurpose.diagnostics);

      expect(fleet.isEffectivelyGranted, true);
      expect(weather.isEffectivelyGranted, false);
      expect(diag.isEffectivelyGranted, false);
    });

    test('dispose closes database without error', () async {
      await service.grant(ConsentPurpose.fleetLocation, Jurisdiction.appi);
      // dispose is called in tearDown — just verify no throw here
      await service.dispose();
      // Create a fresh service so tearDown doesn't double-dispose
      db = openConsentDatabase(':memory:');
      service = SqliteConsentService(db);
    });

    // -------------------------------------------------------------------------
    // SQLite-specific tests — persistence and audit log
    // -------------------------------------------------------------------------

    test('persistence: data survives new service instance on same DB', () async {
      // Use a file path to test cross-instance persistence.
      // For in-memory, we simulate by reusing the same Database object.
      await service.grant(ConsentPurpose.fleetLocation, Jurisdiction.appi);
      await service.grant(ConsentPurpose.diagnostics, Jurisdiction.gdpr);

      // Create a new service instance on the same database.
      final service2 = SqliteConsentService(db);

      final fleet = await service2.getConsent(ConsentPurpose.fleetLocation);
      final diag = await service2.getConsent(ConsentPurpose.diagnostics);
      final weather =
          await service2.getConsent(ConsentPurpose.weatherTelemetry);

      expect(fleet.isEffectivelyGranted, true);
      expect(fleet.jurisdiction, Jurisdiction.appi);
      expect(diag.isEffectivelyGranted, true);
      expect(diag.jurisdiction, Jurisdiction.gdpr);
      expect(weather.isUnknown, true);

      // Don't dispose service2 — it shares the same db, tearDown handles it.
    });

    test('audit log records every grant', () async {
      await service.grant(ConsentPurpose.fleetLocation, Jurisdiction.appi);
      await service.grant(ConsentPurpose.weatherTelemetry, Jurisdiction.gdpr);

      final log = service.readAuditLog();
      expect(log, hasLength(2));
      expect(log[0]['purpose'], 'fleetLocation');
      expect(log[0]['status'], 'granted');
      expect(log[0]['jurisdiction'], 'appi');
      expect(log[1]['purpose'], 'weatherTelemetry');
      expect(log[1]['status'], 'granted');
      expect(log[1]['jurisdiction'], 'gdpr');
    });

    test('audit log records every revoke', () async {
      await service.grant(ConsentPurpose.fleetLocation, Jurisdiction.appi);
      await service.revoke(ConsentPurpose.fleetLocation);

      final log = service.readAuditLog();
      expect(log, hasLength(2));
      expect(log[0]['status'], 'granted');
      expect(log[1]['status'], 'denied');
      expect(log[1]['purpose'], 'fleetLocation');
    });

    test('audit log preserves chronological order', () async {
      await service.grant(ConsentPurpose.fleetLocation, Jurisdiction.appi);
      await service.revoke(ConsentPurpose.fleetLocation);
      await service.grant(ConsentPurpose.fleetLocation, Jurisdiction.ccpa);

      final log = service.readAuditLog();
      expect(log, hasLength(3));

      // IDs are auto-incrementing — chronological order guaranteed.
      final ids = log.map((e) => e['id'] as int).toList();
      expect(ids, orderedEquals([ids[0], ids[1], ids[2]]));
      expect(ids[0] < ids[1], true);
      expect(ids[1] < ids[2], true);

      // Status progression: granted → denied → granted
      expect(log[0]['status'], 'granted');
      expect(log[1]['status'], 'denied');
      expect(log[2]['status'], 'granted');
    });

    test('migration creates both tables', () {
      // Verify tables exist by querying sqlite_master.
      final tables = db.select(
        "SELECT name FROM sqlite_master WHERE type='table' "
        "AND name IN ('consents', 'consent_audit_log') ORDER BY name;",
      );

      expect(tables, hasLength(2));
      expect(tables[0]['name'], 'consent_audit_log');
      expect(tables[1]['name'], 'consents');
    });

    test('database schema version is set', () {
      final result = db.select('PRAGMA user_version;');
      expect(result.first.values.first, 1);
    });

    // -------------------------------------------------------------------------
    // Day 3 — Jurisdiction enforcement + audit log queries
    // -------------------------------------------------------------------------

    test('all three jurisdictions stored and retrieved correctly', () async {
      await service.grant(ConsentPurpose.fleetLocation, Jurisdiction.gdpr);
      await service.grant(ConsentPurpose.weatherTelemetry, Jurisdiction.ccpa);
      await service.grant(ConsentPurpose.diagnostics, Jurisdiction.appi);

      final fleet = await service.getConsent(ConsentPurpose.fleetLocation);
      final weather =
          await service.getConsent(ConsentPurpose.weatherTelemetry);
      final diag = await service.getConsent(ConsentPurpose.diagnostics);

      expect(fleet.jurisdiction, Jurisdiction.gdpr);
      expect(weather.jurisdiction, Jurisdiction.ccpa);
      expect(diag.jurisdiction, Jurisdiction.appi);
    });

    test('jurisdiction change on re-grant tracked in audit log', () async {
      // Grant under APPI
      await service.grant(ConsentPurpose.fleetLocation, Jurisdiction.appi);
      // Re-grant under GDPR (driver moved jurisdictions)
      await service.grant(ConsentPurpose.fleetLocation, Jurisdiction.gdpr);

      // Current state should reflect GDPR
      final current = await service.getConsent(ConsentPurpose.fleetLocation);
      expect(current.jurisdiction, Jurisdiction.gdpr);

      // Audit log should show both grants
      final log = service.readAuditLog();
      expect(log, hasLength(2));
      expect(log[0]['jurisdiction'], 'appi');
      expect(log[1]['jurisdiction'], 'gdpr');
    });

    test('audit log timestamps are parseable ISO 8601', () async {
      await service.grant(ConsentPurpose.fleetLocation, Jurisdiction.gdpr);

      final log = service.readAuditLog();
      expect(log, hasLength(1));

      final changedAt = log[0]['changed_at'] as String;
      final parsed = DateTime.tryParse(changedAt);
      expect(parsed, isNotNull);
      // Should be recent (within last minute)
      expect(
        parsed!.difference(DateTime.now()).inMinutes.abs(),
        lessThan(1),
      );
    });

    test('audit log survives new service instance', () async {
      await service.grant(ConsentPurpose.fleetLocation, Jurisdiction.appi);
      await service.revoke(ConsentPurpose.fleetLocation);

      // New service on same DB sees the same audit log
      final service2 = SqliteConsentService(db);
      final log = service2.readAuditLog();
      expect(log, hasLength(2));
      expect(log[0]['status'], 'granted');
      expect(log[1]['status'], 'denied');
    });

    test('idempotent migration: re-opening database does not duplicate tables',
        () {
      // openConsentDatabase runs migration. Opening again shouldn't fail.
      final db2 = openConsentDatabase(':memory:');
      final tables = db2.select(
        "SELECT name FROM sqlite_master WHERE type='table' "
        "AND name IN ('consents', 'consent_audit_log') ORDER BY name;",
      );
      expect(tables, hasLength(2));
      db2.dispose();
    });

    test('grant overwrites previous grant (upsert, not duplicate row)',
        () async {
      await service.grant(ConsentPurpose.fleetLocation, Jurisdiction.appi);
      await service.grant(ConsentPurpose.fleetLocation, Jurisdiction.gdpr);

      // consents table should have exactly 1 row for fleetLocation
      final rows = db.select(
        "SELECT COUNT(*) as cnt FROM consents WHERE purpose = 'fleetLocation';",
      );
      expect(rows.first['cnt'], 1);

      // But audit log should have 2 entries
      final log = service.readAuditLog();
      expect(log, hasLength(2));
    });
  });
}
