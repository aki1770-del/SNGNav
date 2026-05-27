import 'dart:convert';

import 'package:condition_aggregator/condition_aggregator.dart';
import 'package:condition_aggregator_digitraffic/condition_aggregator_digitraffic.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

/// Builds a minimal Digitraffic traffic-announcement GeoJSON feature
/// mirroring the live response shape inspected on 2026-05-24 against
/// `https://tie.digitraffic.fi/api/traffic-message/v2/traffic-announcements`.
Map<String, dynamic> _feature({
  required String trafficAnnouncementType,
  double lng = 25.0,
  double lat = 60.5,
  String? englishTitle,
  String? englishAdditionalInformation,
  String? englishLocationDescription,
  String? finnishTitle,
  String? finnishAdditionalInformation,
  String? startTimeIso,
  String? endTimeIso,
}) {
  final announcements = <Map<String, dynamic>>[];
  if (englishTitle != null ||
      englishAdditionalInformation != null ||
      englishLocationDescription != null) {
    announcements.add(<String, dynamic>{
      'language': 'en',
      if (englishTitle != null) 'title': englishTitle,
      if (englishAdditionalInformation != null)
        'additionalInformation': englishAdditionalInformation,
      if (englishLocationDescription != null)
        'location': <String, dynamic>{
          'description': englishLocationDescription,
        },
      if (startTimeIso != null || endTimeIso != null)
        'timeAndDuration': <String, dynamic>{
          if (startTimeIso != null) 'startTime': startTimeIso,
          if (endTimeIso != null) 'endTime': endTimeIso,
        },
    });
  }
  if (finnishTitle != null || finnishAdditionalInformation != null) {
    announcements.add(<String, dynamic>{
      'language': 'fi',
      if (finnishTitle != null) 'title': finnishTitle,
      if (finnishAdditionalInformation != null)
        'additionalInformation': finnishAdditionalInformation,
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

/// Wraps one or more features in a GeoJSON FeatureCollection.
Map<String, dynamic> _featureCollection(List<Map<String, dynamic>> features) {
  return <String, dynamic>{
    'type': 'FeatureCollection',
    'dataUpdatedTime': '2026-05-24T08:53:21.013Z',
    'features': features,
  };
}

void main() {
  group('mapTrafficAnnouncementFeatureToAdvisory', () {
    test('maps a minimal English announcement to Advisory with publisher '
        'fields + default CAP mapping for "accident report"', () {
      final feature = _feature(
        trafficAnnouncementType: 'accident report',
        englishTitle:
            'Road 5, Ristijärvi. Traffic announcement of an accident.',
        englishAdditionalInformation:
            'Accident on Road 5; traffic disruption expected.',
        englishLocationDescription: 'Road 5, Ristijärvi, Paltamo',
        startTimeIso: '2026-05-24T10:00:00Z',
        endTimeIso: '2026-05-24T12:00:00Z',
      );

      final advisory = mapTrafficAnnouncementFeatureToAdvisory(feature);

      expect(advisory, isNotNull);
      expect(advisory!.source, AdvisorySource.other);
      expect(advisory.eventClass, 'accident report');
      // v0.0.2: severe / observed / immediate per defaultDigitrafficCapMapping.
      expect(advisory.severity, AdvisorySeverity.severe);
      expect(advisory.certainty, AdvisoryCertainty.observed);
      expect(advisory.urgency, AdvisoryUrgency.immediate);
      expect(
        advisory.headline,
        'Road 5, Ristijärvi. Traffic announcement of an accident.',
      );
      expect(
        advisory.description,
        contains('Accident on Road 5; traffic disruption expected.'),
      );
      expect(advisory.description, contains(kDigitrafficAttributionString));
      expect(advisory.areaDescription, contains('Ristijärvi'));
      expect(advisory.effective, DateTime.utc(2026, 5, 24, 10, 0, 0));
      expect(advisory.expires, DateTime.utc(2026, 5, 24, 12, 0, 0));
    });

    test('falls back to primary-language announcement when no English entry; '
        'applies default CAP mapping for "preliminary accident report"', () {
      final feature = _feature(
        trafficAnnouncementType: 'preliminary accident report',
        lng: 24.93,
        lat: 60.17,
        finnishTitle:
            'Tie 3, Hämeenlinna. Ensitiedote liikenneonnettomuudesta.',
        finnishAdditionalInformation: 'Onnettomuus tiellä 3.',
      );

      final advisory = mapTrafficAnnouncementFeatureToAdvisory(feature);

      expect(advisory, isNotNull);
      expect(advisory!.eventClass, 'preliminary accident report');
      expect(advisory.headline, startsWith('Tie 3'));
      expect(advisory.description, contains('Onnettomuus tiellä 3.'));
      expect(advisory.description, contains(kDigitrafficAttributionString));
      // v0.0.2: moderate / likely / expected.
      expect(advisory.severity, AdvisorySeverity.moderate);
      expect(advisory.certainty, AdvisoryCertainty.likely);
      expect(advisory.urgency, AdvisoryUrgency.expected);
    });

    test('returns null when properties.trafficAnnouncementType is absent', () {
      final feature = <String, dynamic>{
        'type': 'Feature',
        'geometry': {
          'type': 'Point',
          'coordinates': [25.0, 60.5],
        },
        'properties': {
          'situationType': 'traffic announcement',
          // trafficAnnouncementType intentionally omitted.
          'announcements': [
            {'language': 'en', 'title': 'no event class'},
          ],
        },
      };

      expect(mapTrafficAnnouncementFeatureToAdvisory(feature), isNull);
    });

    test('returns null when properties block is missing', () {
      final feature = <String, dynamic>{
        'type': 'Feature',
        'geometry': {
          'type': 'Point',
          'coordinates': [25.0, 60.5],
        },
      };

      expect(mapTrafficAnnouncementFeatureToAdvisory(feature), isNull);
    });
  });

  group('Default CAP mapping covers all 2026-05-24 live API values', () {
    // The 5 trafficAnnouncementType values observed in the live
    // /v2/traffic-announcements response on 2026-05-24 08:53 UTC across
    // 1455 active features: accident report (711), general (442),
    // preliminary accident report (158), ended (143), retracted (1).
    test('"general" maps to minor / possible / expected', () {
      final feature = _feature(
        trafficAnnouncementType: 'general',
        englishTitle: 'General notice',
      );
      final advisory = mapTrafficAnnouncementFeatureToAdvisory(feature);
      expect(advisory, isNotNull);
      expect(advisory!.severity, AdvisorySeverity.minor);
      expect(advisory.certainty, AdvisoryCertainty.possible);
      expect(advisory.urgency, AdvisoryUrgency.expected);
    });

    test('"ended" maps to minor / observed / past', () {
      final feature = _feature(
        trafficAnnouncementType: 'ended',
        englishTitle: 'Situation ended',
      );
      final advisory = mapTrafficAnnouncementFeatureToAdvisory(feature);
      expect(advisory, isNotNull);
      expect(advisory!.severity, AdvisorySeverity.minor);
      expect(advisory.certainty, AdvisoryCertainty.observed);
      expect(advisory.urgency, AdvisoryUrgency.past);
    });

    test('"retracted" maps to minor / unlikely / past', () {
      final feature = _feature(
        trafficAnnouncementType: 'retracted',
        englishTitle: 'Earlier announcement retracted',
      );
      final advisory = mapTrafficAnnouncementFeatureToAdvisory(feature);
      expect(advisory, isNotNull);
      expect(advisory!.severity, AdvisorySeverity.minor);
      expect(advisory.certainty, AdvisoryCertainty.unlikely);
      expect(advisory.urgency, AdvisoryUrgency.past);
    });

    test(
      'defaultDigitrafficCapMapping is exhaustive against 2026-05-24 ground-truth',
      () {
        const observed2026May24 = <String>{
          'accident report',
          'general',
          'preliminary accident report',
          'ended',
          'retracted',
        };
        for (final t in observed2026May24) {
          expect(
            defaultDigitrafficCapMapping.containsKey(t),
            isTrue,
            reason:
                'defaultDigitrafficCapMapping is missing observed event-class "$t" '
                'from 2026-05-24 live API genchi-genbutsu',
          );
        }
      },
    );
  });

  group('Fallback + integrator-override CAP mapping', () {
    test('unobserved trafficAnnouncementType falls through to '
        'fallbackMapping (conservative minor / possible / unknown)', () {
      final feature = _feature(
        trafficAnnouncementType: 'hypothetical_future_class',
        englishTitle: 'Future class',
      );
      final advisory = mapTrafficAnnouncementFeatureToAdvisory(feature);
      expect(advisory, isNotNull);
      expect(advisory!.eventClass, 'hypothetical_future_class');
      expect(advisory.severity, AdvisorySeverity.minor);
      expect(advisory.certainty, AdvisoryCertainty.possible);
      expect(advisory.urgency, AdvisoryUrgency.unknown);
    });

    test('integrator-supplied capMapping override is honored for an '
        'existing event class', () {
      final integratorMapping = <String, DigitrafficCapMapping>{
        // Rural-Finland integrator wants "general" elevated to moderate
        // because in compound-failure-snow conditions any active
        // announcement is potentially driver-actionable.
        'general': DigitrafficCapMapping(
          severity: AdvisorySeverity.moderate,
          certainty: AdvisoryCertainty.likely,
          urgency: AdvisoryUrgency.expected,
        ),
      };
      final feature = _feature(
        trafficAnnouncementType: 'general',
        englishTitle: 'General notice',
      );
      final advisory = mapTrafficAnnouncementFeatureToAdvisory(
        feature,
        capMapping: integratorMapping,
      );
      expect(advisory, isNotNull);
      expect(advisory!.severity, AdvisorySeverity.moderate);
      expect(advisory.certainty, AdvisoryCertainty.likely);
    });

    test('integrator-supplied fallbackMapping override is honored for '
        'unobserved future event-class values', () {
      final integratorFallback = DigitrafficCapMapping(
        severity: AdvisorySeverity.moderate,
        certainty: AdvisoryCertainty.possible,
        urgency: AdvisoryUrgency.expected,
      );
      final feature = _feature(
        trafficAnnouncementType: 'hypothetical_future_class',
        englishTitle: 'Future class',
      );
      final advisory = mapTrafficAnnouncementFeatureToAdvisory(
        feature,
        // Empty override map forces fallback path.
        capMapping: const <String, DigitrafficCapMapping>{},
        fallbackMapping: integratorFallback,
      );
      expect(advisory, isNotNull);
      expect(advisory!.severity, AdvisorySeverity.moderate);
      expect(advisory.urgency, AdvisoryUrgency.expected);
    });

    test(
      'Fintraffic CC-BY-4.0 attribution string appears in every emitted advisory',
      () {
        for (final t in defaultDigitrafficCapMapping.keys) {
          final feature = _feature(
            trafficAnnouncementType: t,
            englishTitle: 'title-for-$t',
            englishAdditionalInformation: 'body-for-$t',
          );
          final advisory = mapTrafficAnnouncementFeatureToAdvisory(feature);
          expect(advisory, isNotNull);
          expect(
            advisory!.description,
            contains(kDigitrafficAttributionString),
            reason:
                'CC-BY-4.0 attribution string must surface verbatim in every '
                'emitted advisory description so the credit reaches the '
                'driver-facing HMI surface (Fintraffic ToS verbatim).',
          );
        }
      },
    );
  });

  group('DigitrafficAdvisoryProvider', () {
    test('source is AdvisorySource.other placeholder per barrel doc', () {
      final provider = DigitrafficAdvisoryProvider();
      try {
        expect(provider.source, AdvisorySource.other);
      } finally {
        provider.close();
      }
    });

    test('init() is a no-op and does not throw', () async {
      final provider = DigitrafficAdvisoryProvider();
      try {
        await provider.init();
        await provider.init();
      } finally {
        provider.close();
      }
    });
  });

  group('DigitrafficAdvisoryProvider mocked-HTTP integration', () {
    test('returns CAP-mapped advisories for features inside the bounding box; '
        'filters features outside', () async {
      final inside = _feature(
        trafficAnnouncementType: 'accident report',
        lng: 24.93,
        lat: 60.17,
        englishTitle: 'Helsinki area accident',
        englishAdditionalInformation: 'Accident reported.',
      );
      final outside = _feature(
        trafficAnnouncementType: 'general',
        // Far north of Helsinki: lat 65 is > 0.5 degrees away from 60.17.
        lng: 25.0,
        lat: 65.5,
        englishTitle: 'Lapland notice',
      );
      final mock = MockClient((http.Request request) async {
        expect(request.url.host, 'tie.digitraffic.fi');
        expect(
          request.url.path,
          '/api/traffic-message/v2/traffic-announcements',
        );
        final body = jsonEncode(_featureCollection([inside, outside]));
        return http.Response(
          body,
          200,
          headers: <String, String>{
            'Content-Type': 'application/json; charset=utf-8',
          },
        );
      });

      final provider = DigitrafficAdvisoryProvider.withClient(mock);
      await provider.init();
      try {
        final advisories = await provider.fetchActiveAdvisoriesAtPoint(
          latitude: 60.17,
          longitude: 24.93,
        );
        expect(advisories, hasLength(1));
        expect(advisories.first.source, AdvisorySource.other);
        expect(advisories.first.eventClass, 'accident report');
        expect(advisories.first.severity, AdvisorySeverity.severe);
        expect(advisories.first.certainty, AdvisoryCertainty.observed);
        expect(advisories.first.urgency, AdvisoryUrgency.immediate);
        expect(advisories.first.headline, 'Helsinki area accident');
        expect(
          advisories.first.description,
          contains(kDigitrafficAttributionString),
        );
      } finally {
        provider.close();
      }
    });

    test('returns an empty list when the publisher response carries an '
        'empty features array (no throw)', () async {
      final mock = MockClient((http.Request request) async {
        final body = jsonEncode(_featureCollection(<Map<String, dynamic>>[]));
        return http.Response(body, 200);
      });
      final provider = DigitrafficAdvisoryProvider.withClient(mock);
      await provider.init();
      try {
        final advisories = await provider.fetchActiveAdvisoriesAtPoint(
          latitude: 60.17,
          longitude: 24.93,
        );
        expect(advisories, isEmpty);
      } finally {
        provider.close();
      }
    });

    test('throws DigitrafficParseException on malformed JSON body', () async {
      final mock = MockClient((http.Request request) async {
        return http.Response('not valid { json', 200);
      });
      final provider = DigitrafficAdvisoryProvider.withClient(mock);
      await provider.init();
      try {
        await expectLater(
          provider.fetchActiveAdvisoriesAtPoint(
            latitude: 60.17,
            longitude: 24.93,
          ),
          throwsA(isA<DigitrafficParseException>()),
        );
      } finally {
        provider.close();
      }
    });

    test(
      'throws DigitrafficHttpException with statusCode on HTTP 503',
      () async {
        final mock = MockClient((http.Request request) async {
          return http.Response('Service Unavailable', 503);
        });
        final provider = DigitrafficAdvisoryProvider.withClient(mock);
        await provider.init();
        try {
          await expectLater(
            provider.fetchActiveAdvisoriesAtPoint(
              latitude: 60.17,
              longitude: 24.93,
            ),
            throwsA(
              isA<DigitrafficHttpException>().having(
                (e) => e.statusCode,
                'statusCode',
                503,
              ),
            ),
          );
        } finally {
          provider.close();
        }
      },
    );

    test(
      'throws DigitrafficParseException when "features" key is missing',
      () async {
        final mock = MockClient((http.Request request) async {
          return http.Response(
            jsonEncode(<String, dynamic>{'type': 'FeatureCollection'}),
            200,
          );
        });
        final provider = DigitrafficAdvisoryProvider.withClient(mock);
        await provider.init();
        try {
          await expectLater(
            provider.fetchActiveAdvisoriesAtPoint(
              latitude: 60.17,
              longitude: 24.93,
            ),
            throwsA(isA<DigitrafficParseException>()),
          );
        } finally {
          provider.close();
        }
      },
    );
  });
}
