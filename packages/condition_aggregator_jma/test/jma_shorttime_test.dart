import 'dart:io';

import 'package:condition_aggregator/condition_aggregator.dart';
import 'package:condition_aggregator_jma/condition_aggregator_jma.dart';
import 'package:test/test.dart';

const _f = 'test/fixtures/';
const _oaSingle =
    '${_f}jma_shorttime_VPOA50_130000_single.frozen_2026-08-22.xml';
const _oaMulti =
    '${_f}jma_shorttime_VPOA50_130000_multiarea.frozen_2026-08-22.xml';
const _oaFuku =
    '${_f}jma_shorttime_VPOA50_070000_fukushima.frozen_2026-08-20.xml';
const _bsRain = '${_f}jma_shorttime_VPBS50_130000_rain.frozen_2026-08-22.xml';
const _bsSnow = '${_f}jma_shorttime_VPBS50_snow.JMA_OFFICIAL_SAMPLE.xml';

String _read(String p) => File(p).readAsStringSync();

void main() {
  group('fixture immutability pins', () {
    test('every fixture is byte-exact as retrieved', () {
      expect(File(_oaSingle).lengthSync(), equals(1724));
      expect(File(_oaMulti).lengthSync(), equals(1773));
      expect(File(_oaFuku).lengthSync(), equals(1736));
      expect(File(_bsRain).lengthSync(), equals(2129));
      expect(File(_bsSnow).lengthSync(), equals(2183));
    });
  });

  group('legacy VPOA50 — typed by InfoKind', () {
    test('parses the real Toshima-ku event', () {
      final r = parseJmaShortTimeReport(_read(_oaSingle));
      expect(r.product, equals(JmaShortTimeProduct.recordShortRain));
      expect(r.family, equals(JmaBulletinFamily.legacy));
      expect(r.areaCode, equals('130000'));
      expect(r.areaCodeKind, equals(JmaAreaCodeKind.prefectureForecastArea));
      expect(
        r.measurement,
        isNull,
        reason: 'the legacy bulletin carries no typed number',
      );
    });

    test('NEGATIVE CONTROL — identity survives TOTAL destruction of the '
        'Japanese prose. If it does not, the integration is prose-matching '
        'and will rot silently.', () {
      final wrecked = _read(_oaSingle).replaceAll(
        RegExp(r'<Text>.*?</Text>', dotAll: true),
        '<Text>XXXX</Text>',
      );
      expect(wrecked, isNot(contains('豊島区')));
      final r = parseJmaShortTimeReport(wrecked);
      expect(r.product, equals(JmaShortTimeProduct.recordShortRain));
      expect(r.areaCode, equals('130000'));
    });

    test('Fukushima instance parses', () {
      expect(
        parseJmaShortTimeReport(_read(_oaFuku)).areaCode,
        equals('070000'),
      );
    });
  });

  group('current VPBS50 — typed by Condition, NOT by the shared InfoKind', () {
    test('rain twin: Condition=記録雨, typed 100mm at a named municipality', () {
      final r = parseJmaShortTimeReport(_read(_bsRain));
      expect(r.product, equals(JmaShortTimeProduct.recordShortRain));
      expect(r.family, equals(JmaBulletinFamily.bosaiSokuho));
      expect(r.areaCode, equals('130010'));
      expect(r.areaCodeKind, equals(JmaAreaCodeKind.primarySubdivision));
      final m = r.measurement!;
      expect(m.value, equals(100));
      expect(m.unit, equals('mm'));
      expect(m.window, equals('前１時間解析雨量'));
    });

    test('snow sample: Condition=短時間大雪, typed 37cm at an AMeDAS station', () {
      final r = parseJmaShortTimeReport(_read(_bsSnow));
      expect(r.product, equals(JmaShortTimeProduct.shortHeavySnow));
      expect(r.family, equals(JmaBulletinFamily.bosaiSokuho));
      final m = r.measurement!;
      expect(m.value, equals(37));
      expect(m.unit, equals('cm'));
      expect(m.window, equals('６時間の降雪深さ'));
      expect(m.stationName, equals('長浜市余呉町柳ケ瀬'));
      expect(r.headline, contains('深刻な交通障害'));
    });

    test('NEGATIVE CONTROL — a VPBS50 whose Condition is a DIFFERENT sub-type '
        'is REFUSED. Control/Title (府県気象防災速報) and InfoKind '
        '(気象解説情報) are identical across 記録雨 / 短時間大雪 / '
        '線状降水帯発生, so keying on either would silently accept the wrong '
        'product.', () {
      final other = _read(_bsRain).replaceAll(
        '<Condition>記録雨</Condition>',
        '<Condition>線状降水帯発生</Condition>',
      );
      expect(other, contains('<InfoKind>気象解説情報</InfoKind>'));
      expect(
        () => parseJmaShortTimeReport(other),
        throwsA(isA<JmaShortTimeParseException>()),
      );
    });
  });

  group('the dual-publish double-count', () {
    test('NEGATIVE CONTROL — the SAME event published as VPOA50 and VPBS50 at '
        'the same second is TWO records until deduped. A whole-feed consumer '
        'without this reports every short-time event twice.', () {
      final a = parseJmaShortTimeReport(_read(_oaSingle));
      final b = parseJmaShortTimeReport(_read(_bsRain));
      expect(a.eventId, equals('JPTK202608221709_202608221727'));
      expect(b.eventId, equals('KJPTK202608221709_202608221727'));
      expect(a.eventId, isNot(equals(b.eventId)));
      expect(<JmaShortTimeRecord>[a, b].length, equals(2));

      final deduped = dedupeShortTimeRecords(<JmaShortTimeRecord>[a, b]);
      expect(deduped.length, equals(1));
      expect(
        deduped.single.family,
        equals(JmaBulletinFamily.bosaiSokuho),
        reason: 'keep the twin that carries the typed measurement',
      );
      expect(deduped.single.measurement, isNotNull);
    });

    test('dedupKey normalizes the K-prefix', () {
      final a = parseJmaShortTimeReport(_read(_oaSingle));
      final b = parseJmaShortTimeReport(_read(_bsRain));
      expect(a.dedupKey, equals(b.dedupKey));
    });

    test('genuinely different events do NOT collapse', () {
      final a = parseJmaShortTimeReport(_read(_oaSingle));
      final c = parseJmaShortTimeReport(_read(_oaFuku));
      expect(a.dedupKey, isNot(equals(c.dedupKey)));
      expect(
        dedupeShortTimeRecords(<JmaShortTimeRecord>[a, c]).length,
        equals(2),
      );
    });
  });

  group('severity is explicit, never suffix-derived', () {
    test(
      'NEGATIVE CONTROL — both products end in 情報, not 警報. A '
      'suffix-derived grade returns unknown, BELOW isHighImpact: JMA\'s '
      'most urgent products would reach an integrator as filterable noise.',
      () {
        for (final p in <String>[_oaSingle, _bsRain, _bsSnow]) {
          final a = mapJmaShortTimeToAdvisory(
            parseJmaShortTimeReport(_read(p)),
          );
          expect(a.severity, equals(AdvisorySeverity.extreme), reason: p);
          expect(a.isHighImpact, isTrue, reason: p);
          expect(a.eventClass, isNot(endsWith('警報')));
        }
      },
    );

    test('certainty/urgency are observed+immediate', () {
      final a = mapJmaShortTimeToAdvisory(
        parseJmaShortTimeReport(_read(_bsSnow)),
      );
      expect(a.certainty, equals(AdvisoryCertainty.observed));
      expect(a.urgency, equals(AdvisoryUrgency.immediate));
      expect(a.eventClass, equals('顕著な大雪に関する気象情報'));
    });

    test('the verbatim headline is relayed, never mined', () {
      final a = mapJmaShortTimeToAdvisory(
        parseJmaShortTimeReport(_read(_oaSingle)),
      );
      expect(a.headline, contains('豊島区付近で１時間に約１００ミリ'));
    });
  });

  group('honest absence', () {
    test('NEGATIVE CONTROL — malformed XML THROWS. Returning [] would be '
        'byte-identical to a verified all-clear.', () {
      expect(
        () => parseJmaShortTimeReport('<Report><broken'),
        throwsA(isA<JmaShortTimeParseException>()),
      );
    });

    test('a warning bulletin is refused, not silently mapped', () {
      const other =
          '<?xml version="1.0" encoding="UTF-8"?><Report><Head>'
          '<InfoKind>気象警報・注意報</InfoKind><InfoType>発表</InfoType>'
          '</Head></Report>';
      expect(
        () => parseJmaShortTimeReport(other),
        throwsA(isA<JmaShortTimeParseException>()),
      );
    });

    test('the LEGACY snow bulletin (VPFJ50) is refused — its identity is prose '
        'only (InfoKind is 同一現象用平文情報 for every phenomenon), so '
        'accepting it would mean headline matching', () {
      const vpfj50 =
          '<?xml version="1.0" encoding="UTF-8"?><Report>'
          '<Control><Title>府県気象情報</Title></Control><Head>'
          '<Title>顕著な大雪に関する新潟県気象情報</Title>'
          '<InfoKind>同一現象用平文情報</InfoKind><InfoType>発表</InfoType>'
          '<ReportDateTime>2021-01-08T16:22:00+09:00</ReportDateTime>'
          '</Head></Report>';
      expect(
        () => parseJmaShortTimeReport(vpfj50),
        throwsA(isA<JmaShortTimeParseException>()),
      );
    });

    test('a document missing Area/Code is refused rather than invented', () {
      final noArea = _read(
        _oaSingle,
      ).replaceAll(RegExp(r'<Area>.*?</Area>', dotAll: true), '');
      expect(
        () => parseJmaShortTimeReport(noArea),
        throwsA(isA<JmaShortTimeParseException>()),
      );
    });

    test('the unavailable notice can never be graded as a hazard', () {
      final n = buildShortTimeUnavailableNotice(areaLabel: '秋田県');
      expect(n.severity, equals(AdvisorySeverity.minor));
      expect(n.isHighImpact, isFalse);
      expect(n.eventClass, isNot(endsWith('警報')));
      expect(n.eventClass, isNot(endsWith('注意報')));
      expect(n.effective, isNull);
      expect(n.headline, contains('秋田県'));
    });
  });

  group('withdrawal', () {
    test('取消 is parsed and marked NOT active', () {
      final c = _read(
        _oaSingle,
      ).replaceAll('<InfoType>発表</InfoType>', '<InfoType>取消</InfoType>');
      expect(parseJmaShortTimeReport(c).isActive, isFalse);
    });

    test('発表 is active', () {
      expect(parseJmaShortTimeReport(_read(_oaMulti)).isActive, isTrue);
    });
  });

  group(
    'the snow tier does NOT reach this adapter\'s northern prefectures',
    () {
      test('Akita — HER mother\'s prefecture — is NOT a 短時間大雪 issuance area, '
          'per JMA introduction_bosaisokuho.pdf R8.2. Recorded so no one '
          'justifies this tier on HER.', () {
        expect(kJmaShortSnowIssuedPrefecturesJa.contains('秋田県'), isFalse);
        expect(kJmaShortSnowIssuedPrefecturesJa.contains('北海道'), isFalse);
        expect(kJmaShortSnowIssuedPrefecturesJa.contains('青森県'), isFalse);
        expect(kJmaShortSnowIssuedPrefecturesJa.contains('岩手県'), isFalse);
      });

      test('the overlap with this package\'s catalogue is 山形 and 新潟 only', () {
        final ours = kJmaPrefectureNamesJa.values.toSet();
        final overlap = ours.intersection(kJmaShortSnowIssuedPrefecturesJa);
        expect(overlap, equals(<String>{'山形県', '新潟県'}));
        expect(overlap.length, equals(2));
        expect(ours.length, equals(13));
      });
    },
  );

  group('every registered product has an event class and a severity', () {
    test('no product can fall through to a default', () {
      for (final p in JmaShortTimeProduct.values) {
        expect(kJmaShortTimeEventClass.containsKey(p), isTrue, reason: '$p');
        expect(kJmaShortTimeSeverity.containsKey(p), isTrue, reason: '$p');
      }
    });
  });
}
