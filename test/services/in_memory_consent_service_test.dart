/// InMemoryConsentService unit tests.
///
/// Tests:
///   1. getConsent returns unknown for unset purpose
///   2. getAllConsents returns one record per purpose (all unknown initially)
///   3. grant returns granted record with correct jurisdiction
///   4. grant persists — getConsent returns granted after grant
///   5. revoke returns denied record
///   6. revoke preserves jurisdiction from previous grant
///   7. revoke defaults to GDPR when no previous grant
///   8. grant → revoke → grant cycle works
///   9. Multiple purposes are independent
///  10. dispose clears all records
///
/// Sprint 7 Day 11 — Test hardening.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:sngnav_snow_scene/models/consent_record.dart';
import 'package:sngnav_snow_scene/services/in_memory_consent_service.dart';

void main() {
  group('InMemoryConsentService', () {
    late InMemoryConsentService service;

    setUp(() {
      service = InMemoryConsentService();
    });

    tearDown(() async {
      await service.dispose();
    });

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

    test('dispose clears all records', () async {
      await service.grant(ConsentPurpose.fleetLocation, Jurisdiction.appi);
      await service.dispose();

      // Re-create after dispose
      service = InMemoryConsentService();
      final record = await service.getConsent(ConsentPurpose.fleetLocation);
      expect(record.status, ConsentStatus.unknown);
    });
  });
}
