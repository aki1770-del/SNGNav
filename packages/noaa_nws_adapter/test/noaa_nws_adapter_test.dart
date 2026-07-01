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
      expect(() => NoaaNwsClient(userAgent: ''), throwsArgumentError);
      expect(() => NoaaNwsClient(userAgent: '   '), throwsArgumentError);
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
      expect(capturedRequest.url.query, contains('point=47.9253,-97.0329'));
      expect(
        capturedRequest.headers['User-Agent'],
        '(sngnav.example, contact@sngnav.example)',
      );
      expect(capturedRequest.headers['Accept'], 'application/geo+json');
      c.close();
    });

    test('returns winter alerts only from a mixed FeatureCollection', () async {
      final mock = MockClient(
        (_) async => http.Response(
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
        ),
      );
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
        throwsA(
          isA<NoaaNwsHttpException>().having(
            (e) => e.statusCode,
            'statusCode',
            429,
          ),
        ),
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

  group('isWithinNwsCoverage predicate (0.0.8)', () {
    test('CONUS interior point is covered', () {
      expect(isWithinNwsCoverage(40.0, -100.0), isTrue); // central plains
      expect(isWithinNwsCoverage(47.9253, -97.0329), isTrue); // Grand Forks ND
    });

    test('Alaska interior point is covered', () {
      expect(isWithinNwsCoverage(64.8378, -147.7164), isTrue); // Fairbanks
    });

    test('Hawaii interior point is covered', () {
      expect(isWithinNwsCoverage(21.3069, -157.8583), isTrue); // Honolulu
    });

    test('CONUS box edges are inclusive', () {
      expect(isWithinNwsCoverage(24, -125), isTrue); // SW corner
      expect(isWithinNwsCoverage(50, -66), isTrue); // NE corner
      expect(isWithinNwsCoverage(24, -66), isTrue);
      expect(isWithinNwsCoverage(50, -125), isTrue);
    });

    test('Alaska + Hawaii box edges are inclusive', () {
      expect(isWithinNwsCoverage(51, -170), isTrue); // AK SW corner
      expect(isWithinNwsCoverage(72, -129), isTrue); // AK NE corner
      expect(isWithinNwsCoverage(18, -161), isTrue); // HI SW corner
      expect(isWithinNwsCoverage(23, -154), isTrue); // HI NE corner
    });

    test('points just outside every box are not covered', () {
      expect(isWithinNwsCoverage(23.9, -100.0), isFalse); // just S of CONUS
      expect(isWithinNwsCoverage(50.1, -100.0), isFalse); // just N of CONUS
      expect(isWithinNwsCoverage(40.0, -125.1), isFalse); // just W of CONUS
      expect(isWithinNwsCoverage(40.0, -65.9), isFalse); // just E of CONUS
      expect(isWithinNwsCoverage(72.1, -150.0), isFalse); // just N of Alaska
      expect(isWithinNwsCoverage(17.9, -157.0), isFalse); // just S of Hawaii
    });

    test('US territories are covered (incl. positive-longitude Pacific)', () {
      // Negative-longitude Caribbean territories.
      expect(isWithinNwsCoverage(18.2, -66.5), isTrue); // Puerto Rico (San Juan)
      expect(isWithinNwsCoverage(18.0, -64.8), isTrue); // US Virgin Islands
      // Positive-longitude Pacific territories.
      expect(isWithinNwsCoverage(13.45, 144.79), isTrue); // Guam (Hagåtña)
      expect(isWithinNwsCoverage(15.19, 145.75), isTrue); // Saipan (N. Mariana)
      expect(isWithinNwsCoverage(52.9, 173.2), isTrue); // W. Aleutians (Attu/Adak-west)
      // Southern-hemisphere territory.
      expect(isWithinNwsCoverage(-14.3, -170.7), isTrue); // American Samoa
    });

    test('Japan (Akita) and Tokyo are NOT covered', () {
      expect(isWithinNwsCoverage(39.7167, 140.0983), isFalse); // Akita
      expect(isWithinNwsCoverage(35.6762, 139.6503), isFalse); // Tokyo
    });

    test('no Japanese point slips into the positive-longitude US boxes', () {
      // Japan is not a US territory and must fall in NO box, even though it
      // shares a longitude band with the Guam/Mariana box. The boxes are
      // latitude-disjoint from Japan (Japan ~24–46°N; Guam box caps at 21°N,
      // Aleutian box starts at 51°N), so the shared longitude never matters.
      expect(isWithinNwsCoverage(45.0, 145.0), isFalse); // NE Hokkaido (Nemuro)
      expect(isWithinNwsCoverage(43.06, 141.35), isFalse); // Sapporo
      expect(isWithinNwsCoverage(26.2, 127.7), isFalse); // Naha, Okinawa
      expect(isWithinNwsCoverage(24.45, 122.9), isFalse); // Yonaguni (SW-most)
      expect(isWithinNwsCoverage(40.0, 140.0), isFalse); // CONUS-lat, Japan-lon
    });

    test('non-finite coordinates report out-of-coverage', () {
      expect(isWithinNwsCoverage(double.nan, -100.0), isFalse);
      expect(isWithinNwsCoverage(40.0, double.nan), isFalse);
      expect(isWithinNwsCoverage(double.infinity, -100.0), isFalse);
      expect(isWithinNwsCoverage(40.0, double.negativeInfinity), isFalse);
    });
  });

  group('fetchActiveWinterAlerts out-of-coverage short-circuit (0.0.8)', () {
    test(
      'out-of-coverage point (Akita) returns EMPTY and makes NO HTTP request',
      () async {
        // A recording fake: the ONLY way this handler runs is if the client
        // actually issued a request. We flag it and fail the test if it did.
        var requestIssued = false;
        final mock = MockClient((req) async {
          requestIssued = true;
          // If we ever reach here, mimic the real endpoint's HTTP 400 for a
          // non-US point — which is exactly what we are proving does NOT
          // happen for an out-of-coverage coordinate.
          return http.Response('bad request', 400);
        });
        final c = NoaaNwsClient(
          userAgent: '(sngnav.example, contact@sngnav.example)',
          client: mock,
        );
        final out = await c.fetchActiveWinterAlerts(
          latitude: 39.7167, // Akita, Japan — outside NWS coverage
          longitude: 140.0983,
        );
        expect(out, isEmpty);
        expect(
          requestIssued,
          isFalse,
          reason:
              'an out-of-coverage point must NOT send a request to '
              'api.weather.gov — the coordinate must never leave the process',
        );
        c.close();
      },
    );

    test(
      'in-coverage US point STILL issues the request and STILL throws on 4xx '
      '(real-error surfacing preserved)',
      () async {
        var requestIssued = false;
        final mock = MockClient((req) async {
          requestIssued = true;
          return http.Response('bad request', 400);
        });
        final c = NoaaNwsClient(
          userAgent: '(sngnav.example, contact@sngnav.example)',
          client: mock,
        );
        await expectLater(
          c.fetchActiveWinterAlerts(
            latitude: 47.9253, // Grand Forks ND — in coverage
            longitude: -97.0329,
          ),
          throwsA(
            isA<NoaaNwsHttpException>().having(
              (e) => e.statusCode,
              'statusCode',
              400,
            ),
          ),
        );
        expect(
          requestIssued,
          isTrue,
          reason:
              'an in-coverage point must still issue the request so a genuine '
              'NWS error surfaces (only out-of-coverage is short-circuited)',
        );
        c.close();
      },
    );

    test(
      'in-coverage US point with alerts still returns them (unchanged path)',
      () async {
        var requestIssued = false;
        final mock = MockClient((req) async {
          requestIssued = true;
          return http.Response(
            jsonEncode(<String, dynamic>{
              'type': 'FeatureCollection',
              'features': <Map<String, dynamic>>[
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
          );
        });
        final c = NoaaNwsClient(
          userAgent: '(sngnav.example, contact@sngnav.example)',
          client: mock,
        );
        final out = await c.fetchActiveWinterAlerts(
          latitude: 47.9,
          longitude: -97.0,
        );
        expect(requestIssued, isTrue);
        expect(out, hasLength(1));
        expect(out.first.event, 'Blizzard Warning');
        c.close();
      },
    );
  });

  _retryGroup();

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

void _retryGroup() {
  group('NoaaNwsRetryPolicy', () {
    test('default policy has 3 retries and 1s base delay', () {
      const p = NoaaNwsRetryPolicy();
      expect(p.maxRetries, 3);
      expect(p.baseDelay, const Duration(seconds: 1));
      expect(p.delayForAttempt(0), const Duration(seconds: 1));
      expect(p.delayForAttempt(1), const Duration(seconds: 2));
      expect(p.delayForAttempt(2), const Duration(seconds: 4));
    });

    test('NoaaNwsRetryPolicy.none has zero retries', () {
      expect(NoaaNwsRetryPolicy.none.maxRetries, 0);
    });

    test('isRetryableStatus: 5xx + 408 + 429 retryable; 4xx not', () {
      const p = NoaaNwsRetryPolicy();
      expect(p.isRetryableStatus(500), isTrue);
      expect(p.isRetryableStatus(502), isTrue);
      expect(p.isRetryableStatus(503), isTrue);
      expect(p.isRetryableStatus(504), isTrue);
      expect(p.isRetryableStatus(408), isTrue);
      expect(p.isRetryableStatus(429), isTrue);
      expect(p.isRetryableStatus(400), isFalse);
      expect(p.isRetryableStatus(401), isFalse);
      expect(p.isRetryableStatus(403), isFalse);
      expect(p.isRetryableStatus(404), isFalse);
    });
  });

  group('NoaaNwsClient retry-with-backoff', () {
    Future<void> noWait(Duration _) async {}

    test('retry-success: 503 then 200 yields parsed alerts', () async {
      int callCount = 0;
      final mock = MockClient((req) async {
        callCount += 1;
        if (callCount == 1) {
          return http.Response('upstream busy', 503);
        }
        return http.Response(
          jsonEncode(<String, dynamic>{
            'type': 'FeatureCollection',
            'features': <Map<String, dynamic>>[
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
          headers: {'content-type': 'application/geo+json'},
        );
      });
      final c = NoaaNwsClient(
        userAgent: '(sngnav.example, contact@sngnav.example)',
        client: mock,
        retryPolicy: const NoaaNwsRetryPolicy(),
        sleep: noWait,
      );
      final out = await c.fetchActiveWinterAlerts(
        latitude: 47.9,
        longitude: -97.0,
      );
      expect(callCount, 2);
      expect(out, hasLength(1));
      expect(out.first.event, 'Blizzard Warning');
      c.close();
    });

    test(
      'retry-exhaust: 4 consecutive 503 surfaces last 503 as 503 exception',
      () async {
        int callCount = 0;
        final mock = MockClient((req) async {
          callCount += 1;
          return http.Response('upstream still busy', 503);
        });
        final c = NoaaNwsClient(
          userAgent: '(sngnav.example, contact@sngnav.example)',
          client: mock,
          retryPolicy: const NoaaNwsRetryPolicy(),
          sleep: noWait,
        );
        await expectLater(
          c.fetchActiveWinterAlerts(latitude: 47.9, longitude: -97.0),
          throwsA(
            isA<NoaaNwsHttpException>().having(
              (e) => e.statusCode,
              'statusCode',
              503,
            ),
          ),
        );
        // 1 initial + 3 retries = 4 total calls.
        expect(callCount, 4);
        c.close();
      },
    );

    test(
      '4xx-no-retry: a single 404 throws immediately without retries',
      () async {
        int callCount = 0;
        final mock = MockClient((req) async {
          callCount += 1;
          return http.Response('not found', 404);
        });
        final c = NoaaNwsClient(
          userAgent: '(sngnav.example, contact@sngnav.example)',
          client: mock,
          retryPolicy: const NoaaNwsRetryPolicy(),
          sleep: noWait,
        );
        await expectLater(
          c.fetchActiveWinterAlerts(latitude: 47.9, longitude: -97.0),
          throwsA(
            isA<NoaaNwsHttpException>().having(
              (e) => e.statusCode,
              'statusCode',
              404,
            ),
          ),
        );
        expect(callCount, 1, reason: '4xx must not retry');
        c.close();
      },
    );

    test('retry-on-429: 429 then 200 yields a result with 2 calls', () async {
      int callCount = 0;
      final mock = MockClient((req) async {
        callCount += 1;
        if (callCount == 1) {
          return http.Response('rate limited', 429);
        }
        return http.Response(
          jsonEncode(<String, dynamic>{
            'type': 'FeatureCollection',
            'features': <Map<String, dynamic>>[],
          }),
          200,
        );
      });
      final c = NoaaNwsClient(
        userAgent: '(sngnav.example, contact@sngnav.example)',
        client: mock,
        retryPolicy: const NoaaNwsRetryPolicy(),
        sleep: noWait,
      );
      final out = await c.fetchActiveWinterAlerts(
        latitude: 47.9,
        longitude: -97.0,
      );
      expect(callCount, 2);
      expect(out, isEmpty);
      c.close();
    });

    test(
      'retry exponential delays: observed sleep durations are 1s, 2s, 4s',
      () async {
        final mock = MockClient((req) async {
          return http.Response('still busy', 503);
        });
        final observedSleeps = <Duration>[];
        Future<void> recordingSleep(Duration d) async {
          observedSleeps.add(d);
        }

        final c = NoaaNwsClient(
          userAgent: '(sngnav.example, contact@sngnav.example)',
          client: mock,
          retryPolicy: const NoaaNwsRetryPolicy(),
          sleep: recordingSleep,
        );
        await expectLater(
          c.fetchActiveWinterAlerts(latitude: 47.9, longitude: -97.0),
          throwsA(isA<NoaaNwsHttpException>()),
        );
        expect(observedSleeps, <Duration>[
          const Duration(seconds: 1),
          const Duration(seconds: 2),
          const Duration(seconds: 4),
        ]);
        c.close();
      },
    );

    test(
      'default retryPolicy is none: 503 throws after 1 call (back-compat)',
      () async {
        int callCount = 0;
        final mock = MockClient((req) async {
          callCount += 1;
          return http.Response('upstream busy', 503);
        });
        final c = NoaaNwsClient(
          userAgent: '(sngnav.example, contact@sngnav.example)',
          client: mock,
          sleep: noWait,
        );
        await expectLater(
          c.fetchActiveWinterAlerts(latitude: 47.9, longitude: -97.0),
          throwsA(isA<NoaaNwsHttpException>()),
        );
        expect(callCount, 1, reason: '0.0.1 back-compat: no retry by default');
        c.close();
      },
    );
  });

  group('WinterAlert typed area (0.0.3)', () {
    test('parseArea returns polygon vertices from a Polygon geometry', () {
      final geometry = <String, dynamic>{
        'type': 'Polygon',
        'coordinates': <dynamic>[
          <dynamic>[
            <double>[-97.5, 47.9],
            <double>[-97.0, 47.9],
            <double>[-97.0, 48.2],
            <double>[-97.5, 48.2],
            <double>[-97.5, 47.9],
          ],
        ],
      };
      final area = WinterAlert.parseArea(geometry, null);
      expect(area, isNotNull);
      expect(area!.polygon, hasLength(5));
      expect(area.polygon.first.latitude, equals(47.9));
      expect(area.polygon.first.longitude, equals(-97.5));
      expect(area.circle, isNull);
    });

    test('parseArea returns circle from CAP-style parameters.circle', () {
      final parameters = <String, dynamic>{
        'circle': <String>['38.5,-97.0 25'],
      };
      final area = WinterAlert.parseArea(null, parameters);
      expect(area, isNotNull);
      expect(area!.polygon, isEmpty);
      expect(area.circle, isNotNull);
      expect(area.circle!.center.latitude, equals(38.5));
      expect(area.circle!.center.longitude, equals(-97.0));
      expect(area.circle!.radiusKm, equals(25.0));
    });

    test('parseArea returns null when no geometry and no parameters', () {
      final area = WinterAlert.parseArea(null, null);
      expect(area, isNull);
    });

    test('parseArea takes first polygon of MultiPolygon', () {
      final geometry = <String, dynamic>{
        'type': 'MultiPolygon',
        'coordinates': <dynamic>[
          <dynamic>[
            <dynamic>[
              <double>[1.0, 2.0],
              <double>[3.0, 4.0],
              <double>[5.0, 6.0],
              <double>[1.0, 2.0],
            ],
          ],
          <dynamic>[
            <dynamic>[
              <double>[10.0, 20.0],
              <double>[30.0, 40.0],
              <double>[50.0, 60.0],
              <double>[10.0, 20.0],
            ],
          ],
        ],
      };
      final area = WinterAlert.parseArea(geometry, null);
      expect(area, isNotNull);
      expect(area!.polygon, hasLength(4));
      expect(area.polygon.first.latitude, equals(2.0));
      expect(area.polygon.first.longitude, equals(1.0));
    });

    test('parseArea skips malformed vertices in a polygon ring', () {
      final geometry = <String, dynamic>{
        'type': 'Polygon',
        'coordinates': <dynamic>[
          <dynamic>[
            <dynamic>[1.0, 2.0],
            <dynamic>['not', 'numeric'],
            <dynamic>[3.0],
            <dynamic>[5.0, 6.0],
            <dynamic>[1.0, 2.0],
          ],
        ],
      };
      final area = WinterAlert.parseArea(geometry, null);
      expect(area, isNotNull);
      // The two clearly-valid vertices (1.0/2.0 and 5.0/6.0) plus the
      // closing 1.0/2.0 must come through; malformed entries skip.
      expect(area!.polygon.length, greaterThanOrEqualTo(3));
    });

    test('parseArea rejects negative radius circle', () {
      final parameters = <String, dynamic>{
        'circle': <String>['38.5,-97.0 -1'],
      };
      final area = WinterAlert.parseArea(null, parameters);
      expect(area, isNull);
    });
  });
}
