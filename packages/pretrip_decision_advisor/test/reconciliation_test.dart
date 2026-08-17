/// 0.5.3 carries TWO independent safety fixes that were developed on divergent
/// branches and had never been in one tree. Neither branch could have written
/// this file, because each held only half of it.
///
///   * the destination-AREA warning line — a warning in hand renders first, and
///     the "nothing in force" claim must be earned (`area_condition_read.dart`);
///   * the trip-window affirmative all-clear — a negative conclusion requires
///     whole knowledge (`snow_aware_pretrip_advisor.dart`, `pretrip_absence.dart`).
///
/// They touch disjoint files, so `git` merged them silently. Silence from a
/// merge tool is not agreement between two behaviours. These tests are the
/// measurement: both fixes present in ONE tree, neither suppressing the other,
/// and the one place where the two halves still answer differently pinned in
/// the open rather than left to be discovered by an integrator.
library;

import 'package:pretrip_decision_advisor/pretrip_decision_advisor.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime(2026, 1, 15, 6);
  const advisor = SnowAwarePretripAdvisor();
  const profile = DriverProfileSpec(
    profileTag: 'ageingRural',
    reactionTimeSeconds: 1.5,
  );
  CommuteShape commute() => CommuteShape(
    plannedDuration: const Duration(hours: 2),
    routeIdentifiers: const [],
    flexibility: CommuteFlexibility.discretionary,
    plannedDeparture: now,
  );

  /// Temperature and nothing else — the shape `pretrip_source_met_norway`
  /// emits on EVERY slot, and the shape this package's own `example/main.dart`
  /// builds. Not a corner case; the normal shape of a compact forecast.
  WeatherForecast temperatureOnly() => WeatherForecast(
    hourly: [
      for (var h = 0; h < 8; h++)
        HourlyForecast(hour: now.add(Duration(hours: h)), tempCelsius: 5),
    ],
    issuedAt: now,
  );

  /// A measured 80 m whiteout at the departure hour.
  WeatherForecast measuredWhiteout() => WeatherForecast(
    hourly: [
      HourlyForecast(hour: now, tempCelsius: -6, visibilityMeters: 80),
      for (var h = 1; h < 8; h++)
        HourlyForecast(hour: now.add(Duration(hours: h)), tempCelsius: -6),
    ],
    issuedAt: now,
  );

  group('both fixes are in this tree — neither was lost to the merge', () {
    test(
      'AREA half: the zero-effort call no longer claims "nothing in force"',
      () {
        // Reverting `warningCheckAvailable`'s default to `true` fails this.
        final chips = areaConditionChips(
          summarizeAreaConditions(
            forecast: temperatureOnly(),
            now: now,
            areaLabel: 'Akita',
          ),
          PretripMessages.en,
        );
        expect(chips.first, contains('check unavailable'));
        expect(chips.first, isNot(contains('No active snow warning')));
      },
    );

    test('AREA half: a warning in hand survives an admitted gap', () {
      // Restoring the pre-0.5.3 branch order fails this: the 大雪警報 was
      // replaced by "check unavailable" whenever the caller was honest.
      final chips = areaConditionChips(
        summarizeAreaConditions(
          forecast: temperatureOnly(),
          now: now,
          areaLabel: 'Akita',
          warningEventVerbatim: '大雪警報',
          warningCheckAvailable: false,
        ),
        PretripMessages.en,
      );
      expect(chips.first, contains('大雪警報'));
    });

    test(
      'WINDOW half: an unearned all-clear is a typed stop, not a briefing',
      () {
        // Deleting the 0.5.3 all-clear gate fails this.
        expect(
          () => advisor.brief(
            forecast: temperatureOnly(),
            commute: commute(),
            profile: profile,
          ),
          throwsA(isA<PretripAssessmentIncompleteException>()),
        );
        expect(
          advisor.briefOrNull(
            forecast: temperatureOnly(),
            commute: commute(),
            profile: profile,
          ),
          isNull,
        );
        expect(
          advisor.allClearEarned(
            forecast: temperatureOnly(),
            commute: commute(),
          ),
          isFalse,
        );
      },
    );
  });

  group('the two halves do not fight each other', () {
    test('NO forecast at all: both surfaces refuse, under ONE catch clause', () {
      // The seam contract. An integrator writes `on PretripDataAbsentException`
      // once and both the area read and the briefing land in it. If either half
      // ever grows its own unrelated exception base, this goes red.
      final none = WeatherForecast(hourly: const [], issuedAt: now);

      expect(
        () =>
            advisor.brief(forecast: none, commute: commute(), profile: profile),
        throwsA(isA<PretripDataAbsentException>()),
      );
      expect(
        () => summarizeAreaConditions(
          forecast: none,
          now: now,
          areaLabel: 'Akita',
        ).areaHazard,
        throwsA(isA<PretripDataAbsentException>()),
      );
      expect(
        summarizeAreaConditions(
          forecast: none,
          now: now,
          areaLabel: 'Akita',
        ).areaHazardOrNull(),
        isNull,
      );
    });

    test('a MEASURED hazard is suppressed by neither fix', () {
      // The failure mode a merge of two "be more honest" patches invites: two
      // gates stacking until they delete the thing she needed to see. The 0.5.3
      // rule is asymmetric on purpose — positive evidence fires on partial
      // knowledge — so a whiteout must survive BOTH halves at once, with the
      // official-warning check honestly incomplete and the later hours blank.
      final area = summarizeAreaConditions(
        forecast: measuredWhiteout(),
        now: now,
        areaLabel: 'Akita',
        warningEventVerbatim: '大雪警報',
        warningCheckAvailable: false,
      );
      expect(area.areaHazard, HourHazard.severe);
      expect(
        areaConditionChips(area, PretripMessages.en).join(' '),
        allOf(contains('大雪警報'), contains('severe')),
      );

      final briefing = advisor.brief(
        forecast: measuredWhiteout(),
        commute: commute(),
        profile: profile,
      );
      expect(briefing.peakHazard, HourHazard.severe);
      // And no delay is offered into the unmeasured later hours.
      expect(briefing.verdict, PretripVerdict.hazardPersists);
    });
  });

  group('the gap this release does NOT close, pinned so it cannot go quiet', () {
    test(
      'the area hazard chip still reports an UNEARNED all-clear — documented, '
      'not endorsed',
      () {
        // Same forecast, two public surfaces, two different answers:
        //   brief()             -> PretripAssessmentIncompleteException
        //   areaConditionChips() -> "no winter hazard signal"
        //
        // The area read runs the same per-slot ladder and has the same gap, and
        // closing it needs a "could not assess" line — a NEW PretripMessages
        // member, which is a compile break for anyone who `implements` that
        // published abstract class, so it cannot ship inside ^0.5.0. It is in
        // the CHANGELOG under honest bounds with this reproduction.
        //
        // THIS TEST IS EXPECTED TO GO RED when the area path is fixed. That is
        // its job: the honest bound in the CHANGELOG must be edited in the same
        // commit that removes it.
        final forecast = temperatureOnly();
        final area = summarizeAreaConditions(
          forecast: forecast,
          now: now,
          areaLabel: 'Akita',
        );
        expect(area.forecastCovered, isTrue);
        expect(area.areaHazardOrNull(), HourHazard.clear);
        expect(
          areaConditionChips(area, PretripMessages.en)[1],
          contains('no winter hazard signal'),
        );

        // And the escape hatch an integrator can use TODAY, inside ^0.5.0,
        // without waiting for the message member: evidenceGaps is public.
        expect(
          forecast.hourly.any((s) => advisor.evidenceGaps(s).isNotEmpty),
          isTrue,
          reason:
              'evidenceGaps is the caller-side countermeasure the '
              'CHANGELOG points area-read consumers at; if it stops seeing '
              'this shape the CHANGELOG advice is wrong.',
        );
      },
    );
  });

  group('FSE-A1 lineage bridge — absence is off the scale HERE too', () {
    // `keep/lock/pretrip_decision_advisor-absence-ordering` (3103abe) locks
    // absence off the measurement scale. That lock is authored against the
    // 0.6.x lineage, where `HourHazard` carries a fifth member `unknown` at
    // index 4; it does not compile on the 0.5.x line, which has no absence
    // member at all (measured this turn: 4 analyzer errors, all
    // `undefined_enum_constant` on `HourHazard.unknown`).
    //
    // Its invariant nonetheless holds here, and holds STRUCTURALLY: there is
    // nothing to misplace. That is a stronger property than the lock asserts,
    // and it is exactly the property that disappears the moment someone adds
    // `unknown` to this line.
    //
    // Honest bound on what this group catches, measured by mutation rather than
    // assumed: adding `unknown` to `HourHazard` breaks the BUILD first — three
    // non-exhaustive switches (`pretrip_messages.dart:282`, `:418`,
    // `snow_aware_pretrip_advisor.dart:369`) — so the compiler is the first net
    // and this test never runs. The test is the SECOND net, and it covers the
    // dangerous path the compiler does not: someone silences those three
    // switches with a `case HourHazard.unknown:` and absence is now on the
    // scale with nothing complaining. On that day this goes red, and the
    // correct response is to PORT THE LOCK, never to edit it.

    test('HourHazard carries measured states ONLY — no absence member', () {
      expect(HourHazard.values, [
        HourHazard.clear,
        HourHazard.caution,
        HourHazard.elevated,
        HourHazard.severe,
      ]);
    });

    test('every member is reachable from the classifier (non-vacuous)', () {
      // Guards the test above from passing because the ladder went dead.
      HourlyForecast slot(RoadConditionEstimate road, double temp) =>
          HourlyForecast(
            hour: now,
            tempCelsius: temp,
            humidityRH: 30,
            precipitationMmPerHour: 0,
            visibilityMeters: 20000,
            estimatedRoadCondition: road,
          );
      expect(
        advisor.hazardOf(slot(RoadConditionEstimate.dry, 10)),
        HourHazard.clear,
      );
      expect(
        advisor.hazardOf(slot(RoadConditionEstimate.slush, 5)),
        HourHazard.caution,
      );
      expect(
        advisor.hazardOf(slot(RoadConditionEstimate.packedSnow, 5)),
        HourHazard.elevated,
      );
      expect(
        advisor.hazardOf(slot(RoadConditionEstimate.ice, 5)),
        HourHazard.severe,
      );
    });

    test('absence reaches the caller as a TYPE, never as a band', () {
      // The 0.5.x expression of FSE-A1.4: an absence value appears if and only
      // if nothing was measured — carried by the exception family, because the
      // enum deliberately cannot say it.
      expect(
        PretripForecastCoverageException(
          plannedDeparture: now,
          plannedDuration: const Duration(hours: 2),
          forecastSlotCount: 0,
        ),
        isA<PretripDataAbsentException>(),
      );
      expect(
        AreaForecastNotCoveredException(areaLabel: 'Akita'),
        isA<PretripDataAbsentException>(),
      );
      expect(
        PretripAssessmentIncompleteException(
          plannedDeparture: now,
          plannedDuration: const Duration(hours: 2),
          gapsByHour: const {},
          windowFullyCovered: true,
        ),
        isA<PretripDataAbsentException>(),
      );
    });
  });
}
