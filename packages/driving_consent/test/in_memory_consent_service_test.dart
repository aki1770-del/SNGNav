import 'package:driving_consent/driving_consent.dart';
import 'package:test/test.dart';

void main() {
  group('InMemoryConsentService', () {
    late InMemoryConsentService service;

    setUp(() {
      service = InMemoryConsentService();
    });

    tearDown(() async {
      await service.dispose();
    });

    // =========================================================================
    // getConsent
    // =========================================================================

    test('getConsent returns unknown for unset purpose', () async {
      final record = await service.getConsent(ConsentPurpose.fleetLocation);

      expect(record.purpose, ConsentPurpose.fleetLocation);
      expect(record.status, ConsentStatus.unknown);
      expect(record.isEffectivelyGranted, false);
    });

    test('getConsent returns unknown for every purpose initially', () async {
      for (final purpose in ConsentPurpose.values) {
        final record = await service.getConsent(purpose);
        expect(record.status, ConsentStatus.unknown,
            reason: '${purpose.name} should be unknown initially');
      }
    });

    // =========================================================================
    // getAllConsents
    // =========================================================================

    test('getAllConsents returns one record per purpose', () async {
      final records = await service.getAllConsents();

      expect(records, hasLength(ConsentPurpose.values.length));
      for (final record in records) {
        expect(record.status, ConsentStatus.unknown);
      }
    });

    test('getAllConsents reflects grants', () async {
      await service.grant(ConsentPurpose.fleetLocation, Jurisdiction.appi);

      final records = await service.getAllConsents();
      final fleet = records.firstWhere(
        (r) => r.purpose == ConsentPurpose.fleetLocation,
      );
      final weather = records.firstWhere(
        (r) => r.purpose == ConsentPurpose.weatherTelemetry,
      );

      expect(fleet.isEffectivelyGranted, true);
      expect(weather.isEffectivelyGranted, false);
    });

    // =========================================================================
    // grant
    // =========================================================================

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

    test('grant sets updatedAt to a recent timestamp', () async {
      final before = DateTime.now();
      final record = await service.grant(
        ConsentPurpose.fleetLocation,
        Jurisdiction.gdpr,
      );
      final after = DateTime.now();

      expect(record.updatedAt.isAfter(before.subtract(const Duration(seconds: 1))), true);
      expect(record.updatedAt.isBefore(after.add(const Duration(seconds: 1))), true);
    });

    test('grant with each jurisdiction type', () async {
      for (final jurisdiction in Jurisdiction.values) {
        final record = await service.grant(
          ConsentPurpose.fleetLocation,
          jurisdiction,
        );
        expect(record.jurisdiction, jurisdiction);
      }
    });

    // =========================================================================
    // revoke
    // =========================================================================

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

    test('revoke persists — getConsent returns denied', () async {
      await service.grant(ConsentPurpose.fleetLocation, Jurisdiction.appi);
      await service.revoke(ConsentPurpose.fleetLocation);

      final record = await service.getConsent(ConsentPurpose.fleetLocation);
      expect(record.status, ConsentStatus.denied);
    });

    // =========================================================================
    // Lifecycle: grant → revoke → grant
    // =========================================================================

    test('grant → revoke → grant cycle works', () async {
      var record = await service.grant(
        ConsentPurpose.weatherTelemetry,
        Jurisdiction.ccpa,
      );
      expect(record.isEffectivelyGranted, true);

      record = await service.revoke(ConsentPurpose.weatherTelemetry);
      expect(record.isEffectivelyGranted, false);

      record = await service.grant(
        ConsentPurpose.weatherTelemetry,
        Jurisdiction.ccpa,
      );
      expect(record.isEffectivelyGranted, true);
    });

    // =========================================================================
    // Purpose independence
    // =========================================================================

    test('multiple purposes are independent', () async {
      await service.grant(ConsentPurpose.fleetLocation, Jurisdiction.appi);

      final fleet = await service.getConsent(ConsentPurpose.fleetLocation);
      final weather = await service.getConsent(ConsentPurpose.weatherTelemetry);
      final diag = await service.getConsent(ConsentPurpose.diagnostics);

      expect(fleet.isEffectivelyGranted, true);
      expect(weather.isEffectivelyGranted, false);
      expect(diag.isEffectivelyGranted, false);
    });

    test('granting all purposes then revoking one', () async {
      for (final purpose in ConsentPurpose.values) {
        await service.grant(purpose, Jurisdiction.gdpr);
      }

      await service.revoke(ConsentPurpose.diagnostics);

      final fleet = await service.getConsent(ConsentPurpose.fleetLocation);
      final weather = await service.getConsent(ConsentPurpose.weatherTelemetry);
      final diag = await service.getConsent(ConsentPurpose.diagnostics);

      expect(fleet.isEffectivelyGranted, true);
      expect(weather.isEffectivelyGranted, true);
      expect(diag.isEffectivelyGranted, false);
    });

    // =========================================================================
    // dispose
    // =========================================================================

    test('dispose clears all records', () async {
      await service.grant(ConsentPurpose.fleetLocation, Jurisdiction.appi);
      await service.dispose();

      service = InMemoryConsentService();
      final record = await service.getConsent(ConsentPurpose.fleetLocation);
      expect(record.status, ConsentStatus.unknown);
    });

    // =========================================================================
    // Jidoka integration — the gate pattern
    // =========================================================================

    test('Jidoka gate: unknown blocks data flow', () async {
      final consent = await service.getConsent(ConsentPurpose.fleetLocation);

      // Simulates the caller's gate check
      final shouldSendData = consent.isEffectivelyGranted;
      expect(shouldSendData, false, reason: 'Jidoka: UNKNOWN = DENIED');
    });

    test('Jidoka gate: explicit grant opens data flow', () async {
      await service.grant(ConsentPurpose.fleetLocation, Jurisdiction.appi);

      final consent = await service.getConsent(ConsentPurpose.fleetLocation);
      final shouldSendData = consent.isEffectivelyGranted;
      expect(shouldSendData, true);
    });

    test('Jidoka gate: revoke re-closes data flow', () async {
      await service.grant(ConsentPurpose.fleetLocation, Jurisdiction.appi);
      await service.revoke(ConsentPurpose.fleetLocation);

      final consent = await service.getConsent(ConsentPurpose.fleetLocation);
      final shouldSendData = consent.isEffectivelyGranted;
      expect(shouldSendData, false);
    });
  });
}
