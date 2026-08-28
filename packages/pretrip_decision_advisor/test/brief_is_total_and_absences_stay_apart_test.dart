/// `brief()` is TOTAL in 0.6.1 — and the two absences must stay apart.
///
/// This release exists to stop one sentence: "No winter hazard signals in your
/// trip window", printed on a morning when nothing that decides winter hazard
/// had been measured. `brief()` closes that WITHOUT a break the compiler
/// cannot see: it returns `PretripVerdict.noData` — a value 0.6.0 already
/// returned and already documented — instead of throwing a new exception at a
/// caller who upgraded without reading.
///
/// The cost of a total function is that it can collapse two different
/// absences into one value, and collapsing them is the SAME defect class:
/// an absence rendered as a conclusion. So this file is an OPPOSED PAIR.
///
///  * **A** — a forecast COVERS the window and measured only temperature.
///  * **B** — NOTHING forecast the window at all.
///
/// Both are `verdict: noData` and `peakHazard: unknown`, by design and
/// unchanged from 0.6.0 for B. What separates them is `chips` (A names what
/// was not measured, B is empty) and the throw on [SnowAwarePretripAdvisor
/// .briefOrThrow] (A stops, B returns).
///
/// Collapse A into B — strip A's chip — and A2/A3/D1 fail while every B test
/// keeps passing. Collapse B into A — give B the assessmentIncomplete chip —
/// and B3/D1 fail while every A test keeps passing. Either direction is
/// caught, which a test asserting only "it did not throw" would not do.
library;

import 'package:pretrip_decision_advisor/pretrip_decision_advisor.dart';
import 'package:test/test.dart';

void main() {
  final base = DateTime.utc(2026, 1, 15, 7, 0);
  const advisor = SnowAwarePretripAdvisor();
  const profile = DriverProfileSpec(
    profileTag: 'her',
    reactionTimeSeconds: 1.5,
  );

  CommuteShape commuteAt(DateTime d) => CommuteShape(
    plannedDuration: const Duration(minutes: 30),
    routeIdentifiers: const ['akita'],
    flexibility: CommuteFlexibility.discretionary,
    plannedDeparture: d,
  );

  // The MET Norway shape: temperature only. `pretrip_source_met_norway` emits
  // `visibilityMeters: null` and `estimatedRoadCondition: null` on every slot,
  // so for a consumer on that source this is the ORDINARY morning.
  final coveredButUnmeasured = WeatherForecast(
    issuedAt: base,
    hourly: [
      HourlyForecast(hour: base, tempCelsius: 5.0),
      HourlyForecast(
        hour: base.add(const Duration(hours: 1)),
        tempCelsius: 5.0,
      ),
    ],
  );

  // Case A: the commute sits inside the forecast.
  final commuteA = commuteAt(base);

  // Case B: the same forecast, a commute three days later — nothing covers it.
  final commuteB = commuteAt(base.add(const Duration(days: 3)));

  group('A — covered but unmeasured: honest, never affirmative', () {
    test('A1 brief() returns rather than throwing', () {
      expect(
        () => advisor.brief(
          forecast: coveredButUnmeasured,
          commute: commuteA,
          profile: profile,
        ),
        returnsNormally,
        reason:
            'THE POINT of this shape: a 0.6.0 caller who upgrades without '
            'reading must not meet an uncaught exception in a pre-trip screen.',
      );
    });

    test('A2 it is noData/unknown with a NON-EMPTY chip', () {
      final b = advisor.brief(
        forecast: coveredButUnmeasured,
        commute: commuteA,
        profile: profile,
      );
      expect(b.verdict, PretripVerdict.noData);
      expect(b.peakHazard, HourHazard.unknown);
      expect(
        b.chips,
        isNotEmpty,
        reason:
            '0.6.0 showed the integrator an empty chip list for its own '
            'unassessable case. An empty list here would repeat that.',
      );
      expect(b.chips, contains(PretripMessages.en.assessmentIncomplete()));
    });

    test('A3 it is NEVER an affirmative all-clear', () {
      final b = advisor.brief(
        forecast: coveredButUnmeasured,
        commute: commuteA,
        profile: profile,
      );
      expect(b.verdict, isNot(PretripVerdict.clear));
      expect(b.peakHazard, isNot(HourHazard.clear));
      expect(b.recommendation, isNull);
      for (final c in b.chips) {
        expect(
          c,
          isNot(contains(PretripMessages.en.noWinterHazard())),
          reason: 'the exact sentence this release exists to stop',
        );
      }
    });

    test('A4 briefOrThrow() still STOPS here', () {
      expect(
        () => advisor.briefOrThrow(
          forecast: coveredButUnmeasured,
          commute: commuteA,
          profile: profile,
        ),
        throwsA(isA<PretripAssessmentIncompleteException>()),
      );
    });
  });

  group('B — genuinely uncovered: unchanged from 0.6.0', () {
    test('B1 brief() returns noData/unknown', () {
      final b = advisor.brief(
        forecast: coveredButUnmeasured,
        commute: commuteB,
        profile: profile,
      );
      expect(b.verdict, PretripVerdict.noData);
      expect(b.peakHazard, HourHazard.unknown);
      expect(b.recommendation, isNull);
    });

    test(
      'B2 briefOrThrow() does NOT throw here — it returns, as 0.6.0 did',
      () {
        expect(
          () => advisor.briefOrThrow(
            forecast: coveredButUnmeasured,
            commute: commuteB,
            profile: profile,
          ),
          returnsNormally,
          reason:
              'a window nothing forecast at all was never the defect; 0.6.0 '
              'already reported it honestly and that behaviour stands',
        );
      },
    );

    test('B3 its chip list is EMPTY — it has nothing unmeasured to name', () {
      final b = advisor.brief(
        forecast: coveredButUnmeasured,
        commute: commuteB,
        profile: profile,
      );
      expect(
        b.chips,
        isEmpty,
        reason:
            'saying "some conditions were not measured" here would be a NEW '
            'false sentence: there were no conditions to measure at all',
      );
    });
  });

  group('D — the two absences are DISTINGUISHABLE', () {
    test('D1 same verdict and peakHazard, DIFFERENT chips', () {
      final a = advisor.brief(
        forecast: coveredButUnmeasured,
        commute: commuteA,
        profile: profile,
      );
      final b = advisor.brief(
        forecast: coveredButUnmeasured,
        commute: commuteB,
        profile: profile,
      );

      // Documented and deliberate: verdict alone cannot tell them apart.
      expect(a.verdict, b.verdict);
      expect(a.peakHazard, b.peakHazard);

      // But something on the public surface MUST.
      expect(
        a.chips,
        isNot(equals(b.chips)),
        reason:
            'if these ever match, the two absences have collapsed and a '
            'chip-rendering surface can no longer tell an unmeasured morning '
            'from an unforecast one',
      );
    });

    test('D2 briefOrThrow() separates them by stopping on A and not on B', () {
      var threwOnA = false;
      try {
        advisor.briefOrThrow(
          forecast: coveredButUnmeasured,
          commute: commuteA,
          profile: profile,
        );
      } on PretripAssessmentIncompleteException {
        threwOnA = true;
      }
      var threwOnB = false;
      try {
        advisor.briefOrThrow(
          forecast: coveredButUnmeasured,
          commute: commuteB,
          profile: profile,
        );
      } on PretripDataAbsentException {
        threwOnB = true;
      }
      expect(threwOnA, isTrue);
      expect(threwOnB, isFalse);
    });
  });

  group('the documented shims still work', () {
    test('briefOrUnassessed() is exactly brief()', () {
      for (final c in [commuteA, commuteB]) {
        final viaBrief = advisor.brief(
          forecast: coveredButUnmeasured,
          commute: c,
          profile: profile,
        );
        final viaShim = advisor.briefOrUnassessed(
          forecast: coveredButUnmeasured,
          commute: c,
          profile: profile,
        );
        expect(viaShim.verdict, viaBrief.verdict);
        expect(viaShim.peakHazard, viaBrief.peakHazard);
        expect(viaShim.chips, viaBrief.chips);
        expect(
          viaShim.recommendation?.strength,
          viaBrief.recommendation?.strength,
        );
      }
    });

    test('briefOrNull() still returns null for BOTH absences', () {
      for (final c in [commuteA, commuteB]) {
        expect(
          advisor.briefOrNull(
            forecast: coveredButUnmeasured,
            commute: c,
            profile: profile,
          ),
          isNull,
        );
      }
    });

    test('advise() still returns null for BOTH absences', () {
      for (final c in [commuteA, commuteB]) {
        expect(
          advisor.advise(
            forecast: coveredButUnmeasured,
            commute: c,
            profile: profile,
          ),
          isNull,
        );
      }
    });
  });
}
