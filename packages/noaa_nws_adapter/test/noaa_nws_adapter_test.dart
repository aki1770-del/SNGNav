/// Tests for the noaa_nws_adapter package.
///
/// Covers: WinterAlert (model + parser), NoaaNwsClient (HTTP +
/// FeatureCollection parser + filters), NoaaNwsParseException,
/// NoaaNwsHttpException. Uses package:http's MockClient — no live
/// network required.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:noaa_nws_adapter/noaa_nws_adapter.dart';
import 'package:test/test.dart';

void main() {
  group('WinterAlert', () {
    test('fromProperties parses a representative winter alert', () {
      final props = <String, dynamic>{
        'event': 'Winter Storm Warning',
        'severity': 'Severe',
        'certainty': 'Likely',
        'urgency': 'Expected',
        'areaDesc': 'Towner; Cavalier; Benson',
        'effective': '2026-05-02T20:45:00-05:00',
        'expires': '2026-05-03T21:00:00-05:00',
        'headline': 'Winter Storm Warning issued ...',
        'description': 'Heavy snow expected.',
        'instruction': 'Travel is strongly discouraged.',
        'status': 'Actual',
        'messageType': 'Update',
        'senderName': 'NWS Grand Forks ND',
      };
      final a = WinterAlert.fromProperties(props);
      expect(a.event, 'Winter Storm Warning');
      expect(a.severity, AlertSeverity.severe);
      expect(a.certainty, AlertCertainty.likely);
      expect(a.urgency, AlertUrgency.expected);
      expect(a.areaDesc, 'Towner; Cavalier; Benson');
      expect(a.effective, isNotNull);
      expect(a.expires, isNotNull);
      expect(a.status, AlertStatus.actual);
      expect(a.messageType, AlertMessageType.update);
      expect(a.senderName, 'NWS Grand Forks ND');
      expect(a.isWinterEvent, isTrue);
      expect(a.isHighImpact, isTrue);
      expect(a.isActual, isTrue);
    });

    test('fromProperties resolves missing optional fields to defaults', () {
      final a = WinterAlert.fromProperties(<String, dynamic>{
        'event': 'Freeze Warning',
      });
      expect(a.event, 'Freeze Warning');
      expect(a.severity, AlertSeverity.unknown);
      expect(a.certainty, AlertCertainty.unknown);
      expect(a.urgency, AlertUrgency.unknown);
      expect(a.areaDesc, '');
      expect(a.effective, isNull);
      expect(a.expires, isNull);
      expect(a.headline, '');
      expect(a.description, '');
      expect(a.instruction, '');
      expect(a.status, AlertStatus.unknown);
      expect(a.messageType, AlertMessageType.unknown);
      expect(a.senderName, '');
      expect(a.isWinterEvent, isTrue);
      expect(a.isHighImpact, isFalse);
      expect(a.isActual, isFalse);
    });

    test('fromProperties throws NoaaNwsParseException on missing event', () {
      expect(
        () => WinterAlert.fromProperties(<String, dynamic>{}),
        throwsA(isA<NoaaNwsParseException>()),
      );
    });

    test('Equatable identity — same fields equal each other', () {
      final a = WinterAlert.fromProperties(<String, dynamic>{
        'event': 'Blizzard Warning',
        'severity': 'Extreme',
        'status': 'Actual',
      });
      final b = WinterAlert.fromProperties(<String, dynamic>{
        'event': 'Blizzard Warning',
        'severity': 'Extreme',
        'status': 'Actual',
      });
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('isWinterEvent rejects non-winter event strings', () {
      final a = WinterAlert.fromProperties(<String, dynamic>{
        'event': 'Red Flag Warning',
      });
      expect(a.isWinterEvent, isFalse);
    });

    test('kNwsWinterEventTypes contains all 14 catalogued winter events', () {
      // Catalogued at api.weather.gov/alerts/types per the NWS API.
      const expected = <String>{
        'Winter Storm Warning',
        'Winter Storm Watch',
        'Winter Weather Advisory',
        'Blizzard Warning',
        'Ice Storm Warning',
        'Heavy Freezing Spray Warning',
        'Heavy Freezing Spray Watch',
        'Lake Effect Snow Warning',
        'Freeze Warning',
        'Freeze Watch',
        'Freezing Fog Advisory',
        'Cold Weather Advisory',
        'Extreme Cold Warning',
        'Extreme Cold Watch',
      };
      expect(kNwsWinterEventTypes, equals(expected));
      expect(kNwsWinterEventTypes.length, 14);
    });
  });

  group('NoaaNwsClient construction', () {
    test('throws ArgumentError when userAgent is empty', () {
      expect(
        () => NoaaNwsClient(userAgent: ''),
        throwsArgumentError,
      );
      expect(
        () => NoaaNwsClient(userAgent: '   '),
        throwsArgumentError,
      );
    });

    test('accepts a well-formed userAgent', () {
      final c = NoaaNwsClient(
        userAgent: '(sngnav.example, contact@sngnav.example)',
      );
      expect(c.userAgent, '(sngnav.example, contact@sngnav.example)');
      expect(c.apiBase, 'https://api.weather.gov');
      expect(c.acceptHeader, 'application/geo+json');
      c.close();
    });
  });

  group('NoaaNwsClient.parseFeatureCollection', () {
    test('parses FeatureCollection with one winter alert', () {
      final payload = <String, dynamic>{
        'type': 'FeatureCollection',
        'features': <Map<String, dynamic>>[
          <String, dynamic>{
            'properties': <String, dynamic>{
              'event': 'Winter Storm Warning',
              'severity': 'Severe',
              'status': 'Actual',
              'areaDesc': 'Cass County',
            },
          },
        ],
      };
      final out = NoaaNwsClient.parseFeatureCollection(payload);
      expect(out, hasLength(1));
      expect(out.first.event, 'Winter Storm Warning');
    });

    test('filters out non-winter events', () {
      final payload = <String, dynamic>{
        'type': 'FeatureCollection',
        'features': <Map<String, dynamic>>[
          <String, dynamic>{
            'properties': <String, dynamic>{
              'event': 'Red Flag Warning',
              'status': 'Actual',
            },
          },
          <String, dynamic>{
            'properties': <String, dynamic>{
              'event': 'Ice Storm Warning',
              'status': 'Actual',
            },
          },
        ],
      };
      final out = NoaaNwsClient.parseFeatureCollection(payload);
      expect(out, hasLength(1));
      expect(out.first.event, 'Ice Storm Warning');
    });

    test('filters out non-Actual statuses by default', () {
      final payload = <String, dynamic>{
        'type': 'FeatureCollection',
        'features': <Map<String, dynamic>>[
          <String, dynamic>{
            'properties': <String, dynamic>{
              'event': 'Winter Storm Warning',
              'status': 'Test',
            },
          },
          <String, dynamic>{
            'properties': <String, dynamic>{
              'event': 'Blizzard Warning',
              'status': 'Actual',
            },
          },
        ],
      };
      final out = NoaaNwsClient.parseFeatureCollection(payload);
      expect(out, hasLength(1));
      expect(out.first.event, 'Blizzard Warning');
    });

    test('actualOnly: false retains non-Actual entries', () {
      final payload = <String, dynamic>{
        'type': 'FeatureCollection',
        'features': <Map<String, dynamic>>[
          <String, dynamic>{
            'properties': <String, dynamic>{
              'event': 'Winter Storm Warning',
              'status': 'Test',
            },
          },
        ],
      };
      final out = NoaaNwsClient.parseFeatureCollection(
        payload,
        actualOnly: false,
      );
      expect(out, hasLength(1));
      expect(out.first.status, AlertStatus.test);
    });

    test('returns empty list for empty FeatureCollection', () {
      final payload = <String, dynamic>{
        'type': 'FeatureCollection',
        'features': <Map<String, dynamic>>[],
      };
      expect(NoaaNwsClient.parseFeatureCollection(payload), isEmpty);
    });

    test('skips malformed features without aborting the batch', () {
      final payload = <String, dynamic>{
        'type': 'FeatureCollection',
        'features': <dynamic>[
          'not-a-map',
          <String, dynamic>{
            'properties': <String, dynamic>{
              'event': 'Winter Weather Advisory',
              'status': 'Actual',
            },
          },
          <String, dynamic>{'properties': 'also-not-a-map'},
          <String, dynamic>{
            'properties': <String, dynamic>{
              // missing event
              'status': 'Actual',
            },
          },
        ],
      };
      final out = NoaaNwsClient.parseFeatureCollection(payload);
      expect(out, hasLength(1));
      expect(out.first.event, 'Winter Weather Advisory');
    });

    test('throws NoaaNwsParseException on wrong top-level type', () {
      expect(
        () => NoaaNwsClient.parseFeatureCollection(<String, dynamic>{
          'type': 'Feature',
          'features': <Map<String, dynamic>>[],
        }),
        throwsA(isA<NoaaNwsParseException>()),
      );
    });

    test('throws NoaaNwsParseException on non-object payload', () {
      expect(
        () => NoaaNwsClient.parseFeatureCollection(<dynamic>[]),
        throwsA(isA<NoaaNwsParseException>()),
      );
    });

    test('throws NoaaNwsParseException on missing features array', () {
      expect(
        () => NoaaNwsClient.parseFeatureCollection(<String, dynamic>{
          'type': 'FeatureCollection',
        }),
        throwsA(isA<NoaaNwsParseException>()),
      );
    });
  });

  group('NoaaNwsClient.fetchActiveWinterAlerts (MockClient)', () {
    test('sends User-Agent + Accept; URL carries point query', () async {
      late http.Request capturedRequest;
      final mock = MockClient((req) async {
        capturedRequest = req;
        return http.Response(
          jsonEncode(<String, dynamic>{
            'type': 'FeatureCollection',
            'features': <Map<String, dynamic>>[],
          }),
          200,
          headers: {'content-type': 'application/geo+json'},
        );
      });
      final c = NoaaNwsClient(
        userAgent: '(sngnav.example, contact@sngnav.example)',
        client: mock,
      );
      final out = await c.fetchActiveWinterAlerts(
        latitude: 47.9253,
        longitude: -97.0329,
      );
      expect(out, isEmpty);
      expect(capturedRequest.method, 'GET');
      expect(capturedRequest.url.host, 'api.weather.gov');
      expect(capturedRequest.url.path, '/alerts/active');
      expect(
        capturedRequest.url.query,
        contains('point=47.9253,-97.0329'),
      );
      expect(
        capturedRequest.headers['User-Agent'],
        '(sngnav.example, contact@sngnav.example)',
      );
      expect(capturedRequest.headers['Accept'], 'application/geo+json');
      c.close();
    });

    test('returns winter alerts only from a mixed FeatureCollection', () async {
      final mock = MockClient((_) async => http.Response(
            jsonEncode(<String, dynamic>{
              'type': 'FeatureCollection',
              'features': <Map<String, dynamic>>[
                <String, dynamic>{
                  'properties': <String, dynamic>{
                    'event': 'Red Flag Warning',
                    'status': 'Actual',
                  },
                },
                <String, dynamic>{
                  'properties': <String, dynamic>{
                    'event': 'Blizzard Warning',
                    'severity': 'Extreme',
                    'status': 'Actual',
                  },
                },
              ],
            }),
            200,
          ));
      final c = NoaaNwsClient(
        userAgent: '(sngnav.example, contact@sngnav.example)',
        client: mock,
      );
      final out = await c.fetchActiveWinterAlerts(
        latitude: 47.9,
        longitude: -97.0,
      );
      expect(out, hasLength(1));
      expect(out.first.event, 'Blizzard Warning');
      c.close();
    });

    test('throws NoaaNwsHttpException on non-2xx', () async {
      final mock = MockClient((_) async => http.Response('rate limited', 429));
      final c = NoaaNwsClient(
        userAgent: '(sngnav.example, contact@sngnav.example)',
        client: mock,
      );
      await expectLater(
        c.fetchActiveWinterAlerts(latitude: 47.9, longitude: -97.0),
        throwsA(isA<NoaaNwsHttpException>().having(
          (e) => e.statusCode,
          'statusCode',
          429,
        )),
      );
      c.close();
    });

    test('throws NoaaNwsHttpException on transport failure', () async {
      final mock = MockClient((_) async => throw const _FakeSocketException());
      final c = NoaaNwsClient(
        userAgent: '(sngnav.example, contact@sngnav.example)',
        client: mock,
      );
      await expectLater(
        c.fetchActiveWinterAlerts(latitude: 47.9, longitude: -97.0),
        throwsA(isA<NoaaNwsHttpException>()),
      );
      c.close();
    });

    test('throws NoaaNwsParseException on invalid JSON body', () async {
      final mock = MockClient((_) async => http.Response('not json', 200));
      final c = NoaaNwsClient(
        userAgent: '(sngnav.example, contact@sngnav.example)',
        client: mock,
      );
      await expectLater(
        c.fetchActiveWinterAlerts(latitude: 47.9, longitude: -97.0),
        throwsA(isA<NoaaNwsParseException>()),
      );
      c.close();
    });
  });

  group('Exception types', () {
    test('NoaaNwsParseException toString carries message', () {
      const e = NoaaNwsParseException('bad shape');
      expect(e.toString(), contains('bad shape'));
      expect(e.toString(), startsWith('NoaaNwsParseException'));
    });

    test('NoaaNwsHttpException toString carries status + uri', () {
      final e = NoaaNwsHttpException(
        'fail',
        statusCode: 500,
        uri: Uri.parse('https://api.weather.gov/alerts/active?point=0,0'),
      );
      final s = e.toString();
      expect(s, contains('500'));
      expect(s, contains('alerts/active'));
      expect(s, contains('fail'));
    });
  });
}

class _FakeSocketException implements Exception {
  const _FakeSocketException();
  @override
  String toString() => 'SocketException: simulated';
}
