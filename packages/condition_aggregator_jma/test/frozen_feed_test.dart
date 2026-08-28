/// Frozen-feed tests — written RED, against the REAL frozen JMA documents.
///
/// Provenance of the fixtures in `test/fixtures/`: fetched live from
/// `https://www.jma.go.jp/bosai/warning/data/warning/<code>.json` on
/// 2026-08-16 (JST). At fetch time the origin objects carried
/// `last-modified: Wed, 27 May 2026 21:11:58 GMT` behind a `max-age=60`
/// CloudFront object with `age: 4` — i.e. these are the CURRENT objects
/// JMA serves, and JMA has not rewritten them in ~80 days. The sibling
/// `bosai/forecast/` path on the same host was fresh the same second, so
/// this is a frozen warning surface, not an outage and not our cache.
///
/// Why these tests exist (HER-trace, one hop): Akita 050000 still lists
/// 雷注意報 `status=発表` from 2026-05-28, and our own winter instrument
/// served that dead advisory as an ACTIVE hazard 230 times on HER
/// mother's prefecture. Niigata 150000 is the same disease with the
/// opposite sign — an 81-day-old document carrying zero warnings, which
/// renders as a clear road.
///
/// Neither shape is expressible through this package today. That is what
/// these tests fail on.
library;

import 'dart:convert';
import 'dart:io';

import 'package:condition_aggregator/condition_aggregator.dart';
import 'package:condition_aggregator_jma/condition_aggregator_jma.dart';
import 'package:condition_aggregator_jma/src/jma_advisory_provider.dart'
    show mergeDedupedAdvisories;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import 'support/legacy_to_r8.dart';

/// 2026-08-16T00:00+09:00 — the wall clock at which the defect was measured.
final DateTime kMeasuredNow = DateTime.parse('2026-08-16T00:00:00+09:00');

String _fixture(String code) => File(
  'test/fixtures/jma_warning_$code.frozen_2026-05.json',
).readAsStringSync();

http.Response _utf8Response(String body, int status) => http.Response.bytes(
  utf8.encode(toR8IfLegacy(body)),
  status,
  headers: const {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  group(
    'END-TO-END on the real frozen documents, through the real provider',
    () {
      test(
        'RED-0 Niigata: an 81-day-old silence must not reach the integrator as '
        'an empty list (existing API only — this is the defect itself)',
        () async {
          final mock = MockClient(
            (req) async => _utf8Response(_fixture('150000'), 200),
          );
          final provider = JmaAdvisoryProvider(
            warningJsonBaseUrl: 'https://test.fixture/jma/warning/',
            client: mock,
            now: () => kMeasuredNow,
          );
          await provider.init();
          final out = await provider.fetchActiveAdvisoriesAtPoint(
            latitude: 37.893333, // Niigata → 150000
            longitude: 139.018333,
          );
          expect(
            out,
            isNotEmpty,
            reason:
                'the document backing this silence was last written '
                '2026-05-26T15:45+09:00. An empty list here is the value an '
                'integrator reads as a clear road.',
          );
        },
      );

      test('RED-0b Akita: the eternal 雷注意報 must arrive accompanied by the age '
          'of the document it rests on', () async {
        final mock = MockClient(
          (req) async => _utf8Response(_fixture('050000'), 200),
        );
        final provider = JmaAdvisoryProvider(
          warningJsonBaseUrl: 'https://test.fixture/jma/warning/',
          client: mock,
          now: () => kMeasuredNow,
        );
        await provider.init();
        final out = await provider.fetchActiveAdvisoriesAtPoint(
          latitude: 39.716667, // Akita → 050000
          longitude: 140.098333,
        );
        expect(out.map((a) => a.eventClass), contains('雷注意報'));
        // The GUARANTEE is that the dead document is marked in band — not
        // that it is marked with one particular identity. This fixture is 88
        // days old, past `pathRetirementThreshold`, so from 0.7.0 the notice
        // NAMES THE LIKELY CAUSE (path retired) instead of only reporting
        // age. Assert the guarantee via `kJmaFeedHealthEventClasses`, and
        // assert MORE than before: that it is non-hazard severity and carries
        // the age.
        final health = out
            .where((a) => kJmaFeedHealthEventClasses.contains(a.eventClass))
            .toList();
        expect(
          health,
          isNotEmpty,
          reason:
              'served as an ACTIVE hazard 230 times on HER mother\'s '
              'prefecture with nothing marking it dead',
        );
        expect(health.single.severity, AdvisorySeverity.minor);
        expect(health.single.isHighImpact, isFalse);
        expect(health.single.headline, contains('日更新されていません'));
      });
    },
  );

  group('the feed carries its own age, and the age survives an empty list', () {
    test(
      'RED-1 Niigata 150000: an 81-day-old document with ZERO warnings must not '
      'be indistinguishable from a calm day',
      () {
        final body = _fixture('150000');

        // The existing parse is unchanged and still returns nothing —
        // there genuinely are no in-force warnings in this document.
        final records = parseJmaWarningJson(body, prefectureCode: '150000');
        expect(records, isEmpty);

        // ...but the document's own age must still reach the consumer.
        // Today `reportDatetime` is parsed and then DISCARDED whenever the
        // warning list is empty, so this fact is unreachable — the exact
        // hole our winter instrument names in its own hourly output:
        // "a frozen feed with zero warnings is indistinguishable from a
        // calm day."
        final feed = parseJmaFeed(body, prefectureCode: '150000');
        expect(feed.advisories, isEmpty);
        expect(
          feed.reportDateTime,
          DateTime.parse('2026-05-26T15:45:00+09:00'),
          reason:
              'the silence has a timestamp; the consumer must be able to read it',
        );
        expect(feed.ageAt(kMeasuredNow)!.inDays, greaterThanOrEqualTo(80));
        expect(feed.isStaleAt(kMeasuredNow, const Duration(hours: 6)), isTrue);
      },
    );

    test(
      'RED-2 Akita 050000: a 雷注意報 resting on an 80-day-dead document must '
      'carry that fact, without fabricating an expiry JMA never declared',
      () {
        final body = _fixture('050000');
        final feed = parseJmaFeed(body, prefectureCode: '050000');

        // The advisory is really there, and we do not suppress it.
        expect(feed.advisories, isNotEmpty);
        final a = feed.advisories.first;
        expect(a.eventClass, '雷注意報');

        // `expires` stays null. JMA declares no machine-readable expiry and
        // we will not invent one — a fabricated publisher assertion is a
        // worse defect than the one we are fixing.
        expect(a.expires, isNull);

        // The honest fact is the FEED's age, and it must be reachable.
        expect(
          feed.reportDateTime,
          DateTime.parse('2026-05-28T06:11:00+09:00'),
        );
        expect(feed.ageAt(kMeasuredNow)!.inDays, greaterThanOrEqualTo(79));
        expect(feed.isStaleAt(kMeasuredNow, const Duration(hours: 6)), isTrue);
      },
    );

    test('RED-3 Yamagata 060000: the border feed carries its own distinct age '
        '(feeds do not freeze in lockstep)', () {
      final feed = parseJmaFeed(_fixture('060000'), prefectureCode: '060000');
      expect(
        feed.reportDateTime,
        DateTime.parse('2026-05-28T09:48:00+09:00'),
        reason:
            'Yamagata froze 3h37m after Akita — a single unit-wide '
            '"the feeds froze at T" claim is false',
      );
      expect(feed.advisories, isNotEmpty);
    });
  });

  group(
    'stale-feed notice — the in-band signal, mirroring buildIncompleteReadNotice',
    () {
      test(
        'RED-4 a stale-feed notice names the prefecture and the measured age',
        () {
          final notice = buildStaleFeedNotice(
            prefectureCodes: const <String>['150000'],
            age: const Duration(days: 81),
          );
          expect(notice.eventClass, kJmaStaleFeedEventClass);
          expect(notice.source, AdvisorySource.jmaJapan);
          // It is not a weather event, so it must never be gradeable as one.
          expect(notice.severity, AdvisorySeverity.minor);
          expect(notice.isHighImpact, isFalse);
          expect(notice.headline, contains('新潟県'));
          expect(notice.headline, contains('81'));
        },
      );

      test('RED-5 the stale-feed event class carries no 警報/注意報 suffix, so the '
          'severity-by-suffix mapping can never grade it as a hazard', () {
        expect(kJmaStaleFeedEventClass, isNot(endsWith('警報')));
        expect(kJmaStaleFeedEventClass, isNot(endsWith('注意報')));
        expect(
          kJmaStaleFeedEventClass,
          isNot(equals(kJmaIncompleteReadEventClass)),
        );
      });

      test(
        'RED-6 the notice survives dedup alongside a real same-area warning',
        () {
          final feed = parseJmaFeed(
            _fixture('050000'),
            prefectureCode: '050000',
          );
          final notice = buildStaleFeedNotice(
            prefectureCodes: const <String>['050000'],
            age: const Duration(days: 80),
          );
          final merged = mergeDedupedAdvisories(<Advisory>[
            ...feed.advisories,
            notice,
          ]);
          expect(merged.length, feed.advisories.length + 1);
          expect(
            merged.where((a) => a.eventClass == kJmaStaleFeedEventClass),
            hasLength(1),
          );
        },
      );
    },
  );
}
