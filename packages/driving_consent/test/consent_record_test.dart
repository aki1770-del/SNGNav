import 'package:driving_consent/driving_consent.dart';
import 'package:test/test.dart';

void main() {
  // ===========================================================================
  // ConsentRecord — model tests
  // ===========================================================================

  group('ConsentRecord', () {
    test('granted record reports isEffectivelyGranted = true', () {
      final record = ConsentRecord(
        purpose: ConsentPurpose.fleetLocation,
        status: ConsentStatus.granted,
        jurisdiction: Jurisdiction.appi,
        updatedAt: DateTime(2026, 3, 8),
      );

      expect(record.isEffectivelyGranted, true);
      expect(record.isExplicitlyDenied, false);
      expect(record.isUnknown, false);
    });

    test('denied record reports isEffectivelyGranted = false', () {
      final record = ConsentRecord(
        purpose: ConsentPurpose.fleetLocation,
        status: ConsentStatus.denied,
        jurisdiction: Jurisdiction.gdpr,
        updatedAt: DateTime(2026, 3, 8),
      );

      expect(record.isEffectivelyGranted, false);
      expect(record.isExplicitlyDenied, true);
      expect(record.isUnknown, false);
    });

    test('unknown record reports isEffectivelyGranted = false (Jidoka)', () {
      final record = ConsentRecord(
        purpose: ConsentPurpose.fleetLocation,
        status: ConsentStatus.unknown,
        jurisdiction: Jurisdiction.gdpr,
        updatedAt: DateTime(2026, 3, 8),
      );

      expect(record.isEffectivelyGranted, false);
      expect(record.isExplicitlyDenied, false);
      expect(record.isUnknown, true);
    });

    test('unknown factory produces Jidoka-safe defaults', () {
      final record = ConsentRecord.unknown(
        purpose: ConsentPurpose.weatherTelemetry,
      );

      expect(record.status, ConsentStatus.unknown);
      expect(record.jurisdiction, Jurisdiction.gdpr);
      expect(record.updatedAt, DateTime.fromMillisecondsSinceEpoch(0));
      expect(record.isEffectivelyGranted, false);
    });

    test('unknown factory accepts custom jurisdiction', () {
      final record = ConsentRecord.unknown(
        purpose: ConsentPurpose.diagnostics,
        jurisdiction: Jurisdiction.appi,
      );

      expect(record.jurisdiction, Jurisdiction.appi);
      expect(record.isUnknown, true);
    });

    test('equatable: same values are equal', () {
      final time = DateTime(2026, 3, 8);
      final a = ConsentRecord(
        purpose: ConsentPurpose.fleetLocation,
        status: ConsentStatus.granted,
        jurisdiction: Jurisdiction.appi,
        updatedAt: time,
      );
      final b = ConsentRecord(
        purpose: ConsentPurpose.fleetLocation,
        status: ConsentStatus.granted,
        jurisdiction: Jurisdiction.appi,
        updatedAt: time,
      );

      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('equatable: different status not equal', () {
      final time = DateTime(2026, 3, 8);
      final granted = ConsentRecord(
        purpose: ConsentPurpose.fleetLocation,
        status: ConsentStatus.granted,
        jurisdiction: Jurisdiction.appi,
        updatedAt: time,
      );
      final denied = ConsentRecord(
        purpose: ConsentPurpose.fleetLocation,
        status: ConsentStatus.denied,
        jurisdiction: Jurisdiction.appi,
        updatedAt: time,
      );

      expect(granted, isNot(equals(denied)));
    });

    test('equatable: different jurisdiction not equal', () {
      final time = DateTime(2026, 3, 8);
      final appi = ConsentRecord(
        purpose: ConsentPurpose.fleetLocation,
        status: ConsentStatus.granted,
        jurisdiction: Jurisdiction.appi,
        updatedAt: time,
      );
      final gdpr = ConsentRecord(
        purpose: ConsentPurpose.fleetLocation,
        status: ConsentStatus.granted,
        jurisdiction: Jurisdiction.gdpr,
        updatedAt: time,
      );

      expect(appi, isNot(equals(gdpr)));
    });

    test('toString includes purpose, status, jurisdiction', () {
      final record = ConsentRecord(
        purpose: ConsentPurpose.fleetLocation,
        status: ConsentStatus.granted,
        jurisdiction: Jurisdiction.appi,
        updatedAt: DateTime(2026, 3, 8),
      );

      final str = record.toString();
      expect(str, contains('fleetLocation'));
      expect(str, contains('granted'));
      expect(str, contains('appi'));
    });
  });

  // ===========================================================================
  // ConsentStatus — enum coverage
  // ===========================================================================

  group('ConsentStatus', () {
    test('has exactly 3 values', () {
      expect(ConsentStatus.values, hasLength(3));
    });

    test('values are granted, denied, unknown', () {
      expect(
        ConsentStatus.values.map((v) => v.name),
        containsAll(['granted', 'denied', 'unknown']),
      );
    });
  });

  // ===========================================================================
  // ConsentPurpose — enum coverage
  // ===========================================================================

  group('ConsentPurpose', () {
    test('has exactly 3 values', () {
      expect(ConsentPurpose.values, hasLength(3));
    });

    test('values are fleetLocation, weatherTelemetry, diagnostics', () {
      expect(
        ConsentPurpose.values.map((v) => v.name),
        containsAll(['fleetLocation', 'weatherTelemetry', 'diagnostics']),
      );
    });
  });

  // ===========================================================================
  // Jurisdiction — enum coverage
  // ===========================================================================

  group('Jurisdiction', () {
    test('has exactly 3 values', () {
      expect(Jurisdiction.values, hasLength(3));
    });

    test('values are gdpr, ccpa, appi', () {
      expect(
        Jurisdiction.values.map((v) => v.name),
        containsAll(['gdpr', 'ccpa', 'appi']),
      );
    });
  });
}
