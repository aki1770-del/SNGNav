/// Tests for condition_aggregator_owm_road_risk.
///
/// Live HTTP is mocked end-to-end via `MockClient` so CI does not burn
/// publisher quota. The fixture below mirrors the publisher's documented
/// response shape — a top-level array with one entry per track waypoint,
/// each entry carrying an `alerts[]` array.
library;

import 'dart:convert';

import 'package:condition_aggregator/condition_aggregator.dart';
import 'package:condition_aggregator_owm_road_risk/condition_aggregator_owm_road_risk.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  group('OwmRoadRiskClient', () {
    test('rejects empty apiKey at construction time', () {
      expect(
        () => OwmRoadRiskClient(apiKey: ''),
        throwsA(isA<AssertionError>()),
      );
    });

    test('rejects empty track on fetchTrack', () async {
      final client = OwmRoadRiskClient(
        apiKey: 'test-key',
        httpClient: MockClient((_) async => http.Response('[]', 200)),
      );
      expect(
        () => client.fetchTrack(<OwmRoadRiskWaypoint>[]),
        throwsA(isA<ArgumentError>()),
      );
      client.close();
    });

    test('parses alerts from a typical publisher response', () async {
      const goldenBody = '''[
        {
          "alerts": [
            {
              "event": "Heavy snow",
              "event_level": 2,
              "sender_name": "NWS Buffalo NY",
              "description": "Heavy snow expected. Travel could be very difficult."
            },
            {
              "event": "Black ice",
              "event_level": 3,
              "sender_name": "NWS Buffalo NY",
              "description": "Black ice possible on bridges and overpasses overnight."
            }
          ]
        }
      ]''';

      final client = OwmRoadRiskClient(
        apiKey: 'test-key',
        httpClient: MockClient((req) async {
          expect(req.method, 'POST');
          expect(req.url.path, '/data/2.5/roadrisk');
          expect(req.url.queryParameters['appid'], 'test-key');
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          expect(body['track'], isA<List<dynamic>>());
          return http.Response(
            goldenBody,
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final alerts = await client.fetchPoint(
        latitude: 42.886,
        longitude: -78.879,
      );
      expect(alerts, hasLength(2));
      expect(alerts[0].event, 'Heavy snow');
      expect(alerts[0].eventLevel, 2);
      expect(alerts[1].event, 'Black ice');
      expect(alerts[1].eventLevel, 3);
      client.close();
    });

    test('throws OwmRoadRiskHttpException on 401', () async {
      final client = OwmRoadRiskClient(
        apiKey: 'bad-key',
        httpClient: MockClient(
          (_) async =>
              http.Response('{"cod":401,"message":"Invalid API key"}', 401),
        ),
      );
      await expectLater(
        client.fetchPoint(latitude: 0.0, longitude: 0.0),
        throwsA(
          isA<OwmRoadRiskHttpException>().having(
            (e) => e.statusCode,
            'statusCode',
            401,
          ),
        ),
      );
      client.close();
    });

    test('throws OwmRoadRiskParseException on non-JSON body', () async {
      final client = OwmRoadRiskClient(
        apiKey: 'test-key',
        httpClient: MockClient(
          (_) async => http.Response('<html>oops</html>', 200),
        ),
      );
      await expectLater(
        client.fetchPoint(latitude: 0.0, longitude: 0.0),
        throwsA(isA<OwmRoadRiskParseException>()),
      );
      client.close();
    });
  });

  group('OwmRoadRiskMapper', () {
    test('severityFromEventLevel maps caution-add-only', () {
      expect(
        OwmRoadRiskMapper.severityFromEventLevel(0),
        AdvisorySeverity.unknown,
      );
      expect(
        OwmRoadRiskMapper.severityFromEventLevel(1),
        AdvisorySeverity.minor,
      );
      expect(
        OwmRoadRiskMapper.severityFromEventLevel(2),
        AdvisorySeverity.moderate,
      );
      expect(
        OwmRoadRiskMapper.severityFromEventLevel(3),
        AdvisorySeverity.severe,
      );
      expect(
        OwmRoadRiskMapper.severityFromEventLevel(4),
        AdvisorySeverity.extreme,
      );
    });

    test('toAdvisory preserves publisher event and description', () {
      const alert = OwmRoadRiskAlert(
        event: 'Heavy snow',
        eventLevel: 2,
        senderName: 'NWS Buffalo NY',
        description: 'Heavy snow expected.',
      );
      final advisory = OwmRoadRiskMapper.toAdvisory(
        alert: alert,
        latitude: 42.886,
        longitude: -78.879,
      );
      expect(advisory.eventClass, 'Heavy snow');
      expect(advisory.severity, AdvisorySeverity.moderate);
      expect(advisory.description, 'Heavy snow expected.');
      expect(advisory.areaDescription, contains('NWS Buffalo NY'));
      expect(advisory.areaDescription, contains('42.8860'));
      expect(advisory.source, AdvisorySource.other);
    });
  });

  group('OwmRoadRiskProvider', () {
    test('fetchActiveAdvisoriesAtPoint maps alerts to Advisories', () async {
      const goldenBody = '''[
        {
          "alerts": [
            {
              "event": "Heavy snow",
              "event_level": 2,
              "sender_name": "NWS Buffalo NY",
              "description": "Heavy snow expected."
            }
          ]
        }
      ]''';

      final provider = OwmRoadRiskProvider.withApiKey(
        apiKey: 'test-key',
        httpClient: MockClient((_) async => http.Response(goldenBody, 200)),
      );
      await provider.init();
      final advisories = await provider.fetchActiveAdvisoriesAtPoint(
        latitude: 42.886,
        longitude: -78.879,
      );
      expect(advisories, hasLength(1));
      expect(advisories.first.eventClass, 'Heavy snow');
      expect(advisories.first.severity, AdvisorySeverity.moderate);
      provider.close();
    });

    test('init is idempotent', () async {
      final provider = OwmRoadRiskProvider.withApiKey(
        apiKey: 'test-key',
        httpClient: MockClient((_) async => http.Response('[]', 200)),
      );
      await provider.init();
      await provider.init();
      provider.close();
    });
  });
}
