/// Unit tests for the pre-trip live-forecast orchestrator.
///
/// Network IO is injected as STUB closures — no real sockets, no XML fixtures,
/// no MockClient. The honesty-critical case (T3) proves a JMA-leg failure can
/// NEVER render as an authoritative "all clear": it keeps the MET base, adds no
/// road band, and reports the `japanJmaFailed` status the caption discloses.
library;

import 'package:condition_aggregator/condition_aggregator.dart';
import 'package:condition_aggregator_jma/condition_aggregator_jma.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pretrip_decision_advisor/pretrip_decision_advisor.dart';
import 'package:sngnav_snow_scene/providers/pretrip_live_forecast.dart';

void main() {
  // Akita is a JMA-catalogued snow-zone prefecture (050000); Nagoya is south of
  // the snow belt → the global MET Norway case.
  const akitaLat = 39.72;
  const akitaLon = 140.10;
  const nagoyaLat = 35.1709;
  const nagoyaLon = 136.8815;

  final now = DateTime(2026, 1, 1, 7, 0);
  const window = Duration(minutes: 30);

  // Temp-only base: a 07:00 + 08:00 slot, road condition + visibility unset
  // (exactly what the MET Norway compact product delivers for Japan).
  WeatherForecast tempOnlyBase() => WeatherForecast(
        issuedAt: DateTime(2026, 1, 1, 6, 0),
        hourly: [
          HourlyForecast(
            hour: DateTime(2026, 1, 1, 7),
            tempCelsius: -2,
            precipitationMmPerHour: 0.5,
            visibilityMeters: null,
            estimatedRoadCondition: null,
          ),
          HourlyForecast(
            hour: DateTime(2026, 1, 1, 8),
            tempCelsius: -2,
            precipitationMmPerHour: 0.5,
            visibilityMeters: null,
            estimatedRoadCondition: null,
          ),
        ],
      );

  Advisory adv(String eventClass) => Advisory(
        source: AdvisorySource.jmaJapan,
        eventClass: eventClass,
        severity: AdvisorySeverity.severe,
        certainty: AdvisoryCertainty.observed,
        urgency: AdvisoryUrgency.immediate,
        areaDescription: '秋田県',
        effective: null,
        expires: null,
        headline: eventClass,
        description: eventClass,
      );

  MetForecastFetch metStub(WeatherForecast? f) => () async => f;
  MetForecastFetch metThrows() => () async => throw Exception('net down');
  JmaAdvisoryFetch jmaStub(List<Advisory> a) => () async => a;

  HourlyForecast slotAt(WeatherForecast f, DateTime hour) =>
      f.hourly.firstWhere((s) => s.hour == hour);

  test('T1 merged: Akita + heavy-snow warning → packedSnow in window', () async {
    final base = tempOnlyBase();
    final result = await resolvePretripLiveForecast(
      latitude: akitaLat,
      longitude: akitaLon,
      now: now,
      window: window,
      fetchMetForecast: metStub(base),
      fetchJmaAdvisories: jmaStub([adv('大雪警報')]),
    );
    expect(result.status, PretripLiveStatus.japanJmaMerged);
    expect(result.jmaEventName, '大雪警報');
    expect(result.prefectureCode, '050000');
    final depSlot = slotAt(result.forecast!, DateTime(2026, 1, 1, 7));
    expect(depSlot.estimatedRoadCondition, RoadConditionEstimate.packedSnow);
  });

  test('T2 ice: Akita + snow-accretion warning → ice in window', () async {
    final result = await resolvePretripLiveForecast(
      latitude: akitaLat,
      longitude: akitaLon,
      now: now,
      window: window,
      fetchMetForecast: metStub(tempOnlyBase()),
      fetchJmaAdvisories: jmaStub([adv('着雪注意報')]),
    );
    expect(result.status, PretripLiveStatus.japanJmaMerged);
    final depSlot = slotAt(result.forecast!, DateTime(2026, 1, 1, 7));
    expect(depSlot.estimatedRoadCondition, RoadConditionEstimate.ice);
  });

  test('T3 JMA-fail (safety): keep base, NO band, honest status', () async {
    final base = tempOnlyBase();
    final result = await resolvePretripLiveForecast(
      latitude: akitaLat,
      longitude: akitaLon,
      now: now,
      window: window,
      fetchMetForecast: metStub(base),
      fetchJmaAdvisories: () async =>
          throw const JmaAdvisoryFetchException('x'),
    );
    expect(result.status, PretripLiveStatus.japanJmaFailed);
    expect(result.jmaEventName, isNull);
    expect(result.prefectureCode, '050000');
    // Road conditions IDENTICAL to base — no JMA band added.
    final got = result.forecast!.hourly
        .map((s) => s.estimatedRoadCondition)
        .toList();
    final want =
        base.hourly.map((s) => s.estimatedRoadCondition).toList();
    expect(got, want);
    expect(got.every((c) => c == null), isTrue);
  });

  test('T4 no-advisory: empty list → no band, base unchanged', () async {
    final base = tempOnlyBase();
    final result = await resolvePretripLiveForecast(
      latitude: akitaLat,
      longitude: akitaLon,
      now: now,
      window: window,
      fetchMetForecast: metStub(base),
      fetchJmaAdvisories: jmaStub(const []),
    );
    expect(result.status, PretripLiveStatus.japanJmaNoAdvisory);
    expect(result.prefectureCode, '050000');
    expect(
      result.forecast!.hourly.map((s) => s.estimatedRoadCondition),
      base.hourly.map((s) => s.estimatedRoadCondition),
    );
  });

  test('T5 non-snow event: rain warning rejected → no-advisory', () async {
    final base = tempOnlyBase();
    final result = await resolvePretripLiveForecast(
      latitude: akitaLat,
      longitude: akitaLon,
      now: now,
      window: window,
      fetchMetForecast: metStub(base),
      fetchJmaAdvisories: jmaStub([adv('大雨警報')]),
    );
    expect(result.status, PretripLiveStatus.japanJmaNoAdvisory);
    expect(
      result.forecast!.hourly.map((s) => s.estimatedRoadCondition),
      base.hourly.map((s) => s.estimatedRoadCondition),
    );
  });

  test('T6 global: Nagoya → MET only, JMA leg NEVER invoked', () async {
    final base = tempOnlyBase();
    var called = false;
    final result = await resolvePretripLiveForecast(
      latitude: nagoyaLat,
      longitude: nagoyaLon,
      now: now,
      window: window,
      fetchMetForecast: metStub(base),
      fetchJmaAdvisories: () async {
        called = true;
        return const [];
      },
    );
    expect(result.status, PretripLiveStatus.metNorway);
    expect(called, isFalse);
    expect(result.forecast, base);
  });

  test('T7 offline: MET null/throws → metNorwayUnavailable, JMA never invoked',
      () async {
    var called = false;
    JmaAdvisoryFetch guard() => () async {
          called = true;
          return const [];
        };

    final r1 = await resolvePretripLiveForecast(
      latitude: akitaLat,
      longitude: akitaLon,
      now: now,
      window: window,
      fetchMetForecast: metStub(null),
      fetchJmaAdvisories: guard(),
    );
    expect(r1.forecast, isNull);
    expect(r1.status, PretripLiveStatus.metNorwayUnavailable);

    final r2 = await resolvePretripLiveForecast(
      latitude: akitaLat,
      longitude: akitaLon,
      now: now,
      window: window,
      fetchMetForecast: metThrows(),
      fetchJmaAdvisories: guard(),
    );
    expect(r2.forecast, isNull);
    expect(r2.status, PretripLiveStatus.metNorwayUnavailable);
    expect(called, isFalse);
  });

  test('T8 never-fabricate-visibility: merged keeps every base vis', () async {
    final base = tempOnlyBase();
    final result = await resolvePretripLiveForecast(
      latitude: akitaLat,
      longitude: akitaLon,
      now: now,
      window: window,
      fetchMetForecast: metStub(base),
      fetchJmaAdvisories: jmaStub([adv('大雪警報')]),
    );
    final merged = result.forecast!.hourly;
    for (var i = 0; i < merged.length; i++) {
      expect(merged[i].visibilityMeters, base.hourly[i].visibilityMeters);
    }
  });

  test('T9 caption strings: exact arms, UNAVAILABLE token, no CJK', () {
    // metNorway arm — byte-equal to the legacy main.dart literal.
    final metCap = pretripLiveSourceCaption(
      status: PretripLiveStatus.metNorway,
      latitude: nagoyaLat,
      longitude: nagoyaLon,
    );
    final legacy = 'LIVE forecast — data: MET Norway (CC BY 4.0), '
        'lat $nagoyaLat lon $nagoyaLon. '
        'No visibility/surface data in this product — hazard signal from '
        'temperature + precipitation only.';
    expect(metCap, legacy);

    final mergedCap = pretripLiveSourceCaption(
      status: PretripLiveStatus.japanJmaMerged,
      latitude: akitaLat,
      longitude: akitaLon,
      prefectureCode: '050000',
      eventGloss: 'heavy-snow',
    );
    expect(
      mergedCap,
      'LIVE forecast — base: MET Norway (CC BY 4.0), '
      'lat $akitaLat lon $akitaLon; departure-window road condition from '
      'OFFICIAL JMA heavy-snow warning '
      '(prefecture 050000) — source: Japan '
      'Meteorological Agency. No visibility number is implied by the '
      'warning.',
    );

    final noAdvCap = pretripLiveSourceCaption(
      status: PretripLiveStatus.japanJmaNoAdvisory,
      latitude: akitaLat,
      longitude: akitaLon,
      prefectureCode: '050000',
    );
    expect(
      noAdvCap,
      'LIVE forecast — data: MET Norway (CC BY 4.0), '
      'lat $akitaLat lon $akitaLon. JMA checked '
      '(prefecture 050000, Japan Meteorological Agency): '
      'no active winter warning. No visibility/surface data in this '
      'product — hazard signal from temperature + precipitation only.',
    );

    final failCap = pretripLiveSourceCaption(
      status: PretripLiveStatus.japanJmaFailed,
      latitude: akitaLat,
      longitude: akitaLon,
      prefectureCode: '050000',
    );
    expect(failCap.contains('UNAVAILABLE'), isTrue);

    // Card legibility lock: NO CJK code points in any caption (DejaVuSans /
    // card font has no CJK glyphs; verbatim JP lives only in the data layer).
    for (final cap in [metCap, mergedCap, noAdvCap, failCap]) {
      for (final rune in cap.runes) {
        expect(rune <= 0x3000, isTrue,
            reason: 'CJK code point U+${rune.toRadixString(16)} in: $cap');
      }
    }
  });

  test('T10 JA caption arms: exact approved strings + verbatim numbers', () {
    // The English default is byte-identical to passing lang:'en' explicitly,
    // and unchanged from the legacy literal (the en arms must not move).
    expect(
      pretripLiveSourceCaption(
        status: PretripLiveStatus.metNorway,
        latitude: nagoyaLat,
        longitude: nagoyaLon,
        lang: 'en',
      ),
      pretripLiveSourceCaption(
        status: PretripLiveStatus.metNorway,
        latitude: nagoyaLat,
        longitude: nagoyaLon,
      ),
    );

    // metNorway ja, no measured visibility ⇒ のみ ("only") present.
    expect(
      pretripLiveSourceCaption(
        status: PretripLiveStatus.metNorway,
        latitude: nagoyaLat,
        longitude: nagoyaLon,
        lang: 'ja',
      ),
      'ライブ予報 — データ:MET Norway (CC BY 4.0)、'
      '緯度 $nagoyaLat 経度 $nagoyaLon。'
      'この予報には視程・路面データはありません — '
      '危険の判断材料は気温と降水のみです。',
    );

    // metNorway ja WITH a measured-visibility clause ⇒ のみ DROPS, exactly as
    // the source ${visCaption.isEmpty ? 'のみ' : ''} conditional dictates.
    final visJa = pretripMeasuredVisibilityCaption(
      meters: 80,
      stationName: '青森空港',
      km: '45',
      attribution: 'Japan Meteorological Agency / AMeDAS (気象庁)',
      lang: 'ja',
    );
    final metWithVis = pretripLiveSourceCaption(
      status: PretripLiveStatus.metNorway,
      latitude: nagoyaLat,
      longitude: nagoyaLon,
      visCaption: visJa,
      lang: 'ja',
    );
    expect(metWithVis.contains('気温と降水のみです'), isFalse);
    expect(metWithVis.contains('気温と降水です。'), isTrue);
    expect(metWithVis.endsWith(visJa), isTrue);

    // japanJmaMerged ja — VERBATIM JMA classification relayed (warning stays a
    // warning; never softened/escalated).
    expect(
      pretripLiveSourceCaption(
        status: PretripLiveStatus.japanJmaMerged,
        latitude: akitaLat,
        longitude: akitaLon,
        prefectureCode: '050000',
        jmaEventName: '大雪警報',
        lang: 'ja',
      ),
      'ライブ予報 — ベース:MET Norway (CC BY 4.0)、'
      '緯度 $akitaLat 経度 $akitaLon。'
      '出発時間帯の路面状況は気象庁の正式な大雪警報'
      '(都道府県 050000)に基づきます — 出典:気象庁。'
      'この警報・注意報からは視程の数値は示されません。',
    );

    // hazard-direction lock: an ADVISORY-class event stays an advisory in JA
    // (着雪注意報 must NOT escalate to 着雪警報).
    final advCap = pretripLiveSourceCaption(
      status: PretripLiveStatus.japanJmaMerged,
      latitude: akitaLat,
      longitude: akitaLon,
      prefectureCode: '050000',
      jmaEventName: '着雪注意報',
      lang: 'ja',
    );
    expect(advCap.contains('正式な着雪注意報('), isTrue);
    expect(advCap.contains('着雪警報'), isFalse);

    // merged ja with a null event name ⇒ the 冬季の警報 fallback.
    expect(
      pretripLiveSourceCaption(
        status: PretripLiveStatus.japanJmaMerged,
        latitude: akitaLat,
        longitude: akitaLon,
        prefectureCode: '050000',
        lang: 'ja',
      ).contains('正式な冬季の警報('),
      isTrue,
    );

    // japanJmaNoAdvisory ja — the all-clear is held to WARNINGS only (it must
    // NOT widen to "no warning OR advisory", which would hide an active 注意報).
    final noAdvJa = pretripLiveSourceCaption(
      status: PretripLiveStatus.japanJmaNoAdvisory,
      latitude: akitaLat,
      longitude: akitaLon,
      prefectureCode: '050000',
      lang: 'ja',
    );
    expect(
      noAdvJa,
      'ライブ予報 — データ:MET Norway (CC BY 4.0)、'
      '緯度 $akitaLat 経度 $akitaLon。'
      '気象庁を確認(都道府県 050000、気象庁):'
      '発表中の冬季の警報はありません。'
      'この予報には視程・路面データはありません — '
      '危険の判断材料は気温と降水のみです。',
    );
    expect(noAdvJa.contains('注意報はありません'), isFalse);

    // japanJmaFailed ja — the SAFETY-CRITICAL caveat preserved at full strength
    // (both halves: 可能性があり + ここには反映されていません; 警報 not downgraded).
    final failJa = pretripLiveSourceCaption(
      status: PretripLiveStatus.japanJmaFailed,
      latitude: akitaLat,
      longitude: akitaLon,
      prefectureCode: '050000',
      lang: 'ja',
    );
    expect(
      failJa,
      'ライブ予報 — データ:MET Norway (CC BY 4.0)、'
      '緯度 $akitaLat 経度 $akitaLon。'
      '気象庁の冬季警報の確認ができませんでした(取得失敗) — '
      '気温と降水のみに基づくブリーフィングです。'
      '実際には正式な雪の警報が発表されている可能性があり、'
      'ここには反映されていません。',
    );

    // measured-visibility ja — verbatim number + station + 0-decimal km + the
    // canonical (never-translated) attribution token.
    expect(
      visJa,
      ' 出発時間帯の計測視程:80 m(青森空港、45 km先) — '
      'データ:Japan Meteorological Agency / AMeDAS (気象庁)。',
    );
    // measured-visibility en stays byte-identical to the legacy clause.
    expect(
      pretripMeasuredVisibilityCaption(
        meters: 80,
        stationName: 'vt1_Espoo_Nupuri',
        km: '3',
        attribution: 'Fintraffic / digitraffic.fi (CC BY 4.0)',
      ),
      ' Departure-hour visibility MEASURED: 80 m at vt1_Espoo_Nupuri '
      '(3 km away) — data: Fintraffic / digitraffic.fi (CC BY 4.0).',
    );

    // verbatim-number lock: the ja arms carry lat/lon + the measured figure
    // through unchanged.
    expect(advCap.contains('緯度 $akitaLat 経度 $akitaLon'), isTrue);
    expect(failJa.contains('緯度 $akitaLat 経度 $akitaLon'), isTrue);
    expect(metWithVis.contains('緯度 $nagoyaLat 経度 $nagoyaLon'), isTrue);
    expect(visJa.contains('80 m(青森空港、45 km先)'), isTrue);
  });
}
