import 'package:driving_consent/driving_consent.dart';
import 'package:test/test.dart';

void main() {
  group('InstrumentationService Jidoka gate', () {
    late InMemoryConsentService consent;
    late InMemoryInstrumentationService instr;

    setUp(() {
      consent = InMemoryConsentService();
      instr = InMemoryInstrumentationService(consent);
    });

    tearDown(() async {
      await instr.dispose();
      await consent.dispose();
    });

    AlertFired makeAlert(DateTime t) => AlertFired(
          timestamp: t,
          driverPseudonym: instr.driverPseudonym,
          alertClass: 'snow_road_warning',
          severity: AlertSeverityClass.warning,
          modalDuration: const Duration(seconds: 6),
          dismissalState: AlertDismissalState.ranToCompletion,
          driverProfile: DriverProfileClass.snowZoneExperienced,
        );

    test(
        'Sakichi-tag: recordEvent throws when consent is UNKNOWN '
        '(UNKNOWN = DENIED)', () async {
      // No grant has been issued for the purpose; default is UNKNOWN.
      await expectLater(
        instr.recordEvent(
          ConsentPurpose.alertExperienceInstrumentation,
          makeAlert(DateTime.now()),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('Sakichi-tag: recordEvent throws when consent is DENIED', () async {
      await consent.grant(
        ConsentPurpose.alertExperienceInstrumentation,
        Jurisdiction.gdpr,
      );
      await consent.revoke(ConsentPurpose.alertExperienceInstrumentation);

      await expectLater(
        instr.recordEvent(
          ConsentPurpose.alertExperienceInstrumentation,
          makeAlert(DateTime.now()),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('recordEvent succeeds when consent is GRANTED', () async {
      await consent.grant(
        ConsentPurpose.alertExperienceInstrumentation,
        Jurisdiction.appi,
      );

      await instr.recordEvent(
        ConsentPurpose.alertExperienceInstrumentation,
        makeAlert(DateTime.now()),
      );

      final events = await instr.readEvents(
        purpose: ConsentPurpose.alertExperienceInstrumentation,
      );
      expect(events, hasLength(1));
    });

    test('readEvents filters by time window (Sakichi-tag: since/until)',
        () async {
      await consent.grant(
        ConsentPurpose.alertExperienceInstrumentation,
        Jurisdiction.gdpr,
      );

      final t0 = DateTime(2026, 5, 5, 9);
      final t1 = DateTime(2026, 5, 5, 10);
      final t2 = DateTime(2026, 5, 5, 11);

      for (final t in [t0, t1, t2]) {
        await instr.recordEvent(
          ConsentPurpose.alertExperienceInstrumentation,
          makeAlert(t),
        );
      }

      final inside = await instr.readEvents(
        purpose: ConsentPurpose.alertExperienceInstrumentation,
        since: DateTime(2026, 5, 5, 9, 30),
        until: DateTime(2026, 5, 5, 10, 30),
      );
      expect(inside, hasLength(1));
      expect(inside.first.timestamp, t1);
    });

    test('readEvents returns chronological order', () async {
      await consent.grant(
        ConsentPurpose.alertExperienceInstrumentation,
        Jurisdiction.gdpr,
      );

      final t0 = DateTime(2026, 5, 5, 9);
      final t1 = DateTime(2026, 5, 5, 10);
      final t2 = DateTime(2026, 5, 5, 11);

      // Record in non-chronological order.
      for (final t in [t2, t0, t1]) {
        await instr.recordEvent(
          ConsentPurpose.alertExperienceInstrumentation,
          makeAlert(t),
        );
      }

      final events = await instr.readEvents(
        purpose: ConsentPurpose.alertExperienceInstrumentation,
      );
      expect(events.map((e) => e.timestamp).toList(), [t0, t1, t2]);
    });

    test('setRetention persists per-purpose; getRetention reads it',
        () async {
      // Default is 30 days for any purpose.
      final defaultRetention = await instr.getRetention(
        ConsentPurpose.alertExperienceInstrumentation,
      );
      expect(defaultRetention, const Duration(days: 30));

      await instr.setRetention(
        ConsentPurpose.alertExperienceInstrumentation,
        const Duration(days: 7),
      );
      expect(
        await instr.getRetention(ConsentPurpose.alertExperienceInstrumentation),
        const Duration(days: 7),
      );

      // Other purposes still default.
      expect(
        await instr.getRetention(ConsentPurpose.voiceExperienceInstrumentation),
        const Duration(days: 30),
      );
    });

    test('deleteAllEvents removes events but preserves consent state',
        () async {
      await consent.grant(
        ConsentPurpose.alertExperienceInstrumentation,
        Jurisdiction.appi,
      );
      await instr.recordEvent(
        ConsentPurpose.alertExperienceInstrumentation,
        makeAlert(DateTime.now()),
      );

      expect(
        (await instr.readEvents(
                purpose: ConsentPurpose.alertExperienceInstrumentation))
            .length,
        1,
      );

      await instr.deleteAllEvents(
        ConsentPurpose.alertExperienceInstrumentation,
      );

      expect(
        await instr.readEvents(
          purpose: ConsentPurpose.alertExperienceInstrumentation,
        ),
        isEmpty,
      );

      // Consent state is preserved.
      final consentRecord = await consent.getConsent(
        ConsentPurpose.alertExperienceInstrumentation,
      );
      expect(consentRecord.status, ConsentStatus.granted);
    });
  });
}
