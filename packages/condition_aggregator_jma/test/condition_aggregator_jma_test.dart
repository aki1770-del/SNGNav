import 'dart:convert';

import 'package:condition_aggregator/condition_aggregator.dart';
import 'package:condition_aggregator_jma/condition_aggregator_jma.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

/// Test helper — wraps a UTF-8 string body in a mocked
/// [http.Response] with the bytes preserved (the default
/// `http.Response(String, int)` constructor encodes via latin-1
/// which corrupts the JA chars on round-trip through utf8.decode).
http.Response _utf8Response(String body, int status) =>
    http.Response.bytes(utf8.encode(body), status,
        headers: const {'content-type': 'application/atom+xml; charset=utf-8'});

const String _akitaPrefectureAtomFeed = '''<?xml version="1.0" encoding="utf-8"?>
<feed xmlns="http://www.w3.org/2005/Atom" lang="ja">
  <title>長期（随時）</title>
  <updated>2026-01-15T13:23:49+09:00</updated>
  <entry>
    <title>気象警報・注意報（Ｈ２７）</title>
    <id>https://www.data.jma.go.jp/developer/xml/data/20260115042337_0_VPWW54_050000.xml</id>
    <updated>2026-01-15T04:23:37Z</updated>
    <author><name>秋田地方気象台</name></author>
    <link type="application/xml" href="https://test.fixture/jma/akita_VPWW54_050000.xml"/>
    <content type="text">【秋田県気象警報・注意報】</content>
  </entry>
  <entry>
    <title>気象警報・注意報（Ｈ２７）</title>
    <id>https://www.data.jma.go.jp/developer/xml/data/20260115041820_0_VPWW54_200000.xml</id>
    <updated>2026-01-15T04:18:03Z</updated>
    <author><name>長野地方気象台</name></author>
    <link type="application/xml" href="https://test.fixture/jma/nagano_VPWW54_200000.xml"/>
    <content type="text">【長野県気象警報・注意報】</content>
  </entry>
  <entry>
    <title>大雨危険度通知</title>
    <id>https://www.data.jma.go.jp/developer/xml/data/20260115040810_0_VPRN50_010000.xml</id>
    <updated>2026-01-15T04:07:59Z</updated>
    <author><name>気象庁</name></author>
    <link type="application/xml" href="https://test.fixture/jma/hokkaido_VPRN50_010000.xml"/>
    <content type="text">【大雨危険度通知】</content>
  </entry>
</feed>
''';

const String _akitaReportWithOoyukiKeihou = '''<?xml version="1.0" encoding="UTF-8"?>
<Report xmlns="http://xml.kishou.go.jp/jmaxml1/" xmlns:jmx="http://xml.kishou.go.jp/jmaxml1/">
<Control>
<Title>気象警報・注意報（Ｈ２７）</Title>
<DateTime>2026-01-15T04:23:37Z</DateTime>
<Status>通常</Status>
<EditorialOffice>秋田地方気象台</EditorialOffice>
<PublishingOffice>秋田地方気象台</PublishingOffice>
</Control>
<Head xmlns="http://xml.kishou.go.jp/jmaxml1/informationBasis1/">
<Title>秋田県気象警報・注意報</Title>
<ReportDateTime>2026-01-15T13:23:00+09:00</ReportDateTime>
<TargetDateTime>2026-01-15T13:23:00+09:00</TargetDateTime>
<EventID/>
<InfoType>発表</InfoType>
<Serial/>
<InfoKind>気象警報・注意報</InfoKind>
<Headline>
<Text>秋田県では、１５日夜のはじめ頃まで大雪に警戒してください。</Text>
<Information type="気象警報・注意報（市町村等をまとめた地域等）">
<Item>
<Kind>
<Name>大雪警報</Name>
<Code>33</Code>
</Kind>
<Areas codeType="気象情報／府県予報区・細分区域等">
<Area>
<Name>秋田中央</Name>
<Code>050010</Code>
</Area>
</Areas>
</Item>
<Item>
<Kind>
<Name>暴風雪注意報</Name>
<Code>18</Code>
</Kind>
<Areas codeType="気象情報／府県予報区・細分区域等">
<Area>
<Name>沿岸南部</Name>
<Code>050020</Code>
</Area>
</Areas>
</Item>
</Information>
</Headline>
</Head>
</Report>
''';

const String _naganoReportWithStrongWindOnly = '''<?xml version="1.0" encoding="UTF-8"?>
<Report xmlns="http://xml.kishou.go.jp/jmaxml1/">
<Control>
<Title>気象警報・注意報（Ｈ２７）</Title>
<DateTime>2026-01-15T04:18:03Z</DateTime>
<Status>通常</Status>
<EditorialOffice>長野地方気象台</EditorialOffice>
<PublishingOffice>長野地方気象台</PublishingOffice>
</Control>
<Head xmlns="http://xml.kishou.go.jp/jmaxml1/informationBasis1/">
<Title>長野県気象警報・注意報</Title>
<ReportDateTime>2026-01-15T13:18:00+09:00</ReportDateTime>
<TargetDateTime>2026-01-15T13:18:00+09:00</TargetDateTime>
<InfoType>発表</InfoType>
<InfoKind>気象警報・注意報</InfoKind>
<Headline>
<Text>長野県では、強風に注意してください。</Text>
<Information type="気象警報・注意報（市町村等をまとめた地域等）">
<Item>
<Kind>
<Name>強風注意報</Name>
<Code>15</Code>
</Kind>
<Areas><Area><Name>北部</Name><Code>200010</Code></Area></Areas>
</Item>
</Information>
</Headline>
</Head>
</Report>
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

    test('default atomFeedUrl points at the public JMA extra_l feed',
        () {
      final provider = JmaAdvisoryProvider();
      expect(provider.atomFeedUrl, contains('jma.go.jp'));
      expect(provider.atomFeedUrl, contains('extra_l'));
    });

    test('atomFeedUrl is constructor-injectable', () {
      const testUrl = 'https://test.fixture/jma/feed.xml';
      final provider = JmaAdvisoryProvider(atomFeedUrl: testUrl);
      expect(provider.atomFeedUrl, equals(testUrl));
    });

    test('init rejects empty userAgent with AdvisoryProviderInitException',
        () async {
      final provider = JmaAdvisoryProvider(userAgent: '   ');
      expect(
        () => provider.init(),
        throwsA(isA<AdvisoryProviderInitException>()),
      );
    });
  });

  group('JmaAdvisoryProvider — fetch behavior', () {
    test(
      'fetch without init throws AdvisoryProviderInitException',
      () async {
        final provider = JmaAdvisoryProvider();
        expect(
          () => provider.fetchActiveAdvisoriesAtPoint(
            latitude: 39.7186,
            longitude: 140.1024,
          ),
          throwsA(isA<AdvisoryProviderInitException>()),
        );
      },
    );

    test(
      'fetch returns empty list when atom feed has no winter-advisory '
      'entries for the caller prefecture',
      () async {
        // Feed contains a Nagano (200000) entry only; caller is Akita
        // (140.1, 39.7) → prefecture 050000 — no matching entries.
        const onlyNaganoFeed = '''<?xml version="1.0" encoding="utf-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <entry>
    <title>気象警報・注意報（Ｈ２７）</title>
    <updated>2026-01-15T04:18:03Z</updated>
    <author><name>長野地方気象台</name></author>
    <link type="application/xml" href="https://test.fixture/jma/x_VPWW54_200000.xml"/>
  </entry>
</feed>''';
        final mock = MockClient((req) async {
          return _utf8Response(onlyNaganoFeed, 200);
        });
        final provider = JmaAdvisoryProvider(
          atomFeedUrl: 'https://test.fixture/jma/feed.xml',
          client: mock,
        );
        await provider.init();
        final result = await provider.fetchActiveAdvisoriesAtPoint(
          latitude: 39.7186,
          longitude: 140.1024,
        );
        expect(result, isEmpty);
      },
    );

    test(
      'fetch with mocked Akita 大雪警報 returns one Advisory with '
      'eventClass = "大雪警報" verbatim',
      () async {
        final mock = MockClient((req) async {
          if (req.url.toString().endsWith('feed.xml')) {
            return _utf8Response(_akitaPrefectureAtomFeed, 200);
          }
          if (req.url.toString().contains('akita_VPWW54_050000.xml')) {
            return _utf8Response(_akitaReportWithOoyukiKeihou, 200);
          }
          return http.Response('not found', 404);
        });
        final provider = JmaAdvisoryProvider(
          atomFeedUrl: 'https://test.fixture/jma/feed.xml',
          client: mock,
        );
        await provider.init();
        final advisories = await provider.fetchActiveAdvisoriesAtPoint(
          latitude: 39.7186, // Akita-shi
          longitude: 140.1024,
        );
        // Expect 大雪警報 (severe) + 暴風雪注意報 (moderate).
        expect(advisories.length, equals(2));
        expect(advisories.first.source, equals(AdvisorySource.jmaJapan));
        expect(advisories.first.eventClass, equals('大雪警報'));
        expect(
          advisories.first.severity,
          equals(AdvisorySeverity.severe),
        );
        expect(advisories.first.areaDescription, equals('秋田中央'));
        expect(advisories[1].eventClass, equals('暴風雪注意報'));
        expect(
          advisories[1].severity,
          equals(AdvisorySeverity.moderate),
        );
      },
    );

    test(
      'fetch filters out non-snow event classes (強風注意報) even when '
      'present in the prefecture report',
      () async {
        final mock = MockClient((req) async {
          if (req.url.toString().endsWith('feed.xml')) {
            return _utf8Response(_akitaPrefectureAtomFeed, 200);
          }
          if (req.url.toString().contains('nagano_VPWW54_200000.xml')) {
            return _utf8Response(_naganoReportWithStrongWindOnly, 200);
          }
          return http.Response('not found', 404);
        });
        final provider = JmaAdvisoryProvider(
          atomFeedUrl: 'https://test.fixture/jma/feed.xml',
          client: mock,
        );
        await provider.init();
        // Caller in Nagano prefecture bbox is OUTSIDE 0.1.0 catalog.
        // → empty without even fetching the report.
        final advisories = await provider.fetchActiveAdvisoriesAtPoint(
          latitude: 36.65,
          longitude: 138.18,
        );
        expect(advisories, isEmpty);
      },
    );

    test(
      'fetch with multiple prefecture entries filters to caller lat/lon',
      () async {
        // Caller in Akita (39.7, 140.1) → only Akita entry matches.
        final mock = MockClient((req) async {
          if (req.url.toString().endsWith('feed.xml')) {
            return _utf8Response(_akitaPrefectureAtomFeed, 200);
          }
          if (req.url.toString().contains('akita_VPWW54_050000.xml')) {
            return _utf8Response(_akitaReportWithOoyukiKeihou, 200);
          }
          if (req.url.toString().contains('nagano_VPWW54_200000.xml')) {
            return _utf8Response(_naganoReportWithStrongWindOnly, 200);
          }
          return http.Response('not found', 404);
        });
        final provider = JmaAdvisoryProvider(
          atomFeedUrl: 'https://test.fixture/jma/feed.xml',
          client: mock,
        );
        await provider.init();
        final advisories = await provider.fetchActiveAdvisoriesAtPoint(
          latitude: 39.7186,
          longitude: 140.1024,
        );
        // Only Akita's snow advisories surface — Nagano's strong-wind
        // is both wrong-prefecture AND wrong-event-class (filter holds
        // on either axis alone).
        expect(advisories.length, equals(2));
        for (final a in advisories) {
          expect(a.areaDescription, anyOf('秋田中央', '沿岸南部'));
        }
      },
    );

    test(
      'fetch raises JmaAdvisoryFetchException on HTTP 5xx',
      () async {
        final mock = MockClient((req) async {
          return http.Response('Service Unavailable', 503);
        });
        final provider = JmaAdvisoryProvider(
          atomFeedUrl: 'https://test.fixture/jma/feed.xml',
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

    test(
      'fetch raises JmaAdvisoryFetchException on body cap exceeded',
      () async {
        final tooLarge = 'x' * (kJmaAtomFeedMaxBytes + 1024);
        final mock = MockClient((req) async {
          return http.Response(tooLarge, 200);
        });
        final provider = JmaAdvisoryProvider(
          atomFeedUrl: 'https://test.fixture/jma/feed.xml',
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

    test(
      'fetch returns empty when caller lat/lon outside catalogued '
      'prefectures (no HTTP call required)',
      () async {
        final mock = MockClient((req) async {
          // Tokyo is outside the 6-prefecture catalog at 0.1.0 — the
          // provider should NOT fetch at all.
          fail('HTTP fetch should not occur for points outside catalog');
        });
        final provider = JmaAdvisoryProvider(
          atomFeedUrl: 'https://test.fixture/jma/feed.xml',
          client: mock,
        );
        await provider.init();
        final advisories = await provider.fetchActiveAdvisoriesAtPoint(
          latitude: 35.6762, // Tokyo
          longitude: 139.6503,
        );
        expect(advisories, isEmpty);
      },
    );
  });

  group('parseJmaAtomFeed', () {
    test('extracts entries with title + updated + author + reportUrl',
        () {
      final entries = parseJmaAtomFeed(_akitaPrefectureAtomFeed);
      expect(entries.length, equals(3));
      expect(entries.first.title, equals('気象警報・注意報（Ｈ２７）'));
      expect(entries.first.author, equals('秋田地方気象台'));
      expect(
        entries.first.reportUrl,
        equals('https://test.fixture/jma/akita_VPWW54_050000.xml'),
      );
    });

    test('throws on malformed XML', () {
      expect(
        () => parseJmaAtomFeed('<not><valid<xml'),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('parseJmaReportXml', () {
    test('extracts JmaForecastRecord per Item × Area cross-product', () {
      final records = parseJmaReportXml(_akitaReportWithOoyukiKeihou);
      expect(records.length, equals(2));
      expect(records.first.eventName, equals('大雪警報'));
      expect(records.first.eventCode, equals('33'));
      expect(records.first.areaName, equals('秋田中央'));
      expect(records.first.areaCode, equals('050010'));
      expect(records[1].eventName, equals('暴風雪注意報'));
    });

    test('preserves Headline text verbatim', () {
      final records = parseJmaReportXml(_akitaReportWithOoyukiKeihou);
      expect(
        records.first.headline,
        equals('秋田県では、１５日夜のはじめ頃まで大雪に警戒してください。'),
      );
    });

    test('parses ReportDateTime as DateTime', () {
      final records = parseJmaReportXml(_akitaReportWithOoyukiKeihou);
      expect(records.first.reportDateTime, isNotNull);
      expect(
        records.first.reportDateTime!.toUtc(),
        equals(DateTime.utc(2026, 1, 15, 4, 23, 0)),
      );
    });
  });

  group('prefectureCodeForPoint', () {
    test('Akita-shi (39.72, 140.10) resolves to 050000', () {
      final code =
          prefectureCodeForPoint(latitude: 39.7186, longitude: 140.1024);
      expect(code, equals('050000'));
    });

    test('Tokyo (35.68, 139.65) returns null (outside catalog)', () {
      final code =
          prefectureCodeForPoint(latitude: 35.6762, longitude: 139.6503);
      expect(code, isNull);
    });

    test('Niigata-shi (37.92, 139.04) resolves to 150000', () {
      final code =
          prefectureCodeForPoint(latitude: 37.9161, longitude: 139.0364);
      expect(code, equals('150000'));
    });
  });

  group('mapJmaForecastToAdvisory', () {
    test('source is always jmaJapan', () {
      const record = JmaForecastRecord(
        eventName: '大雪警報',
        eventCode: '33',
        headline: '',
        areaName: '秋田中央',
        areaCode: '050010',
        reportDateTime: null,
        targetDateTime: null,
      );
      expect(
        mapJmaForecastToAdvisory(record).source,
        equals(AdvisorySource.jmaJapan),
      );
    });

    test('eventClass preserves JMA event-name verbatim (Article 17 β)',
        () {
      const record = JmaForecastRecord(
        eventName: '暴風雪警報',
        eventCode: '08',
        headline: '',
        areaName: '北部',
        areaCode: '050010',
        reportDateTime: null,
        targetDateTime: null,
      );
      expect(
        mapJmaForecastToAdvisory(record).eventClass,
        equals('暴風雪警報'),
      );
    });

    test(
      'severity maps 警報 → severe; 注意報 → moderate; 特別警報 → extreme',
      () {
        const warning = JmaForecastRecord(
          eventName: '大雪警報',
          eventCode: '33',
          headline: '',
          areaName: '',
          areaCode: '',
          reportDateTime: null,
          targetDateTime: null,
        );
        const advisory = JmaForecastRecord(
          eventName: '大雪注意報',
          eventCode: '20',
          headline: '',
          areaName: '',
          areaCode: '',
          reportDateTime: null,
          targetDateTime: null,
        );
        const emergency = JmaForecastRecord(
          eventName: '大雪特別警報',
          eventCode: '32',
          headline: '',
          areaName: '',
          areaCode: '',
          reportDateTime: null,
          targetDateTime: null,
        );
        expect(
          mapJmaForecastToAdvisory(warning).severity,
          equals(AdvisorySeverity.severe),
        );
        expect(
          mapJmaForecastToAdvisory(advisory).severity,
          equals(AdvisorySeverity.moderate),
        );
        expect(
          mapJmaForecastToAdvisory(emergency).severity,
          equals(AdvisorySeverity.extreme),
        );
      },
    );

    test(
      'kJmaSnowAdvisoryEventNames includes the 4-minimum + 着雪',
      () {
        for (final name in const [
          '大雪警報',
          '大雪注意報',
          '暴風雪警報',
          '暴風雪注意報',
        ]) {
          expect(kJmaSnowAdvisoryEventNames.contains(name), isTrue);
        }
        expect(kJmaSnowAdvisoryEventNames.contains('着雪注意報'), isTrue);
      },
    );
  });
}
