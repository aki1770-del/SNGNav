/// Pre-trip live-forecast orchestrator: picks the authoritative source BY
/// LOCATION (MET Norway global vs JMA Japan snow-zone) using the shipped
/// forecast_case selector, fetches + merges, and reports an HONEST per-case
/// status. Network IO is injected as closures so this file is unit-testable
/// without a socket. JMA only ever ADDS a road-condition band to the MET base;
/// it never fabricates a visibility number and never discards the MET base.
library;

// `Advisory` is the source-neutral typed event from the aggregator interface
// (a direct dependency); the JMA umbrella does not re-export it.
import 'package:condition_aggregator/condition_aggregator.dart';
import 'package:pretrip_decision_advisor/pretrip_decision_advisor.dart';

import 'forecast_case.dart';
import 'jma_briefing_merge.dart';

typedef MetForecastFetch = Future<WeatherForecast?> Function();
typedef JmaAdvisoryFetch = Future<List<Advisory>> Function();

/// The honest outcome of a live resolve. The caption switches on this ONLY.
enum PretripLiveStatus {
  metNorway, // global case: live MET base only.
  metNorwayUnavailable, // MET base fetch failed/empty → forecast == null → demo.
  japanJmaMerged, // Japan case: an official snow warning was merged.
  japanJmaNoAdvisory, // Japan case: JMA reached, no active snow warning.
  japanJmaFailed, // Japan case: MET base OK, JMA fetch/parse/timeout FAILED.
}

class PretripLiveResult {
  final WeatherForecast? forecast; // null ⇒ caller keeps the offline demo.
  final DateTime? departure;
  final PretripLiveStatus status;
  final String? jmaEventName; // verbatim JP (e.g. 大雪警報); non-null only on merged.
  final String? prefectureCode; // e.g. '050000'; non-null on Japan arms.
  const PretripLiveResult({
    this.forecast,
    this.departure,
    required this.status,
    this.jmaEventName,
    this.prefectureCode,
  });
}

T? _firstWhereOrNull<T>(Iterable<T> it, bool Function(T) test) {
  for (final e in it) {
    if (test(e)) return e;
  }
  return null;
}

/// Resolves the pre-trip live forecast for [latitude]/[longitude]. Both IO
/// legs are injected. The worst case it returns is `metNorwayUnavailable`
/// (forecast == null) — it never throws.
Future<PretripLiveResult> resolvePretripLiveForecast({
  required double latitude,
  required double longitude,
  required DateTime now,
  required Duration window,
  required MetForecastFetch fetchMetForecast,
  required JmaAdvisoryFetch fetchJmaAdvisories,
}) async {
  // 1) MET base FIRST. Offline / global-fail ⇒ demo stays (honest floor).
  WeatherForecast? base;
  try {
    base = await fetchMetForecast();
  } catch (_) {
    base = null;
  }
  if (base == null) {
    return const PretripLiveResult(
        status: PretripLiveStatus.metNorwayUnavailable);
  }

  final departure = now;

  // 2) Route by location with the shipped selector.
  switch (forecastCaseForLocation(latitude: latitude, longitude: longitude)) {
    case ForecastCase.metNorwayGlobal:
      // Non-Japan: byte-for-byte the existing path. JMA is NEVER called.
      return PretripLiveResult(
        forecast: base,
        departure: departure,
        status: PretripLiveStatus.metNorway,
      );

    case ForecastCase.japanSnowZone:
      final code = japanPrefectureCodeForLocation(
        latitude: latitude,
        longitude: longitude,
      );
      try {
        final advisories = await fetchJmaAdvisories();
        // Pick via the merge helper's OWN predicate (decoupled from the
        // provider's internal filter + from severity ordering — a non-goal).
        final snow = _firstWhereOrNull(
          advisories,
          (a) => roadConditionForJmaSnowAdvisory(a.eventClass) != null,
        );
        if (snow == null) {
          return PretripLiveResult(
            forecast: base,
            departure: departure,
            status: PretripLiveStatus.japanJmaNoAdvisory,
            prefectureCode: code,
          );
        }
        // BINDING: JMA only ADDS a road-condition band into null/unknown
        // window slots; it NEVER writes a visibility number (jma_briefing_merge
        // leaves visibilityMeters untouched). The MET base is never discarded.
        final merged = mergeJmaWinterAdvisory(
          base,
          jmaEventName: snow.eventClass,
          windowStart: departure,
          windowDuration: window,
        );
        return PretripLiveResult(
          forecast: merged,
          departure: departure,
          status: PretripLiveStatus.japanJmaMerged,
          jmaEventName: snow.eventClass,
          prefectureCode: code,
        );
      } catch (_) {
        // ANY JMA failure (fetch/parse/timeout/init) → keep the MET base,
        // add NO band, and disclose the gap honestly via the caption.
        return PretripLiveResult(
          forecast: base,
          departure: departure,
          status: PretripLiveStatus.japanJmaFailed,
          prefectureCode: code,
        );
      }
  }
}

/// English gloss for the en locale only. The card now renders real CJK glyphs,
/// so the "CJK-font-free" rationale is stale; for a ja caption the verbatim
/// [PretripLiveResult.jmaEventName] (暴風雪 / 大雪 / 着雪) is more faithful than
/// re-glossing — that localization is queued with the live-caption reach-fix.
String jmaEventEnglishGloss(String eventName) {
  if (eventName.contains('暴風雪')) return 'blizzard';
  if (eventName.contains('大雪')) return 'heavy-snow';
  if (eventName.contains('着雪')) return 'snow-accretion (icing)';
  return 'winter';
}

/// Pure caption builder — shared by the view AND the caption unit test.
/// Returns the on-card sourceCaption for the four LIVE arms. (The
/// `metNorwayUnavailable` arm renders the existing demo caption in main.)
String pretripLiveSourceCaption({
  required PretripLiveStatus status,
  required double latitude,
  required double longitude,
  String? prefectureCode,
  String? eventGloss,
  String? jmaEventName,
  String visCaption = '',
  String lang = 'en',
}) {
  // Japanese reach-fix for HER mother in Akita: the live-arm caveats + the
  // measured-number clause now reach her in her own language. English stays
  // the default + fallback (any non-`ja` locale renders the English arms
  // below, byte-for-byte unchanged). The merged arm carries the VERBATIM JMA
  // classification ([jmaEventName], e.g. 大雪警報 / 着雪注意報) rather than the
  // English gloss — relaying the official 警報/注意報 byte-for-byte is more
  // faithful than re-glossing, and never softens a 警報 to a 注意 (or the
  // reverse). The honesty caveats (no-visibility-number, fetch-UNAVAILABLE,
  // a-real-warning-may-be-unseen) are preserved at full strength; measured
  // NUMBERS pass through verbatim via the same interpolations.
  if (lang == 'ja') {
    switch (status) {
      case PretripLiveStatus.metNorway:
        return 'ライブ予報 — データ:MET Norway (CC BY 4.0)、'
            '緯度 $latitude 経度 $longitude。'
            'この予報には視程・路面データはありません — '
            '危険の判断材料は気温と降水${visCaption.isEmpty ? 'のみ' : ''}です。'
            '$visCaption';
      case PretripLiveStatus.japanJmaMerged:
        return 'ライブ予報 — ベース:MET Norway (CC BY 4.0)、'
            '緯度 $latitude 経度 $longitude。'
            '出発時間帯の路面状況は気象庁の正式な${jmaEventName ?? '冬季の警報'}'
            '(都道府県 ${prefectureCode ?? '?'})に基づきます — 出典:気象庁。'
            'この警報・注意報からは視程の数値は示されません。$visCaption';
      case PretripLiveStatus.japanJmaNoAdvisory:
        return 'ライブ予報 — データ:MET Norway (CC BY 4.0)、'
            '緯度 $latitude 経度 $longitude。'
            '気象庁を確認(都道府県 ${prefectureCode ?? '?'}、気象庁):'
            '発表中の冬季の警報はありません。'
            'この予報には視程・路面データはありません — '
            '危険の判断材料は気温と降水のみです。$visCaption';
      case PretripLiveStatus.japanJmaFailed:
        return 'ライブ予報 — データ:MET Norway (CC BY 4.0)、'
            '緯度 $latitude 経度 $longitude。'
            '気象庁の冬季警報の確認ができませんでした(取得失敗) — '
            '気温と降水のみに基づくブリーフィングです。'
            '実際には正式な雪の警報が発表されている可能性があり、'
            'ここには反映されていません。$visCaption';
      case PretripLiveStatus.metNorwayUnavailable:
        // Caller never asks for a live caption in this arm; demo string is used.
        return '';
    }
  }
  switch (status) {
    case PretripLiveStatus.metNorway:
      return 'LIVE forecast — data: MET Norway (CC BY 4.0), '
          'lat $latitude lon $longitude. '
          'No visibility/surface data in this product — hazard signal from '
          'temperature + precipitation${visCaption.isEmpty ? ' only' : ''}.'
          '$visCaption';
    case PretripLiveStatus.japanJmaMerged:
      return 'LIVE forecast — base: MET Norway (CC BY 4.0), '
          'lat $latitude lon $longitude; departure-window road condition from '
          'OFFICIAL JMA ${eventGloss ?? 'winter'} warning '
          '(prefecture ${prefectureCode ?? '?'}) — source: Japan '
          'Meteorological Agency. No visibility number is implied by the '
          'warning.$visCaption';
    case PretripLiveStatus.japanJmaNoAdvisory:
      return 'LIVE forecast — data: MET Norway (CC BY 4.0), '
          'lat $latitude lon $longitude. JMA checked '
          '(prefecture ${prefectureCode ?? '?'}, Japan Meteorological Agency): '
          'no active winter warning. No visibility/surface data in this '
          'product — hazard signal from temperature + precipitation only.'
          '$visCaption';
    case PretripLiveStatus.japanJmaFailed:
      return 'LIVE forecast — data: MET Norway (CC BY 4.0), '
          'lat $latitude lon $longitude. JMA winter-warning check UNAVAILABLE '
          '(fetch failed) — briefing on temperature + precipitation only; an '
          'official snow warning may exist that is NOT reflected here.'
          '$visCaption';
    case PretripLiveStatus.metNorwayUnavailable:
      // Caller never asks for a live caption in this arm; demo string is used.
      return '';
  }
}

/// The MEASURED departure-hour visibility clause appended to a live source
/// caption when a REAL visibility observation is merged (the most concrete,
/// measured reason on the card). Localized for HER mother in Akita; English is
/// the default + fallback. The leading space is intentional (this clause is
/// appended to the caption). The measured NUMBERS pass through VERBATIM:
/// [meters] is already the rounded integer (`obs.meters.round()`), and [km] is
/// already `distanceKm.toStringAsFixed(0)` — no rounding/conversion happens
/// here, so the figure HER reads is byte-identical across locales. The
/// [attribution] token is the canonical source string and is NEVER translated.
String pretripMeasuredVisibilityCaption({
  required int meters,
  required String stationName,
  required String km,
  required String attribution,
  String lang = 'en',
}) {
  if (lang == 'ja') {
    return ' 出発時間帯の計測視程:$meters m($stationName、$km km先) — '
        'データ:$attribution。';
  }
  return ' Departure-hour visibility MEASURED: $meters m at $stationName '
      '($km km away) — data: $attribution.';
}
