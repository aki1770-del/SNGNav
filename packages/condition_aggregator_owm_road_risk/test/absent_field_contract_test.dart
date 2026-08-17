/// The absent-field contract for this adapter.
///
/// A publisher can be silent in four distinguishable ways, and this adapter's
/// job at the mapping seam is to make sure they arrive at the consumer as four
/// things rather than one:
///
///   (a) measured emptiness — the publisher answered; nothing is active here.
///   (b) field absence      — a good record, but the field we need is missing.
///   (c) read failure       — we could not reach or could not read the answer.
///   (d) declared coverage gap — the publisher told us it does not cover this.
///
/// State (d) has no vocabulary in this publisher's response shape: the road-risk
/// endpoint has no way to say "not covered here". That is recorded as an honest
/// bound in the README rather than simulated, and there is no test for it,
/// because a test asserting a distinction the wire cannot carry would assert a
/// fiction.
///
/// The rule the rest of this file exists to hold: **an unmeasured field may not
/// buy a downgrade.** "We do not know" and "it is fine" are different sentences,
/// and only one of them is safe to tell a driver.
library;

import 'package:condition_aggregator/condition_aggregator.dart';
import 'package:condition_aggregator_owm_road_risk/condition_aggregator_owm_road_risk.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

/// A provider wired to a mock that returns [body] with HTTP 200.
OwmRoadRiskProvider providerReturning(String body) =>
    OwmRoadRiskProvider(client: clientReturning(body));

OwmRoadRiskClient clientReturning(String body) => OwmRoadRiskClient(
  apiKey: 'test-key',
  httpClient: MockClient((_) async => http.Response(body, 200)),
);

/// One well-formed alert with a stated level, for the "nothing is wrong"
/// baseline the other cases are contrasted against.
const String kGoodAlert =
    '{"event":"Black ice","event_level":3,'
    '"sender_name":"NWS Buffalo","description":"Black ice on US-219."}';

void main() {
  group(
    '(a) measured emptiness — the publisher answered, nothing is active',
    () {
      test(
        'an empty alerts array is a complete read, not a partial one',
        () async {
          final read = await clientReturning(
            '[{"alerts":[]}]',
          ).fetchPointRead(latitude: 42.886, longitude: -78.879);
          expect(read.alerts, isEmpty);
          expect(
            read.isComplete,
            isTrue,
            reason:
                'an empty answer that was fully read is a measurement, and '
                'must not be reported as an incomplete read',
          );
          expect(read.unreadableEntries, 0);
        },
      );

      test(
        'a track entry with no alerts key at all is still a complete read',
        () async {
          final read = await clientReturning(
            '[{}]',
          ).fetchPointRead(latitude: 42.886, longitude: -78.879);
          expect(read.alerts, isEmpty);
          expect(read.isComplete, isTrue);
        },
      );

      test(
        'a fully-read empty answer produces no advisories and no notice',
        () async {
          final advisories = await providerReturning(
            '[{"alerts":[]}]',
          ).fetchActiveAdvisoriesAtPoint(latitude: 42.886, longitude: -78.879);
          expect(
            advisories,
            isEmpty,
            reason: 'appending a notice to a complete read would cry wolf',
          );
        },
      );
    },
  );

  group('(b) field absence — the record is good but the level is missing', () {
    test('an absent event_level is carried as absent, not as a level', () {
      final alert = OwmRoadRiskAlert.fromJson(const <String, dynamic>{
        'event': 'Black ice',
        'sender_name': 'NWS Buffalo',
        'description': 'Black ice on US-219.',
      });
      expect(alert.eventLevelWasReported, isFalse);
      expect(
        alert.reportedEventLevel,
        isNull,
        reason: 'null is off the scale; 0 is the bottom of it',
      );
    });

    test('an absent level and a stated level 0 are not the same value', () {
      final absent = OwmRoadRiskAlert.fromJson(const <String, dynamic>{
        'event': 'Black ice',
        'sender_name': 'X',
        'description': 'd',
      });
      final statedZero = OwmRoadRiskAlert.fromJson(const <String, dynamic>{
        'event': 'Black ice',
        'event_level': 0,
        'sender_name': 'X',
        'description': 'd',
      });
      expect(
        absent,
        isNot(equals(statedZero)),
        reason:
            'before 0.1.5 these compared equal, so a caller reading the '
            'alert directly could not tell an unstated level from a stated '
            'zero — the two absences had collapsed into one value',
      );
      expect(absent.reportedEventLevel, isNull);
      expect(statedZero.reportedEventLevel, 0);
    });

    test(
      'the alert itself survives an absent level — only the level is lost',
      () {
        final alert = OwmRoadRiskAlert.fromJson(const <String, dynamic>{
          'event': 'Black ice',
          'sender_name': 'NWS Buffalo',
          'description': 'Black ice on US-219.',
        });
        expect(alert.event, 'Black ice');
        expect(alert.senderName, 'NWS Buffalo');
        expect(alert.description, 'Black ice on US-219.');
      },
    );

    test('an unstated level does not count as an unreadable entry', () async {
      final read = await clientReturning(
        '[{"alerts":[{"event":"Black ice","sender_name":"X",'
        '"description":"d"}]}]',
      ).fetchPointRead(latitude: 42.886, longitude: -78.879);
      expect(read.alerts, hasLength(1));
      expect(
        read.isComplete,
        isTrue,
        reason:
            'the entry was read; it was the field that was absent, and '
            'that absence is carried on the alert, not on the read',
      );
    });
  });

  group('an unmeasured field may not buy a downgrade', () {
    test('an unstated level maps to unknown, never to a low severity', () {
      final alert = OwmRoadRiskAlert.fromJson(const <String, dynamic>{
        'event': 'Black ice',
        'sender_name': 'X',
        'description': 'd',
      });
      final severity = OwmRoadRiskMapper.severityFromAlert(alert);
      expect(severity, AdvisorySeverity.unknown);
      expect(
        severity,
        isNot(AdvisorySeverity.minor),
        reason: 'minor is a measurement of mildness; we took no measurement',
      );
    });

    test('through the provider, an unstated level reaches the consumer as '
        'unknown', () async {
      final advisories = await providerReturning(
        '[{"alerts":[{"event":"Black ice","sender_name":"NWS",'
        '"description":"Black ice on US-219."}]}]',
      ).fetchActiveAdvisoriesAtPoint(latitude: 42.886, longitude: -78.879);
      expect(advisories, hasLength(1));
      expect(advisories.single.severity, AdvisorySeverity.unknown);
      expect(advisories.single.eventClass, 'Black ice');
    });

    test('it is the absence that governs the severity, not the residual '
        'number', () {
      // Without this case the absence-handling in severityFromAlert is not
      // load-bearing: an unstated level leaves `eventLevel` reading 0, and
      // severityFromEventLevel maps 0 to unknown too, so the two rules agree
      // and deleting the absence check changes nothing observable. They only
      // disagree here — an alert whose level was never stated but whose
      // residual number is not 0. Found by mutation: removing the absence
      // check was silent to every other test in this file.
      const unstatedButNonZero = OwmRoadRiskAlert(
        event: 'Black ice',
        eventLevel: 3,
        eventLevelWasReported: false,
        senderName: 'X',
        description: 'd',
      );
      expect(
        OwmRoadRiskMapper.severityFromAlert(unstatedButNonZero),
        AdvisorySeverity.unknown,
        reason:
            'the publisher stated no level, so there is no severity to '
            'report — whatever number happens to sit in the field',
      );
      expect(unstatedButNonZero.reportedEventLevel, isNull);
    });

    test('a stated level still governs, so the absence check has not simply '
        'disabled the mapping', () {
      const stated = OwmRoadRiskAlert(
        event: 'Black ice',
        eventLevel: 3,
        senderName: 'X',
        description: 'd',
      );
      expect(
        OwmRoadRiskMapper.severityFromAlert(stated),
        AdvisorySeverity.severe,
      );
    });

    test('an unknown severity is not ranked below minor by the umbrella', () {
      // The umbrella tests driver-actionability by member equality, not by
      // ordinal, so `unknown` (ordinal 0) is not silently sorted beneath
      // `minor` (ordinal 1) on the way to a driver.
      const unknown = Advisory(
        source: AdvisorySource.other,
        eventClass: 'Black ice',
        severity: AdvisorySeverity.unknown,
        certainty: AdvisoryCertainty.likely,
        urgency: AdvisoryUrgency.expected,
        areaDescription: 'a',
        effective: null,
        expires: null,
        headline: 'h',
        description: 'd',
      );
      expect(unknown.isHighImpact, isFalse);
    });

    test(
      'every uncoercible level shape is treated as unstated, not as zero',
      () {
        for (final raw in <Object?>[
          '3', // a string
          3.5, // fractional: not a level on an integer scale
          double.nan,
          double.infinity,
          <String, dynamic>{'value': 3},
          <int>[3],
          true,
        ]) {
          final alert = OwmRoadRiskAlert.fromJson(<String, dynamic>{
            'event': 'Heavy snow',
            'event_level': raw,
            'sender_name': 'X',
            'description': 'd',
          });
          expect(
            alert.reportedEventLevel,
            isNull,
            reason: 'event_level $raw must not be coerced into a level',
          );
          expect(
            OwmRoadRiskMapper.severityFromAlert(alert),
            AdvisorySeverity.unknown,
            reason: 'event_level $raw must not resolve to a severity rung',
          );
        }
      },
    );

    test(
      'a whole-valued JSON number is the same integer, and is read as one',
      () {
        final alert = OwmRoadRiskAlert.fromJson(const <String, dynamic>{
          'event': 'Heavy snow',
          'event_level': 3.0,
          'sender_name': 'X',
          'description': 'd',
        });
        expect(
          alert.reportedEventLevel,
          3,
          reason:
              '3.0 is exactly 3; refusing it would discard a real '
              'measurement, which is the mirror of inventing one',
        );
        expect(
          OwmRoadRiskMapper.severityFromAlert(alert),
          AdvisorySeverity.severe,
        );
      },
    );
  });

  group('(c) read failure must never arrive as measured emptiness', () {
    test(
      'a sole unreadable alert entry throws instead of reporting all-clear',
      () async {
        final client = clientReturning('[{"alerts":["Black ice on US-219"]}]');
        await expectLater(
          client.fetchPointRead(latitude: 42.886, longitude: -78.879),
          throwsA(isA<OwmRoadRiskParseException>()),
          reason:
              'returning [] here would assert that the publisher reported '
              'no road risk — a measurement this adapter never took',
        );
      },
    );

    test(
      'an unreadable alerts container throws instead of reporting all-clear',
      () async {
        await expectLater(
          clientReturning(
            '[{"alerts":{"event":"Black ice"}}]',
          ).fetchPointRead(latitude: 42.886, longitude: -78.879),
          throwsA(isA<OwmRoadRiskParseException>()),
        );
      },
    );

    test(
      'an unreadable track entry throws instead of reporting all-clear',
      () async {
        await expectLater(
          clientReturning(
            '["unexpected"]',
          ).fetchPointRead(latitude: 42.886, longitude: -78.879),
          throwsA(isA<OwmRoadRiskParseException>()),
        );
      },
    );

    test('the throw also protects the plain fetchTrack surface', () async {
      await expectLater(
        clientReturning(
          '[{"alerts":["garbage"]}]',
        ).fetchPoint(latitude: 42.886, longitude: -78.879),
        throwsA(isA<OwmRoadRiskParseException>()),
      );
    });

    test('the throw reaches the AdvisoryProvider surface', () async {
      await expectLater(
        providerReturning(
          '[{"alerts":["garbage"]}]',
        ).fetchActiveAdvisoriesAtPoint(latitude: 42.886, longitude: -78.879),
        throwsA(isA<OwmRoadRiskParseException>()),
      );
    });

    test('an alert object that cannot be read is a read failure, not a '
        'missing hazard', () async {
      // `event` is a number, so the record cannot be turned into an alert at
      // all. That is state (c) for this entry, not state (b).
      await expectLater(
        clientReturning(
          '[{"alerts":[{"event":7,"event_level":3}]}]',
        ).fetchPointRead(latitude: 42.886, longitude: -78.879),
        throwsA(isA<OwmRoadRiskParseException>()),
      );
    });
  });

  group('(c) partial read is surfaced, never presented as complete', () {
    test('good alerts survive and the read is marked incomplete', () async {
      final read = await clientReturning(
        '[{"alerts":[$kGoodAlert,"garbage"]}]',
      ).fetchPointRead(latitude: 42.886, longitude: -78.879);
      expect(read.alerts, hasLength(1));
      expect(read.alerts.single.event, 'Black ice');
      expect(read.isComplete, isFalse);
      expect(read.unreadableEntries, 1);
      expect(read.unreadableCauses, hasLength(1));
    });

    test('the provider appends an incomplete-read notice in band', () async {
      final advisories = await providerReturning(
        '[{"alerts":[$kGoodAlert,"garbage"]}]',
      ).fetchActiveAdvisoriesAtPoint(latitude: 42.886, longitude: -78.879);
      expect(
        advisories,
        hasLength(2),
        reason: 'the real hazard plus the notice that something was unread',
      );
      expect(advisories.first.eventClass, 'Black ice');
      expect(advisories.last.eventClass, kOwmRoadRiskIncompleteReadEventClass);
    });

    test('the notice cannot masquerade as a road-risk event', () async {
      final advisories = await providerReturning(
        '[{"alerts":[$kGoodAlert,"garbage"]}]',
      ).fetchActiveAdvisoriesAtPoint(latitude: 42.886, longitude: -78.879);
      final notice = advisories.last;
      expect(notice.severity, AdvisorySeverity.minor);
      expect(
        notice.isHighImpact,
        isFalse,
        reason:
            'an availability notice must never displace a real hazard in '
            'an integrator that renders only driver-actionable items',
      );
      expect(notice.certainty, AdvisoryCertainty.unknown);
      expect(notice.urgency, AdvisoryUrgency.unknown);
      expect(notice.effective, isNull);
      expect(notice.expires, isNull);
      expect(
        notice.eventClass,
        isNot('Black ice'),
        reason: 'the identity must not collide with a publisher event name',
      );
    });

    test('a complete read appends no notice', () async {
      final advisories = await providerReturning(
        '[{"alerts":[$kGoodAlert]}]',
      ).fetchActiveAdvisoriesAtPoint(latitude: 42.886, longitude: -78.879);
      expect(advisories, hasLength(1));
      expect(
        advisories.single.eventClass,
        'Black ice',
        reason:
            'a notice on a clean read would train the integrator to '
            'ignore notices',
      );
    });
  });

  group('what escapes the adapter is always catchable as an Exception', () {
    // The AdvisoryProvider contract promises an adapter-specific exception
    // (a subtype of Exception) on transport or parse failure. A TypeError is
    // an Error, not an Exception, so `on Exception catch` would not catch it
    // and the failure would cross the seam as a crash.
    const malformedBodies = <String>[
      '[{"alerts":[{"event":"Black ice","event_level":"3",'
          '"sender_name":"X","description":"d"}]}]',
      '[{"alerts":[{"event":"Black ice","event_level":3.5,'
          '"sender_name":"X","description":"d"}]}]',
      '[{"alerts":[{"event":7}]}]',
      '[{"alerts":"not an array"}]',
      '["not an object"]',
      'not json at all',
      '{"alerts":[]}',
    ];

    for (var i = 0; i < malformedBodies.length; i++) {
      test('body #$i never escapes as an Error', () async {
        Object? thrown;
        try {
          await providerReturning(
            malformedBodies[i],
          ).fetchActiveAdvisoriesAtPoint(latitude: 42.886, longitude: -78.879);
        } on Object catch (e) {
          thrown = e;
        }
        if (thrown == null) return; // returning normally is also acceptable
        expect(
          thrown,
          isA<Exception>(),
          reason:
              'the adapter contract promises an Exception subtype; '
              '${thrown.runtimeType} would not be caught by a caller '
              'guarding the declared types',
        );
        expect(thrown, isNot(isA<Error>()));
      });
    }
  });

  group('source compatibility with 0.1.4 callers', () {
    test('a directly-constructed alert still reports a stated level', () {
      const alert = OwmRoadRiskAlert(
        event: 'Heavy snow',
        eventLevel: 2,
        senderName: 'X',
        description: 'd',
      );
      expect(
        alert.eventLevelWasReported,
        isTrue,
        reason: 'a caller who supplied a level did state one',
      );
      expect(alert.reportedEventLevel, 2);
      expect(
        OwmRoadRiskMapper.severityFromAlert(alert),
        AdvisorySeverity.moderate,
      );
    });

    test('severityFromEventLevel keeps its 0.1.4 mapping', () {
      expect(
        OwmRoadRiskMapper.severityFromEventLevel(-1),
        AdvisorySeverity.unknown,
      );
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

    test('a well-formed response is unchanged from 0.1.4', () async {
      final alerts = await clientReturning(
        '[{"alerts":[$kGoodAlert]}]',
      ).fetchPoint(latitude: 42.886, longitude: -78.879);
      expect(alerts, hasLength(1));
      expect(alerts.single.eventLevel, 3);
      expect(alerts.single.reportedEventLevel, 3);
      expect(alerts.single.event, 'Black ice');
    });
  });
}
