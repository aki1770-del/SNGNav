// The affirmative all-clear must be EARNED.
//
// 0.6.0 shipped, and published on 2026-08-21, an advisor that told a driver
// "No winter hazard signals in your trip window" / 「出発時間帯に冬季の危険を
// 示す兆候はありません」 on a morning where the road surface, the visibility,
// the precipitation and the humidity were NEVER MEASURED.
//
// Every hazard test in `hazardOf` is guarded `field != null && ...`, so a slot
// carrying a temperature and nothing else fails every test, falls through all
// of them, returns HourHazard.clear, and the briefing prints the all-clear.
// The sentence was not a summary of evidence; it was produced BY the absence
// of evidence.
//
// This is not a corner case. `pretrip_source_met_norway` emits
// `visibilityMeters: null` and `estimatedRoadCondition: null` on EVERY slot,
// by its own honesty rule — the MET Norway compact product carries neither
// field. On that path the false all-clear was the DEFAULT, not an edge.
//
// DISCRIMINATION: the tests below are split into two groups. `THE GATE` fails
// against published 0.6.0 and passes here. `CONTROLS` pass against BOTH — they
// exist so the suite cannot merely agree with the change.
import 'package:pretrip_decision_advisor/pretrip_decision_advisor.dart';
import 'package:test/test.dart';

void main() {
  final base = DateTime.utc(2026, 1, 15, 7, 0);
  const advisor = SnowAwarePretripAdvisor();
  const profile = DriverProfileSpec(
    profileTag: 'ageingRural',
    reactionTimeSeconds: 1.5,
  );

  CommuteShape commute({Duration d = const Duration(minutes: 30)}) =>
      CommuteShape(
        plannedDuration: d,
        routeIdentifiers: const ['akita-morning'],
        flexibility: CommuteFlexibility.discretionary,
        plannedDeparture: base,
      );

  WeatherForecast fc(List<HourlyForecast> h) =>
      WeatherForecast(issuedAt: base, hourly: h);

  /// Benign temperature, and NOTHING that decides the ladder.
  HourlyForecast unmeasured(DateTime h, {double t = 5.0}) =>
      HourlyForecast(hour: h, tempCelsius: t);

  /// Every deciding field measured, all benign.
  HourlyForecast fullyMeasured(DateTime h) => HourlyForecast(
    hour: h,
    tempCelsius: 5.0,
    visibilityMeters: 20000,
    precipitationMmPerHour: 0,
    humidityRH: 40,
    estimatedRoadCondition: RoadConditionEstimate.dry,
  );

  final h2 = base.add(const Duration(hours: 1));

  group('THE GATE — these fail against published 0.6.0', () {
    test('an unmeasured morning does not earn "no winter hazard"', () {
      expect(
        () => advisor.brief(
          forecast: fc([unmeasured(base), unmeasured(h2)]),
          commute: commute(),
          profile: profile,
        ),
        throwsA(isA<PretripAssessmentIncompleteException>()),
      );
    });

    test('the refusal names WHAT was not measured, per hour', () {
      try {
        advisor.brief(
          forecast: fc([unmeasured(base), unmeasured(h2)]),
          commute: commute(),
          profile: profile,
        );
        fail('expected the advisor to refuse');
      } on PretripAssessmentIncompleteException catch (e) {
        // The developer catching this must learn what to measure, not merely
        // that something was missing.
        expect(e.gapsByHour.keys, contains(base));
        expect(
          e.gapsByHour[base],
          containsAll(<HazardEvidenceGap>[
            HazardEvidenceGap.visibility,
            HazardEvidenceGap.roadSurface,
          ]),
        );
        expect(e.message, contains('Not measured'));
        expect(e.message, contains('visibility'));
        expect(e.windowFullyCovered, isTrue);
      }
    });

    test('a NaN visibility is absent, not benign', () {
      // `NaN < 100` is false, so every ladder test failed and the slot
      // fell through to clear.
      expect(
        () => advisor.brief(
          forecast: fc([
            HourlyForecast(
              hour: base,
              tempCelsius: 5.0,
              visibilityMeters: double.nan,
              precipitationMmPerHour: 0,
              humidityRH: 40,
              estimatedRoadCondition: RoadConditionEstimate.dry,
            ),
            HourlyForecast(
              hour: h2,
              tempCelsius: 5.0,
              visibilityMeters: double.nan,
              precipitationMmPerHour: 0,
              humidityRH: 40,
              estimatedRoadCondition: RoadConditionEstimate.dry,
            ),
          ]),
          commute: commute(),
          profile: profile,
        ),
        throwsA(isA<PretripAssessmentIncompleteException>()),
      );
    });

    test('an Infinity visibility is absent, not benign — and it is reachable '
        'from publisher JSON', () {
      // Not synthetic: this is what a JSON number too large for a double
      // parses to.
      final fromJson = double.tryParse('1e400');
      expect(fromJson, double.infinity);

      HourlyForecast s(DateTime h) => HourlyForecast(
        hour: h,
        tempCelsius: 5.0,
        visibilityMeters: fromJson,
        precipitationMmPerHour: 0,
        humidityRH: 40,
        estimatedRoadCondition: RoadConditionEstimate.dry,
      );

      expect(
        () => advisor.brief(
          forecast: fc([s(base), s(h2)]),
          commute: commute(),
          profile: profile,
        ),
        throwsA(isA<PretripAssessmentIncompleteException>()),
      );
    });

    test('a caller who HONESTLY says the road is unknown is not told the same '
        'as one reporting a dry road', () {
      HourlyForecast s(DateTime h, RoadConditionEstimate r) => HourlyForecast(
        hour: h,
        tempCelsius: 5.0,
        visibilityMeters: 20000,
        precipitationMmPerHour: 0,
        humidityRH: 40,
        estimatedRoadCondition: r,
      );

      // Honest "I could not look" -> refused.
      expect(
        () => advisor.brief(
          forecast: fc([
            s(base, RoadConditionEstimate.unknown),
            s(h2, RoadConditionEstimate.unknown),
          ]),
          commute: commute(),
          profile: profile,
        ),
        throwsA(isA<PretripAssessmentIncompleteException>()),
      );

      // "I looked, it is dry" -> earns the all-clear.
      expect(
        advisor
            .brief(
              forecast: fc([
                s(base, RoadConditionEstimate.dry),
                s(h2, RoadConditionEstimate.dry),
              ]),
              commute: commute(),
              profile: profile,
            )
            .verdict,
        PretripVerdict.clear,
      );
    });

    test('a partly-forecast window does not earn the all-clear', () {
      // 3 h trip, only the first hour forecast.
      expect(
        () => advisor.brief(
          forecast: fc([fullyMeasured(base)]),
          commute: commute(d: const Duration(hours: 3)),
          profile: profile,
        ),
        throwsA(isA<PretripAssessmentIncompleteException>()),
      );
    });

    test('no suggested delay points into an unmeasured hour', () {
      // Whiteout now; hour+1 unmeasured; hour+2 fully measured and benign.
      // The advisor must not offer the hour it knows least about.
      final hourly = [
        HourlyForecast(
          hour: base,
          tempCelsius: -6,
          visibilityMeters: 40,
          precipitationMmPerHour: 1.0,
          humidityRH: 95,
          estimatedRoadCondition: RoadConditionEstimate.ice,
        ),
        unmeasured(h2),
        fullyMeasured(base.add(const Duration(hours: 2))),
        fullyMeasured(base.add(const Duration(hours: 3))),
      ];
      final b = advisor.brief(
        forecast: fc(hourly),
        commute: commute(),
        profile: profile,
      );
      final delay = b.recommendation?.suggestedDelay;
      // If a delay is offered at all, it is never the +1 h unmeasured hour.
      if (delay != null && delay > Duration.zero) {
        expect(delay, isNot(const Duration(hours: 1)));
      }
    });

    test('a non-finite reading never throws an UNTYPED error out of the '
        'advisor', () {
      // Up to 0.6.0 `.round()` on a non-finite value threw
      // `UnsupportedError: Infinity or NaN toInt` — untyped, so the
      // `on PretripDataAbsentException` clause integrators were told to write
      // did not catch it and the app went down.
      HourlyForecast s(DateTime h) => HourlyForecast(
        hour: h,
        tempCelsius: double.negativeInfinity,
        visibilityMeters: double.negativeInfinity,
        precipitationMmPerHour: 1.0,
        humidityRH: 95,
        estimatedRoadCondition: RoadConditionEstimate.ice,
      );

      try {
        advisor.brief(
          forecast: fc([s(base), s(h2)]),
          commute: commute(),
          profile: profile,
        );
      } on PretripDataAbsentException {
        // acceptable: a typed stop
      } catch (e) {
        fail('threw an untyped ${e.runtimeType}: $e');
      }
    });
  });

  group('THE THREE DOORS', () {
    final unmeasuredForecast = fc([unmeasured(base), unmeasured(h2)]);

    test('briefOrNull returns null — never a clear briefing', () {
      expect(
        advisor.briefOrNull(
          forecast: unmeasuredForecast,
          commute: commute(),
          profile: profile,
        ),
        isNull,
      );
    });

    test('briefOrUnassessed returns unknown with a chip that is NOT an '
        'all-clear and NOT the no-data string', () {
      final b = advisor.briefOrUnassessed(
        forecast: unmeasuredForecast,
        commute: commute(),
        profile: profile,
      );
      expect(b.peakHazard, HourHazard.unknown);
      expect(b.verdict, PretripVerdict.noData);
      expect(b.recommendation, isNull);
      // 0.6.0 returned an empty chip list for its unassessable case, so an
      // integrator rendering chips showed the driver nothing.
      expect(b.chips, isNotEmpty);
      expect(b.chips.first, isNot(contains('No winter hazard')));
      // C6: it must not reuse the "we had no forecast" string — we HAD data.
      expect(b.chips.first, isNot(PretripMessages.en.areaForecastNotCovered()));
    });

    test(
      'allClearEarned answers before you call brief, and throws nothing',
      () {
        expect(
          advisor.allClearEarned(
            forecast: unmeasuredForecast,
            commute: commute(),
          ),
          isFalse,
        );
        expect(
          advisor.allClearEarned(
            forecast: fc([fullyMeasured(base), fullyMeasured(h2)]),
            commute: commute(),
          ),
          isTrue,
        );
      },
    );

    test('advise() still returns null rather than throwing', () {
      expect(
        advisor.advise(
          forecast: unmeasuredForecast,
          commute: commute(),
          profile: profile,
        ),
        isNull,
      );
    });
  });

  group('CONTROLS — these pass against published 0.6.0 TOO', () {
    test('a fully measured benign morning still earns the all-clear', () {
      final b = advisor.brief(
        forecast: fc([fullyMeasured(base), fullyMeasured(h2)]),
        commute: commute(),
        profile: profile,
      );
      expect(b.verdict, PretripVerdict.clear);
      expect(b.peakHazard, HourHazard.clear);
      expect(b.chips.first, contains('No winter hazard'));
    });

    test(
      'a MEASURED whiteout beside an UNMEASURED hour still reports severe',
      () {
        // The mask guard. This is the exact shape that routing unmeasured slots
        // to `HourHazard.unknown` INSIDE `hazardOf` would break: `unknown` is
        // declared last, so it wins the index-ordered peak reduce over `severe`
        // and the whole briefing collapses to noData with no chips. Driven and
        // confirmed 2026-08-28. Positive evidence fires on partial knowledge.
        final b = advisor.brief(
          forecast: fc([
            HourlyForecast(
              hour: base,
              tempCelsius: -6,
              visibilityMeters: 40,
              precipitationMmPerHour: 2.0,
              humidityRH: 95,
              estimatedRoadCondition: RoadConditionEstimate.ice,
            ),
            unmeasured(h2),
          ]),
          commute: commute(d: const Duration(minutes: 90)),
          profile: profile,
        );
        expect(b.peakHazard, HourHazard.severe);
        expect(b.chips, isNotEmpty);
      },
    );

    test('a measured hazard reports from PARTIAL data, as it always has', () {
      // Road surface measured as ice; visibility never measured. A hazard is
      // still asserted — only the affirmative all-clear needs whole knowledge.
      final b = advisor.brief(
        forecast: fc([
          HourlyForecast(
            hour: base,
            tempCelsius: -3,
            estimatedRoadCondition: RoadConditionEstimate.ice,
          ),
          HourlyForecast(
            hour: h2,
            tempCelsius: -3,
            estimatedRoadCondition: RoadConditionEstimate.ice,
          ),
        ]),
        commute: commute(),
        profile: profile,
      );
      expect(b.peakHazard, HourHazard.severe);
    });

    test('an empty forecast is unknown, never clear', () {
      // 0.6.0's own improvement, kept unchanged by 0.6.1.
      final b = advisor.brief(
        forecast: fc(const []),
        commute: commute(),
        profile: profile,
      );
      expect(b.peakHazard, HourHazard.unknown);
      expect(b.verdict, PretripVerdict.noData);
    });
  });

  group('INVARIANTS the fix must not break', () {
    test('hazardOf NEVER returns unknown — it is not a rung on the ladder', () {
      // AAA's design constraint, pinned mechanically. `unknown` is declared
      // last precisely so it sits OUTSIDE the index-ordered peak reduce; if a
      // future edit makes `hazardOf` produce it, it silently outranks `severe`.
      final samples = <HourlyForecast>[
        unmeasured(base),
        fullyMeasured(base),
        HourlyForecast(hour: base, tempCelsius: double.nan),
        HourlyForecast(
          hour: base,
          tempCelsius: double.infinity,
          visibilityMeters: double.nan,
        ),
        HourlyForecast(
          hour: base,
          tempCelsius: -20,
          visibilityMeters: 10,
          precipitationMmPerHour: 5,
          humidityRH: 99,
          estimatedRoadCondition: RoadConditionEstimate.ice,
        ),
        HourlyForecast(
          hour: base,
          tempCelsius: 30,
          visibilityMeters: 50000,
          precipitationMmPerHour: 0,
          humidityRH: 10,
          estimatedRoadCondition: RoadConditionEstimate.dry,
        ),
      ];
      for (final s in samples) {
        expect(
          advisor.hazardOf(s),
          isNot(HourHazard.unknown),
          reason: 'hazardOf produced unknown for $s',
        );
      }
      // And the ordering that makes that necessary is still what we think.
      expect(HourHazard.unknown.index, greaterThan(HourHazard.severe.index));
    });

    test('the gate constant and the ladder cannot drift apart', () {
      // `coldRainTempCelsius` decides whether an absent precipitation figure
      // is a gap; the ladder uses the same constant for cold rain. If someone
      // changes one, this pins the other.
      const t = SnowAwarePretripAdvisor.coldRainTempCelsius;
      final justInside = HourlyForecast(
        hour: base,
        tempCelsius: t,
        precipitationMmPerHour: 1.0,
      );
      final justOutside = HourlyForecast(
        hour: base,
        tempCelsius: t + 0.1,
        precipitationMmPerHour: 1.0,
      );
      expect(advisor.hazardOf(justInside), HourHazard.caution);
      expect(advisor.hazardOf(justOutside), HourHazard.clear);

      // And an ABSENT precipitation figure is a gap only inside that band.
      expect(
        advisor.evidenceGaps(HourlyForecast(hour: base, tempCelsius: t)),
        contains(HazardEvidenceGap.precipitation),
      );
      expect(
        advisor.evidenceGaps(HourlyForecast(hour: base, tempCelsius: t + 0.1)),
        isNot(contains(HazardEvidenceGap.precipitation)),
      );
    });

    test('a gap NEVER raises the hazard band', () {
      // Absence is reported beside the ladder, never on it.
      for (final s in <HourlyForecast>[
        unmeasured(base),
        HourlyForecast(hour: base, tempCelsius: 20),
        HourlyForecast(hour: base, tempCelsius: double.nan),
      ]) {
        expect(advisor.evidenceGaps(s), isNotEmpty);
        expect(advisor.hazardOf(s), HourHazard.clear);
      }
    });
  });
}
