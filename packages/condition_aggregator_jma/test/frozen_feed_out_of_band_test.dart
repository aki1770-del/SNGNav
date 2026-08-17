/// 0.3.2 — the frozen-feed backport, and the guard that keeps it out of band.
///
/// Two things are under test and they pull in opposite directions, which is
/// why they are in one file:
///
///   1. The adapter must be able to say **"the document I just read is 80 days
///      old"** — including when that document listed no warnings at all, which
///      is the shape that reads as a clear road.
///
///   2. Saying it must not change **one byte** of the advisory list. A real
///      consumer of this package grades hazard by taking the maximum
///      `Advisory.severity` across the returned list, with no filter on
///      `eventClass`. Append a synthetic "feed is stale" advisory there and a
///      statement about the FEED becomes a positive assertion of small
///      WEATHER — and the empty-list branch flips at the same time. The
///      second group below is that guard, and it is written to fail loudly if
///      anyone later reaches for the in-band shortcut.
///
/// Fixtures are the **real documents**, fetched live 2026-08-16:
///   * `jma_050000_frozen_2026-05-28.json` — Akita, `reportDatetime`
///     2026-05-28T06:11+09:00, 80.3 days old, still serving one in-force
///     雷注意報 (code 14, status 発表). Our own winter instrument recorded that
///     dead thunder advisory as an ACTIVE moderate hazard 355 times — 198 of
///     them while the measured temperature was at or above 25 C, the hottest
///     at 34.9 C.
///   * `jma_150000_frozen_empty.json` — Niigata, 2026-05-26T15:45+09:00,
///     81.9 days old, 発表警報・注意報はなし. The false all-clear: an empty
///     list from a dead document, indistinguishable from a clear sky.
library;

import 'dart:convert';
import 'dart:io';

import 'package:condition_aggregator/condition_aggregator.dart';
import 'package:condition_aggregator_jma/condition_aggregator_jma.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

/// Akita city — interior to the 050000 box, so exactly one prefecture.
const double kAkitaLat = 39.7186;
const double kAkitaLon = 140.1024;

/// Niigata city — interior to the 150000 box.
const double kNiigataLat = 37.9161;
const double kNiigataLon = 139.0364;

String _fixture(String name) =>
    File('test/fixtures/$name').readAsStringSync(encoding: utf8);

/// A clock frozen at a real instant shortly after the fixtures were read, so
/// the ages under test are the ages actually measured on 2026-08-16.
DateTime _asOf() => DateTime.parse('2026-08-16T04:43:00Z');

MockClient _serving(Map<String, String> bodyByPrefecture) {
  return MockClient((req) async {
    for (final e in bodyByPrefecture.entries) {
      if (req.url.path.endsWith('/${e.key}.json')) {
        return http.Response.bytes(
          utf8.encode(e.value),
          200,
          headers: <String, String>{'content-type': 'application/json'},
        );
      }
    }
    return http.Response('not found', 404);
  });
}

Future<JmaAdvisoryProvider> _provider(
  MockClient client, {
  Duration? threshold,
}) async {
  final p = JmaAdvisoryProvider(
    client: client,
    clock: _asOf,
    staleFeedThreshold: threshold ?? kJmaDefaultStaleFeedThreshold,
  );
  await p.init();
  return p;
}

void main() {
  group('the adapter can finally say how old the document is', () {
    test(
      'frozen document WITH a dead warning is reported stale, with its real age',
      () async {
        final p = await _provider(
          _serving({'050000': _fixture('jma_050000_frozen_2026-05-28.json')}),
        );
        final advisories = await p.fetchActiveAdvisoriesAtPoint(
          latitude: kAkitaLat,
          longitude: kAkitaLon,
        );

        // The dead 雷注意報 is still returned — we do not suppress it. A
        // suppression would turn a false alarm into a false all-clear, which
        // is the worse of the two failures.
        expect(advisories, hasLength(1));
        expect(advisories.single.eventClass, contains('雷'));

        final s = p.feedStaleness;
        expect(s, isNotNull, reason: 'an 80-day-old document must be reported');
        expect(s!.source, AdvisorySource.jmaJapan);
        expect(s.documentTime, DateTime.parse('2026-05-28T06:11:00+09:00'));
        expect(s.age!.inDays, 80);
        expect(s.detail, contains('050000'));
        p.close();
      },
    );

    test('frozen document with NO warnings — the false all-clear — is reported '
        'stale, and this is the case 0.3.1 could not express at all', () async {
      final p = await _provider(
        _serving({'150000': _fixture('jma_150000_frozen_empty.json')}),
      );
      final advisories = await p.fetchActiveAdvisoriesAtPoint(
        latitude: kNiigataLat,
        longitude: kNiigataLon,
      );

      // Still empty. We did not manufacture a hazard to carry the news.
      expect(advisories, isEmpty);

      final s = p.feedStaleness;
      expect(
        s,
        isNotNull,
        reason:
            'an empty list from a dead document is the identical value a '
            'clear sky produces; the age is the only thing that separates '
            'them, and it has to survive the empty list',
      );
      expect(s!.age!.inDays, 81);
      expect(s.documentTime, DateTime.parse('2026-05-26T15:45:00+09:00'));
      p.close();
    });

    test('a CURRENT document is not reported stale — no cry-wolf', () async {
      final fresh =
          jsonDecode(_fixture('jma_050000_frozen_2026-05-28.json'))
              as Map<String, dynamic>;
      fresh['reportDatetime'] =
          '2026-08-16T12:00:00+09:00'; // 1.7 h before asOf

      final p = await _provider(_serving({'050000': jsonEncode(fresh)}));
      final advisories = await p.fetchActiveAdvisoriesAtPoint(
        latitude: kAkitaLat,
        longitude: kAkitaLon,
      );
      expect(advisories, hasLength(1));
      expect(p.feedStaleness, isNull);
      p.close();
    });

    test('a FAILED fetch does not report staleness — absence is not staleness, '
        'and the failure already has its own channel', () async {
      final p = await _provider(
        MockClient((req) async => http.Response('gone', 503)),
      );
      await expectLater(
        p.fetchActiveAdvisoriesAtPoint(
          latitude: kAkitaLat,
          longitude: kAkitaLon,
        ),
        throwsA(isA<JmaAdvisoryFetchException>()),
      );
      expect(p.feedStaleness, isNull);
      p.close();
    });

    test(
      'snapshot semantics — a later fresh read clears the stale report',
      () async {
        final frozen = _fixture('jma_050000_frozen_2026-05-28.json');
        final fresh = jsonDecode(frozen) as Map<String, dynamic>;
        fresh['reportDatetime'] = '2026-08-16T12:00:00+09:00';

        var serveFrozen = true;
        final p = await _provider(
          MockClient(
            (req) async => http.Response.bytes(
              utf8.encode(serveFrozen ? frozen : jsonEncode(fresh)),
              200,
            ),
          ),
        );

        await p.fetchActiveAdvisoriesAtPoint(
          latitude: kAkitaLat,
          longitude: kAkitaLon,
        );
        expect(p.feedStaleness, isNotNull);

        serveFrozen = false;
        await p.fetchActiveAdvisoriesAtPoint(
          latitude: kAkitaLat,
          longitude: kAkitaLon,
        );
        expect(
          p.feedStaleness,
          isNull,
          reason: "this query's answer, never the previous query's",
        );
        p.close();
      },
    );

    test(
      'a document with no parseable reportDatetime reports null, and null is '
      'not a claim of freshness',
      () async {
        final noStamp =
            jsonDecode(_fixture('jma_050000_frozen_2026-05-28.json'))
                as Map<String, dynamic>;
        noStamp.remove('reportDatetime');

        final p = await _provider(_serving({'050000': jsonEncode(noStamp)}));
        await p.fetchActiveAdvisoriesAtPoint(
          latitude: kAkitaLat,
          longitude: kAkitaLon,
        );
        expect(p.feedStaleness, isNull);
        expect(jmaFeedReportDatetime(jsonEncode(noStamp)), isNull);
        p.close();
      },
    );
  });

  group("THE GUARD — the advisory list 0.3.2 returns is 0.3.1's, exactly", () {
    // This group is the mechanical form of the objection that shaped this
    // release. It must go RED the moment anyone appends a feed-health entry to
    // the returned list.

    test('a frozen feed adds NO advisory — nothing synthetic, nothing minor, '
        'nothing that a severity-max consumer could read as weather', () async {
      final p = await _provider(
        _serving({'050000': _fixture('jma_050000_frozen_2026-05-28.json')}),
      );
      final advisories = await p.fetchActiveAdvisoriesAtPoint(
        latitude: kAkitaLat,
        longitude: kAkitaLon,
      );

      expect(
        advisories,
        hasLength(1),
        reason: '0.3.1 returned exactly the one dead 雷注意報 here',
      );

      // Reproduce the consumer's grading verbatim: max severity across the
      // list, no eventClass filter. It must be unchanged by the fix.
      AdvisorySeverity? maxSeverity;
      for (final a in advisories) {
        if (maxSeverity == null || a.severity.index > maxSeverity.index) {
          maxSeverity = a.severity;
        }
      }
      expect(
        maxSeverity,
        AdvisorySeverity.moderate,
        reason:
            'the grade a real consumer computes must be the grade it '
            'computed on 0.3.1 — the fix is not allowed to move it',
      );

      expect(
        advisories.where((a) => a.severity == AdvisorySeverity.minor),
        isEmpty,
        reason:
            'minor is not a floor at the consumer that grades this list, it '
            'is a rung on the ladder',
      );
      expect(
        advisories.map((a) => a.eventClass),
        everyElement(isNot(contains('更新'))),
        reason: 'no feed-health text may appear inside the advisory list',
      );
      p.close();
    });

    test(
      'the empty-list branch does not flip — a frozen empty feed still returns '
      'an EMPTY list, so a consumer isEmpty test sees what it saw on 0.3.1',
      () async {
        final p = await _provider(
          _serving({'150000': _fixture('jma_150000_frozen_empty.json')}),
        );
        final advisories = await p.fetchActiveAdvisoriesAtPoint(
          latitude: kNiigataLat,
          longitude: kNiigataLon,
        );
        expect(
          advisories,
          isEmpty,
          reason:
              'a consumer branching on advisories.isEmpty must take the same '
              'branch it took on 0.3.1; the news travels out of band',
        );
        expect(p.feedStaleness, isNotNull);
        p.close();
      },
    );

    test(
      'the exported surface is additive — every symbol 0.3.1 exported is still '
      'exported, so nobody has to rewrite code to accept the fix',
      () {
        // Referencing them IS the assertion: this file would not compile if a
        // 0.3.1 symbol had been removed or renamed.
        expect(kJmaWarningJsonBaseUrl, isNotEmpty);
        expect(kJmaWarningJsonMaxBytes, greaterThan(0));
        expect(kJmaFetchWallClockBudget.inSeconds, greaterThan(0));
        expect(kJmaWarningCodes, isNotEmpty);
        expect(kJmaSnowWarningCodes, isNotEmpty);
        expect(kJmaSnowAdvisoryEventNames, isNotEmpty);
        expect(kJmaPrefectureBoundingBoxes, isNotEmpty);
        expect(kJmaPrefectureNames, isNotEmpty);
        expect(kJmaPrefectureNamesJa, isNotEmpty);
        expect(kJmaIncompleteReadEventClass, isNotEmpty);
        expect(jmaPrefectureName('050000'), 'Akita');
        expect(jmaPrefectureNameJa('050000'), isNotNull);
        expect(
          prefectureCodeForPoint(latitude: kAkitaLat, longitude: kAkitaLon),
          isNotNull,
        );
        expect(
          prefectureCodesForPoint(latitude: kAkitaLat, longitude: kAkitaLon),
          contains('050000'),
        );
        expect(
          parseJmaWarningJson(
            _fixture('jma_050000_frozen_2026-05-28.json'),
            prefectureCode: '050000',
          ),
          hasLength(1),
        );
        expect(
          buildIncompleteReadNotice(const <String>['050000']).severity,
          AdvisorySeverity.minor,
        );
        expect(
          mapJmaWarningToAdvisory(
            parseJmaWarningJson(
              _fixture('jma_050000_frozen_2026-05-28.json'),
              prefectureCode: '050000',
            ).single,
          ).source,
          AdvisorySource.jmaJapan,
        );
      },
    );

    test(
      'expires stays null — we still refuse to write our own inference into a '
      'field a consumer reads as the publisher word',
      () async {
        final p = await _provider(
          _serving({'050000': _fixture('jma_050000_frozen_2026-05-28.json')}),
        );
        final advisories = await p.fetchActiveAdvisoriesAtPoint(
          latitude: kAkitaLat,
          longitude: kAkitaLon,
        );
        expect(advisories.single.expires, isNull);
        p.close();
      },
    );
  });

  group('what the fix actually reaches — the aggregator gate the app reads', () {
    test(
      'AdvisoryAggregateResult.canAssertNoAdvisory is FALSE over a frozen '
      'feed, so an app gating its all-clear on it stops showing one',
      () async {
        final p = await _provider(
          _serving({'150000': _fixture('jma_150000_frozen_empty.json')}),
        );
        final agg = AdvisoryAggregator(providers: <AdvisoryProvider>[p]);
        await agg.init();
        final result = await agg.fetchActiveAdvisoriesAtPoint(
          latitude: kNiigataLat,
          longitude: kNiigataLon,
        );

        expect(result.advisories, isEmpty);
        expect(result.providerErrors, isEmpty, reason: 'nothing failed');
        expect(
          result.canAssertNoAdvisory,
          isFalse,
          reason:
              'every source answered, and one of them answered with a document '
              'nobody has written to since May — that is not a measured calm',
        );
        expect(result.hasStaleSource, isTrue);
        expect(result.staleSources.single.age!.inDays, 81);
        p.close();
      },
    );

    test('and over a CURRENT feed the same gate still opens — the fix does not '
        'jam the all-clear shut', () async {
      final fresh =
          jsonDecode(_fixture('jma_150000_frozen_empty.json'))
              as Map<String, dynamic>;
      fresh['reportDatetime'] = '2026-08-16T12:00:00+09:00';

      final p = await _provider(_serving({'150000': jsonEncode(fresh)}));
      final agg = AdvisoryAggregator(providers: <AdvisoryProvider>[p]);
      await agg.init();
      final result = await agg.fetchActiveAdvisoriesAtPoint(
        latitude: kNiigataLat,
        longitude: kNiigataLon,
      );
      expect(result.advisories, isEmpty);
      expect(result.hasStaleSource, isFalse);
      expect(result.canAssertNoAdvisory, isTrue);
      p.close();
    });
  });
}
