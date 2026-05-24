import 'package:condition_aggregator/condition_aggregator.dart';
import 'package:condition_aggregator_digitraffic/condition_aggregator_digitraffic.dart';
import 'package:test/test.dart';

void main() {
  group('mapTrafficAnnouncementFeatureToAdvisory', () {
    test('maps a minimal English announcement to Advisory with publisher fields',
        () {
      final feature = <String, dynamic>{
        'type': 'Feature',
        'geometry': {
          'type': 'Point',
          'coordinates': [25.0, 60.5],
        },
        'properties': {
          'situationType': 'traffic announcement',
          'trafficAnnouncementType': 'accident report',
          'announcements': [
            {
              'language': 'en',
              'title': 'Road 5, Ristijärvi. Traffic announcement of an accident.',
              'additionalInformation':
                  'Accident on Road 5; traffic disruption expected.',
              'timeAndDuration': {
                'startTime': '2026-05-24T10:00:00Z',
                'endTime': '2026-05-24T12:00:00Z',
              },
              'location': {
                'description': 'Road 5, Ristijärvi, Paltamo',
              },
            },
          ],
        },
      };

      final advisory = mapTrafficAnnouncementFeatureToAdvisory(feature);

      expect(advisory, isNotNull);
      expect(advisory!.source, AdvisorySource.other);
      expect(advisory.eventClass, 'accident report');
      expect(advisory.severity, AdvisorySeverity.unknown);
      expect(advisory.certainty, AdvisoryCertainty.unknown);
      expect(advisory.urgency, AdvisoryUrgency.unknown);
      expect(advisory.headline,
          'Road 5, Ristijärvi. Traffic announcement of an accident.');
      expect(advisory.description,
          'Accident on Road 5; traffic disruption expected.');
      expect(advisory.areaDescription, contains('Ristijärvi'));
      expect(advisory.effective, DateTime.utc(2026, 5, 24, 10, 0, 0));
      expect(advisory.expires, DateTime.utc(2026, 5, 24, 12, 0, 0));
    });

    test('falls back to primary-language announcement when no English entry',
        () {
      final feature = <String, dynamic>{
        'type': 'Feature',
        'geometry': {
          'type': 'Point',
          'coordinates': [24.93, 60.17],
        },
        'properties': {
          'trafficAnnouncementType': 'preliminary accident report',
          'announcements': [
            {
              'language': 'fi',
              'title': 'Tie 3, Hämeenlinna. Ensitiedote liikenneonnettomuudesta.',
              'additionalInformation': 'Onnettomuus tiellä 3.',
              'location': {'description': 'Tie 3, Hämeenlinna'},
            },
          ],
        },
      };

      final advisory = mapTrafficAnnouncementFeatureToAdvisory(feature);

      expect(advisory, isNotNull);
      expect(advisory!.eventClass, 'preliminary accident report');
      expect(advisory.headline, startsWith('Tie 3'));
      expect(advisory.description, 'Onnettomuus tiellä 3.');
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
}
