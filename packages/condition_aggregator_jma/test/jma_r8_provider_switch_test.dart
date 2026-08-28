import 'dart:convert';
import 'dart:io';

import 'package:condition_aggregator/condition_aggregator.dart';
import 'package:condition_aggregator_jma/condition_aggregator_jma.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

const _r8Akita = 'test/fixtures/jma_warning_r8_050000.frozen_2026-08-23.json';
const _offices = 'test/fixtures/jma_area_offices.frozen_2026-08-24.json';
String _read(String p) => File(p).readAsStringSync();

/// Akita city — HER mother's prefecture.
const _akitaLat = 39.7186;
const _akitaLon = 140.1024;

void main() {
  group('the catalogue must contain only REAL JMA office codes', () {
    test('NEGATIVE CONTROL — every catalogued prefecture code must appear in '
        "JMA's own area master. `010000` does not exist there: Hokkaido is "
        'eight offices, and every Hokkaido point resolves to a code that '
        '404s on both the retired and the live path.', () {
      final master = json.decode(_read(_offices)) as Map<String, dynamic>;
      final offices = (master['offices'] as Map<String, dynamic>).keys.toSet();
      final unknown = kJmaPrefectureBoundingBoxes.keys
          .where((c) => !offices.contains(c))
          .toList();
      expect(
        unknown,
        isEmpty,
        reason: 'catalogued codes absent from JMA area master: $unknown',
      );
    });

    test('every catalogued code carries both an en and a ja label', () {
      for (final c in kJmaPrefectureBoundingBoxes.keys) {
        expect(jmaPrefectureName(c), isNotNull, reason: c);
        expect(jmaPrefectureNameJa(c), isNotNull, reason: c);
      }
    });

    test('NEGATIVE CONTROL — real Hokkaido cities must resolve to a real '
        'office. Sapporo is the largest city in the snowiest prefecture in '
        'Japan.', () {
      final master = json.decode(_read(_offices)) as Map<String, dynamic>;
      final offices = (master['offices'] as Map<String, dynamic>).keys.toSet();
      const cities = <String, List<double>>{
        'Sapporo': [43.0621, 141.3544],
        'Asahikawa': [43.7706, 142.3650],
        'Wakkanai': [45.4156, 141.6730],
        'Kushiro': [42.9849, 144.3820],
        'Hakodate': [41.7687, 140.7288],
        'Obihiro': [42.9236, 143.1963],
        'Abashiri': [44.0206, 144.2735],
        'Tomakomai': [42.6341, 141.6055],
      };
      for (final e in cities.entries) {
        final codes = prefectureCodesForPoint(
          latitude: e.value[0],
          longitude: e.value[1],
        );
        expect(codes, isNotEmpty, reason: '${e.key} resolved to nothing');
        for (final c in codes) {
          expect(
            offices.contains(c),
            isTrue,
            reason: '${e.key} resolved to non-existent office $c',
          );
        }
      }
    });
  });

  group('the provider reads the LIVE path', () {
    test('NEGATIVE CONTROL — the default base URL must be the r8 path. The '
        'retired path answers 200 with a well-formed document frozen at '
        '2026-05-28 and will do so forever.', () {
      expect(kJmaWarningJsonBaseUrl, contains('/r8/'));
    });

    test('a real r8 document is fetched, parsed and surfaced', () async {
      late Uri seen;
      final mock = MockClient((req) async {
        seen = req.url;
        return http.Response(
          _read(_r8Akita),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final p = JmaAdvisoryProvider(
        userAgent: '(test)',
        client: mock,
        now: () => DateTime.parse('2026-08-24T01:00:00+09:00'),
      );
      await p.init();
      final out = await p.fetchActiveAdvisoriesAtPoint(
        latitude: _akitaLat,
        longitude: _akitaLon,
      );
      expect(seen.toString(), contains('/r8/050000.json'));
      expect(
        out.any((a) => a.eventClass == '濃霧注意報'),
        isTrue,
        reason: 'the advisory in force in Akita must reach the caller',
      );
    });
  });

  group('the stale loom SURVIVES the switch and covers the NEW path', () {
    test('a live r8 read injects NO stale notice', () async {
      final mock = MockClient(
        (_) async => http.Response(
          _read(_r8Akita),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );
      final p = JmaAdvisoryProvider(
        userAgent: '(test)',
        client: mock,
        now: () => DateTime.parse('2026-08-24T01:00:00+09:00'),
      );
      await p.init();
      final out = await p.fetchActiveAdvisoriesAtPoint(
        latitude: _akitaLat,
        longitude: _akitaLon,
      );
      expect(out.any((a) => a.eventClass == kJmaStaleFeedEventClass), isFalse);
      expect(
        out.any((a) => a.eventClass == kJmaPathRetirementEventClass),
        isFalse,
      );
    });

    test(
      'an ordinary quiet gap still produces the ORDINARY stale notice',
      () async {
        final mock = MockClient(
          (_) async => http.Response(
            _read(_r8Akita),
            200,
            headers: {'content-type': 'application/json'},
          ),
        );
        final p = JmaAdvisoryProvider(
          userAgent: '(test)',
          client: mock,
          // 20 hours after the fixture's newest document: stale, not retired.
          now: () => DateTime.parse('2026-08-24T19:51:00+09:00'),
        );
        await p.init();
        final out = await p.fetchActiveAdvisoriesAtPoint(
          latitude: _akitaLat,
          longitude: _akitaLon,
        );
        expect(out.any((a) => a.eventClass == kJmaStaleFeedEventClass), isTrue);
        expect(
          out.any((a) => a.eventClass == kJmaPathRetirementEventClass),
          isFalse,
          reason: 'a quiet day must NOT be diagnosed as a retired path',
        );
      },
    );
  });

  group('the loom that would have caught the migration', () {
    test('NEGATIVE CONTROL — at 88 days the notice must say the PATH MAY BE '
        'RETIRED, not merely that data is old. Measured fact: the 0.5.0 '
        'stale notice DID fire for 87 days and nothing moved, because '
        '「更新されていません」reads as a publisher having a quiet spell. The '
        'gap was the DIAGNOSIS, not the alarm.', () async {
      final mock = MockClient(
        (_) async => http.Response(
          _read(_r8Akita),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );
      final p = JmaAdvisoryProvider(
        userAgent: '(test)',
        client: mock,
        now: () => DateTime.parse('2026-11-20T01:00:00+09:00'),
      );
      await p.init();
      final out = await p.fetchActiveAdvisoriesAtPoint(
        latitude: _akitaLat,
        longitude: _akitaLon,
      );
      final notice = out.firstWhere(
        (a) => a.eventClass == kJmaPathRetirementEventClass,
        orElse: () => throw StateError('no path-retirement notice emitted'),
      );
      expect(notice.headline, contains('提供が終了'));
      expect(notice.severity, equals(AdvisorySeverity.minor));
      expect(notice.eventClass, isNot(endsWith('警報')));
      expect(notice.eventClass, isNot(endsWith('注意報')));
    });

    test('the retirement threshold would have fired on day 8 of 87', () {
      expect(kJmaDefaultPathRetirementThreshold.inDays, lessThanOrEqualTo(7));
      expect(
        kJmaDefaultPathRetirementThreshold,
        greaterThan(kJmaDefaultStaleFeedThreshold),
      );
    });
  });

  group('honest absence is unchanged by the switch', () {
    test(
      'a 404 on the only containing prefecture THROWS, never all-clear',
      () async {
        final mock = MockClient((_) async => http.Response('nope', 404));
        final p = JmaAdvisoryProvider(userAgent: '(test)', client: mock);
        await p.init();
        expect(
          () => p.fetchActiveAdvisoriesAtPoint(
            latitude: _akitaLat,
            longitude: _akitaLon,
          ),
          throwsA(isA<JmaAdvisoryFetchException>()),
        );
      },
    );

    test(
      'a legacy-shaped document is REFUSED, never silently misread',
      () async {
        final legacy = _read(
          'test/fixtures/jma_warning_050000.frozen_2026-05.json',
        );
        final mock = MockClient(
          (_) async => http.Response(
            legacy,
            200,
            headers: {'content-type': 'application/json'},
          ),
        );
        final p = JmaAdvisoryProvider(userAgent: '(test)', client: mock);
        await p.init();
        expect(
          () => p.fetchActiveAdvisoriesAtPoint(
            latitude: _akitaLat,
            longitude: _akitaLon,
          ),
          throwsA(isA<JmaAdvisoryFetchException>()),
        );
      },
    );
  });
}
