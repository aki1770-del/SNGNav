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
  return <String, dynamic>{
    'type': 'FeatureCollection',
    'features': features,
  };
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
  group('DigitrafficWeatherProvider.advisoriesToCondition (pure mapping)', () {
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

    test('empty list maps to clear (not hazardous)', () {
      final c = DigitrafficWeatherProvider.advisoriesToCondition(const []);
      expect(c.isHazardous, isFalse);
      expect(c.precipType, PrecipitationType.none);
    });

    test('severe advisory maps to a hazardous condition', () {
      final c = DigitrafficWeatherProvider.advisoriesToCondition(
        [advisory(AdvisorySeverity.severe)],
      );
      expect(c.isHazardous, isTrue);
      expect(c.intensity, PrecipitationIntensity.heavy);
    });

    test('extreme advisory maps to a hazardous condition', () {
      final c = DigitrafficWeatherProvider.advisoriesToCondition(
        [advisory(AdvisorySeverity.extreme)],
      );
      expect(c.isHazardous, isTrue);
    });

    test('moderate advisory maps to non-hazardous reduced-visibility', () {
      final c = DigitrafficWeatherProvider.advisoriesToCondition(
        [advisory(AdvisorySeverity.moderate)],
      );
      expect(c.isHazardous, isFalse);
      expect(c.hasReducedVisibility, isTrue);
      expect(c.intensity, PrecipitationIntensity.moderate);
    });

    test('minor advisory maps to non-hazardous light condition', () {
      final c = DigitrafficWeatherProvider.advisoriesToCondition(
        [advisory(AdvisorySeverity.minor)],
      );
      expect(c.isHazardous, isFalse);
      expect(c.intensity, PrecipitationIntensity.light);
    });

    test('worst-severity advisory drives the condition', () {
      final c = DigitrafficWeatherProvider.advisoriesToCondition([
        advisory(AdvisorySeverity.minor),
        advisory(AdvisorySeverity.extreme),
        advisory(AdvisorySeverity.moderate),
      ]);
      expect(c.isHazardous, isTrue);
      expect(c.intensity, PrecipitationIntensity.heavy);
    });
  });

  group('DigitrafficWeatherProvider stream (mocked HTTP, no live network)', () {
    test('emits a hazardous condition for an "accident report" feature',
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
      final condition = await first;

      expect(condition.isHazardous, isTrue);
      expect(condition.intensity, PrecipitationIntensity.heavy);

      provider.dispose();
    });

    test('emits a clear condition when no advisories are active', () async {
      final source = _mockSource(const []);
      final provider = DigitrafficWeatherProvider.withSource(source);

      final first = provider.conditions.first;
      await provider.startMonitoring();
      final condition = await first;

      expect(condition.isHazardous, isFalse);
      expect(condition.precipType, PrecipitationType.none);

      provider.dispose();
    });

    test('filters features outside the bounding box around the query point',
        () async {
      // Feature is far south (Helsinki ~60.17), query point is Oulu (65.01):
      // > 0.5° away, so it is filtered and the condition is clear.
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
      final condition = await first;

      expect(condition.isHazardous, isFalse);

      provider.dispose();
    });

    test('on fetch failure re-emits last known condition (offline fallback)',
        () async {
      // First call: severe (hazardous). Second call: HTTP 503 → fallback to
      // the last known hazardous condition rather than going silent.
      var call = 0;
      final mock = MockClient((http.Request request) async {
        call++;
        if (call == 1) {
          return http.Response(
            jsonEncode(_featureCollection([
              _feature(
                trafficAnnouncementType: 'accident report',
                englishTitle: 'Oulu accident',
              ),
            ])),
            200,
          );
        }
        return http.Response('Service Unavailable', 503);
      });
      final provider = DigitrafficWeatherProvider.withSource(
        DigitrafficAdvisoryProvider.withClient(mock),
        pollInterval: const Duration(milliseconds: 50),
      );

      final emitted = <WeatherCondition>[];
      final sub = provider.conditions.listen(emitted.add);

      await provider.startMonitoring();
      // Wait for at least one poll-driven (failing) fetch to fire.
      await Future<void>.delayed(const Duration(milliseconds: 120));
      await provider.stopMonitoring();
      await sub.cancel();
      provider.dispose();

      // At least two emissions; all hazardous (fallback re-emitted the first).
      expect(emitted.length, greaterThanOrEqualTo(2));
      expect(emitted.every((c) => c.isHazardous), isTrue);
    });
  });
}
