// The Measured-or-Absent contract, at the seam where it actually reaches a
// driver.
//
// snow_rendering held the FATAL PATH of the 0.2.7 fabrication defect:
//
//   WeatherCondition.clear()   (temp 5.0, vis 10000, iceRisk false — all fake)
//     -> RoadSurfaceState.dry
//     -> gripFactor 1.0                       (MAXIMUM GRIP on an unmeasured road)
//     -> RecommendedResponse.proceed
//     -> advisory "Conditions normal"         (shown to a driver in Akita)
//
// Every test below is a guard on one link of that chain. They are written to
// fail loudly if absence is ever again resolved toward the benign branch.
//
// The asymmetry under test (contract O2):
//   * POSITIVE evidence of a hazard fires even on partial data.
//   * The NEGATIVE verdict ("all clear") requires COMPLETE data.
//   * Everything else is `unknown` — reported AS unknown, never as a green
//     light and never as a fabricated hazard (crying wolf is a different lie,
//     not honesty).

import 'package:driving_weather/driving_weather.dart';
import 'package:snow_rendering/snow_rendering.dart';
import 'package:test/test.dart';

final _t = DateTime.utc(2026, 1, 15, 6, 30);

/// A fully-measured, genuinely benign condition — the ONLY shape that may
/// legitimately produce `proceed`.
WeatherCondition _measuredClear() => WeatherCondition(
  precipType: PrecipitationType.none,
  intensity: PrecipitationIntensity.none,
  temperatureCelsius: 5.0,
  visibilityMeters: 10000,
  windSpeedKmh: 0,
  iceRisk: false,
  source: ObservationSource.measured,
  timestamp: _t,
);

void main() {
  group('THE FATAL PATH — nothing measured must never become a green light', () {
    final unknown = WeatherCondition.unknown(timestamp: _t);

    test('surface is null, NOT RoadSurfaceState.dry', () {
      final surface = RoadSurfaceState.fromCondition(unknown);
      expect(surface, isNull);
      expect(surface, isNot(RoadSurfaceState.dry));
    });

    test('gripFactor is null, NOT 1.0 (absence is not maximum grip)', () {
      final a = DrivingConditionAssessment.fromCondition(unknown);
      expect(a.gripFactor, isNull);
      expect(a.gripFactor, isNot(1.0));
    });

    test('response is conditionsUnknown, NOT proceed', () {
      final a = DrivingConditionAssessment.fromCondition(unknown);
      expect(a.recommendedResponse, RecommendedResponse.conditionsUnknown);
      expect(a.recommendedResponse, isNot(RecommendedResponse.proceed));
    });

    test('advisory SAYS SO — and never says "Conditions normal"', () {
      final a = DrivingConditionAssessment.fromCondition(unknown);
      // The loom's third property: it stops, and it tells the weaver WHY.
      expect(a.advisoryMessage, contains('No conditions data'));
      expect(a.advisoryMessage, contains('drive to what you can see'));
      expect(a.advisoryMessage, isNot(contains('Conditions normal')));
    });

    test('isAssessed is false — the object admits it is not a claim', () {
      expect(DrivingConditionAssessment.fromCondition(unknown).isAssessed,
          isFalse);
    });

    test('precipitation is null, NOT PrecipitationConfig.none', () {
      final a = DrivingConditionAssessment.fromCondition(unknown);
      // `none` renders a clear sky. That is a positive claim about weather
      // nobody measured — the same defect, one layer down at the render seam.
      expect(a.precipitation, isNull);
      expect(a.precipitation, isNot(PrecipitationConfig.none));
    });

    test('visibility is null, NOT VisibilityDegradation.clear', () {
      final a = DrivingConditionAssessment.fromCondition(unknown);
      expect(a.visibility, isNull);
      expect(a.visibility, isNot(VisibilityDegradation.clear));
    });
  });

  group('POSITIVE evidence still fires on PARTIAL data (caution-add-only)', () {
    test('iceRisk alone, every other field absent → blackIce + reduceSpeed', () {
      final c = WeatherCondition(
        iceRisk: true,
        source: ObservationSource.measured,
        timestamp: _t,
      );
      expect(RoadSurfaceState.fromCondition(c), RoadSurfaceState.blackIce);

      final a = DrivingConditionAssessment.fromCondition(c);
      expect(a.recommendedResponse, RecommendedResponse.reduceSpeed);
      expect(a.advisoryMessage, contains('Black ice'));
    });

    test(
        'heavy snow with NO temperature → surface unknown, but STILL '
        'reduceSpeed (an absent field cannot suppress a known hazard)', () {
      final c = WeatherCondition(
        precipType: PrecipitationType.snow,
        intensity: PrecipitationIntensity.heavy,
        source: ObservationSource.measured,
        timestamp: _t,
      );
      // We honestly cannot classify the surface without a temperature...
      expect(RoadSurfaceState.fromCondition(c), isNull);

      // ...but heavy snow is positive evidence, so the driver is still warned.
      final a = DrivingConditionAssessment.fromCondition(c);
      expect(a.recommendedResponse, RecommendedResponse.reduceSpeed);
      expect(a.recommendedResponse,
          isNot(RecommendedResponse.conditionsUnknown));
      expect(a.recommendedResponse, isNot(RecommendedResponse.proceed));
    });

    test(
        'the Digitraffic shape — a SEVERE authority assertion carrying no '
        'measurements at all → still warns, and invents no numbers', () {
      // This is exactly what an authority feed publishes: a declared situation
      // with a CAP severity, and NO temperature, visibility or wind. 0.4.4
      // laundered this into fake sensor readings (-4.0 °C / 150 m / 40 km/h).
      final c = WeatherCondition(
        hazardAssertion: HazardAssertion.severe,
        source: ObservationSource.measured,
        timestamp: _t,
      );
      expect(c.hazard, SafetyVerdict.hazardous);
      expect(c.temperatureCelsius, isNull);
      expect(c.visibilityMeters, isNull);
      expect(c.windSpeedKmh, isNull);

      final a = DrivingConditionAssessment.fromCondition(c);
      expect(a.recommendedResponse, RecommendedResponse.reduceSpeed);
      expect(a.gripFactor, isNull); // warned, without a fabricated surface
    });

    test('deep cold with precipitation unreported → blackIce (residual ice)',
        () {
      final c = WeatherCondition(
        temperatureCelsius: -8.0,
        source: ObservationSource.measured,
        timestamp: _t,
      );
      expect(RoadSurfaceState.fromCondition(c), RoadSurfaceState.blackIce);
    });

    test('whiteout visibility with nothing else → considerTurningBack', () {
      final c = WeatherCondition(
        visibilityMeters: 50,
        source: ObservationSource.measured,
        timestamp: _t,
      );
      final a = DrivingConditionAssessment.fromCondition(c);
      expect(
          a.recommendedResponse, RecommendedResponse.considerTurningBack);
    });
  });

  group('PARTIAL data that is not positive evidence → unknown, not proceed', () {
    test('mild temperature but precipitation unreported → NOT dry', () {
      // +5 °C tells us nothing about whether it is snowing.
      final c = WeatherCondition(
        temperatureCelsius: 5.0,
        source: ObservationSource.measured,
        timestamp: _t,
      );
      expect(RoadSurfaceState.fromCondition(c), isNull);

      final a = DrivingConditionAssessment.fromCondition(c);
      expect(a.recommendedResponse, RecommendedResponse.conditionsUnknown);
      expect(a.recommendedResponse, isNot(RecommendedResponse.proceed));
    });

    test('benign-looking but iceRisk UNREPORTED → still not proceed', () {
      // Everything looks fine — except nobody checked for ice. 0.2.7 called
      // this "Conditions normal". A negative claim needs COMPLETE knowledge.
      final c = WeatherCondition(
        precipType: PrecipitationType.none,
        intensity: PrecipitationIntensity.none,
        temperatureCelsius: 5.0,
        visibilityMeters: 10000,
        iceRisk: null, // <-- the one thing nobody measured
        source: ObservationSource.measured,
        timestamp: _t,
      );
      expect(c.hazard, SafetyVerdict.unknown);

      final a = DrivingConditionAssessment.fromCondition(c);
      expect(a.recommendedResponse, RecommendedResponse.conditionsUnknown);
      expect(a.advisoryMessage, isNot(contains('Conditions normal')));
    });
  });

  group('NO CRYING WOLF — measured-benign still proceeds', () {
    test('fully measured clear conditions → dry, grip 1.0, proceed', () {
      final a = DrivingConditionAssessment.fromCondition(_measuredClear());
      expect(a.surfaceState, RoadSurfaceState.dry);
      expect(a.gripFactor, 1.0);
      expect(a.recommendedResponse, RecommendedResponse.proceed);
      expect(a.advisoryMessage, 'Conditions normal');
      expect(a.isAssessed, isTrue);
    });

    test('unknown is NOT escalated to a hazard (that would be a different lie)',
        () {
      final a = DrivingConditionAssessment.fromCondition(
        WeatherCondition.unknown(timestamp: _t),
      );
      // Fail-safe-to-hazard would paint black ice on every offline moment; the
      // driver would learn within one trip that the alert means nothing, and
      // ignore it on the night it was real.
      expect(a.recommendedResponse, isNot(RecommendedResponse.reduceSpeed));
      expect(
          a.recommendedResponse, isNot(RecommendedResponse.considerTurningBack));
      expect(a.recommendedResponse, RecommendedResponse.conditionsUnknown);
    });

    test('a SIMULATOR asserting clear is honest → proceed', () {
      // A simulator asserting a scenario is not a claim about the world.
      final a = DrivingConditionAssessment.fromCondition(
        WeatherCondition.simulatedClear(timestamp: _t),
      );
      expect(a.recommendedResponse, RecommendedResponse.proceed);
      expect(a.surfaceState, RoadSurfaceState.dry);
    });
  });

  // ==========================================================================
  // The last inch: the STRING the driver actually reads.
  //
  // Every test above asserted the response TIER and the grip factor. None
  // asserted `advisoryMessage` — and that gap is how a bare authority
  // assertion shipped as tier=reduceSpeed with the words "Conditions normal"
  // printed underneath it. The type system was honest; the sentence was not.
  // ==========================================================================
  group('"Conditions normal" is unreachable unless the tier is proceed', () {
    test('a SEVERE authority assertion never says "Conditions normal"', () {
      final a = DrivingConditionAssessment.fromCondition(
        WeatherCondition.unknown(
          timestamp: DateTime.now(),
          hazardAssertion: HazardAssertion.severe,
        ),
      );

      expect(a.recommendedResponse, isNot(RecommendedResponse.proceed));
      expect(a.advisoryMessage, isNot(contains('Conditions normal')));
    });

    test('heavy snow with no temperature never says "Conditions normal"', () {
      final a = DrivingConditionAssessment.fromCondition(
        WeatherCondition(
          precipType: PrecipitationType.snow,
          intensity: PrecipitationIntensity.heavy,
          source: ObservationSource.measured,
          timestamp: DateTime.now(),
        ),
      );

      expect(a.recommendedResponse, RecommendedResponse.reduceSpeed);
      expect(a.advisoryMessage, isNot(contains('Conditions normal')));
    });

    test('a benign, fully-measured road still says "Conditions normal"', () {
      final a = DrivingConditionAssessment.fromCondition(
        WeatherCondition(
          precipType: PrecipitationType.none,
          intensity: PrecipitationIntensity.none,
          temperatureCelsius: 8.0,
          visibilityMeters: 10000.0,
          windSpeedKmh: 3.0,
          iceRisk: false,
          source: ObservationSource.measured,
          timestamp: DateTime.now(),
        ),
      );

      expect(a.recommendedResponse, RecommendedResponse.proceed);
      expect(a.advisoryMessage, 'Conditions normal');
    });
  });

  group('a real authority advisory is not reported as "no data"', () {
    test('a MODERATE Digitraffic advisory does NOT read as conditionsUnknown', () {
      final a = DrivingConditionAssessment.fromCondition(
        WeatherCondition.unknown(
          timestamp: DateTime.now(),
          hazardAssertion: HazardAssertion.moderate,
        ),
      );

      // The road authority PUBLISHED a hazard. Telling the driver we have
      // nothing is a reach REGRESSION on a real, live signal.
      expect(
        a.recommendedResponse,
        isNot(RecommendedResponse.conditionsUnknown),
      );
      expect(a.recommendedResponse, RecommendedResponse.reduceSpeed);
      expect(a.advisoryMessage, isNot(contains('no data')));
      expect(a.advisoryMessage, contains('advisory'));
      expect(a.advisoryMessage, contains('not measured'));
    });

    test('a MINOR advisory also reaches the driver', () {
      final a = DrivingConditionAssessment.fromCondition(
        WeatherCondition.unknown(
          timestamp: DateTime.now(),
          hazardAssertion: HazardAssertion.minor,
        ),
      );

      expect(a.recommendedResponse, RecommendedResponse.reduceSpeed);
    });

    test('an UNSTATED-severity advisory also reaches the driver', () {
      final a = DrivingConditionAssessment.fromCondition(
        WeatherCondition.unknown(
          timestamp: DateTime.now(),
          hazardAssertion: HazardAssertion.unknown,
        ),
      );

      expect(a.recommendedResponse, RecommendedResponse.reduceSpeed);
    });
  });

  group('we do not claim an absence we did not observe, either', () {
    test('nothing measured at all => "No conditions data"', () {
      final a = DrivingConditionAssessment.fromCondition(
        WeatherCondition.unknown(timestamp: DateTime.now()),
      );

      expect(a.recommendedResponse, RecommendedResponse.conditionsUnknown);
      expect(a.advisoryMessage, contains('No conditions data'));
    });

    test(
      'a feed that answered but omitted visibility does NOT say "no data '
      'received"',
      () {
        final a = DrivingConditionAssessment.fromCondition(
          WeatherCondition(
            precipType: PrecipitationType.none,
            intensity: PrecipitationIntensity.none,
            temperatureCelsius: 4.0,
            windSpeedKmh: 5.0,
            iceRisk: false,
            source: ObservationSource.measured,
            timestamp: DateTime.now(),
          ),
        );

        // Data WAS received. Asserting "no data received" is our own
        // fabrication rule broken in mirror image — and a driver who sees it
        // on ordinary days stops believing the band.
        expect(a.recommendedResponse, RecommendedResponse.conditionsUnknown);
        expect(a.advisoryMessage, isNot(contains('no data received')));
        expect(a.advisoryMessage, contains('not measured'));
      },
    );
  });

  group('the absence tier has a voice, in the language she reads', () {
    test('conditionsUnknown carries a Japanese spoken line', () {
      final ann = RecommendedResponse.conditionsUnknown.announcement;

      expect(ann, isNotNull);
      expect(ann!.jaSpokenText, isNotEmpty);
      expect(ann.jaSpokenText, contains('路面状況を取得できていません'));
      expect(ann.jaSpokenText, contains('見える範囲で運転してください'));
    });

    test('the unknown-tier ja line never says 安全 or 正常', () {
      final ja = conditionsUnknownAnnouncement.jaSpokenText;

      // Absence must not be spoken as safety.
      expect(ja, isNot(contains('安全')));
      expect(ja, isNot(contains('正常')));
    });

    test('the road-advisory-unmeasured line says both facts in Japanese', () {
      final ja = roadAdvisoryUnmeasuredAnnouncement.jaSpokenText;

      expect(ja, contains('注意報'));
      expect(ja, contains('実測データはありません'));
      expect(ja, isNot(contains('正常')));
    });

    test('proceed announces nothing (there is nothing to announce)', () {
      expect(RecommendedResponse.proceed.announcement, isNull);
    });
  });
}
