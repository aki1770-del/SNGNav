import 'dart:convert';

import 'package:condition_aggregator/condition_aggregator.dart';
import 'package:condition_aggregator_jma/condition_aggregator_jma.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

/// Test helper — wraps a UTF-8 string body in a mocked [http.Response]
/// with the bytes preserved (the default `http.Response(String, int)`
/// constructor encodes via latin-1 which corrupts the JA chars on
/// round-trip through utf8.decode).
http.Response _utf8Response(String body, int status) => http.Response.bytes(
  utf8.encode(body),
  status,
  headers: const {'content-type': 'application/json; charset=utf-8'},
);

/// Akita warning JSON fixture carrying an in-force 大雪警報 (code 06,
/// status 発表) in the coarse area + a 着雪注意報 (code 26) in a
/// municipality block, plus a non-snow 雷注意報 (code 14) that the
/// snow filter must drop. Shape mirrors the live
/// `bosai/warning/data/warning/050000.json` (verified 2026-06-26).
const String _akitaWarningJsonWithOoyukiKeihou = '''
{
  "reportDatetime": "2026-01-15T13:23:00+09:00",
  "publishingOffice": "秋田地方気象台",
  "headlineText": "秋田県では、１５日夜のはじめ頃まで大雪に警戒してください。",
  "areaTypes": [
    {
      "areas": [
        {"code": "050010", "warnings": [{"code": "06", "status": "発表"}, {"code": "14", "status": "発表"}]},
        {"code": "050020", "warnings": [{"code": "06", "status": "発表"}]}
      ]
    },
    {
      "areas": [
        {"code": "0520100", "warnings": [{"code": "06", "status": "発表"}, {"code": "26", "status": "発表"}]},
        {"code": "0520200", "warnings": [{"code": "26", "status": "継続"}]}
      ]
    }
  ],
  "timeSeries": [
    {"areaTypes": [{"areas": [{"code": "050010", "warnings": [{"code": "12", "status": "発表"}]}]}]}
  ]
}
''';

/// Akita warning JSON with only a non-snow 雷注意報 (code 14) — the
/// real currently-in-force live shape (Akita, observed 2026-06-26).
const String _akitaWarningJsonThunderOnly = '''
{
  "reportDatetime": "2026-05-28T06:11:00+09:00",
  "publishingOffice": "秋田地方気象台",
  "headlineText": "秋田県では、２８日昼過ぎから２８日夜のはじめ頃まで急な強い雨や落雷に注意してください。",
  "areaTypes": [
    {
      "areas": [
        {"code": "050010", "warnings": [{"code": "14", "status": "発表"}]},
        {"code": "050020", "warnings": [{"code": "14", "status": "発表"}]}
      ]
    }
  ]
}
''';

/// Akita warning JSON where a 大雪警報 has just been cancelled
/// (status 解除) — must NOT surface as in-force.
const String _akitaWarningJsonCancelled = '''
{
  "reportDatetime": "2026-01-16T09:00:00+09:00",
  "publishingOffice": "秋田地方気象台",
  "headlineText": "秋田県の大雪警報は解除されました。",
  "areaTypes": [
    {
      "areas": [
        {"code": "050010", "warnings": [{"code": "06", "status": "解除"}]}
      ]
    }
  ]
}
''';

/// Akita warning JSON carrying an in-force 大雪特別警報 (code 36, the
/// 特別警報 / emergency level — verified against the JMA bosai
/// `code2WarningInfo` served table 2026-06-26:
/// `36:{nameParts:e.snow[5],level:50}`, `e.snow[5]=["大雪","特別警報"]`).
const String _akitaWarningJsonWithOoyukiTokubetsuKeihou = '''
{
  "reportDatetime": "2026-01-20T05:00:00+09:00",
  "publishingOffice": "秋田地方気象台",
  "headlineText": "秋田県では、数年に一度の記録的な大雪となるおそれがあります。",
  "areaTypes": [
    {
      "areas": [
        {"code": "050010", "warnings": [{"code": "36", "status": "発表"}]},
        {"code": "050020", "warnings": [{"code": "36", "status": "継続"}]}
      ]
    }
  ]
}
''';

void main() {
  group('JmaAdvisoryProvider — interface compliance', () {
    test('source returns AdvisorySource.jmaJapan', () {
      final provider = JmaAdvisoryProvider();
      expect(provider.source, equals(AdvisorySource.jmaJapan));
    });

    test('init completes without throwing', () async {
      final provider = JmaAdvisoryProvider();
      await provider.init();
    });

    test('default warningJsonBaseUrl points at the public JMA bosai '
        'warning endpoint', () {
      final provider = JmaAdvisoryProvider();
      expect(provider.warningJsonBaseUrl, contains('jma.go.jp'));
      expect(
        provider.warningJsonBaseUrl,
        equals('https://www.jma.go.jp/bosai/warning/data/warning/'),
      );
      // Regression guard (0.2.0): the windowless per-prefecture warning
      // JSON path replaces the 0.1.x atom feed, which had a window /
      // scroll-off false-negative for still-in-force warnings.
      expect(provider.warningJsonBaseUrl, isNot(contains('extra')));
      expect(provider.warningJsonBaseUrl, isNot(contains('feed')));
    });

    test('warningJsonBaseUrl is constructor-injectable', () {
      const testUrl = 'https://test.fixture/jma/warning/';
      final provider = JmaAdvisoryProvider(warningJsonBaseUrl: testUrl);
      expect(provider.warningJsonBaseUrl, equals(testUrl));
    });

    test(
      'init rejects empty userAgent with AdvisoryProviderInitException',
      () async {
        final provider = JmaAdvisoryProvider(userAgent: '   ');
        expect(
          () => provider.init(),
          throwsA(isA<AdvisoryProviderInitException>()),
        );
      },
    );
  });

  group('JmaAdvisoryProvider — fetch behavior', () {
    test('fetch without init throws AdvisoryProviderInitException', () async {
      final provider = JmaAdvisoryProvider();
      expect(
        () => provider.fetchActiveAdvisoriesAtPoint(
          latitude: 39.7186,
          longitude: 140.1024,
        ),
        throwsA(isA<AdvisoryProviderInitException>()),
      );
    });

    test('fetch requests the caller-prefecture warning JSON URL', () async {
      Uri? requested;
      final mock = MockClient((req) async {
        requested = req.url;
        return _utf8Response(_akitaWarningJsonThunderOnly, 200);
      });
      final provider = JmaAdvisoryProvider(
        warningJsonBaseUrl: 'https://test.fixture/jma/warning/',
        client: mock,
      );
      await provider.init();
      await provider.fetchActiveAdvisoriesAtPoint(
        latitude: 39.7186, // Akita → 050000
        longitude: 140.1024,
      );
      expect(
        requested.toString(),
        equals('https://test.fixture/jma/warning/050000.json'),
      );
    });

    test('fetch maps an in-force 大雪警報 (code 06) to one severe '
        'Advisory with eventClass "大雪警報" verbatim', () async {
      final mock = MockClient((req) async {
        return _utf8Response(_akitaWarningJsonWithOoyukiKeihou, 200);
      });
      final provider = JmaAdvisoryProvider(
        warningJsonBaseUrl: 'https://test.fixture/jma/warning/',
        client: mock,
      );
      await provider.init();
      final advisories = await provider.fetchActiveAdvisoriesAtPoint(
        latitude: 39.7186, // Akita-shi
        longitude: 140.1024,
      );
      // Distinct snow codes in force: 06 (大雪警報) + 26 (着雪注意報).
      // 14 (雷) is non-snow → dropped; 12 lives only in timeSeries
      // (forecast) → ignored.
      final byClass = {for (final a in advisories) a.eventClass: a};
      expect(byClass.keys.toSet(), equals({'大雪警報', '着雪注意報'}));

      final ooyuki = byClass['大雪警報']!;
      expect(ooyuki.source, equals(AdvisorySource.jmaJapan));
      expect(ooyuki.severity, equals(AdvisorySeverity.severe));
      expect(ooyuki.areaDescription, equals('Akita'));
      expect(
        ooyuki.headline,
        equals('秋田県では、１５日夜のはじめ頃まで大雪に警戒してください。'),
      );
      expect(ooyuki.effective, isNotNull);

      expect(byClass['着雪注意報']!.severity, equals(AdvisorySeverity.moderate));
    });

    test('fetch maps an in-force 大雪特別警報 (code 36) to one EXTREME '
        'Advisory with eventClass "大雪特別警報" verbatim — worst-case '
        '特別警報 coverage', () async {
      final mock = MockClient((req) async {
        return _utf8Response(_akitaWarningJsonWithOoyukiTokubetsuKeihou, 200);
      });
      final provider = JmaAdvisoryProvider(
        warningJsonBaseUrl: 'https://test.fixture/jma/warning/',
        client: mock,
      );
      await provider.init();
      final advisories = await provider.fetchActiveAdvisoriesAtPoint(
        latitude: 39.7186, // Akita-shi → 050000
        longitude: 140.1024,
      );
      expect(advisories.length, equals(1));
      final tokubetsu = advisories.single;
      expect(tokubetsu.eventClass, equals('大雪特別警報'));
      expect(tokubetsu.severity, equals(AdvisorySeverity.extreme));
      expect(tokubetsu.source, equals(AdvisorySource.jmaJapan));
      expect(tokubetsu.areaDescription, equals('Akita'));
    });

    test('fetch returns empty when only non-snow warnings are in force '
        '(live Akita 雷注意報 shape) — proves fetch+parse+filter on the '
        'real current state', () async {
      final mock = MockClient((req) async {
        return _utf8Response(_akitaWarningJsonThunderOnly, 200);
      });
      final provider = JmaAdvisoryProvider(
        warningJsonBaseUrl: 'https://test.fixture/jma/warning/',
        client: mock,
      );
      await provider.init();
      final advisories = await provider.fetchActiveAdvisoriesAtPoint(
        latitude: 39.7186,
        longitude: 140.1024,
      );
      expect(advisories, isEmpty);
    });

    test('fetch drops a just-cancelled (解除) snow warning', () async {
      final mock = MockClient((req) async {
        return _utf8Response(_akitaWarningJsonCancelled, 200);
      });
      final provider = JmaAdvisoryProvider(
        warningJsonBaseUrl: 'https://test.fixture/jma/warning/',
        client: mock,
      );
      await provider.init();
      final advisories = await provider.fetchActiveAdvisoriesAtPoint(
        latitude: 39.7186,
        longitude: 140.1024,
      );
      expect(advisories, isEmpty);
    });

    test('fetch raises JmaAdvisoryFetchException on HTTP 5xx', () async {
      final mock = MockClient((req) async {
        return http.Response('Service Unavailable', 503);
      });
      final provider = JmaAdvisoryProvider(
        warningJsonBaseUrl: 'https://test.fixture/jma/warning/',
        client: mock,
      );
      await provider.init();
      expect(
        () => provider.fetchActiveAdvisoriesAtPoint(
          latitude: 39.7186,
          longitude: 140.1024,
        ),
        throwsA(isA<JmaAdvisoryFetchException>()),
      );
    });

    test(
      'fetch raises JmaAdvisoryFetchException on body cap exceeded',
      () async {
        final tooLarge = 'x' * (kJmaWarningJsonMaxBytes + 1024);
        final mock = MockClient((req) async {
          return http.Response(tooLarge, 200);
        });
        final provider = JmaAdvisoryProvider(
          warningJsonBaseUrl: 'https://test.fixture/jma/warning/',
          client: mock,
        );
        await provider.init();
        expect(
          () => provider.fetchActiveAdvisoriesAtPoint(
            latitude: 39.7186,
            longitude: 140.1024,
          ),
          throwsA(isA<JmaAdvisoryFetchException>()),
        );
      },
    );

    test('fetch returns empty when caller lat/lon outside catalogued '
        'prefectures (no HTTP call required)', () async {
      final mock = MockClient((req) async {
        // Tokyo is outside the 6-prefecture catalog — the provider
        // should NOT fetch at all.
        fail('HTTP fetch should not occur for points outside catalog');
      });
      final provider = JmaAdvisoryProvider(
        warningJsonBaseUrl: 'https://test.fixture/jma/warning/',
        client: mock,
      );
      await provider.init();
      final advisories = await provider.fetchActiveAdvisoriesAtPoint(
        latitude: 35.6762, // Tokyo
        longitude: 139.6503,
      );
      expect(advisories, isEmpty);
    });
  });

  group('parseJmaWarningJson', () {
    test('maps snow code 06 to verbatim 大雪警報, dedups across areas, '
        'and reads reportDatetime + headline', () {
      final records = parseJmaWarningJson(
        _akitaWarningJsonWithOoyukiKeihou,
        prefectureCode: '050000',
      );
      final byCode = {for (final r in records) r.warningCode: r};
      expect(byCode.keys.toSet(), equals({'06', '26'}));

      final ooyuki = byCode['06']!;
      expect(ooyuki.eventName, equals('大雪警報'));
      expect(ooyuki.status, equals('発表'));
      expect(ooyuki.prefectureCode, equals('050000'));
      expect(ooyuki.areaName, equals('Akita'));
      expect(
        ooyuki.headline,
        equals('秋田県では、１５日夜のはじめ頃まで大雪に警戒してください。'),
      );
      expect(
        ooyuki.reportDateTime!.toUtc(),
        equals(DateTime.utc(2026, 1, 15, 4, 23, 0)),
      );
    });

    test('ignores timeSeries (forecast) warnings — only current '
        'in-force areaTypes are surfaced', () {
      // code 12 (大雪注意報) appears ONLY in timeSeries here.
      final records = parseJmaWarningJson(
        _akitaWarningJsonWithOoyukiKeihou,
        prefectureCode: '050000',
      );
      expect(records.any((r) => r.warningCode == '12'), isFalse);
    });

    test('filters out cancelled (解除) warnings', () {
      final records = parseJmaWarningJson(
        _akitaWarningJsonCancelled,
        prefectureCode: '050000',
      );
      expect(records, isEmpty);
    });

    test('filters out non-snow codes (14 雷注意報)', () {
      final records = parseJmaWarningJson(
        _akitaWarningJsonThunderOnly,
        prefectureCode: '050000',
      );
      expect(records, isEmpty);
    });

    test('throws FormatException on malformed JSON', () {
      expect(
        () => parseJmaWarningJson('{not valid json', prefectureCode: '050000'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('prefectureCodeForPoint', () {
    test('Akita-shi (39.72, 140.10) resolves to 050000', () {
      final code = prefectureCodeForPoint(
        latitude: 39.7186,
        longitude: 140.1024,
      );
      expect(code, equals('050000'));
    });

    test('Tokyo (35.68, 139.65) returns null (outside catalog)', () {
      final code = prefectureCodeForPoint(
        latitude: 35.6762,
        longitude: 139.6503,
      );
      expect(code, isNull);
    });

    test('Niigata-shi (37.92, 139.04) resolves to 150000', () {
      final code = prefectureCodeForPoint(
        latitude: 37.9161,
        longitude: 139.0364,
      );
      expect(code, equals('150000'));
    });
  });

  group('kJmaSnowWarningCodes', () {
    test('maps the authoritatively-verified bosai snow codes verbatim', () {
      expect(kJmaSnowWarningCodes['06'], equals('大雪警報'));
      expect(kJmaSnowWarningCodes['12'], equals('大雪注意報'));
      expect(kJmaSnowWarningCodes['02'], equals('暴風雪警報'));
      expect(kJmaSnowWarningCodes['26'], equals('着雪注意報'));
      // 特別警報 (emergency / level-50) snow codes — verified against the
      // JMA bosai code2WarningInfo served table (2026-06-26).
      expect(kJmaSnowWarningCodes['36'], equals('大雪特別警報'));
      expect(kJmaSnowWarningCodes['32'], equals('暴風雪特別警報'));
    });

    test('does NOT contain a 着雪特別警報 (the JMA served snow_accretion '
        'array has no 特別警報 level)', () {
      expect(kJmaSnowWarningCodes.values.contains('着雪特別警報'), isFalse);
    });

    test('does NOT contain a code for 暴風雪注意報 (no bosai-JSON code '
        'exists for it; the advisory-level counterpart is 風雪注意報)', () {
      expect(
        kJmaSnowWarningCodes.values.contains('暴風雪注意報'),
        isFalse,
      );
    });
  });

  group('mapJmaWarningToAdvisory', () {
    JmaWarningRecord record(String name, String code) => JmaWarningRecord(
      warningCode: code,
      eventName: name,
      status: '発表',
      prefectureCode: '050000',
      areaName: 'Akita',
      headline: '',
      reportDateTime: null,
    );

    test('source is always jmaJapan', () {
      expect(
        mapJmaWarningToAdvisory(record('大雪警報', '06')).source,
        equals(AdvisorySource.jmaJapan),
      );
    });

    test('eventClass preserves JMA event-name verbatim (Article 17 β)', () {
      expect(
        mapJmaWarningToAdvisory(record('暴風雪警報', '02')).eventClass,
        equals('暴風雪警報'),
      );
    });

    test('severity maps 警報 → severe; 注意報 → moderate; 特別警報 → extreme', () {
      expect(
        mapJmaWarningToAdvisory(record('大雪警報', '06')).severity,
        equals(AdvisorySeverity.severe),
      );
      expect(
        mapJmaWarningToAdvisory(record('大雪注意報', '12')).severity,
        equals(AdvisorySeverity.moderate),
      );
      expect(
        mapJmaWarningToAdvisory(record('大雪特別警報', '36')).severity,
        equals(AdvisorySeverity.extreme),
      );
    });
  });
}
