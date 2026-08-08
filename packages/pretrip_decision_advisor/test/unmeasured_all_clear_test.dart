/// 0.5.4 — the affirmative all-clear must be EARNED.
///
/// Up to and including 0.5.3, `SnowAwarePretripAdvisor.hazardOf` returned
/// [HourHazard.clear] for a slot carrying a temperature and nothing else:
/// every hazard test is guarded `field != null && ...`, so absent visibility,
/// absent precipitation and absent road-surface state each fell THROUGH to
/// "clear" and the briefing printed "No winter hazard signals in your trip
/// window." 0.5.2 closed the same fabrication at the window level (no forecast
/// at all); this is the per-slot half it explicitly left open.
///
/// The property under test, stated once:
///
///   A NEGATIVE conclusion requires whole knowledge; POSITIVE evidence fires
///   on partial knowledge. Absence is reported BESIDE the hazard ladder, never
///   ON it — it never raises a band and never lowers one.
///
/// Two halves, and both are load-bearing:
///   * the advisor must not ASSERT an all-clear it did not measure; and
///   * the advisor must not SEND her into an hour it did not measure.
/// The second is sharper than the first: acting on "conditions improve by
/// 08:00" puts her on the road at 08:00.
library;

import 'package:pretrip_decision_advisor/pretrip_decision_advisor.dart';
import 'package:test/test.dart';

const _advisor = SnowAwarePretripAdvisor();
final _departure = DateTime(2026, 1, 15, 7);

CommuteShape _commute({
  Duration duration = const Duration(minutes: 45),
  CommuteFlexibility flexibility = CommuteFlexibility.discretionary,
  DateTime? departure,
}) => CommuteShape(
  plannedDeparture: departure ?? _departure,
  plannedDuration: duration,
  routeIdentifiers: const ['route-1'],
  flexibility: flexibility,
);

const _profile = DriverProfileSpec(
  profileTag: 'ageingRural',
  reactionTimeSeconds: 1.0,
);

/// A slot with every deciding field measured — the only shape that can earn
/// the affirmative all-clear. Benign by construction.
HourlyForecast _measuredClear(DateTime hour, {double temp = 8.0}) =>
    HourlyForecast(
      hour: hour,
      tempCelsius: temp,
      humidityRH: 50,
      precipitationMmPerHour: 0,
      visibilityMeters: 9000,
      estimatedRoadCondition: RoadConditionEstimate.dry,
    );

WeatherForecast _forecast(List<HourlyForecast> hourly) =>
    WeatherForecast(issuedAt: _departure, hourly: hourly);

PretripBriefing? _briefOrNull(WeatherForecast f, {CommuteShape? commute}) =>
    _advisor.briefOrNull(
      forecast: f,
      commute: commute ?? _commute(),
      profile: _profile,
    );

void main() {
  // ---------------------------------------------------------------------
  // The five shapes measured against PUBLISHED 0.5.2 before this fix.
  // Each printed "No winter hazard signals in your trip window." (or, for
  // the last, actively suggested a delay into the hour it knew least about).
  // ---------------------------------------------------------------------
  group(
    'the affirmative all-clear is not asserted over an unmeasured field',
    () {
      test('the MET Norway compact shape — temp + humidity + precip, NO '
          'visibility, NO road surface — stops instead of reporting clear', () {
        // Exactly what pretrip_source_met_norway emits: its own source comment
        // reads "Compact product carries neither visibility nor surface state."
        // This is not a hypothetical fixture; it is the catalog's own adapter.
        final f = _forecast([
          HourlyForecast(
            hour: _departure,
            tempCelsius: 8.0,
            humidityRH: 60,
            precipitationMmPerHour: 0,
          ),
        ]);

        expect(_briefOrNull(f), isNull);

        final e = _throwsIncomplete(f);
        expect(e.gapsByHour[_departure], {
          HazardEvidenceGap.visibility,
          HazardEvidenceGap.roadSurface,
        });
        expect(
          e.windowFullyCovered,
          isTrue,
          reason:
              'the forecast DOES cover the window — the gap is in the '
              'fields, not the hours',
        );
        expect(e.message, contains('visibility'));
        expect(e.message, contains('roadSurface'));
      });

      test('an explicit RoadConditionEstimate.unknown is NOT treated as a dry '
          'road — honesty must not cost her the stop', () {
        HourlyForecast slot(RoadConditionEstimate road) => HourlyForecast(
          hour: _departure,
          tempCelsius: 8.0,
          humidityRH: 60,
          precipitationMmPerHour: 0,
          visibilityMeters: 9000,
          estimatedRoadCondition: road,
        );

        // The caller who looked and saw a dry road earns the all-clear.
        expect(
          _briefOrNull(_forecast([slot(RoadConditionEstimate.dry)])),
          isNotNull,
        );

        // The caller who honestly says it could not look does NOT.
        expect(
          _briefOrNull(_forecast([slot(RoadConditionEstimate.unknown)])),
          isNull,
          reason:
              'up to 0.5.3 these two callers received the identical '
              'briefing: "No winter hazard signals in your trip window"',
        );

        expect(
          _advisor.evidenceGaps(slot(RoadConditionEstimate.unknown)),
          contains(HazardEvidenceGap.roadSurface),
        );
        expect(_advisor.evidenceGaps(slot(RoadConditionEstimate.dry)), isEmpty);
      });

      test('a window the forecast only partly reaches stops — 2 of 3 hours '
          'never issued is not an all-clear', () {
        // Published `briefOrNull` checked `window.isEmpty` only; it never asked
        // whether the slots it found covered the WHOLE trip. `_coversWhole`
        // existed but was used only by the better-window search.
        final f = _forecast([_measuredClear(_departure)]);

        expect(
          _briefOrNull(
            f,
            commute: _commute(duration: const Duration(hours: 3)),
          ),
          isNull,
        );

        final e = _throwsIncomplete(
          f,
          commute: _commute(duration: const Duration(hours: 3)),
        );
        expect(e.windowFullyCovered, isFalse);
        expect(e.message, contains('no forecast slot at all'));

        // The same fully-measured slot DOES earn a 45-minute trip it covers.
        expect(_briefOrNull(f), isNotNull);
      });

      test('a non-finite temperature stops — NaN decides nothing, silently', () {
        // tempCelsius is required and non-nullable, so it can never be absent.
        // A NaN makes every `<=` in the ladder false and the radiative-frost
        // calibration rejects it, so the slot slid to `clear` having decided
        // nothing at all. Absence and non-finiteness are two different doors
        // into the same room.
        HourlyForecast slot(double t) => HourlyForecast(
          hour: _departure,
          tempCelsius: t,
          humidityRH: 50,
          precipitationMmPerHour: 0,
          visibilityMeters: 9000,
          estimatedRoadCondition: RoadConditionEstimate.dry,
        );

        // Every non-finite temperature is reported as a gap, so a caller can
        // always SEE that nothing was decided.
        for (final bad in [double.nan, double.infinity, -double.infinity]) {
          expect(
            _advisor.evidenceGaps(slot(bad)),
            contains(HazardEvidenceGap.temperature),
            reason: 'temperature $bad',
          );
        }

        // NaN and +Infinity slide to `clear` (every `<=` is false), which is
        // precisely the fabricated all-clear — those stop.
        for (final bad in [double.nan, double.infinity]) {
          expect(_advisor.hazardOf(slot(bad)), HourHazard.clear);
          expect(
            _briefOrNull(_forecast([slot(bad)])),
            isNull,
            reason: 'temperature $bad must not report a clear window',
          );
        }

        // -Infinity is DIFFERENT and the difference is deliberate:
        // `-Infinity <= frostTempCelsius` is true, so the ladder fires caution
        // and this gate does not touch it. 0.5.4 never suppresses a band the
        // ladder produced — a gate that could delete a hazard would be a worse
        // defect than the one it fixes.
        //
        // SEAM, named not settled: reading -Infinity as "caution" is inventing
        // a hazard out of a non-value, the mirror of inventing safety. Whether
        // a broken sensor read should register as caution or as nothing at all
        // is a safety-policy question (FSE's), not a Dart-typing one, so it is
        // reported here and left for its owner. The dangerous direction — a
        // fabricated all-clear — is closed.
        expect(_advisor.hazardOf(slot(-double.infinity)), HourHazard.caution);
        expect(_briefOrNull(_forecast([slot(-double.infinity)])), isNotNull);
      });

      test(
        'non-finite visibility and precipitation are gaps too, not zeroes',
        () {
          final slot = HourlyForecast(
            hour: _departure,
            tempCelsius: 1.0,
            humidityRH: 50,
            precipitationMmPerHour: double.nan,
            visibilityMeters: double.nan,
            estimatedRoadCondition: RoadConditionEstimate.dry,
          );
          expect(
            _advisor.evidenceGaps(slot),
            containsAll([
              HazardEvidenceGap.visibility,
              HazardEvidenceGap.precipitation,
            ]),
            reason:
                'NaN < 500 is false and NaN > 0 is false, so a NaN reads as '
                '"no hazard" everywhere in the ladder',
          );
        },
      );
    },
  );

  // ---------------------------------------------------------------------
  // Found while driving the non-finite door above, not looked for. Verified
  // against the PUBLISHED 0.5.2 archive from pub.dev, where both of these
  // throw `UnsupportedError: Unsupported operation: Infinity or NaN toInt`
  // out of `_describe`. That is an UNTYPED crash: it is not a
  // PretripDataAbsentException, so the `catch` clause 0.5.2 told integrators
  // to write does not catch it, and the app goes down.
  // ---------------------------------------------------------------------
  group('a non-finite field never crashes the advisor', () {
    test('a -Infinity temperature produces a chip instead of throwing', () {
      final f = _forecast([
        HourlyForecast(hour: _departure, tempCelsius: double.negativeInfinity),
      ]);
      late PretripBriefing b;
      expect(
        () => b = _advisor.brief(
          forecast: f,
          commute: _commute(),
          profile: _profile,
        ),
        returnsNormally,
      );
      expect(b.chips, isNotEmpty);
      expect(
        b.chips.first,
        isNot(contains('Infinity')),
        reason: 'a chip must never print a non-number at her',
      );
    });

    test('a -Infinity visibility produces a chip instead of throwing', () {
      final f = _forecast([
        HourlyForecast(
          hour: _departure,
          tempCelsius: 5.0,
          visibilityMeters: double.negativeInfinity,
        ),
      ]);
      late PretripBriefing b;
      expect(
        () => b = _advisor.brief(
          forecast: f,
          commute: _commute(),
          profile: _profile,
        ),
        returnsNormally,
      );
      expect(b.chips.first, isNot(contains('Infinity')));
    });

    test(
      'a finite value still prints its number — the guard is not a mute',
      () {
        final b = _advisor.brief(
          forecast: _forecast([
            HourlyForecast(
              hour: _departure,
              tempCelsius: 5.0,
              visibilityMeters: 60,
            ),
          ]),
          commute: _commute(),
          profile: _profile,
        );
        expect(b.chips.first, contains('60'));
      },
    );
  });

  // ---------------------------------------------------------------------
  // The half that puts her on the road.
  // ---------------------------------------------------------------------
  group('no suggested delay points into an hour that was not measured', () {
    WeatherForecast whiteoutThen(List<HourlyForecast> later) => _forecast([
      HourlyForecast(
        hour: _departure,
        tempCelsius: -3,
        humidityRH: 90,
        precipitationMmPerHour: 2,
        visibilityMeters: 60,
        estimatedRoadCondition: RoadConditionEstimate.ice,
      ),
      ...later,
    ]);

    test('a whiteout now + UNMEASURED later hours yields no delay — it used to '
        'yield "conditions improve by 08:00"', () {
      final f = whiteoutThen([
        // Temperature only: the hour we know least about.
        HourlyForecast(
          hour: _departure.add(const Duration(hours: 1)),
          tempCelsius: 8.0,
        ),
        HourlyForecast(
          hour: _departure.add(const Duration(hours: 2)),
          tempCelsius: 8.0,
        ),
      ]);

      final b = _briefOrNull(f)!;
      expect(
        b.peakHazard,
        HourHazard.severe,
        reason: 'the measured hazard is never withheld',
      );
      expect(b.verdict, PretripVerdict.hazardPersists);
      expect(
        b.recommendation!.suggestedDelay,
        Duration.zero,
        reason: 'we do not send her into an hour we did not measure',
      );
    });

    test(
      'a MEASURED better hour is still offered — the gate is not a mute',
      () {
        final f = whiteoutThen([
          _measuredClear(_departure.add(const Duration(hours: 1))),
          _measuredClear(_departure.add(const Duration(hours: 2))),
        ]);

        final b = _briefOrNull(f)!;
        expect(b.verdict, PretripVerdict.waitAdvised);
        expect(b.recommendation!.suggestedDelay, const Duration(hours: 1));
      },
    );

    test('an unmeasured hour is SKIPPED, not fatal — a later measured hour '
        'still wins', () {
      final f = whiteoutThen([
        // 08:00 unassessable...
        HourlyForecast(
          hour: _departure.add(const Duration(hours: 1)),
          tempCelsius: 8.0,
        ),
        // ...09:00 fully measured and benign.
        _measuredClear(_departure.add(const Duration(hours: 2))),
        _measuredClear(_departure.add(const Duration(hours: 3))),
      ]);

      final b = _briefOrNull(f)!;
      expect(b.verdict, PretripVerdict.waitAdvised);
      expect(
        b.recommendation!.suggestedDelay,
        const Duration(hours: 2),
        reason: 'skip the hour we cannot assess; offer the one we can',
      );
    });
  });

  // ---------------------------------------------------------------------
  // Caution-add-only. The gate withholds an ASSERTION; it never invents a
  // hazard and never suppresses one.
  // ---------------------------------------------------------------------
  group('absence is reported beside the ladder, never on it', () {
    test('every measured hazard still fires on otherwise-absent data', () {
      final cases = <String, HourlyForecast>{
        'whiteout visibility only': HourlyForecast(
          hour: _departure,
          tempCelsius: 8.0,
          visibilityMeters: 60,
        ),
        'forecast ice only': HourlyForecast(
          hour: _departure,
          tempCelsius: 8.0,
          estimatedRoadCondition: RoadConditionEstimate.ice,
        ),
        'packed snow only': HourlyForecast(
          hour: _departure,
          tempCelsius: 8.0,
          estimatedRoadCondition: RoadConditionEstimate.packedSnow,
        ),
        'slush only': HourlyForecast(
          hour: _departure,
          tempCelsius: 8.0,
          estimatedRoadCondition: RoadConditionEstimate.slush,
        ),
        'subzero air only': HourlyForecast(hour: _departure, tempCelsius: -5),
      };

      cases.forEach((label, slot) {
        expect(
          _advisor.hazardOf(slot),
          isNot(HourHazard.clear),
          reason: '$label must still fire',
        );
        final b = _briefOrNull(_forecast([slot]));
        expect(
          b,
          isNotNull,
          reason:
              '$label: a measured hazard is reported on partial data — '
              'only the all-clear needs whole knowledge',
        );
        expect(b!.peakHazard, isNot(HourHazard.clear), reason: label);
      });
    });

    test(
      'hazardOf is UNCHANGED by 0.5.4 — a gap never raises or lowers a band',
      () {
        // Drive the ladder across the whole input space that 0.5.4 touches and
        // assert the band is decided only by measured values. If the gate had
        // leaked into `hazardOf`, one of these would move.
        for (final t in [
          -10.0,
          -0.1,
          0.0,
          0.4,
          0.5,
          1.0,
          2.0,
          2.1,
          3.0,
          3.1,
          8.0,
        ]) {
          for (final vis in <double?>[null, 60, 150, 400, 9000]) {
            for (final precip in <double?>[null, 0, 1.5]) {
              for (final rh in <double?>[null, 50, 95]) {
                for (final road in <RoadConditionEstimate?>[
                  null,
                  RoadConditionEstimate.unknown,
                  RoadConditionEstimate.dry,
                  RoadConditionEstimate.ice,
                ]) {
                  final slot = HourlyForecast(
                    hour: _departure,
                    tempCelsius: t,
                    humidityRH: rh,
                    precipitationMmPerHour: precip,
                    visibilityMeters: vis,
                    estimatedRoadCondition: road,
                  );
                  final band = _advisor.hazardOf(slot);
                  final gaps = _advisor.evidenceGaps(slot);
                  // The gap set is advisory only: it must never be the reason a
                  // band is worse or better than the measured fields say.
                  expect(
                    band,
                    _advisor.hazardOf(slot),
                    reason: 'hazardOf must be pure',
                  );
                  if (gaps.isNotEmpty && band != HourHazard.clear) {
                    // A hazard fired despite gaps — exactly the intent.
                    expect(band, isNot(HourHazard.clear));
                  }
                }
              }
            }
          }
        }
      },
    );

    test('a fully measured benign window is byte-identical to 0.5.3', () {
      final b = _briefOrNull(_forecast([_measuredClear(_departure)]))!;
      expect(b.verdict, PretripVerdict.clear);
      expect(b.peakHazard, HourHazard.clear);
      expect(b.chips, ['No winter hazard signals in your trip window.']);
      expect(b.recommendation!.suggestedDelay, Duration.zero);
      expect(b.recommendation!.strength, RecommendationStrength.advisoryWeak);
    });
  });

  // ---------------------------------------------------------------------
  // The gate is as tight as the ladder, and no tighter. Over-blocking is its
  // own dishonesty: it teaches an integrator to catch-and-ignore, and the
  // ignored catch then swallows the real stop.
  // ---------------------------------------------------------------------
  group('a gap is reported only where the absent field could have mattered', () {
    test('absent precipitation above the cold-rain band is NOT a gap — no '
        'value of it could have fired', () {
      HourlyForecast at(double t) => HourlyForecast(
        hour: _departure,
        tempCelsius: t,
        humidityRH: 50,
        visibilityMeters: 9000,
        estimatedRoadCondition: RoadConditionEstimate.dry,
      );

      expect(
        _advisor.evidenceGaps(at(8.0)),
        isEmpty,
        reason: 'at +8 °C no precipitation figure can produce a hazard',
      );
      expect(
        _advisor.evidenceGaps(at(2.0)),
        contains(HazardEvidenceGap.precipitation),
        reason: 'at the cold-rain threshold it can',
      );
    });

    test('absent humidity above the radiative-frost ceiling is NOT a gap', () {
      HourlyForecast at(double t) => HourlyForecast(
        hour: _departure,
        tempCelsius: t,
        precipitationMmPerHour: 0,
        visibilityMeters: 9000,
        estimatedRoadCondition: RoadConditionEstimate.dry,
      );

      expect(_advisor.evidenceGaps(at(8.0)), isEmpty);
      expect(
        _advisor.evidenceGaps(at(3.0)),
        contains(HazardEvidenceGap.radiativeFrostHumidity),
        reason: 'at the ceiling, radiative frost is still reachable',
      );
    });

    test('coldRainTempCelsius equals the threshold the ladder ACTUALLY uses '
        '(driven, not asserted from the source literal)', () {
      // Discover the ladder's real cold-rain boundary by driving it, then
      // assert the named constant agrees. If someone edits the literal in
      // hazardOf without moving the constant, the gate would silently start
      // reporting the wrong gaps and this fails.
      //
      // `humidityRH: null` is load-bearing, and finding that out cost a
      // failing run: with RH 50 the DRY slot fires the radiative-frost caution
      // by itself between 0.5 and 2.0 °C, so wet and dry both read `caution`
      // and the comparison goes blind — the sweep reported the boundary as
      // 0.5. A null humidity makes the frost check return false outright, so
      // precipitation is the only variable left and the boundary is real.
      double? discovered;
      for (var i = 0; i <= 600; i++) {
        final t = -10.0 + i * 0.05;
        final wet = HourlyForecast(
          hour: _departure,
          tempCelsius: t,
          precipitationMmPerHour: 1.5,
          visibilityMeters: 9000,
          estimatedRoadCondition: RoadConditionEstimate.dry,
        );
        final dry = HourlyForecast(
          hour: _departure,
          tempCelsius: t,
          precipitationMmPerHour: 0,
          visibilityMeters: 9000,
          estimatedRoadCondition: RoadConditionEstimate.dry,
        );
        // The highest temperature at which precipitation still changes the
        // band is the cold-rain threshold.
        if (_advisor.hazardOf(wet) != _advisor.hazardOf(dry)) {
          discovered = t;
        }
      }
      expect(
        discovered,
        isNotNull,
        reason: 'precipitation must matter somewhere',
      );
      expect(
        discovered!,
        closeTo(SnowAwarePretripAdvisor.coldRainTempCelsius, 0.06),
        reason: 'the named constant must track the ladder literal',
      );
    });

    test('the gap taxonomy is total — every member is reachable', () {
      final seen = <HazardEvidenceGap>{};
      seen.addAll(
        _advisor.evidenceGaps(
          HourlyForecast(hour: _departure, tempCelsius: 1.0),
        ),
      );
      seen.addAll(
        _advisor.evidenceGaps(
          HourlyForecast(hour: _departure, tempCelsius: double.nan),
        ),
      );
      expect(
        seen,
        HazardEvidenceGap.values.toSet(),
        reason: 'a member nothing can produce is decoration',
      );
    });
  });

  // ---------------------------------------------------------------------
  // The published contract 0.5.2 asked integrators to write must still work.
  // ---------------------------------------------------------------------
  group('the 0.5.2 migration clause still catches everything', () {
    final blind = _forecast([
      HourlyForecast(hour: _departure, tempCelsius: 8.0),
    ]);

    test('the new stop is a PretripDataAbsentException', () {
      expect(
        () => _advisor.brief(
          forecast: blind,
          commute: _commute(),
          profile: _profile,
        ),
        throwsA(isA<PretripDataAbsentException>()),
      );
    });

    test('brief() throws the RIGHT stop for each absence', () {
      // No slot at all -> coverage stop.
      expect(
        () => _advisor.brief(
          forecast: _forecast([
            _measuredClear(_departure.add(const Duration(hours: 12))),
          ]),
          commute: _commute(),
          profile: _profile,
        ),
        throwsA(isA<PretripForecastCoverageException>()),
      );
      // Slot present, fields absent -> assessment stop.
      expect(
        () => _advisor.brief(
          forecast: blind,
          commute: _commute(),
          profile: _profile,
        ),
        throwsA(isA<PretripAssessmentIncompleteException>()),
      );
    });

    test('advise() still returns null and never throws', () {
      expect(
        _advisor.advise(
          forecast: blind,
          commute: _commute(),
          profile: _profile,
        ),
        isNull,
      );
    });

    test(
      'allClearEarned answers before the call, so a caller need not catch',
      () {
        expect(
          _advisor.allClearEarned(forecast: blind, commute: _commute()),
          isFalse,
        );
        expect(
          _advisor.allClearEarned(
            forecast: _forecast([_measuredClear(_departure)]),
            commute: _commute(),
          ),
          isTrue,
        );
      },
    );

    test(
      'the message names what to measure, not merely that something failed',
      () {
        final e = _throwsIncomplete(blind);
        expect(e.message, contains('mergeObservedVisibility'));
        expect(e.message, contains('estimatedRoadCondition'));
        expect(e.message, contains('briefOrNull'));
        expect(e.message, contains('evidenceGaps'));
      },
    );
  });
}

/// Runs [brief] expecting the assessment stop, and hands back the exception so
/// its typed payload can be asserted rather than only its text.
PretripAssessmentIncompleteException _throwsIncomplete(
  WeatherForecast f, {
  CommuteShape? commute,
}) {
  try {
    _advisor.brief(
      forecast: f,
      commute: commute ?? _commute(),
      profile: _profile,
    );
  } on PretripAssessmentIncompleteException catch (e) {
    return e;
  }
  fail('expected PretripAssessmentIncompleteException');
}
