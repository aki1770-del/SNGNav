import 'package:driving_consent/driving_consent.dart';
import 'package:test/test.dart';

void main() {
  group('InMemoryInstrumentationService specifics', () {
    late InMemoryConsentService consent;
    late InMemoryInstrumentationService instr;

    setUp(() async {
      consent = InMemoryConsentService();
      instr = InMemoryInstrumentationService(consent);
      await consent.grant(
        ConsentPurpose.alertExperienceInstrumentation,
        Jurisdiction.gdpr,
      );
    });

    tearDown(() async {
      await instr.dispose();
      await consent.dispose();
    });

    AlertFired makeAlert(DateTime t) => AlertFired(
          timestamp: t,
          driverPseudonym: instr.driverPseudonym,
          alertClass: 'alert_x',
          severity: AlertSeverity.info,
          modalDuration: const Duration(seconds: 4),
          dismissalState: AlertDismissalState.ranToCompletion,
          driverProfile: DriverProfileClass.defaultProfile,
        );

    test(
        'Sakichi-tag: auto-prune drops events older than per-purpose retention',
        () async {
      // Set retention to 1 hour for the purpose.
      await instr.setRetention(
        ConsentPurpose.alertExperienceInstrumentation,
        const Duration(hours: 1),
      );

      final tooOld = DateTime.now().subtract(const Duration(hours: 2));
      final fresh = DateTime.now();

      // Record an old event first; auto-prune removes it on the next record.
      await instr.recordEvent(
        ConsentPurpose.alertExperienceInstrumentation,
        makeAlert(tooOld),
      );
      await instr.recordEvent(
        ConsentPurpose.alertExperienceInstrumentation,
        makeAlert(fresh),
      );

      final events = await instr.readEvents(
        purpose: ConsentPurpose.alertExperienceInstrumentation,
      );
      expect(events, hasLength(1));
      expect(events.first.timestamp, fresh);
    });

    test('pruneExpired returns the count of pruned events', () async {
      await instr.setRetention(
        ConsentPurpose.alertExperienceInstrumentation,
        const Duration(hours: 1),
      );

      final tooOld1 = DateTime.now().subtract(const Duration(hours: 2));
      final tooOld2 = DateTime.now().subtract(const Duration(hours: 3));
      final fresh = DateTime.now();

      // Record fresh first so the auto-prune does not strip the old ones
      // before we count them: but auto-prune fires on every recordEvent, so
      // we record the fresh event last and rely on pruneExpired explicitly.
      // To exercise pruneExpired, we set retention long, record old events,
      // then shrink retention and call pruneExpired.
      await instr.setRetention(
        ConsentPurpose.alertExperienceInstrumentation,
        const Duration(days: 30),
      );
      await instr.recordEvent(
        ConsentPurpose.alertExperienceInstrumentation,
        makeAlert(tooOld1),
      );
      await instr.recordEvent(
        ConsentPurpose.alertExperienceInstrumentation,
        makeAlert(tooOld2),
      );
      await instr.recordEvent(
        ConsentPurpose.alertExperienceInstrumentation,
        makeAlert(fresh),
      );

      // Now shrink retention and prune.
      await instr.setRetention(
        ConsentPurpose.alertExperienceInstrumentation,
        const Duration(hours: 1),
      );
      final pruned = await instr.pruneExpired();
      expect(pruned, 2);

      final remaining = await instr.readEvents(
        purpose: ConsentPurpose.alertExperienceInstrumentation,
      );
      expect(remaining, hasLength(1));
      expect(remaining.first.timestamp, fresh);
    });

    test(
        'Sakichi-tag: driverPseudonym is stable across events for one '
        'install', () async {
      final p1 = instr.driverPseudonym;
      await instr.recordEvent(
        ConsentPurpose.alertExperienceInstrumentation,
        makeAlert(DateTime.now()),
      );
      final p2 = instr.driverPseudonym;
      await instr.recordEvent(
        ConsentPurpose.alertExperienceInstrumentation,
        makeAlert(DateTime.now()),
      );
      final p3 = instr.driverPseudonym;

      expect(p1, equals(p2));
      expect(p2, equals(p3));
    });

    test(
        'Sakichi-tag: driverPseudonym does not link across installs '
        '(distinct service instances yield distinct pseudonyms)', () async {
      final consent2 = InMemoryConsentService();
      final instr2 = InMemoryInstrumentationService(consent2);
      try {
        // Force pseudonym generation on both instances.
        final p1 = instr.driverPseudonym;
        final p2 = instr2.driverPseudonym;
        expect(p1, isNot(equals(p2)),
            reason: 'distinct installs must not share a pseudonym');
      } finally {
        await instr2.dispose();
        await consent2.dispose();
      }
    });

    test('null retention means indefinite (no auto-prune)', () async {
      await instr.setRetention(
        ConsentPurpose.alertExperienceInstrumentation,
        null,
      );

      final ancient = DateTime(1970, 1, 1);
      await instr.recordEvent(
        ConsentPurpose.alertExperienceInstrumentation,
        makeAlert(ancient),
      );
      await instr.recordEvent(
        ConsentPurpose.alertExperienceInstrumentation,
        makeAlert(DateTime.now()),
      );

      final events = await instr.readEvents(
        purpose: ConsentPurpose.alertExperienceInstrumentation,
      );
      expect(events, hasLength(2));

      final pruned = await instr.pruneExpired();
      expect(pruned, 0);
    });
  });
}
