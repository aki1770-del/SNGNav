import 'dart:convert';

import 'package:condition_aggregator/condition_aggregator.dart';
import 'package:condition_aggregator_met_norway/condition_aggregator_met_norway.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

/// A minimal MET Norway locationforecast/2.0/compact response shape,
/// mirroring the live response inspected on 2026-05-24.
Map<String, dynamic> _baseResponse({
  required String time,
  required double airTemperature,
  required double precipitationNext1h,
  String symbolCode = 'cloudy',
  double lat = 59.91,
  double lon = 10.75,
}) {
  return <String, dynamic>{
    'type': 'Feature',
    'geometry': <String, dynamic>{
      'type': 'Point',
      'coordinates': <double>[lon, lat, 3],
    },
    'properties': <String, dynamic>{
      'meta': <String, dynamic>{
        'updated_at': '2026-05-24T06:28:29Z',
        'units': <String, String>{
          'air_temperature': 'celsius',
          'precipitation_amount': 'mm',
        },
      },
      'timeseries': <Map<String, dynamic>>[
        <String, dynamic>{
          'time': time,
          'data': <String, dynamic>{
            'instant': <String, dynamic>{
              'details': <String, dynamic>{'air_temperature': airTemperature},
            },
            'next_1_hours': <String, dynamic>{
              'summary': <String, dynamic>{'symbol_code': symbolCode},
              'details': <String, dynamic>{
                'precipitation_amount': precipitationNext1h,
              },
            },
          },
        },
      ],
    },
  };
}

void main() {
  group('mapLocationForecastResponseToAdvisory', () {
    test(
      'maps freezing precipitation slice to severe Advisory with metNorway source',
      () {
        final response = _baseResponse(
          time: '2026-05-24T06:00:00Z',
          airTemperature: -2.5,
          precipitationNext1h: 1.2,
          symbolCode: 'lightsnow',
        );

        final advisory = mapLocationForecastResponseToAdvisory(
          response: response,
        );

        expect(advisory, isNotNull);
        expect(advisory!.source, AdvisorySource.metNorway);
        expect(advisory.eventClass, 'Freezing precipitation');
        expect(advisory.severity, AdvisorySeverity.severe);
        expect(advisory.certainty, AdvisoryCertainty.likely);
        expect(advisory.urgency, AdvisoryUrgency.expected);
        expect(advisory.effective, DateTime.utc(2026, 5, 24, 6, 0, 0));
        expect(advisory.expires, DateTime.utc(2026, 5, 24, 7, 0, 0));
        expect(advisory.headline, 'Freezing precipitation — lightsnow');
        expect(advisory.description, contains('-2.5'));
        expect(advisory.description, contains('1.2'));
        expect(
          advisory.description,
          contains(AdvisorySource.metNorway.attributionString),
        );
        expect(advisory.areaDescription, 'Lat 59.9100, Lon 10.7500');
      },
    );

    test(
      'maps freezing precipitation with heavy precipitation rate to extreme',
      () {
        final response = _baseResponse(
          time: '2026-05-24T06:00:00Z',
          airTemperature: -3.0,
          precipitationNext1h: 5.5,
          symbolCode: 'heavysnow',
        );

        final advisory = mapLocationForecastResponseToAdvisory(
          response: response,
        );

        expect(advisory, isNotNull);
        expect(advisory!.eventClass, 'Freezing precipitation');
        expect(advisory.severity, AdvisorySeverity.extreme);
      },
    );

    test(
      'maps subzero forecast without precipitation to moderate severity',
      () {
        final response = _baseResponse(
          time: '2026-05-24T06:00:00Z',
          airTemperature: -5.0,
          precipitationNext1h: 0.0,
          symbolCode: 'fair_day',
        );

        final advisory = mapLocationForecastResponseToAdvisory(
          response: response,
        );

        expect(advisory, isNotNull);
        expect(advisory!.eventClass, 'Subzero forecast');
        expect(advisory.severity, AdvisorySeverity.moderate);
      },
    );

    test('maps above-freezing heavy precipitation to severe Advisory', () {
      final response = _baseResponse(
        time: '2026-05-24T06:00:00Z',
        airTemperature: 8.0,
        precipitationNext1h: 6.0,
        symbolCode: 'heavyrain',
      );

      final advisory = mapLocationForecastResponseToAdvisory(
        response: response,
      );

      expect(advisory, isNotNull);
      expect(advisory!.eventClass, 'Heavy precipitation');
      expect(advisory.severity, AdvisorySeverity.severe);
    });

    test(
      'returns null when above-freezing AND no heavy precipitation (no advisory)',
      () {
        final response = _baseResponse(
          time: '2026-05-24T06:00:00Z',
          airTemperature: 15.8,
          precipitationNext1h: 0.0,
          symbolCode: 'cloudy',
        );

        final advisory = mapLocationForecastResponseToAdvisory(
          response: response,
        );

        expect(advisory, isNull);
      },
    );

    test('certainty drops to possible when symbol_code is absent', () {
      final response = _baseResponse(
        time: '2026-05-24T06:00:00Z',
        airTemperature: -2.0,
        precipitationNext1h: 1.0,
      );
      // Strip symbol_code from the next_1_hours summary.
      final ts =
          (response['properties'] as Map<String, dynamic>)['timeseries']
              as List<dynamic>;
      final slice = ts.first as Map<String, dynamic>;
      final data = slice['data'] as Map<String, dynamic>;
      final next1 = data['next_1_hours'] as Map<String, dynamic>;
      next1.remove('summary');

      final advisory = mapLocationForecastResponseToAdvisory(
        response: response,
      );
      expect(advisory, isNotNull);
      expect(advisory!.certainty, AdvisoryCertainty.possible);
    });

    test('returns null when timeseries is absent or empty', () {
      final response = <String, dynamic>{
        'type': 'Feature',
        'geometry': <String, dynamic>{
          'type': 'Point',
          'coordinates': <double>[10.75, 59.91, 3],
        },
        'properties': <String, dynamic>{
          'meta': <String, dynamic>{},
          'timeseries': <Map<String, dynamic>>[],
        },
      };
      expect(mapLocationForecastResponseToAdvisory(response: response), isNull);
    });
  });

  group('MetNorwayAdvisoryProvider', () {
    test(
      'source is AdvisorySource.metNorway (parent enum carries the member)',
      () {
        final provider = MetNorwayAdvisoryProvider();
        try {
          expect(provider.source, AdvisorySource.metNorway);
        } finally {
          provider.close();
        }
      },
    );

    test(
      'init() succeeds with default User-Agent + non-negative thresholds',
      () async {
        final provider = MetNorwayAdvisoryProvider();
        try {
          await provider.init();
          await provider.init();
        } finally {
          provider.close();
        }
      },
    );

    test(
      'init() throws MetNorwayConfigurationException on empty User-Agent',
      () async {
        final provider = MetNorwayAdvisoryProvider(userAgent: '   ');
        try {
          await expectLater(
            provider.init(),
            throwsA(isA<MetNorwayConfigurationException>()),
          );
        } finally {
          provider.close();
        }
      },
    );

    test('fetchActiveAdvisoriesAtPoint returns an Advisory when MET Norway '
        'response carries a freezing-precipitation next-hour slice', () async {
      final mock = MockClient((http.Request request) async {
        // Verify User-Agent is sent per MET Norway terms.
        expect(request.headers['User-Agent'], isNotNull);
        expect(request.headers['User-Agent']!.isNotEmpty, isTrue);
        expect(request.url.host, 'api.met.no');
        // Dart's double.toString() strips trailing zeros; 59.91 →
        // '59.91'. The truncation contract is "at most 4 decimals",
        // satisfied for an already-2-decimal input.
        expect(request.url.queryParameters['lat'], '59.91');
        expect(request.url.queryParameters['lon'], '10.75');

        final body = jsonEncode(
          _baseResponse(
            time: '2026-05-24T06:00:00Z',
            airTemperature: -2.5,
            precipitationNext1h: 1.2,
            symbolCode: 'lightsnow',
          ),
        );
        return http.Response(
          body,
          200,
          headers: <String, String>{
            'Content-Type': 'application/json; charset=utf-8',
          },
        );
      });

      final provider = MetNorwayAdvisoryProvider.withClient(mock);
      await provider.init();
      final advisories = await provider.fetchActiveAdvisoriesAtPoint(
        latitude: 59.91,
        longitude: 10.75,
      );
      expect(advisories, hasLength(1));
      expect(advisories.first.source, AdvisorySource.metNorway);
      expect(advisories.first.eventClass, 'Freezing precipitation');
    });

    test('fetchActiveAdvisoriesAtPoint returns an empty list when no '
        'driver-actionable condition is forecast', () async {
      final mock = MockClient((http.Request request) async {
        final body = jsonEncode(
          _baseResponse(
            time: '2026-05-24T06:00:00Z',
            airTemperature: 15.8,
            precipitationNext1h: 0.0,
            symbolCode: 'cloudy',
          ),
        );
        return http.Response(body, 200);
      });

      final provider = MetNorwayAdvisoryProvider.withClient(mock);
      await provider.init();
      final advisories = await provider.fetchActiveAdvisoriesAtPoint(
        latitude: 59.91,
        longitude: 10.75,
      );
      expect(advisories, isEmpty);
    });

    test(
      'fetchActiveAdvisoriesAtPoint throws MetNorwayHttpException on non-200',
      () async {
        final mock = MockClient((http.Request request) async {
          return http.Response('Forbidden', 403);
        });

        final provider = MetNorwayAdvisoryProvider.withClient(mock);
        await provider.init();
        await expectLater(
          provider.fetchActiveAdvisoriesAtPoint(
            latitude: 59.91,
            longitude: 10.75,
          ),
          throwsA(isA<MetNorwayHttpException>()),
        );
      },
    );

    test('fetchActiveAdvisoriesAtPoint throws AdvisoryProviderInitException '
        'when called before init()', () async {
      final mock = MockClient((http.Request request) async {
        return http.Response('{}', 200);
      });
      final provider = MetNorwayAdvisoryProvider.withClient(mock);
      await expectLater(
        provider.fetchActiveAdvisoriesAtPoint(
          latitude: 59.91,
          longitude: 10.75,
        ),
        throwsA(isA<AdvisoryProviderInitException>()),
      );
    });

    test(
      'coordinates are truncated to four decimal places before request',
      () async {
        Uri? observedUri;
        final mock = MockClient((http.Request request) async {
          observedUri = request.url;
          final body = jsonEncode(
            _baseResponse(
              time: '2026-05-24T06:00:00Z',
              airTemperature: 15.0,
              precipitationNext1h: 0.0,
            ),
          );
          return http.Response(body, 200);
        });

        final provider = MetNorwayAdvisoryProvider.withClient(mock);
        await provider.init();
        await provider.fetchActiveAdvisoriesAtPoint(
          latitude: 59.123456789,
          longitude: 10.987654321,
        );

        expect(observedUri, isNotNull);
        expect(observedUri!.queryParameters['lat'], '59.1234');
        expect(observedUri!.queryParameters['lon'], '10.9876');
      },
    );
  });
}
