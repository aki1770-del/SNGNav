/// DigitrafficWeatherProvider — the Measured-or-Absent contract at the feed.
///
/// Digitraffic declares road SITUATIONS. It measures no temperature, no
/// visibility, no wind. Two groups here FAIL against 0.4.4:
///
///   * "an empty feed is not a clear road" — 0.4.4 returned a fabricated
///     +5.0 °C / 10 km / iceRisk=false condition whenever no advisory was
///     published.
///   * "a failed fetch says so" — 0.4.4 silently re-emitted the last condition
///     with no staleness marker, and emitted nothing at all when it had none.
///
/// Plus "an assertion is not a measurement": 0.4.4 turned a severe advisory
/// into -4.0 °C / 150 m / 40 km/h. Digitraffic said none of that.
library;

import 'dart:convert';

import 'package:condition_aggregator/condition_aggregator.dart';
import 'package:condition_aggregator_digitraffic/condition_aggregator_digitraffic.dart';
import 'package:driving_weather/driving_weather.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

/// Builds a minimal Digitraffic traffic-announcement GeoJSON feature,
/// mirroring the package's own test fixture shape (2026-05-24 live response).
Map<String, dynamic> _feature({
  required String trafficAnnouncementType,
  double lng = 25.4682,
  double lat = 65.0124,
  String? englishTitle,
  String? englishAdditionalInformation,
}) {
  final announcements = <Map<String, dynamic>>[];
  if (englishTitle != null || englishAdditionalInformation != null) {
    announcements.add(<String, dynamic>{
      'language': 'en',
      if (englishTitle != null) 'title': englishTitle,
      if (englishAdditionalInformation != null)
        'additionalInformation': englishAdditionalInformation,
    });
  }
  return <String, dynamic>{
    'type': 'Feature',
    'geometry': <String, dynamic>{
      'type': 'Point',
      'coordinates': <double>[lng, lat],
    },
    'properties': <String, dynamic>{
      'situationType': 'traffic announcement',
      'trafficAnnouncementType': trafficAnnouncementType,
      if (announcements.isNotEmpty) 'announcements': announcements,
    },
  };
}

Map<String, dynamic> _featureCollection(List<Map<String, dynamic>> features) {
  return <String, dynamic>{'type': 'FeatureCollection', 'features': features};
}

/// A source adapter backed by a MockClient that returns [features].
DigitrafficAdvisoryProvider _mockSource(List<Map<String, dynamic>> features) {
  final mock = MockClient((http.Request request) async {
    return http.Response(
      jsonEncode(_featureCollection(features)),
      200,
      headers: const {'Content-Type': 'application/json; charset=utf-8'},
    );
  });
  return DigitrafficAdvisoryProvider.withClient(mock);
}

void main() {
  Advisory advisory(AdvisorySeverity severity) => Advisory(
    source: AdvisorySource.other,
    eventClass: 'test',
    severity: severity,
    certainty: AdvisoryCertainty.observed,
    urgency: AdvisoryUrgency.immediate,
    areaDescription: 'Road 4, Oulu',
    effective: null,
    expires: null,
    headline: 'Test advisory',
    description: 'body',
  );

  group('an empty feed is not a clear road', () {
    test('empty advisory list maps to unknown, NOT to a fabricated clear', () {
      final c = DigitrafficWeatherProvider.advisoriesToCondition(const []);

      // 0.4.4 returned WeatherCondition.clear() here: +5.0 °C, 10 km
      // visibility, 0 km/h wind, iceRisk = false — for a road nobody looked at.
      expect(c.temperatureCelsius, isNull);
      expect(c.visibilityMeters, isNull);
      expect(c.windSpeedKmh, isNull);
      expect(c.iceRisk, isNull);
      expect(c.precipType, isNull);
      expect(c.isFullyUnknown, isTrue);
    });

    test('an empty feed yields hazard == unknown, never notHazardous', () {
      final c = DigitrafficWeatherProvider.advisoriesToCondition(const []);

      // "No advisory was published" is not "the road is clear and +5 °C".
      expect(c.hazard, SafetyVerdict.unknown);
      expect(c.hazard, isNot(SafetyVerdict.notHazardous));
    });
  });

  group('an assertion is not a measurement', () {
    test('a severe advisory is hazardous and fabricates NOTHING', () {
      final c = DigitrafficWeatherProvider.advisoriesToCondition([
        advisory(AdvisorySeverity.severe),
      ]);

      // The alert still reaches the driver — carried by the real signal.
      expect(c.hazard, SafetyVerdict.hazardous);
      expect(c.hazardAssertion, HazardAssertion.severe);

      // 0.4.4 invented -4.0 °C, 150 m and 40 km/h here. Digitraffic measures
      // none of them, so none of them are claimed.
      expect(c.temperatureCelsius, isNull);
      expect(c.visibilityMeters, isNull);
      expect(c.windSpeedKmh, isNull);
      expect(c.precipType, isNull); // it never said it was snowing, either
    });

    test('an extreme advisory is hazardous', () {
      final c = DigitrafficWeatherProvider.advisoriesToCondition([
        advisory(AdvisorySeverity.extreme),
      ]);

      expect(c.hazard, SafetyVerdict.hazardous);
      expect(c.hazardAssertion, HazardAssertion.extreme);
    });

    test('a moderate advisory carries its severity and yields unknown — the '
        'road was declared, never measured', () {
      final c = DigitrafficWeatherProvider.advisoriesToCondition([
        advisory(AdvisorySeverity.moderate),
      ]);

      expect(c.hazardAssertion, HazardAssertion.moderate);
      // 0.4.4 asserted 800 m visibility and -1.0 °C here and called it
      // "not hazardous". It knew neither.
      expect(c.hazard, SafetyVerdict.unknown);
      expect(c.visibilityMeters, isNull);
    });

    test('a minor advisory carries its severity and yields unknown', () {
      final c = DigitrafficWeatherProvider.advisoriesToCondition([
        advisory(AdvisorySeverity.minor),
      ]);

      expect(c.hazardAssertion, HazardAssertion.minor);
      expect(c.hazard, SafetyVerdict.unknown);
    });

    test('an advisory of UNSTATED severity is not downgraded to minor', () {
      final c = DigitrafficWeatherProvider.advisoriesToCondition([
        advisory(AdvisorySeverity.unknown),
      ]);

      // Something was declared; how bad it is was not. Sorting that onto the
      // benign end of the scale is the same defect in miniature.
      expect(c.hazardAssertion, HazardAssertion.unknown);
      expect(c.hazardAssertion, isNot(HazardAssertion.minor));
      expect(c.hazardAssertion, isNot(HazardAssertion.none));
    });

    test('worst-severity advisory drives the condition', () {
      final c = DigitrafficWeatherProvider.advisoriesToCondition([
        advisory(AdvisorySeverity.minor),
        advisory(AdvisorySeverity.extreme),
        advisory(AdvisorySeverity.moderate),
      ]);

      expect(c.hazard, SafetyVerdict.hazardous);
      expect(c.hazardAssertion, HazardAssertion.extreme);
    });
  });

  group('stream (mocked HTTP, no live network)', () {
    test(
      'emits an observed hazardous reading for an "accident report"',
      () async {
        final source = _mockSource([
          _feature(
            trafficAnnouncementType: 'accident report', // → severe per default
            englishTitle: 'Road 4, Oulu. Accident.',
            englishAdditionalInformation: 'Lane blocked.',
          ),
        ]);
        final provider = DigitrafficWeatherProvider.withSource(source);

        final first = provider.conditions.first;
        await provider.startMonitoring();
        final reading = await first;

        expect(reading, isA<WeatherObserved>());
        final condition = (reading as WeatherObserved).condition;
        expect(condition.hazard, SafetyVerdict.hazardous);
        expect(condition.hazardAssertion, HazardAssertion.severe);

        provider.dispose();
      },
    );

    test(
      'emits an observed UNKNOWN reading when no advisories are active',
      () async {
        final source = _mockSource(const []);
        final provider = DigitrafficWeatherProvider.withSource(source);

        final first = provider.conditions.first;
        await provider.startMonitoring();
        final reading = await first;

        // The fetch SUCCEEDED — so this is an observation. What it observed is
        // "no advisory", which is not weather, and certainly not clear weather.
        expect(reading, isA<WeatherObserved>());
        final condition = (reading as WeatherObserved).condition;
        expect(condition.hazard, SafetyVerdict.unknown);
        expect(condition.temperatureCelsius, isNull);

        provider.dispose();
      },
    );

    test(
      'filters features outside the bounding box around the query point',
      () async {
        // Feature is far south (Helsinki ~60.17), query point is Oulu (65.01):
        // > 0.5° away, so it is filtered and no advisory remains.
        final source = _mockSource([
          _feature(
            trafficAnnouncementType: 'accident report',
            lng: 24.93,
            lat: 60.17,
            englishTitle: 'Helsinki accident',
          ),
        ]);
        final provider = DigitrafficWeatherProvider.withSource(source);

        final first = provider.conditions.first;
        await provider.startMonitoring();
        final reading = await first;

        final condition = (reading as WeatherObserved).condition;
        expect(condition.hazard, isNot(SafetyVerdict.hazardous));
        expect(condition.hazardAssertion, isNull);

        provider.dispose();
      },
    );
  });

  group('a failed fetch says so', () {
    test(
      'emits WeatherStale with the REAL age — never a re-dated re-emit',
      () async {
        // First call: severe (hazardous). Second call: HTTP 503.
        var call = 0;
        final mock = MockClient((http.Request request) async {
          call++;
          if (call == 1) {
            return http.Response(
              jsonEncode(
                _featureCollection([
                  _feature(
                    trafficAnnouncementType: 'accident report',
                    englishTitle: 'Oulu accident',
                  ),
                ]),
              ),
              200,
            );
          }
          return http.Response('Service Unavailable', 503);
        });
        final provider = DigitrafficWeatherProvider.withSource(
          DigitrafficAdvisoryProvider.withClient(mock),
          pollInterval: const Duration(milliseconds: 50),
        );

        final emitted = <WeatherReading>[];
        final sub = provider.conditions.listen(emitted.add);

        await provider.startMonitoring();
        await Future<void>.delayed(const Duration(milliseconds: 120));
        await provider.stopMonitoring();
        await sub.cancel();
        provider.dispose();

        expect(emitted.length, greaterThanOrEqualTo(2));
        expect(emitted.first, isA<WeatherObserved>());

        // 0.4.4 emitted an indistinguishable copy of the first condition here.
        // Old data now announces itself as old.
        final stale = emitted.skip(1).whereType<WeatherStale>().toList();
        expect(stale, isNotEmpty, reason: 'the failed poll must emit stale');
        expect(stale.first.lastKnown.hazard, SafetyVerdict.hazardous);
        expect(stale.first.observedAt, isNotNull);
        expect(stale.first.age, isNotNull);
        expect(stale.first.cause, isNotNull);
        // Nothing after the first emission pretends to be a fresh observation.
        expect(emitted.skip(1).whereType<WeatherObserved>(), isEmpty);
      },
    );

    test(
      'emits WeatherUnavailable when it never had data — never silence',
      () async {
        final mock = MockClient((_) async {
          return http.Response('Service Unavailable', 503);
        });
        final provider = DigitrafficWeatherProvider.withSource(
          DigitrafficAdvisoryProvider.withClient(mock),
          pollInterval: const Duration(milliseconds: 50),
        );

        final emitted = <WeatherReading>[];
        final sub = provider.conditions.listen(emitted.add);

        await provider.startMonitoring();
        await Future<void>.delayed(const Duration(milliseconds: 120));
        await provider.stopMonitoring();
        await sub.cancel();
        provider.dispose();

        // 0.4.4 emitted NOTHING here, which the UI could not tell apart from
        // "not fetched yet". The absence of data is now itself a reading.
        expect(emitted, isNotEmpty);
        expect(emitted.every((r) => r is WeatherUnavailable), isTrue);
        expect((emitted.first as WeatherUnavailable).cause, isNotNull);

        provider.dispose();
      },
    );
  });

  group('an unstated severity is not sorted onto the benign end', () {
    test(
      'a feed carrying [unknown-severity, minor] does NOT reduce to minor',
      () {
        // AdvisorySeverity.unknown is declared FIRST in condition_aggregator,
        // so its enum INDEX is 0 — the lowest. A raw index comparison in the
        // worst-advisory reduce therefore threw away the advisory whose
        // severity the authority never stated, in favour of a `minor` one.
        final c = DigitrafficWeatherProvider.advisoriesToCondition([
          advisory(AdvisorySeverity.unknown),
          advisory(AdvisorySeverity.minor),
        ]);

        expect(c.hazardAssertion, isNot(HazardAssertion.minor));
        expect(c.hazardAssertion, HazardAssertion.unknown);
      },
    );

    test('an unstated severity does NOT out-rank a stated severe one', () {
      final c = DigitrafficWeatherProvider.advisoriesToCondition([
        advisory(AdvisorySeverity.unknown),
        advisory(AdvisorySeverity.severe),
      ]);

      expect(c.hazardAssertion, HazardAssertion.severe);
      expect(c.hazard, SafetyVerdict.hazardous);
    });
  });
}
