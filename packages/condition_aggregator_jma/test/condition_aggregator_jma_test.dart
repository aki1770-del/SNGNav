import 'dart:async';
import 'dart:convert';

import 'package:condition_aggregator/condition_aggregator.dart';
import 'package:condition_aggregator_jma/condition_aggregator_jma.dart';
// Direct src import for the non-exported border-union dedup helper. Same
// declaration as the package export resolves JmaAdvisoryProvider et al., so
// no symbol conflict; this only adds the unexported `mergeDedupedAdvisories`.
import 'package:condition_aggregator_jma/src/jma_advisory_provider.dart'
    show mergeDedupedAdvisories;
import 'package:fake_async/fake_async.dart';
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
/// municipality block, plus a 雷注意報 (code 14). Through 0.3.0 code 14
/// was the non-snow drop-proof; from 0.4.0 it IS surfaced (moderate) —
/// the widening is the point. Shape mirrors the live
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

/// Akita warning JSON with only a 雷注意報 (code 14) — the real
/// currently-in-force live shape (Akita, observed 2026-06-26). Through
/// 0.3.0 this parsed to empty (non-snow); from 0.4.0 雷注意報 is a
/// surfaced class and this shape yields one moderate Advisory.
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

/// Akita warning JSON with only a 乾燥注意報 (code 21 — a real served
/// class that is genuinely OUTSIDE the 0.4.0 surfaced set). Takes over
/// the "non-surfaced code is dropped" proof role that 雷注意報 (code 14)
/// held through 0.3.0, since code 14 now surfaces.
const String _akitaWarningJsonDryOnly = '''
{
  "reportDatetime": "2026-07-10T06:11:00+09:00",
  "publishingOffice": "秋田地方気象台",
  "headlineText": "秋田県では、空気の乾燥した状態が続いています。",
  "areaTypes": [
    {
      "areas": [
        {"code": "050010", "warnings": [{"code": "21", "status": "発表"}]},
        {"code": "050020", "warnings": [{"code": "21", "status": "発表"}]}
      ]
    }
  ]
}
''';

/// Akita warning JSON carrying an in-force 大雨警報 (code 03, 発表) in the
/// coarse area + a 強風注意報 (code 15, 継続) in a municipality block —
/// a realistic sudden summer / typhoon turmoil shape for the 0.4.0
/// widening (same document structure as the live
/// `bosai/warning/data/warning/050000.json`).
const String _akitaWarningJsonRainstorm = '''
{
  "reportDatetime": "2026-07-10T13:23:00+09:00",
  "publishingOffice": "秋田地方気象台",
  "headlineText": "秋田県では、１０日夜のはじめ頃まで土砂災害や低い土地の浸水に警戒してください。",
  "areaTypes": [
    {
      "areas": [
        {"code": "050010", "warnings": [{"code": "03", "status": "発表"}]},
        {"code": "050020", "warnings": [{"code": "03", "status": "発表"}]}
      ]
    },
    {
      "areas": [
        {"code": "0520100", "warnings": [{"code": "03", "status": "発表"}, {"code": "15", "status": "継続"}]},
        {"code": "0520200", "warnings": [{"code": "15", "status": "継続"}]}
      ]
    }
  ]
}
''';

/// Akita warning JSON carrying an in-force 大雨危険警報 (code 43, JMA
/// level 40 / 警戒レベル4相当 — the only 危険警報 rung among the surfaced
/// classes) — end-to-end proof that code 43 maps to extreme through the
/// full fetch path, so a reorder of the severity endsWith chain cannot
/// silently under-grade a level-40 to severe with a green suite.
const String _akitaWarningJsonWithOoameKikenKeihou = '''
{
  "reportDatetime": "2026-07-10T18:40:00+09:00",
  "publishingOffice": "秋田地方気象台",
  "headlineText": "秋田県では、災害の危険度が高まっています。警戒レベル４相当。",
  "areaTypes": [
    {
      "areas": [
        {"code": "050010", "warnings": [{"code": "43", "status": "発表"}]}
      ]
    }
  ]
}
''';

/// Akita warning JSON where a 大雨警報 (code 03) and a 強風注意報 (code
/// 15) have just been cancelled (status 解除) — the 0.4.0 classes must
/// honour the same 解除 exclusion as the snow classes.
const String _akitaWarningJsonRainstormCancelled = '''
{
  "reportDatetime": "2026-07-10T18:00:00+09:00",
  "publishingOffice": "秋田地方気象台",
  "headlineText": "秋田県の大雨警報は解除されました。",
  "areaTypes": [
    {
      "areas": [
        {"code": "050010", "warnings": [{"code": "03", "status": "解除"}, {"code": "15", "status": "解除"}]}
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

/// Yamagata (060000) warning JSON carrying an in-force 暴風雪警報 (code
/// 02). Used for the border-union tests: a point in the Akita∩Yamagata
/// overlap must surface BOTH prefectures' warnings, so the Yamagata feed
/// carries a DIFFERENT snow class (暴風雪警報) than the Akita feed
/// (大雪警報) to prove the union is not a single-prefecture result.
const String _yamagataWarningJsonWithBoufuusetsuKeihou = '''
{
  "reportDatetime": "2026-01-15T14:05:00+09:00",
  "publishingOffice": "山形地方気象台",
  "headlineText": "山形県では、１５日夜のはじめ頃まで暴風雪に警戒してください。",
  "areaTypes": [
    {
      "areas": [
        {"code": "060010", "warnings": [{"code": "02", "status": "発表"}]}
      ]
    }
  ]
}
''';

/// Yamagata (060000) warning JSON carrying only a 乾燥注意報 (code 21 —
/// outside the surfaced set) — a fast, in-force-but-nothing-surfaced
/// ("fast-empty") sibling used by the border-slow-own-warning regression
/// test, where HER OWN prefecture answers a real snow warning on a slow
/// link while the other containing prefecture answers quickly with no
/// surfaced warning. (Through 0.3.0 this fixture used 雷注意報, code 14;
/// that class surfaces from 0.4.0, so the empty-contribution role moved
/// to a genuinely non-surfaced code.)
const String _yamagataWarningJsonDryOnly = '''
{
  "reportDatetime": "2026-01-15T14:00:00+09:00",
  "publishingOffice": "山形地方気象台",
  "headlineText": "山形県では、空気の乾燥した状態が続いています。",
  "areaTypes": [
    {
      "areas": [
        {"code": "060010", "warnings": [{"code": "21", "status": "発表"}]}
      ]
    }
  ]
}
''';

/// Yamagata (060000) warning JSON carrying an in-force 大雪警報 (code 06)
/// — the SAME snow class the Akita fixture carries. Used to prove the
/// union keeps BOTH prefectures' same-class warnings (distinct by
/// prefecture label) rather than collapsing them: over-warn at a border.
const String _yamagataWarningJsonWithOoyukiKeihou = '''
{
  "reportDatetime": "2026-01-15T14:10:00+09:00",
  "publishingOffice": "山形地方気象台",
  "headlineText": "山形県では、１５日夜のはじめ頃まで大雪に警戒してください。",
  "areaTypes": [
    {
      "areas": [
        {"code": "060010", "warnings": [{"code": "06", "status": "発表"}]}
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
      // Distinct surfaced codes in force: 06 (大雪警報) + 26 (着雪注意報)
      // + 14 (雷注意報 — surfaced from 0.4.0); 12 lives only in
      // timeSeries (forecast) → ignored.
      final byClass = {for (final a in advisories) a.eventClass: a};
      expect(byClass.keys.toSet(), equals({'大雪警報', '着雪注意報', '雷注意報'}));

      final ooyuki = byClass['大雪警報']!;
      expect(ooyuki.source, equals(AdvisorySource.jmaJapan));
      expect(ooyuki.severity, equals(AdvisorySeverity.severe));
      // Driver-facing label is the Japanese prefecture name (D4: a
      // Japanese-reading driver reads it to disambiguate a border over-warn).
      expect(ooyuki.areaDescription, equals('秋田県'));
      expect(ooyuki.headline, equals('秋田県では、１５日夜のはじめ頃まで大雪に警戒してください。'));
      expect(ooyuki.effective, isNotNull);

      expect(byClass['着雪注意報']!.severity, equals(AdvisorySeverity.moderate));
      expect(byClass['雷注意報']!.severity, equals(AdvisorySeverity.moderate));
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
      expect(tokubetsu.areaDescription, equals('秋田県'));
    });

    test('fetch surfaces an in-force 雷注意報 (code 14, the live Akita '
        'shape that parsed to empty through 0.3.0) as one moderate '
        'Advisory — the 0.4.0 widening on a real observed state', () async {
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
      expect(advisories.length, equals(1));
      final thunder = advisories.single;
      expect(thunder.eventClass, equals('雷注意報'));
      expect(thunder.severity, equals(AdvisorySeverity.moderate));
      expect(thunder.areaDescription, equals('秋田県'));
    });

    test('fetch maps a realistic turmoil state (大雨警報 code 03 + '
        '強風注意報 code 15) to the right Advisories — severe downpour '
        'card + moderate wind card (0.4.0)', () async {
      final mock = MockClient((req) async {
        return _utf8Response(_akitaWarningJsonRainstorm, 200);
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
      final byClass = {for (final a in advisories) a.eventClass: a};
      expect(byClass.keys.toSet(), equals({'大雨警報', '強風注意報'}));

      final ooame = byClass['大雨警報']!;
      expect(ooame.source, equals(AdvisorySource.jmaJapan));
      expect(ooame.severity, equals(AdvisorySeverity.severe));
      expect(ooame.areaDescription, equals('秋田県'));
      expect(ooame.effective, isNotNull);

      final kyoufuu = byClass['強風注意報']!;
      expect(kyoufuu.severity, equals(AdvisorySeverity.moderate));
      expect(kyoufuu.areaDescription, equals('秋田県'));
    });

    test('fetch maps an in-force 大雨危険警報 (code 43, JMA level 40) to '
        'ONE extreme Advisory end-to-end — the ordering-sensitive '
        '危険警報 rung cannot be under-graded to severe (0.4.0)', () async {
      final mock = MockClient((req) async {
        return _utf8Response(_akitaWarningJsonWithOoameKikenKeihou, 200);
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
      expect(advisories.length, equals(1));
      final kiken = advisories.single;
      expect(kiken.eventClass, equals('大雨危険警報'));
      expect(kiken.severity, equals(AdvisorySeverity.extreme));
      expect(kiken.source, equals(AdvisorySource.jmaJapan));
      expect(kiken.areaDescription, equals('秋田県'));
    });

    test('fetch drops just-cancelled (解除) 0.4.0-class warnings '
        '(大雨警報 03 + 強風注意報 15 解除) — the new classes honour the '
        'same 解除 exclusion as the snow classes', () async {
      final mock = MockClient((req) async {
        return _utf8Response(_akitaWarningJsonRainstormCancelled, 200);
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

    test('fetch returns empty when only NON-surfaced warnings are in '
        'force (乾燥注意報 code 21) — proves fetch+parse+filter still '
        'drops classes outside kJmaWarningCodes', () async {
      final mock = MockClient((req) async {
        return _utf8Response(_akitaWarningJsonDryOnly, 200);
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
      // 14 (雷注意報) is surfaced from 0.4.0 alongside the snow codes.
      expect(byCode.keys.toSet(), equals({'06', '14', '26'}));

      final ooyuki = byCode['06']!;
      expect(ooyuki.eventName, equals('大雪警報'));
      expect(ooyuki.status, equals('発表'));
      expect(ooyuki.prefectureCode, equals('050000'));
      expect(ooyuki.areaName, equals('秋田県'));
      expect(ooyuki.headline, equals('秋田県では、１５日夜のはじめ頃まで大雪に警戒してください。'));
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

    test('maps 雷注意報 (code 14, surfaced from 0.4.0) — the live shape '
        'that parsed to empty through 0.3.0', () {
      final records = parseJmaWarningJson(
        _akitaWarningJsonThunderOnly,
        prefectureCode: '050000',
      );
      expect(records.length, equals(1));
      expect(records.single.warningCode, equals('14'));
      expect(records.single.eventName, equals('雷注意報'));
    });

    test('filters out non-surfaced codes (21 乾燥注意報)', () {
      final records = parseJmaWarningJson(
        _akitaWarningJsonDryOnly,
        prefectureCode: '050000',
      );
      expect(records, isEmpty);
    });

    test('maps 0.4.0 turmoil codes 03 (大雨警報) + 15 (強風注意報) to '
        'verbatim names, deduped across areas', () {
      final records = parseJmaWarningJson(
        _akitaWarningJsonRainstorm,
        prefectureCode: '050000',
      );
      final byCode = {for (final r in records) r.warningCode: r};
      expect(byCode.keys.toSet(), equals({'03', '15'}));
      expect(byCode['03']!.eventName, equals('大雨警報'));
      expect(byCode['15']!.eventName, equals('強風注意報'));
    });

    test('filters out cancelled (解除) 0.4.0-class warnings', () {
      final records = parseJmaWarningJson(
        _akitaWarningJsonRainstormCancelled,
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

  group('prefectureCodesForPoint — conservative border union', () {
    test('Chōkai/Nikaho southern band (39.10, 140.05) returns BOTH Akita '
        '(050000) AND Yamagata (060000) — the south-Akita border the '
        'single-prefecture resolver mis-assigns', () {
      final codes = prefectureCodesForPoint(latitude: 39.10, longitude: 140.05);
      // Over-warn at the border: both containing prefectures surface.
      expect(codes, equals(<String>['050000', '060000']));
    });

    test('northern Aomori∩Akita overlap (40.30, 140.30) returns BOTH '
        'Aomori (020000) AND Akita (050000)', () {
      final codes = prefectureCodesForPoint(latitude: 40.30, longitude: 140.30);
      expect(codes, equals(<String>['020000', '050000']));
    });

    test('a clearly-interior point (39.70, 140.30) returns exactly ONE '
        'code — no spurious border neighbours', () {
      final codes = prefectureCodesForPoint(latitude: 39.70, longitude: 140.30);
      expect(codes, equals(<String>['050000']));
    });

    test('a point outside every catalogued box (Osaka 34.69, 135.50) '
        'returns an empty list', () {
      final codes = prefectureCodesForPoint(latitude: 34.69, longitude: 135.50);
      expect(codes, isEmpty);
    });

    test('prefectureCodeForPoint stays the FIRST of prefectureCodesForPoint '
        '(back-compat: the single resolver returns Akita at the '
        'Akita∩Yamagata border, dropping the neighbour)', () {
      final first = prefectureCodeForPoint(latitude: 39.10, longitude: 140.05);
      final all = prefectureCodesForPoint(latitude: 39.10, longitude: 140.05);
      expect(first, equals('050000'));
      expect(first, equals(all.first));
      // The new union surfaces the neighbour the single resolver drops.
      expect(all, contains('060000'));
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
      expect(kJmaSnowWarningCodes.values.contains('暴風雪注意報'), isFalse);
    });
  });

  group('kJmaWarningCodes (the 0.4.0 parse filter)', () {
    test('pins the six 0.2.0 snow codes unchanged (verbatim)', () {
      expect(kJmaWarningCodes['06'], equals('大雪警報'));
      expect(kJmaWarningCodes['12'], equals('大雪注意報'));
      expect(kJmaWarningCodes['02'], equals('暴風雪警報'));
      expect(kJmaWarningCodes['26'], equals('着雪注意報'));
      expect(kJmaWarningCodes['36'], equals('大雪特別警報'));
      expect(kJmaWarningCodes['32'], equals('暴風雪特別警報'));
    });

    test('pins the nine 0.4.0 downpour / typhoon / turmoil codes verbatim '
        '(verified against the JMA bosai code2WarningInfo served table, '
        'read twice 2026-07-10)', () {
      expect(kJmaWarningCodes['33'], equals('大雨特別警報'));
      expect(kJmaWarningCodes['43'], equals('大雨危険警報'));
      expect(kJmaWarningCodes['03'], equals('大雨警報'));
      expect(kJmaWarningCodes['10'], equals('大雨注意報'));
      expect(kJmaWarningCodes['35'], equals('暴風特別警報'));
      expect(kJmaWarningCodes['05'], equals('暴風警報'));
      expect(kJmaWarningCodes['15'], equals('強風注意報'));
      expect(kJmaWarningCodes['14'], equals('雷注意報'));
      expect(kJmaWarningCodes['20'], equals('濃霧注意報'));
      // Exactly the six snow + nine turmoil classes — an accidental
      // add/delete cannot pass silently.
      expect(kJmaWarningCodes.length, equals(15));
    });

    test('back-compat invariant: every kJmaSnowWarningCodes entry is in '
        'kJmaWarningCodes with the identical name (the doc-comment '
        'promise on the retained snow map)', () {
      for (final entry in kJmaSnowWarningCodes.entries) {
        expect(
          kJmaWarningCodes[entry.key],
          equals(entry.value),
          reason: 'snow code ${entry.key} must be in the parse filter '
              'with the identical verbatim name',
        );
      }
    });

    test('does NOT contain 暴風危険警報 / 大雪危険警報 / 暴風雪危険警報 '
        '(the served level-40 slot is empty for the wind / snow families '
        '— only 大雨 has a 危険警報 rung)', () {
      expect(kJmaWarningCodes.values.contains('暴風危険警報'), isFalse);
      expect(kJmaWarningCodes.values.contains('大雪危険警報'), isFalse);
      expect(kJmaWarningCodes.values.contains('暴風雪危険警報'), isFalse);
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

    test('severity maps 危険警報 (JMA level 40) → extreme, NOT severe — '
        'the ordering-sensitive rung: 危険警報 also ends with 警報, so a '
        'reordered suffix chain would under-grade it (0.4.0)', () {
      expect(
        mapJmaWarningToAdvisory(record('大雨危険警報', '43')).severity,
        equals(AdvisorySeverity.extreme),
      );
      // The neighbouring rain rungs keep their own grades — the 危険警報
      // check must not swallow them.
      expect(
        mapJmaWarningToAdvisory(record('大雨警報', '03')).severity,
        equals(AdvisorySeverity.severe),
      );
      expect(
        mapJmaWarningToAdvisory(record('大雨注意報', '10')).severity,
        equals(AdvisorySeverity.moderate),
      );
      expect(
        mapJmaWarningToAdvisory(record('大雨特別警報', '33')).severity,
        equals(AdvisorySeverity.extreme),
      );
    });
  });

  group('JmaAdvisoryProvider — border union fetch', () {
    // Chōkai / Nikaho southern band — inside BOTH Akita (050000) and
    // Yamagata (060000) boxes (verified against the bounding-box catalog).
    const borderLat = 39.10;
    const borderLon = 140.05;

    /// MockClient that answers per prefecture URL; records which URLs were
    /// requested so the union behaviour (both endpoints hit) is observable.
    MockClient borderMock(
      Set<Uri> requested,
      Map<String, http.Response Function()> byAreaCode,
    ) {
      return MockClient((req) async {
        requested.add(req.url);
        for (final entry in byAreaCode.entries) {
          if (req.url.path.endsWith('${entry.key}.json')) {
            return entry.value();
          }
        }
        fail('Unexpected URL fetched: ${req.url}');
      });
    }

    test('a border point fetches BOTH prefectures and returns the UNION of '
        'their advisories (Akita 大雪警報 + Yamagata 暴風雪警報)', () async {
      final requested = <Uri>{};
      final provider = JmaAdvisoryProvider(
        warningJsonBaseUrl: 'https://test.fixture/jma/warning/',
        client: borderMock(requested, {
          '050000': () => _utf8Response(_akitaWarningJsonWithOoyukiKeihou, 200),
          '060000': () =>
              _utf8Response(_yamagataWarningJsonWithBoufuusetsuKeihou, 200),
        }),
      );
      await provider.init();
      final advisories = await provider.fetchActiveAdvisoriesAtPoint(
        latitude: borderLat,
        longitude: borderLon,
      );

      // Both prefecture endpoints were hit.
      expect(
        requested.map((u) => u.path).toSet(),
        equals({'/jma/warning/050000.json', '/jma/warning/060000.json'}),
      );

      // Union: Akita 大雪警報 + 着雪注意報 + 雷注意報 (code 14, surfaced
      // from 0.4.0 — the widening flows through the border union too) +
      // Yamagata 暴風雪警報.
      final byClassToArea = <String, Set<String>>{};
      for (final a in advisories) {
        byClassToArea
            .putIfAbsent(a.eventClass, () => <String>{})
            .add(a.areaDescription);
      }
      expect(
        byClassToArea.keys.toSet(),
        equals({'大雪警報', '着雪注意報', '雷注意報', '暴風雪警報'}),
      );
      expect(byClassToArea['雷注意報'], equals({'秋田県'}));
      // The neighbouring prefecture's warning is present and correctly
      // labelled in Japanese (D4) — the south-Akita driver sees Yamagata's
      // 暴風雪警報 labelled 山形県, distinct from their own 秋田県 warning.
      expect(byClassToArea['暴風雪警報'], equals({'山形県'}));
      expect(byClassToArea['大雪警報'], equals({'秋田県'}));
      expect(byClassToArea['暴風雪警報'], equals({jmaPrefectureNameJa('060000')}));
    });

    test('over-warn: when BOTH prefectures carry the SAME class (大雪警報), '
        'the union keeps BOTH (distinct prefecture labels) — a border '
        'warning is never hidden as a "duplicate"', () async {
      final requested = <Uri>{};
      final provider = JmaAdvisoryProvider(
        warningJsonBaseUrl: 'https://test.fixture/jma/warning/',
        client: borderMock(requested, {
          '050000': () => _utf8Response(_akitaWarningJsonWithOoyukiKeihou, 200),
          '060000': () =>
              _utf8Response(_yamagataWarningJsonWithOoyukiKeihou, 200),
        }),
      );
      await provider.init();
      final advisories = await provider.fetchActiveAdvisoriesAtPoint(
        latitude: borderLat,
        longitude: borderLon,
      );

      final ooyuki = advisories.where((a) => a.eventClass == '大雪警報').toList();
      // TWO 大雪警報 survive — one per prefecture — NOT collapsed to one.
      expect(ooyuki.length, equals(2));
      expect(
        ooyuki.map((a) => a.areaDescription).toSet(),
        equals({'秋田県', '山形県'}),
      );
    });

    test('partial failure: one border endpoint down (Yamagata 503) still '
        'returns the reachable prefecture (Akita) advisories — never '
        'withhold a successfully-fetched warning', () async {
      final requested = <Uri>{};
      final provider = JmaAdvisoryProvider(
        warningJsonBaseUrl: 'https://test.fixture/jma/warning/',
        client: borderMock(requested, {
          '050000': () => _utf8Response(_akitaWarningJsonWithOoyukiKeihou, 200),
          '060000': () => http.Response('Service Unavailable', 503),
        }),
      );
      await provider.init();
      final advisories = await provider.fetchActiveAdvisoriesAtPoint(
        latitude: borderLat,
        longitude: borderLon,
      );

      // Both endpoints attempted; Akita's warnings still surface.
      expect(requested.length, equals(2));
      final classes = advisories.map((a) => a.eventClass).toSet();
      expect(classes, contains('大雪警報'));
      // No real WARNING from the failed Yamagata fetch leaks in (the only
      // non-Akita record is the in-band incomplete-read meta-notice).
      final warnings = advisories
          .where((a) => a.eventClass != kJmaIncompleteReadEventClass)
          .toList();
      expect(warnings.every((a) => a.areaDescription == '秋田県'), isTrue);
    });

    test(
      'total failure: when EVERY border endpoint fails, '
      'JmaAdvisoryFetchException is thrown (no silent empty result)',
      () async {
        final requested = <Uri>{};
        final provider = JmaAdvisoryProvider(
          warningJsonBaseUrl: 'https://test.fixture/jma/warning/',
          client: borderMock(requested, {
            '050000': () => http.Response('Service Unavailable', 503),
            '060000': () => http.Response('Service Unavailable', 503),
          }),
        );
        await provider.init();
        // SHOULD-C: assert the thrown exception preserves the failure VALUES,
        // not just its TYPE — the all-failed path rethrows the first failure,
        // which on a 503 carries a meaningful source uri AND statusCode 503.
        JmaAdvisoryFetchException? thrown;
        try {
          await provider.fetchActiveAdvisoriesAtPoint(
            latitude: borderLat,
            longitude: borderLon,
          );
        } on JmaAdvisoryFetchException catch (e) {
          thrown = e;
        }
        expect(thrown, isNotNull, reason: 'all-failed must throw');
        expect(
          thrown!.uri,
          isNotNull,
          reason:
              'the all-failed rethrow must carry the failing prefecture uri',
        );
        expect(thrown.uri.toString(), endsWith('.json'));
        expect(
          thrown.statusCode,
          equals(503),
          reason:
              'the 503 statusCode must be preserved on the all-failed throw',
        );
      },
    );

    test('an interior point triggers exactly ONE prefecture fetch '
        '(no spurious border fetch)', () async {
      final requested = <Uri>{};
      final provider = JmaAdvisoryProvider(
        warningJsonBaseUrl: 'https://test.fixture/jma/warning/',
        client: borderMock(requested, {
          '050000': () => _utf8Response(_akitaWarningJsonWithOoyukiKeihou, 200),
        }),
      );
      await provider.init();
      await provider.fetchActiveAdvisoriesAtPoint(
        latitude: 39.70, // clearly interior to Akita only
        longitude: 140.30,
      );
      expect(requested.length, equals(1));
      expect(requested.single.path, equals('/jma/warning/050000.json'));
    });

    // Hung-sibling isolation: a hung sibling must NOT discard a successful
    // sibling's warnings. Without the per-request timeout, Future.wait blocks
    // on the hung Yamagata endpoint until the batch backstop fires and THROWS,
    // discarding Akita's already-fetched 大雪警報 — exactly the worst-case
    // regression at a degraded-connectivity border. With the single
    // [kJmaFetchWallClockBudget] per-request timeout the hung sibling
    // self-bounds as a captured failure and the success survives. fake_async
    // drives the budget in virtual time (no real wait). FAILS against the
    // un-hardened code (which throws → result is null, error is set).
    test('a HUNG border sibling (Yamagata never responds) does NOT discard '
        'the fast sibling (Akita) — its 大雪警報 is still returned, and the '
        'hung sibling is signalled (not silently dropped)', () {
      fakeAsync((async) {
        final provider = JmaAdvisoryProvider(
          warningJsonBaseUrl: 'https://test.fixture/jma/warning/',
          client: MockClient((req) async {
            if (req.url.path.endsWith('060000.json')) {
              // Yamagata hangs forever (degraded compound-failure link).
              return Completer<http.Response>().future;
            }
            return _utf8Response(_akitaWarningJsonWithOoyukiKeihou, 200);
          }),
        );
        List<Advisory>? result;
        Object? error;
        unawaited(() async {
          await provider.init();
          try {
            result = await provider.fetchActiveAdvisoriesAtPoint(
              latitude: borderLat,
              longitude: borderLon,
            );
          } catch (e) {
            error = e;
          }
        }());
        // Advance just past the per-request budget: the hung Yamagata fetch
        // self-bounds as a captured failure; Akita resolved near-instantly.
        async.elapse(kJmaFetchWallClockBudget + const Duration(seconds: 1));

        expect(
          error,
          isNull,
          reason: 'a hung sibling must not throw away a successful sibling',
        );
        expect(result, isNotNull);
        expect(result!.map((a) => a.eventClass).toSet(), contains('大雪警報'));
        // No real WARNING from the hung Yamagata fetch leaks in (the only
        // non-Akita record is the meta-notice, excluded here).
        final warnings = result!
            .where((a) => a.eventClass != kJmaIncompleteReadEventClass)
            .toList();
        expect(warnings.every((a) => a.areaDescription == '秋田県'), isTrue);
        // The hung sibling is SIGNALLED in-band (MUST-1), not silently dropped.
        expect(
          result!.any(
            (a) =>
                a.eventClass == kJmaIncompleteReadEventClass &&
                a.areaDescription.contains('山形県'),
          ),
          isTrue,
        );
      });
    });

    // SHOULD-2: one containing prefecture succeeds EMPTY (Akita, only a
    // non-surfaced 乾燥注意報 in force) while another FAILS (Yamagata 503). The
    // empty union is an INCOMPLETE read, not a true all-clear — returning []
    // would tell a border driver 'no warnings' when the unreachable
    // prefecture could hold an active 大雪警報. FAILS against the un-hardened
    // code (which returns [] because anySuccess is true).
    test('SHOULD-2: empty union with a FAILED sibling throws (no false '
        'all-clear) — Akita succeeds-empty + Yamagata 503', () async {
      final requested = <Uri>{};
      final provider = JmaAdvisoryProvider(
        warningJsonBaseUrl: 'https://test.fixture/jma/warning/',
        client: borderMock(requested, {
          '050000': () => _utf8Response(
                _akitaWarningJsonDryOnly,
                200,
              ), // no surfaced class (code 21 乾燥注意報; 雷注意報 surfaces from 0.4.0)
          '060000': () => http.Response('Service Unavailable', 503), // fails
        }),
      );
      await provider.init();
      expect(requested, isEmpty); // sanity: nothing fetched yet
      // SHOULD-C: the incomplete-read throw must preserve the failing
      // sibling's VALUES (uri + statusCode), not just the exception TYPE.
      JmaAdvisoryFetchException? thrown;
      try {
        await provider.fetchActiveAdvisoriesAtPoint(
          latitude: borderLat,
          longitude: borderLon,
        );
      } on JmaAdvisoryFetchException catch (e) {
        thrown = e;
      }
      expect(thrown, isNotNull, reason: 'incomplete read must throw');
      expect(thrown!.message, contains('Incomplete border read'));
      expect(
        thrown.uri,
        isNotNull,
        reason: 'the incomplete-read throw must carry the failing sibling uri',
      );
      expect(thrown.uri.toString(), endsWith('060000.json'));
      expect(
        thrown.statusCode,
        equals(503),
        reason: 'the 503 statusCode must be preserved on the incomplete read',
      );
    });

    // SHOULD-2 boundary: a NON-empty union with a failed sibling is STILL
    // returned (the driver already sees real warnings — never withhold a
    // fetched warning). This is the existing partial-failure behaviour; the
    // throw is reserved for the EMPTY-and-incomplete case above.
    test('SHOULD-2 boundary: NON-empty union with a failed sibling is '
        'returned, not thrown (Akita 大雪警報 + Yamagata 503)', () async {
      final requested = <Uri>{};
      final provider = JmaAdvisoryProvider(
        warningJsonBaseUrl: 'https://test.fixture/jma/warning/',
        client: borderMock(requested, {
          '050000': () => _utf8Response(_akitaWarningJsonWithOoyukiKeihou, 200),
          '060000': () => http.Response('Service Unavailable', 503),
        }),
      );
      await provider.init();
      final advisories = await provider.fetchActiveAdvisoriesAtPoint(
        latitude: borderLat,
        longitude: borderLon,
      );
      expect(advisories.map((a) => a.eventClass).toSet(), contains('大雪警報'));
    });

    // MUST-1 (this round): a NON-empty union with a FAILED containing
    // prefecture must NOT silently discard the captured failure. The reachable
    // Akita 大雪警報 lands AND a synthetic, clearly-marked, LOW-severity
    // incomplete-read notice naming the UNREACHABLE 山形県 is injected — so a
    // partial border read is never presented as a complete, fully-successful
    // result (the silent under-warn this fix closes). FAILS against the
    // un-fixed code, which returns ONLY the Akita warning (firstFailure
    // discarded → no notice).
    test('incomplete-read notice: a non-empty union with a FAILED sibling '
        'returns BOTH the real warning AND a synthetic notice naming the '
        'unreachable prefecture (Akita 大雪警報 + 山形県 notice)', () async {
      final requested = <Uri>{};
      final provider = JmaAdvisoryProvider(
        warningJsonBaseUrl: 'https://test.fixture/jma/warning/',
        client: borderMock(requested, {
          '050000': () => _utf8Response(_akitaWarningJsonWithOoyukiKeihou, 200),
          '060000': () => http.Response('Service Unavailable', 503),
        }),
      );
      await provider.init();
      final advisories = await provider.fetchActiveAdvisoriesAtPoint(
        latitude: borderLat,
        longitude: borderLon,
      );

      // The real Akita warning is present (and labelled 秋田県).
      final realWarnings = advisories
          .where((a) => a.eventClass != kJmaIncompleteReadEventClass)
          .toList();
      expect(realWarnings.map((a) => a.eventClass), contains('大雪警報'));
      expect(realWarnings.every((a) => a.areaDescription == '秋田県'), isTrue);

      // Exactly one synthetic incomplete-read notice is present.
      final notices = advisories
          .where((a) => a.eventClass == kJmaIncompleteReadEventClass)
          .toList();
      expect(notices.length, equals(1));
      final notice = notices.single;

      // It names the UNREACHABLE prefecture (山形県), not the reachable one.
      expect(notice.areaDescription, equals('山形県'));
      expect(notice.headline, contains('山形県'));
      expect(notice.headline, contains('確認できませんでした'));
      expect(notice.areaDescription, isNot(contains('秋田県')));

      // It cannot masquerade as a weather warning: lowest impact, below the
      // isHighImpact (severe/extreme) threshold, no CAP certainty/urgency.
      expect(notice.severity, equals(AdvisorySeverity.minor));
      expect(notice.isHighImpact, isFalse);
      expect(notice.certainty, equals(AdvisoryCertainty.unknown));
      expect(notice.urgency, equals(AdvisoryUrgency.unknown));
      expect(notice.source, equals(AdvisorySource.jmaJapan));
      // Staleness-honesty: an availability notice has no weather validity
      // window, so effective/expires are null — keeping `stalenessAt` honestly
      // "unknown" rather than fabricating a freshness timestamp that would
      // imply a fresh, complete read.
      expect(notice.effective, isNull);
      expect(notice.expires, isNull);
    });

    // MUST-1 boundary (negative half of the spec): an ALL-SUCCESS border union
    // injects NO synthetic notice (the notice is reserved for an
    // actually-partial read). This is a regression guard; by construction it
    // also holds against the un-fixed code (which never injects).
    test('incomplete-read notice: an ALL-SUCCESS border union injects NO '
        'synthetic notice (Akita 大雪警報 + Yamagata 暴風雪警報)', () async {
      final requested = <Uri>{};
      final provider = JmaAdvisoryProvider(
        warningJsonBaseUrl: 'https://test.fixture/jma/warning/',
        client: borderMock(requested, {
          '050000': () => _utf8Response(_akitaWarningJsonWithOoyukiKeihou, 200),
          '060000': () =>
              _utf8Response(_yamagataWarningJsonWithBoufuusetsuKeihou, 200),
        }),
      );
      await provider.init();
      final advisories = await provider.fetchActiveAdvisoriesAtPoint(
        latitude: borderLat,
        longitude: borderLon,
      );
      expect(
        advisories.any((a) => a.eventClass == kJmaIncompleteReadEventClass),
        isFalse,
      );
      // The real union is unchanged (both prefectures' warnings present;
      // 雷注意報 surfaces from 0.4.0).
      expect(
        advisories.map((a) => a.eventClass).toSet(),
        equals({'大雪警報', '着雪注意報', '雷注意報', '暴風雪警報'}),
      );
    });

    // SHOULD-1: a sibling whose body is malformed UTF-8 raises a RAW
    // FormatException from utf8.decode (NOT a JmaAdvisoryFetchException). The
    // broadened `catch (Object)` must capture it as a failed sibling rather
    // than let it escape into Future.wait and discard the successful Akita
    // 大雪警報. FAILS against the un-hardened narrow-catch code (the raw
    // FormatException escapes → the whole batch throws → Akita is discarded).
    test('SHOULD-1: a malformed-UTF-8 sibling (raw FormatException) is '
        'captured, not escaped — Akita 大雪警報 still returned', () async {
      final requested = <Uri>{};
      final provider = JmaAdvisoryProvider(
        warningJsonBaseUrl: 'https://test.fixture/jma/warning/',
        client: borderMock(requested, {
          '050000': () => _utf8Response(_akitaWarningJsonWithOoyukiKeihou, 200),
          // 0xFF is never a valid UTF-8 byte → utf8.decode(allowMalformed:
          // false) throws a raw FormatException inside _httpGet.
          '060000': () => http.Response.bytes(
            <int>[0xFF, 0xFE, 0xFF],
            200,
            headers: const {'content-type': 'application/json'},
          ),
        }),
      );
      await provider.init();
      final advisories = await provider.fetchActiveAdvisoriesAtPoint(
        latitude: borderLat,
        longitude: borderLon,
      );
      // The malformed sibling did not throw away Akita's warning.
      expect(advisories.map((a) => a.eventClass).toSet(), contains('大雪警報'));
      // No real WARNING leaks in from the malformed sibling (the only
      // non-Akita record is the in-band incomplete-read meta-notice, which
      // correctly names the unreachable 山形県).
      final warnings = advisories
          .where((a) => a.eventClass != kJmaIncompleteReadEventClass)
          .toList();
      expect(warnings.every((a) => a.areaDescription == '秋田県'), isTrue);
      expect(
        advisories.any(
          (a) =>
              a.eventClass == kJmaIncompleteReadEventClass &&
              a.areaDescription == '山形県',
        ),
        isTrue,
      );
    });

    // Concurrency guard: two hung siblings must bound the whole call at ~ONE
    // PER-REQUEST budget (concurrent), not ~2× (a future sequentialization to
    // `for (code) await fetch().timeout()` would). The siblings are fetched
    // CONCURRENTLY, so two hung endpoints bound the call at ~one budget (~30 s),
    // NOT ~2× (~60 s, which a sequential await-loop would need). This is the
    // sequentialization guard.
    test('concurrency timing — two hung siblings bound the call at ~one '
        'budget (~30 s), not ~2× (a sequential await-loop)', () {
      fakeAsync((async) {
        final provider = JmaAdvisoryProvider(
          warningJsonBaseUrl: 'https://test.fixture/jma/warning/',
          client: MockClient((req) async => Completer<http.Response>().future),
        );
        var completed = false;
        unawaited(() async {
          await provider.init();
          try {
            await provider.fetchActiveAdvisoriesAtPoint(
              latitude: borderLat,
              longitude: borderLon,
            );
          } catch (_) {
            // All siblings hung → all-failed throw is expected; the timing,
            // not the outcome, is under test here.
          }
          completed = true;
        }());
        // Just before one budget: still pending (it genuinely waits the budget
        // rather than resolving instantly).
        async.elapse(kJmaFetchWallClockBudget - const Duration(seconds: 1));
        expect(completed, isFalse);
        // Just after one budget: the CONCURRENT fetch has bounded + completed.
        // A sequential `for (code) await fetch().timeout()` would NOT have
        // finished here (it needs ~2× the budget).
        async.elapse(const Duration(seconds: 2));
        expect(
          completed,
          isTrue,
          reason:
              'concurrent fetch bounds at ~one budget; a sequential await-loop '
              'would need ~2×',
        );
      });
    });

    // The all-hung / timeout path must PRESERVE a uri on the thrown exception
    // (the 0.2.0 batch onTimeout dropped it). FAILS against the un-hardened
    // code, whose batch onTimeout throws WITHOUT a uri.
    test('an all-hung border throws an exception that PRESERVES a uri (the '
        'per-request timeout path no longer drops it)', () {
      fakeAsync((async) {
        final provider = JmaAdvisoryProvider(
          warningJsonBaseUrl: 'https://test.fixture/jma/warning/',
          client: MockClient((req) async => Completer<http.Response>().future),
        );
        Object? error;
        unawaited(() async {
          await provider.init();
          try {
            await provider.fetchActiveAdvisoriesAtPoint(
              latitude: borderLat,
              longitude: borderLon,
            );
          } catch (e) {
            error = e;
          }
        }());
        async.elapse(kJmaFetchWallClockBudget + const Duration(seconds: 1));
        expect(error, isA<JmaAdvisoryFetchException>());
        expect(
          (error as JmaAdvisoryFetchException).uri,
          isNotNull,
          reason: 'the timeout path must carry a meaningful source uri',
        );
      });
    });

    // Latency budget: a single-prefecture fetch whose warning JSON arrives at
    // ~20 s on a marginal snow-link is SERVED, exactly as 0.2.0 served the
    // single fetch at the full 30 s budget — not timed out into a false
    // 'warning check unavailable'. fake_async drives the 20 s response in
    // virtual time (no real wait). This pins that the per-request budget is the
    // full [kJmaFetchWallClockBudget] (30 s); a hypothetical short (e.g. 10 s)
    // budget would fire before the 20 s response → all-failed throw → the
    // 大雪警報 lost.
    test('a single-prefecture fetch completing at ~20 s SUCCEEDS — the '
        'per-request budget is the full 30 s wall-clock budget', () {
      fakeAsync((async) {
        final provider = JmaAdvisoryProvider(
          warningJsonBaseUrl: 'https://test.fixture/jma/warning/',
          client: MockClient((req) async {
            // The marginal snow-link answers Akita's 大雪警報 at ~20 s — inside
            // the 10–30 s window the 0.2.0 single-fetch budget covered.
            return Future<http.Response>.delayed(
              const Duration(seconds: 20),
              () => _utf8Response(_akitaWarningJsonWithOoyukiKeihou, 200),
            );
          }),
        );
        List<Advisory>? result;
        Object? error;
        unawaited(() async {
          await provider.init();
          try {
            result = await provider.fetchActiveAdvisoriesAtPoint(
              latitude:
                  39.70, // clearly interior to Akita only (ONE prefecture)
              longitude: 140.30,
            );
          } catch (e) {
            error = e;
          }
        }());
        // At ~11 s the fetch must STILL be in-flight (it responds at ~20 s,
        // inside the 30 s budget). A short (10 s) budget would already have
        // thrown here — this is the fail-against-a-short-budget pin.
        async.elapse(const Duration(seconds: 11));
        expect(
          error,
          isNull,
          reason:
              'the fetch is bounded at the full 30 s budget; a 10 s budget '
              'would have thrown by now',
        );
        expect(
          result,
          isNull,
          reason: 'still in-flight at 11 s (responds ~20 s)',
        );
        // Past the 20 s response: the interior fetch resolves with the real
        // 大雪警報 — served, not a false 'warning check unavailable'.
        async.elapse(const Duration(seconds: 10));
        expect(
          error,
          isNull,
          reason: 'a 20 s interior fetch must not time out',
        );
        expect(result, isNotNull);
        expect(result!.map((a) => a.eventClass).toSet(), contains('大雪警報'));
        // A single SUCCESSFUL interior fetch carries no incomplete-read notice.
        expect(
          result!.any((a) => a.eventClass == kJmaIncompleteReadEventClass),
          isFalse,
        );
      });
    });

    // A 2-prefecture BORDER fetch with a HUNG sibling bounds at the single
    // per-request budget (~30 s) — the near-side Akita 大雪警報 is preserved
    // (never discarded) and the hung Yamagata sibling is signalled in-band. The
    // Chair-ratified trade (D-VGC, 2026-06-30): a hung border neighbour may add
    // up to ~30 s of latency before the union returns, which is preferred over
    // EVER dropping a slow-but-valid warning (the false-negative a shorter cap
    // would reintroduce — see the slow-own-warning test below).
    test('a 2-prefecture BORDER fetch with a HUNG sibling bounds at ~30 s and '
        'preserves the near-side warning + signals the hung sibling', () {
      fakeAsync((async) {
        final provider = JmaAdvisoryProvider(
          warningJsonBaseUrl: 'https://test.fixture/jma/warning/',
          client: MockClient((req) async {
            if (req.url.path.endsWith('060000.json')) {
              // Yamagata hangs forever (degraded compound-failure link).
              return Completer<http.Response>().future;
            }
            return _utf8Response(_akitaWarningJsonWithOoyukiKeihou, 200);
          }),
        );
        List<Advisory>? result;
        unawaited(() async {
          await provider.init();
          result = await provider.fetchActiveAdvisoriesAtPoint(
            latitude: borderLat,
            longitude: borderLon,
          );
        }());
        // Just BEFORE the 30 s budget: the batch still waits for the hung
        // Yamagata sibling's per-request timeout to fire.
        async.elapse(kJmaFetchWallClockBudget - const Duration(seconds: 1));
        expect(result, isNull, reason: 'still within the 30 s budget');
        // Just AFTER the 30 s budget: the hung sibling is captured, the union
        // returns with the near-side warning preserved.
        async.elapse(const Duration(seconds: 2));
        expect(result, isNotNull);
        expect(result!.map((a) => a.eventClass).toSet(), contains('大雪警報'));
        // The hung Yamagata sibling is signalled in-band, not silently dropped.
        expect(
          result!.any(
            (a) =>
                a.eventClass == kJmaIncompleteReadEventClass &&
                a.areaDescription.contains('山形県'),
          ),
          isTrue,
        );
      });
    });

    // The Chair-ratified regression closer (the round-5 her-trace MUST): at a
    // BORDER, HER OWN prefecture answers a real 大雪警報 on a marginal ~15 s link
    // while the OTHER containing prefecture answers fast with no snow warning.
    // Under the single 30 s budget her 15 s warning is SERVED. FAILS against the
    // rejected 10 s-at-border code: the 15 s fetch would time out at 10 s →
    // captured failure; the fast-empty sibling → empty union + a failure →
    // incomplete-read THROW → her 大雪警報 lost (a strict regression vs 0.2.0).
    test('a BORDER fetch where HER OWN prefecture returns a 大雪警報 at ~15 s '
        '(the other fast-empty) SERVES the warning — no false unavailable', () {
      fakeAsync((async) {
        final provider = JmaAdvisoryProvider(
          warningJsonBaseUrl: 'https://test.fixture/jma/warning/',
          client: MockClient((req) async {
            if (req.url.path.endsWith('060000.json')) {
              // The OTHER prefecture answers fast with a non-snow advisory only
              // (success, but nothing for the snow classes) → empty contribution.
              return _utf8Response(_yamagataWarningJsonDryOnly, 200);
            }
            // HER own prefecture (Akita) answers a real 大雪警報 at ~15 s.
            return Future<http.Response>.delayed(
              const Duration(seconds: 15),
              () => _utf8Response(_akitaWarningJsonWithOoyukiKeihou, 200),
            );
          }),
        );
        List<Advisory>? result;
        Object? error;
        unawaited(() async {
          await provider.init();
          try {
            result = await provider.fetchActiveAdvisoriesAtPoint(
              latitude: borderLat,
              longitude: borderLon,
            );
          } catch (e) {
            error = e;
          }
        }());
        // Just before her 15 s warning arrives: still in-flight (a 10 s cap
        // would already have thrown — the fail-against-rejected-code pin).
        async.elapse(const Duration(seconds: 14));
        expect(
          error,
          isNull,
          reason: 'a 10 s border cap would have thrown here',
        );
        expect(result, isNull);
        // After her 15 s warning arrives: it is SERVED.
        async.elapse(const Duration(seconds: 2));
        expect(
          error,
          isNull,
          reason: 'her own slow-but-valid warning is served',
        );
        expect(result, isNotNull);
        expect(result!.map((a) => a.eventClass).toSet(), contains('大雪警報'));
        // Both prefectures succeeded → NO incomplete-read notice.
        expect(
          result!.any((a) => a.eventClass == kJmaIncompleteReadEventClass),
          isFalse,
        );
      });
    });
  });

  group('jmaPrefectureNameJa — driver-facing Japanese label (D4)', () {
    test('returns the Japanese prefecture name for catalogued codes', () {
      expect(jmaPrefectureNameJa('050000'), equals('秋田県'));
      expect(jmaPrefectureNameJa('060000'), equals('山形県'));
      expect(jmaPrefectureNameJa('010000'), equals('北海道'));
      expect(jmaPrefectureNameJa('020000'), equals('青森県'));
      expect(jmaPrefectureNameJa('030000'), equals('岩手県'));
      expect(jmaPrefectureNameJa('150000'), equals('新潟県'));
    });

    test('returns null for an uncatalogued code', () {
      expect(jmaPrefectureNameJa('999999'), isNull);
    });

    test('every catalogued bounding-box code has a Japanese name', () {
      for (final code in kJmaPrefectureBoundingBoxes.keys) {
        expect(
          jmaPrefectureNameJa(code),
          isNotNull,
          reason: 'code $code needs a driver-facing JA label',
        );
      }
    });

    test('parseJmaWarningJson labels areaName in Japanese (秋田県), not '
        'romaji', () {
      final records = parseJmaWarningJson(
        _akitaWarningJsonWithOoyukiKeihou,
        prefectureCode: '050000',
      );
      expect(records, isNotEmpty);
      expect(records.every((r) => r.areaName == '秋田県'), isTrue);
    });
  });

  group('mergeDedupedAdvisories', () {
    Advisory adv({
      required String eventClass,
      required AdvisorySeverity severity,
      required String area,
      String headline = '',
      DateTime? effective,
    }) => Advisory(
      source: AdvisorySource.jmaJapan,
      eventClass: eventClass,
      severity: severity,
      certainty: AdvisoryCertainty.unknown,
      urgency: AdvisoryUrgency.unknown,
      areaDescription: area,
      effective: effective,
      expires: null,
      headline: headline,
      description: headline,
    );

    test('collapses a byte-identical advisory to a single entry, '
        'preserving first-seen order', () {
      final a = adv(
        eventClass: '大雪警報',
        severity: AdvisorySeverity.severe,
        area: 'Akita',
        headline: '秋田県では大雪に警戒してください。',
      );
      final aDuplicate = adv(
        eventClass: '大雪警報',
        severity: AdvisorySeverity.severe,
        area: 'Akita',
        headline: '秋田県では大雪に警戒してください。',
      );
      final b = adv(
        eventClass: '暴風雪警報',
        severity: AdvisorySeverity.severe,
        area: 'Yamagata',
        headline: '山形県では暴風雪に警戒してください。',
      );
      final merged = mergeDedupedAdvisories(<Advisory>[a, aDuplicate, b]);
      expect(merged.length, equals(2));
      expect(merged[0].areaDescription, equals('Akita'));
      expect(merged[0].eventClass, equals('大雪警報'));
      expect(merged[1].areaDescription, equals('Yamagata'));
    });

    test('keeps two same-class warnings that differ only by prefecture '
        'label — over-warn: a border warning is never dropped as a '
        '"duplicate"', () {
      final akita = adv(
        eventClass: '大雪警報',
        severity: AdvisorySeverity.severe,
        area: 'Akita',
        headline: '秋田県では大雪に警戒してください。',
      );
      final yamagata = adv(
        eventClass: '大雪警報',
        severity: AdvisorySeverity.severe,
        area: 'Yamagata',
        headline: '山形県では大雪に警戒してください。',
      );
      final merged = mergeDedupedAdvisories(<Advisory>[akita, yamagata]);
      expect(merged.length, equals(2));
      expect(
        merged.map((a) => a.areaDescription).toSet(),
        equals({'Akita', 'Yamagata'}),
      );
    });

    test('an empty input yields an empty union', () {
      expect(mergeDedupedAdvisories(const <Advisory>[]), isEmpty);
    });
  });

  group('buildIncompleteReadNotice', () {
    test('notice is dedup-safe: it survives mergeDedupedAdvisories alongside '
        'a real same-area warning (distinct eventClass keeps them apart)', () {
      // A real 暴風雪警報 that shares the notice's area label (山形県) — the
      // worst case for an accidental dedup collision.
      final realWarning = Advisory(
        source: AdvisorySource.jmaJapan,
        eventClass: '暴風雪警報',
        severity: AdvisorySeverity.severe,
        certainty: AdvisoryCertainty.unknown,
        urgency: AdvisoryUrgency.unknown,
        areaDescription: '山形県',
        effective: null,
        expires: null,
        headline: '山形県では暴風雪に警戒してください。',
        description: '山形県では暴風雪に警戒してください。',
      );
      final notice = buildIncompleteReadNotice(<String>['060000']); // 山形県
      expect(notice.areaDescription, equals('山形県')); // SAME area label

      final merged = mergeDedupedAdvisories(<Advisory>[realWarning, notice]);
      // BOTH survive — the notice is NOT deduped against the real warning even
      // though they share an area label (eventClass + severity + headline
      // differ in the full-identity dedup key).
      expect(merged.length, equals(2));
      expect(
        merged.map((a) => a.eventClass).toSet(),
        equals({'暴風雪警報', kJmaIncompleteReadEventClass}),
      );
    });

    test('notice names multiple unreachable prefectures, JA-localized + '
        'joined, in catalog order', () {
      final notice = buildIncompleteReadNotice(<String>['050000', '060000']);
      expect(notice.areaDescription, equals('秋田県・山形県'));
      expect(notice.headline, contains('秋田県・山形県'));
      expect(notice.headline, contains('確認できませんでした'));
    });

    test('kJmaIncompleteReadEventClass carries no 警報/注意報 suffix (the '
        'severity-by-suffix mapping never classifies it as a hazard)', () {
      expect(kJmaIncompleteReadEventClass.endsWith('警報'), isFalse);
      expect(kJmaIncompleteReadEventClass.endsWith('注意報'), isFalse);
      expect(kJmaIncompleteReadEventClass.endsWith('特別警報'), isFalse);
    });
  });
}
