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
// The JMA umbrella exports the IN-BAND partial-read marker: at a border point a
// reachable prefecture's real warnings are returned ALONGSIDE a synthetic
// incomplete-read notice (`eventClass == kJmaIncompleteReadEventClass`) naming
// the unreachable sibling(s). We honour it so a PARTIAL read never reaches HER
// dressed as a COMPLETE one.
import 'package:condition_aggregator_jma/condition_aggregator_jma.dart'
    show kJmaIncompleteReadEventClass;
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

  /// True when the JMA read was PARTIAL: at a border point a containing
  /// prefecture could NOT be fetched while a reachable sibling DID return, so
  /// the official-warning check is incomplete — a real sibling warning (up to a
  /// 大雪特別警報) could be missing from [forecast]. Carried in-band from the
  /// aggregator's incomplete-read notice (`kJmaIncompleteReadEventClass`) and
  /// NEVER silently dropped: the partial read must reach HER alongside any real
  /// warning that DID arrive. Always false on the global MET arm, the
  /// no-Japan-source arms, and the total-failure arm.
  final bool jmaBorderCheckIncomplete;

  /// The unreachable prefecture name(s) for the partial read — verbatim JA from
  /// the notice (e.g. `秋田県` / `秋田県・山形県`). Null unless
  /// [jmaBorderCheckIncomplete] is true.
  final String? jmaUnreachableArea;

  const PretripLiveResult({
    this.forecast,
    this.departure,
    required this.status,
    this.jmaEventName,
    this.prefectureCode,
    this.jmaBorderCheckIncomplete = false,
    this.jmaUnreachableArea,
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
        // IN-BAND PARTIAL-READ signal FIRST. At a border the aggregator returns
        // the reachable prefecture's real warnings AND a synthetic, low-severity
        // incomplete-read notice naming the unreachable sibling(s). It is NOT a
        // snow advisory (the snow filter below skips it), but it MUST reach HER:
        // discarding it would present a partial read as a complete all-clear at
        // the exact degraded-connectivity scenario this product exists for. We
        // detect it independently of the snow filter and honour BOTH — the real
        // warning (merged below) AND this flag.
        final incomplete = _firstWhereOrNull(
          advisories,
          (a) => a.eventClass == kJmaIncompleteReadEventClass,
        );
        final borderIncomplete = incomplete != null;
        final unreachableArea = incomplete?.areaDescription;
        // Pick via the merge helper's OWN predicate (decoupled from the
        // provider's internal filter + from severity ordering — a non-goal).
        final snow = _firstWhereOrNull(
          advisories,
          (a) => roadConditionForJmaSnowAdvisory(a.eventClass) != null,
        );
        if (snow == null) {
          // No reachable snow warning. Still honour a partial read: if a sibling
          // was unreachable, this is NOT a clean all-clear — carry the flag so
          // HER sees the gap instead of an implied "no warnings".
          return PretripLiveResult(
            forecast: base,
            departure: departure,
            status: PretripLiveStatus.japanJmaNoAdvisory,
            prefectureCode: code,
            jmaBorderCheckIncomplete: borderIncomplete,
            jmaUnreachableArea: unreachableArea,
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
          // Surface the real warning AND the partial-read flag together: the
          // merged 着雪注意報 is shown, and HER is told 秋田県 could not be checked.
          jmaBorderCheckIncomplete: borderIncomplete,
          jmaUnreachableArea: unreachableArea,
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
  String visCaption = '',
}) {
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
