// FSE-A1 — THE ABSENCE-ORDERING LOCK.
//
// `HourHazard` carries four MEASURED states (`clear < caution < elevated <
// severe`) and one ABSENCE state (`unknown`, "the hazard could not be
// assessed"). Absence is not a point on that ladder. It is the interval
// "somewhere between mild and worst" — so wherever it is placed on the ladder,
// the placement fabricates something:
//
//   * placed ABOVE the alarming states, it DELETES them. `unknown` is declared
//     last (index 4) and the peak reduce is `a.index >= b.index ? a : b`, so
//     `_worse(severe, unknown)` returns `unknown`. One unmeasured hour beside a
//     measured whiteout does not merely relabel the briefing: `brief()` then
//     takes `case HourHazard.unknown` and returns
//     `verdict: noData, chips: []` — the whiteout is discarded and reported as
//     "no forecast". She is told nothing about an hour we measured as lethal.
//
//   * placed BELOW or INSIDE the benign band — the naive repair for the above —
//     it BUYS A DOWNGRADE. `_findBetterWindow` accepts a window when
//     `peak.index <= HourHazard.caution.index`, so an unmeasured window would
//     be recommended as the better one, and we would send her out into hours
//     nobody forecast.
//
// The library is CORRECT today, and correct for a stated reason: `hazardOf`
// never returns an absence member, so absence never reaches an ordering
// comparison at all. Absence is produced only where there is nothing to order —
// the empty window (`snow_aware_pretrip_advisor.dart:190`) and the uncovered
// area read (`area_condition_read.dart:153`).
//
// That reason is carried by a doc comment ("never produced by hazardOf") and by
// nothing else. A comment does not fail. This file makes the precondition
// EXECUTABLE, so the day someone makes absence flow — the obvious next feature,
// since a per-hour "we could not assess this hour" is a real thing to want — the
// suite goes red BEFORE the ordering can silently mask a whiteout.
//
// WHAT THIS LOCKS, in one line:
//   absence must stay OFF the measurement scale — not be repositioned on it.
//
// Scope, stated so the boundary is not over-claimed (FSE C12): this file locks
// the ORDERING property only. The representation (nullable vs. enum member vs.
// sentinel), the wording HER reads, and whether any of it is published are not
// FSE's — they belong to the package owner, AAE, and the Chair respectively.
//
// Every assertion below EVALUATES the library (FSE C12.1: a property test that
// greps is not a property test). Nothing here reads source text.

import 'package:pretrip_decision_advisor/pretrip_decision_advisor.dart';
import 'package:test/test.dart';

/// The MEASURED states, in ascending adversity.
///
/// Declared here as an INDEPENDENT witness to the ordering. The library orders
/// by `.index`; asserting against `.index` would be asserting the ordering
/// against itself and would pass for any declaration order whatsoever.
const List<HourHazard> measuredLadder = <HourHazard>[
  HourHazard.clear,
  HourHazard.caution,
  HourHazard.elevated,
  HourHazard.severe,
];

/// The ABSENCE states — "we could not look", not "we looked and it was mild".
const Set<HourHazard> absenceMembers = <HourHazard>{HourHazard.unknown};

/// The most adverse of two measured states, by [measuredLadder] position.
HourHazard worseMeasured(HourHazard a, HourHazard b) =>
    measuredLadder.indexOf(a) >= measuredLadder.indexOf(b) ? a : b;

/// A slot that classifies to [h] under [SnowAwarePretripAdvisor.hazardOf].
///
/// Every recipe is asserted against the real classifier in the first group
/// below, so the pair matrix can never pass vacuously on a mis-built input.
HourlyForecast slotFor(HourHazard h, DateTime hour) {
  switch (h) {
    case HourHazard.severe:
      return HourlyForecast(
        hour: hour,
        tempCelsius: 5.0,
        humidityRH: 30.0,
        precipitationMmPerHour: 0.0,
        visibilityMeters: 20000.0,
        estimatedRoadCondition: RoadConditionEstimate.ice,
      );
    case HourHazard.elevated:
      return HourlyForecast(
        hour: hour,
        tempCelsius: 5.0,
        humidityRH: 30.0,
        precipitationMmPerHour: 0.0,
        visibilityMeters: 20000.0,
        estimatedRoadCondition: RoadConditionEstimate.packedSnow,
      );
    case HourHazard.caution:
      return HourlyForecast(
        hour: hour,
        tempCelsius: 5.0,
        humidityRH: 30.0,
        precipitationMmPerHour: 0.0,
        visibilityMeters: 20000.0,
        estimatedRoadCondition: RoadConditionEstimate.slush,
      );
    case HourHazard.clear:
      return HourlyForecast(
        hour: hour,
        tempCelsius: 10.0,
        humidityRH: 30.0,
        precipitationMmPerHour: 0.0,
        visibilityMeters: 20000.0,
        estimatedRoadCondition: RoadConditionEstimate.dry,
      );
    case HourHazard.unknown:
      throw ArgumentError(
        'No forecast slot can denote absence: absence is the answer when there '
        'is no slot. If this throw is ever removed, FSE-A1 has been inverted.',
      );
  }
}

void main() {
  const advisor = SnowAwarePretripAdvisor();
  final base = DateTime.utc(2026, 1, 15, 7, 0);

  const profile = DriverProfileSpec(
    profileTag: 'ageingRural',
    reactionTimeSeconds: 1.5,
  );

  CommuteShape commute({
    Duration duration = const Duration(hours: 2),
    CommuteFlexibility flexibility = CommuteFlexibility.discretionary,
  }) => CommuteShape(
    plannedDuration: duration,
    routeIdentifiers: const ['route-a'],
    flexibility: flexibility,
    plannedDeparture: base,
  );

  // ---------------------------------------------------------------------
  // 0. The witnesses this file's other assertions rest on.
  // ---------------------------------------------------------------------

  group('FSE-A1.0 — the taxonomy is total, and a new member cannot slip in', () {
    test('every HourHazard member is classified as measured OR absence', () {
      final classified = <HourHazard>{...measuredLadder, ...absenceMembers};

      expect(
        classified,
        HourHazard.values.toSet(),
        reason:
            'A HourHazard member exists that this lock has not been told '
            'how to treat. It cannot be left unclassified: a MEASURED member '
            'must take a position in `measuredLadder`, and an ABSENCE member '
            'must be added to `absenceMembers` AND kept unreachable from '
            '`hazardOf`. Choosing wrongly is the whole defect this file exists '
            'to prevent — see the header.',
      );
      expect(
        measuredLadder.length + absenceMembers.length,
        HourHazard.values.length,
        reason: 'A member is listed both as measured and as absence.',
      );
    });

    test('each slot recipe really classifies to the hazard it claims', () {
      for (final h in measuredLadder) {
        expect(
          advisor.hazardOf(slotFor(h, base)),
          h,
          reason:
              'The recipe for $h no longer classifies to $h, so every '
              'matrix below would be testing something other than what it '
              'says it tests.',
        );
      }
    });
  });

  // ---------------------------------------------------------------------
  // 1. THE LOAD-BEARING ONE. Absence never reaches an ordering.
  // ---------------------------------------------------------------------

  group('FSE-A1.1 — absence stays OFF the measurement scale', () {
    test('hazardOf yields no absence member, for any slot whatsoever', () {
      // Driven, not reasoned about: nulls, boundary values on every documented
      // threshold, out-of-domain values, and non-finites.
      const temps = <double>[
        -40.0,
        -11.7,
        -0.1,
        0.0,
        0.5,
        1.0,
        2.0,
        2.9,
        3.0,
        10.0,
        45.0,
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ];
      const precips = <double?>[
        null,
        0.0,
        0.1,
        5.0,
        -1.0,
        double.nan,
        double.infinity,
      ];
      const visibilities = <double?>[
        null,
        -1.0,
        0.0,
        99.0,
        100.0,
        199.0,
        200.0,
        499.0,
        500.0,
        20000.0,
        double.nan,
      ];
      const humidities = <double?>[
        null,
        0.0,
        25.0,
        95.0,
        100.0,
        120.0,
        double.nan,
      ];
      final roads = <RoadConditionEstimate?>[
        null,
        ...RoadConditionEstimate.values,
      ];

      final produced = <HourHazard>{};
      var slots = 0;

      for (final t in temps) {
        for (final p in precips) {
          for (final v in visibilities) {
            for (final rh in humidities) {
              for (final r in roads) {
                slots++;
                produced.add(
                  advisor.hazardOf(
                    HourlyForecast(
                      hour: base,
                      tempCelsius: t,
                      humidityRH: rh,
                      precipitationMmPerHour: p,
                      visibilityMeters: v,
                      estimatedRoadCondition: r,
                    ),
                  ),
                );
              }
            }
          }
        }
      }

      expect(slots, greaterThan(20000), reason: 'the sweep collapsed');

      expect(
        produced.intersection(absenceMembers),
        isEmpty,
        reason:
            'THE PRECONDITION HAS BROKEN. `hazardOf` now emits an absence '
            'member, so absence can reach the peak reduce '
            '(`a.index >= b.index ? a : b`). With `unknown` declared last, '
            '`_worse(severe, unknown)` returns `unknown`, `brief()` takes '
            '`case HourHazard.unknown`, and a measured whiteout is returned to '
            'her as `verdict: noData, chips: []`. Do NOT repair this by moving '
            '`unknown` down the enum — that inverts it into '
            '`_findBetterWindow` accepting an unmeasured window as the better '
            'one. Route absence AROUND the ordering instead (a separate '
            'coverage flag, or a nullable peak), exactly as the empty-window '
            'and uncovered-area paths already do.',
      );

      expect(
        produced,
        measuredLadder.toSet(),
        reason:
            'The set of hazards the classifier can produce has changed. '
            'Every producible hazard must hold a position in `measuredLadder`, '
            'because the peak reduce orders them.',
      );
    });
  });

  // ---------------------------------------------------------------------
  // 2. Upper half of the bracket, at the public surface.
  // ---------------------------------------------------------------------

  group('FSE-A1.2 — no hour can mask a more adverse measured hour', () {
    for (final a in measuredLadder) {
      for (final b in measuredLadder) {
        test('peak of ($a, $b) is the more adverse of the two', () {
          final briefing = advisor.brief(
            forecast: WeatherForecast(
              issuedAt: base,
              hourly: [
                slotFor(a, base),
                slotFor(b, base.add(const Duration(hours: 1))),
              ],
            ),
            commute: commute(),
            profile: profile,
          );

          expect(
            briefing.peakHazard,
            worseMeasured(a, b),
            reason:
                'The peak reduce no longer returns the more adverse '
                'measured hour. An hour classified $a and an hour classified '
                '$b reduced to ${briefing.peakHazard}.',
          );
          expect(
            briefing.peakHazard,
            isNot(isIn(absenceMembers)),
            reason:
                'A window in which EVERY hour was measured reported '
                'absence as its peak.',
          );
          expect(
            briefing.verdict,
            isNot(PretripVerdict.noData),
            reason: 'A fully forecast window was reported as having no data.',
          );
        });
      }
    }

    test('an unmeasurable-looking hour cannot delete an adjacent whiteout', () {
      // The nastiest realistic input short of the mutation itself: an hour with
      // every optional field absent, beside a measured whiteout.
      final briefing = advisor.brief(
        forecast: WeatherForecast(
          issuedAt: base,
          hourly: [
            slotFor(HourHazard.severe, base),
            HourlyForecast(
              hour: base.add(const Duration(hours: 1)),
              tempCelsius: 8.0,
            ),
          ],
        ),
        commute: commute(),
        profile: profile,
      );

      expect(briefing.peakHazard, HourHazard.severe);
      expect(briefing.verdict, isNot(PretripVerdict.noData));
      expect(
        briefing.chips,
        isNotEmpty,
        reason: 'The whiteout was measured; she must be told about it.',
      );
    });
  });

  // ---------------------------------------------------------------------
  // 3. Lower half of the bracket: absence must never buy a departure.
  // ---------------------------------------------------------------------

  group('FSE-A1.3 — absence never buys a downgrade', () {
    /// Re-classifies the window a suggested delay points at, and asserts it is
    /// fully covered and benign. This is the property `_findBetterWindow`'s
    /// `peak.index <= caution.index` test is SUPPOSED to enforce; it is
    /// asserted here against `measuredLadder`, independently of `.index`.
    void assertSuggestedDelayIsMeasuredAndBenign(
      PretripBriefing briefing,
      WeatherForecast forecast,
      CommuteShape shape,
    ) {
      final delay = briefing.recommendation?.suggestedDelay;
      if (delay == null || delay == Duration.zero) return;

      final start = shape.plannedDeparture.add(delay);
      final end = start.add(shape.plannedDuration);
      final covering = forecast.hourly
          .where(
            (s) =>
                s.hour.isBefore(end) &&
                s.hour.add(const Duration(hours: 1)).isAfter(start),
          )
          .toList();

      expect(
        covering,
        isNotEmpty,
        reason: 'A delay was suggested into hours with NO forecast at all.',
      );

      var cursor = start;
      for (final s in covering..sort((x, y) => x.hour.compareTo(y.hour))) {
        if (s.hour.isAfter(cursor)) {
          fail(
            'A delay was suggested into a window with a forecast GAP at '
            '$cursor — absence bought a departure recommendation.',
          );
        }
        cursor = s.hour.add(const Duration(hours: 1));
      }
      expect(
        cursor.isBefore(end),
        isFalse,
        reason: 'The suggested window is only partly forecast.',
      );

      for (final s in covering) {
        final h = advisor.hazardOf(s);
        // Order matters: `indexOf` returns -1 for a non-member, and -1
        // satisfies the `<=` below. Membership is asserted FIRST so an
        // unmeasured hour cannot pass the benign check by not being on the
        // ladder at all.
        expect(
          h,
          isIn(measuredLadder),
          reason:
              'A delay was suggested into an hour classified $h, which is '
              'not a measured state — absence bought a departure.',
        );
        expect(
          measuredLadder.indexOf(h),
          lessThanOrEqualTo(measuredLadder.indexOf(HourHazard.caution)),
          reason: 'A delay was suggested into an hour classified $h.',
        );
      }
    }

    test('a delay IS suggested when a later window is measured and benign', () {
      final forecast = WeatherForecast(
        issuedAt: base,
        hourly: [
          slotFor(HourHazard.severe, base),
          slotFor(HourHazard.severe, base.add(const Duration(hours: 1))),
          for (var h = 2; h <= 8; h++)
            slotFor(HourHazard.clear, base.add(Duration(hours: h))),
        ],
      );
      final shape = commute();
      final briefing = advisor.brief(
        forecast: forecast,
        commute: shape,
        profile: profile,
      );

      // Non-vacuity: this case must actually exercise the branch.
      expect(briefing.recommendation?.suggestedDelay, isNotNull);
      expect(
        briefing.recommendation!.suggestedDelay,
        greaterThan(Duration.zero),
        reason:
            'The positive case stopped suggesting a delay, so the '
            'guard below is no longer being exercised by anything.',
      );

      assertSuggestedDelayIsMeasuredAndBenign(briefing, forecast, shape);
    });

    test('no delay is suggested into a window containing a forecast GAP', () {
      final forecast = WeatherForecast(
        issuedAt: base,
        hourly: [
          slotFor(HourHazard.severe, base),
          slotFor(HourHazard.severe, base.add(const Duration(hours: 1))),
          slotFor(HourHazard.clear, base.add(const Duration(hours: 2))),
          // hour 3 is MISSING — nobody forecast it.
          for (var h = 4; h <= 8; h++)
            slotFor(HourHazard.clear, base.add(Duration(hours: h))),
        ],
      );
      final shape = commute();
      final briefing = advisor.brief(
        forecast: forecast,
        commute: shape,
        profile: profile,
      );

      assertSuggestedDelayIsMeasuredAndBenign(briefing, forecast, shape);
    });

    test('no delay is suggested into hours carrying no usable signal', () {
      // The OTHER shape of absence in a later window: the hours exist, so the
      // coverage check is satisfied, but they carry nothing except a
      // temperature. Today those classify `clear` — measured and benign — so a
      // delay is legitimately offered and this passes on its merits. The day a
      // bare hour classifies as absence AND absence is placed benign-ward (the
      // naive repair for the masking defect), this is the assertion that says
      // we just sent her out into hours nobody assessed.
      final forecast = WeatherForecast(
        issuedAt: base,
        hourly: [
          slotFor(HourHazard.severe, base),
          slotFor(HourHazard.severe, base.add(const Duration(hours: 1))),
          for (var h = 2; h <= 8; h++)
            HourlyForecast(
              hour: base.add(Duration(hours: h)),
              tempCelsius: 8.0,
            ),
        ],
      );
      final shape = commute();
      final briefing = advisor.brief(
        forecast: forecast,
        commute: shape,
        profile: profile,
      );

      // Non-vacuity: the branch must actually be taken.
      expect(
        briefing.recommendation?.suggestedDelay,
        isNotNull,
        reason:
            'This case no longer reaches the better-window search, so it '
            'is guarding nothing.',
      );
      expect(
        briefing.recommendation!.suggestedDelay,
        greaterThan(Duration.zero),
        reason:
            'This case no longer suggests a delay, so it is guarding '
            'nothing.',
      );

      assertSuggestedDelayIsMeasuredAndBenign(briefing, forecast, shape);
    });

    test('an empty forecast never yields a recommendation', () {
      final briefing = advisor.brief(
        forecast: WeatherForecast(issuedAt: base, hourly: const []),
        commute: commute(),
        profile: profile,
      );
      expect(
        briefing.recommendation,
        isNull,
        reason: 'Absence produced a departure recommendation.',
      );
    });
  });

  // ---------------------------------------------------------------------
  // 4. Absence means exactly one thing, on both public surfaces.
  // ---------------------------------------------------------------------

  group('FSE-A1.4 — an absence value appears IF AND ONLY IF nothing was '
      'measured', () {
    final cases = <String, WeatherForecast>{
      'empty': WeatherForecast(issuedAt: base, hourly: const []),
      'misses the window': WeatherForecast(
        issuedAt: base,
        hourly: [slotFor(HourHazard.severe, base.add(const Duration(days: 3)))],
      ),
      'covered, benign': WeatherForecast(
        issuedAt: base,
        hourly: [
          for (var h = 0; h <= 8; h++)
            slotFor(HourHazard.clear, base.add(Duration(hours: h))),
        ],
      ),
      'covered, whiteout': WeatherForecast(
        issuedAt: base,
        hourly: [
          for (var h = 0; h <= 8; h++)
            slotFor(HourHazard.severe, base.add(Duration(hours: h))),
        ],
      ),
      'covered, mixed': WeatherForecast(
        issuedAt: base,
        hourly: [
          slotFor(HourHazard.clear, base),
          slotFor(HourHazard.severe, base.add(const Duration(hours: 1))),
          for (var h = 2; h <= 8; h++)
            slotFor(HourHazard.caution, base.add(Duration(hours: h))),
        ],
      ),
    };

    cases.forEach((label, forecast) {
      test('brief(): peakHazard is absence <=> verdict is noData [$label]', () {
        final briefing = advisor.brief(
          forecast: forecast,
          commute: commute(),
          profile: profile,
        );

        expect(
          absenceMembers.contains(briefing.peakHazard),
          briefing.verdict == PretripVerdict.noData,
          reason:
              'peakHazard=${briefing.peakHazard} with '
              'verdict=${briefing.verdict}. Either a measured window is being '
              'reported as absence (a measurement was deleted), or an '
              'unmeasured window is being reported as a measured band (absence '
              'was dressed as data).',
        );
      });

      test('area read: areaHazard is absence <=> !forecastCovered [$label]', () {
        final read = summarizeAreaConditions(
          forecast: forecast,
          now: base,
          areaLabel: 'Akita',
        );

        expect(
          absenceMembers.contains(read.areaHazard),
          !read.forecastCovered,
          reason:
              'areaHazard=${read.areaHazard} with '
              'forecastCovered=${read.forecastCovered}. `area_condition_read` '
              'has its OWN copy of the index reduce (`_worse`), so it can '
              'break independently of the advisor.',
        );

        if (read.forecastCovered) {
          expect(
            read.areaHazard,
            isIn(measuredLadder),
            reason: 'A covered area read reported a non-measured band.',
          );
        }
      });
    });
  });
}
