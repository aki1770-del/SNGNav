import 'package:compound_failure_advisor/compound_failure_advisor.dart';
import 'package:condition_aggregator/condition_aggregator.dart';
import 'package:drive_situation_fusion/drive_situation_fusion.dart';
import 'package:localization_fallback/localization_fallback.dart';
import 'package:test/test.dart';

LocalizationEstimate estimate({
  required LocalizationMode mode,
  double lat = 39.7,
  double lon = 140.1,
  double radius = 12,
  double sinceTrusted = 0,
}) =>
    LocalizationEstimate(
      latitude: lat,
      longitude: lon,
      confidenceRadiusMeters: radius,
      mode: mode,
      secondsSinceTrustedFix: sinceTrusted,
      basis: EstimateBasis.trustedGpsFix,
    );

Advisory advisory(AdvisorySeverity severity) => Advisory(
      source: AdvisorySource.nwsUnitedStates,
      eventClass: 'Winter Storm Warning',
      severity: severity,
      certainty: AdvisoryCertainty.likely,
      urgency: AdvisoryUrgency.expected,
      areaDescription: 'Akita',
      effective: null,
      expires: null,
      headline: 'h',
      description: 'd',
    );

void main() {
  group('positionTrustOf — the position seam is total and correct', () {
    test('every LocalizationMode maps, deadReckoning -> degraded (safety case)',
        () {
      expect(positionTrustOf(LocalizationMode.gpsTrusted), PositionTrust.trusted);
      expect(positionTrustOf(LocalizationMode.gpsSuspect), PositionTrust.suspect);
      // The load-bearing one: GPS gone, still emitting -> degraded, NOT trusted.
      expect(
        positionTrustOf(LocalizationMode.deadReckoning),
        PositionTrust.degraded,
      );
      expect(positionTrustOf(LocalizationMode.lost), PositionTrust.lost);
    });

    test('the mapping is exhaustive over all 4 modes', () {
      for (final m in LocalizationMode.values) {
        // Must return a value for every mode without throwing.
        expect(positionTrustOf(m), isA<PositionTrust>());
      }
    });
  });

  group('advisoryLevelOf — the advisory seam', () {
    test('null (no advisory passed) -> null', () {
      expect(advisoryLevelOf(null), isNull);
    });

    test(
        'unknown (advisory present, severity ungraded) -> moderate, NOT null '
        '— a live warning we cannot grade must not vanish', () {
      // condition_aggregator emits AdvisorySeverity.unknown only as a parse-fail
      // sink on a real, constructed advisory. Aliasing it to null would drop a
      // live blizzard/heavy-snow warning whose token drifted. Floor to moderate.
      expect(advisoryLevelOf(AdvisorySeverity.unknown), AdvisoryLevel.moderate);
    });

    test(
        'END-TO-END: an ungraded live advisory still reaches HER as a concern',
        () {
      // Trusted position, no fresh visibility reading, and the ONLY advisory in
      // force has an ungraded severity. Before the fix this produced zero
      // advisory concern; now it must surface.
      final withUngraded = adviseInDrive(fuseDriveSituation(
        estimate: estimate(mode: LocalizationMode.gpsTrusted, radius: 8),
        advisory: advisory(AdvisorySeverity.unknown),
      ));
      final withNone = adviseInDrive(fuseDriveSituation(
        estimate: estimate(mode: LocalizationMode.gpsTrusted, radius: 8),
      ));
      // The ungraded advisory must raise the caution above the no-advisory
      // baseline — it is not silently equal to "no advisory".
      expect(withUngraded.reasons.length,
          greaterThan(withNone.reasons.length),
          reason: 'ungraded live advisory must add a concern, not vanish');
    });

    test('real severities map one-to-one', () {
      expect(advisoryLevelOf(AdvisorySeverity.minor), AdvisoryLevel.minor);
      expect(advisoryLevelOf(AdvisorySeverity.moderate), AdvisoryLevel.moderate);
      expect(advisoryLevelOf(AdvisorySeverity.severe), AdvisoryLevel.severe);
      expect(advisoryLevelOf(AdvisorySeverity.extreme), AdvisoryLevel.extreme);
    });
  });

  group('fuseDriveSituation — field pass-through', () {
    test('carries the estimate fields straight through', () {
      final s = fuseDriveSituation(
        estimate: estimate(
          mode: LocalizationMode.deadReckoning,
          radius: 250,
          sinceTrusted: 42,
        ),
        visibilityMeters: 80,
        visibilityAgeSeconds: 5,
        speedMetersPerSecond: 11,
      );
      expect(s.positionTrust, PositionTrust.degraded);
      expect(s.confidenceRadiusMeters, 250);
      expect(s.secondsSinceTrustedFix, 42);
      expect(s.hasPosition, isTrue);
      expect(s.visibilityMeters, 80);
      expect(s.visibilityAgeSeconds, 5);
      expect(s.advisorySeverity, isNull);
      expect(s.speedMetersPerSecond, 11);
    });

    test('non-finite estimate coordinates => hasPosition false (bootstrap)', () {
      final s = fuseDriveSituation(
        estimate: estimate(mode: LocalizationMode.lost, lat: double.nan),
      );
      expect(s.hasPosition, isFalse);
      expect(s.positionTrust, PositionTrust.lost);
    });

    test('advisory severity flows through the seam', () {
      final s = fuseDriveSituation(
        estimate: estimate(mode: LocalizationMode.gpsTrusted),
        advisory: advisory(AdvisorySeverity.extreme),
      );
      expect(s.advisorySeverity, AdvisoryLevel.extreme);
    });

    test('is total — degenerate radius / time / all-null optionals never throw',
        () {
      expect(
        () => fuseDriveSituation(
          estimate: estimate(
            mode: LocalizationMode.deadReckoning,
            radius: double.nan,
            sinceTrusted: double.infinity,
          ),
        ),
        returnsNormally,
      );
    });
  });

  group('END-TO-END: the catalyst actually makes the reaction happen for HER',
      () {
    test(
        'GPS dead-reckoning AND low visibility => the compound caution fires',
        () {
      // HER worst case: GPS gone (dead reckoning, radius growing) while she can
      // barely see, with a severe area advisory in force. Before this package
      // nothing assembled these signals into the advisor's input.
      final situation = fuseDriveSituation(
        estimate: estimate(
          mode: LocalizationMode.deadReckoning,
          radius: 300,
          sinceTrusted: 90,
        ),
        advisory: advisory(AdvisorySeverity.severe),
        visibilityMeters: 60,
        visibilityAgeSeconds: 4,
        speedMetersPerSecond: 12,
      );

      final advice = adviseInDrive(situation);

      // The advisor's own contract: position-uncertain AND low-visibility
      // together is the strongest caution — the danger compounds.
      expect(advice.positionUncertain, isTrue);
      expect(advice.visibilityLow, isTrue);
      expect(advice.compounding, isTrue,
          reason: 'fused degraded position + low visibility must compound');
    });

    test(
        'counterfactual — same LOW visibility but trusted GPS => does NOT '
        'compound (proves the deadReckoning->degraded mapping is load-bearing)',
        () {
      // Identical low-visibility situation as the compounding test, but the
      // position is a trusted fix. If deadReckoning had been mis-mapped to
      // trusted, the compounding test above would falsely pass; this pins that
      // the position mapping is what enables the compound caution.
      final advice = adviseInDrive(fuseDriveSituation(
        estimate: estimate(mode: LocalizationMode.gpsTrusted, radius: 8),
        visibilityMeters: 60,
        visibilityAgeSeconds: 4,
        speedMetersPerSecond: 12,
      ));
      expect(advice.visibilityLow, isTrue);
      expect(advice.positionUncertain, isFalse);
      expect(advice.compounding, isFalse);
    });

    test('clear day, trusted GPS, no advisory => no manufactured alarm', () {
      final advice = adviseInDrive(fuseDriveSituation(
        estimate: estimate(mode: LocalizationMode.gpsTrusted, radius: 8),
        visibilityMeters: 10000,
        visibilityAgeSeconds: 2,
        speedMetersPerSecond: 14,
      ));
      expect(advice.positionUncertain, isFalse);
      expect(advice.compounding, isFalse);
    });
  });
}
