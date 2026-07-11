/// JMA warning-record → source-neutral [Advisory] mapping plus the
/// parse helper (windowless per-prefecture warning JSON) and the
/// bounding-box prefecture-code resolution that the
/// [JmaAdvisoryProvider] composes.
///
/// All surfaced advisory event names — the winter-snow classes plus the
/// downpour / typhoon-wind / thunder / fog turmoil classes added in
/// 0.4.0 — are passed through `Advisory.eventClass` verbatim per AAA
/// Article 17 (β) verbatim-relay discipline. The CAP-class severity
/// mapping is conservative (警報 → severe; 注意報 → moderate;
/// 危険警報 → extreme; 特別警報 → extreme).
///
/// ## Why the per-prefecture warning JSON (0.2.0)
///
/// Through 0.1.x this adapter read the JMA disaster-info atom feed
/// (`extra.xml` / `extra_l.xml`) and walked each linked per-prefecture
/// report XML. An independent safety audit found a **window /
/// scroll-off false-negative**: those feeds are a recent-publication
/// *window* (a stream of the latest reports). A warning that is still
/// in force but was last re-issued before the window opens silently
/// scrolls off the feed and is missed — a false-negative for a
/// snow-WARNING package, where a stale-but-active 大雪警報 is exactly
/// what the driver must still see.
///
/// 0.2.0 reads the **windowless per-prefecture warning JSON**
/// (`https://www.jma.go.jp/bosai/warning/data/warning/{areacode}.json`),
/// which always reflects the *current in-force* warning state for the
/// prefecture with no window to scroll off. It is also tiny (~7 KB for
/// Akita vs ~0.6 MB for the atom feed) — lighter on constrained
/// in-vehicle hardware.
///
/// ## Severity mapping (listed in check order)
/// - 特別警報 (emergency warning) suffix → `AdvisorySeverity.extreme`
/// - 危険警報 (danger warning, JMA level 40 / 警戒レベル4相当) suffix →
///   `AdvisorySeverity.extreme` (checked BEFORE the bare 警報 suffix,
///   which would under-grade it to severe; see [_severityForEventName])
/// - 警報 (warning) suffix → `AdvisorySeverity.severe`
/// - 注意報 (advisory) suffix → `AdvisorySeverity.moderate`
/// - any other → `AdvisorySeverity.unknown`
///
/// Certainty / urgency are `unknown` — JMA's classification does not
/// map cleanly to CAP's certainty/urgency scales without a
/// per-event-class table; the publisher's authoritative term is
/// preserved verbatim in `eventClass` either way.
library;

import 'dart:convert';

import 'package:condition_aggregator/condition_aggregator.dart';

/// JMA warning-code → verbatim event-name for the **snow classes only**,
/// keyed on the **bosai warning JSON** numeric `code` value (NOT the
/// jmaxml report `<Kind><Code>`; the two code systems differ — e.g. in
/// the bosai JSON `06` = 大雪警報, whereas the jmaxml report XML uses
/// `33` for the same event name).
///
/// **Back-compat (0.4.0):** through 0.3.0 this map WAS the complete
/// surfaced set and the parse filter. As of 0.4.0 the parse filter is
/// [kJmaWarningCodes] (this snow subset plus the downpour / typhoon /
/// turmoil classes); this map is retained unchanged — its six snow
/// entries only — for consumers that key on the snow classes
/// specifically.
///
/// Each code↔name pair below was verified against the JMA bosai
/// warning code taxonomy (the `level-NN` legend transcribed from the
/// JMA `bosai/warning` frontend, cross-checked across three
/// independent references, 2026-06-26) and is consistent with the live
/// Akita feed (`14` = 雷注意報, observed in-force 2026-06-26):
/// - `06` → 大雪警報         (heavy-snow warning)
/// - `12` → 大雪注意報       (heavy-snow advisory)
/// - `02` → 暴風雪警報       (blizzard warning)
/// - `26` → 着雪注意報       (snow-accretion advisory)
///
/// NOTE — `暴風雪注意報` is intentionally absent here: the JMA bosai
/// warning JSON has **no code for it**. JMA's official 注意報 taxonomy
/// has no 暴風雪注意報; the advisory-level counterpart of 暴風雪警報 is
/// 風雪注意報 (code `13`), which is outside this adapter's 0.2.0 snow
/// catalog. The name is retained in [kJmaSnowAdvisoryEventNames] for
/// back-compat, but the windowless JSON source will never emit it, so
/// no Advisory is ever produced for it (correct — the source does not
/// publish that class). See CHANGELOG 0.2.0.
/// 特別警報 (emergency / level-50) snow codes `36` + `32` added in
/// 0.2.0 (AAA safety-audit gap: the highest-severity snow class — strictly
/// more dangerous than 警報 — was missing). Verified directly against the
/// JMA bosai warning frontend's own served `code2WarningInfo` lookup
/// (2026-06-26): the page inlines
/// `36:{nameParts:e.snow[5],elem:"snow",level:50}` with
/// `e.snow[5]=["大雪","特別警報"]`, and
/// `32:{nameParts:e.wind_snow[5],elem:"wind_snow",level:50}` with
/// `e.wind_snow[5]=["暴風雪","特別警報"]` (`level:50` = 特別警報).
/// There is no 着雪特別警報: the served `e.snow_accretion` array has only
/// the advisory slot populated (`[[],[],["着雪","注意報"],[],[],[]]`), so 着雪
/// has no 警報 or 特別警報 level and none is added.
const Map<String, String> kJmaSnowWarningCodes = <String, String>{
  '06': '大雪警報',
  '12': '大雪注意報',
  '02': '暴風雪警報',
  '26': '着雪注意報',
  '36': '大雪特別警報',
  '32': '暴風雪特別警報',
};

/// JMA warning-code → verbatim event-name for the **complete** set of
/// classes this adapter surfaces (0.4.0): the six winter-snow classes
/// retained from 0.2.0 ([kJmaSnowWarningCodes]) plus the downpour /
/// typhoon-wind / thunder / fog turmoil classes added in 0.4.0. Keyed
/// on the **bosai warning JSON** numeric `code` value (NOT the jmaxml
/// report `<Kind><Code>`; see [kJmaSnowWarningCodes]). This is the map
/// the parse filter ([parseJmaWarningJson]) consumes.
///
/// Each 0.4.0 code↔name pair was verified directly against the JMA
/// bosai warning frontend's own served `code2WarningInfo` lookup
/// (`https://www.jma.go.jp/bosai/warning/`, page fetched and the
/// inlined map extracted 2026-07-10; independently cross-checked
/// against a second same-day read of the same source — both reads
/// agree on every code below, and both reproduce the six 0.2.0 snow
/// codes exactly):
/// - `33` → 大雨特別警報   (`elem:"rain"`, `level:50`)
/// - `43` → 大雨危険警報   (`elem:"rain"`, `level:40` — 警戒レベル4相当)
/// - `03` → 大雨警報       (`elem:"rain"`, `level:30`)
/// - `10` → 大雨注意報     (`elem:"rain"`, `level:20`)
/// - `35` → 暴風特別警報   (`elem:"wind"`, `level:50`)
/// - `05` → 暴風警報       (`elem:"wind"`, `level:30`)
/// - `15` → 強風注意報     (`elem:"wind"`, `level:20`)
/// - `14` → 雷注意報       (`elem:"thunder"`, `level:20`)
/// - `20` → 濃霧注意報     (`elem:"fog"`, `level:20`)
///
/// Extraction note: the served entries are shaped like
/// `"03":{shortNameParts:s.rain[3],nameParts:e.rain[3],elem:"rain",level:30}`
/// with `e.rain[3]=["レベル３","大雨","警報"]`; the rain-family
/// `nameParts` carry a leading `レベルＮ` display part, which the
/// composed event name drops (the snow/wind families carry none, e.g.
/// `e.wind[3]=["暴風","警報"]`).
///
/// NOTE — there is no 暴風危険警報 / 大雪危険警報 / 暴風雪危険警報: the
/// served level-40 (危険警報) slot is populated only for the rain /
/// landslide / flood / tide families (`e.wind[4]`, `e.snow[4]`, and
/// `e.wind_snow[4]` are all `[]`), so of the classes this adapter
/// surfaces only 大雨 has a 危険警報 rung.
///
/// NOTE — 氾濫 (river-flood) classes are **not** in this map: they ride
/// JMA's separate served `code2FloodWarningInfo` lookup (its own code
/// space — `20`/`21`/`22`/`30`/`31`/`40`/`41`/`51`/`53` — colliding
/// with this map's codes) and a different JSON branch, so they cannot
/// be added to this table without a source-branch change. Recorded in
/// CHANGELOG 0.4.0 as out of scope for this widening.
const Map<String, String> kJmaWarningCodes = <String, String>{
  // Winter-snow classes (0.2.0; provenance on [kJmaSnowWarningCodes]).
  '06': '大雪警報',
  '12': '大雪注意報',
  '02': '暴風雪警報',
  '26': '着雪注意報',
  '36': '大雪特別警報',
  '32': '暴風雪特別警報',
  // Downpour / typhoon / turmoil classes (0.4.0; provenance above).
  '33': '大雨特別警報',
  '43': '大雨危険警報',
  '03': '大雨警報',
  '10': '大雨注意報',
  '35': '暴風特別警報',
  '05': '暴風警報',
  '15': '強風注意報',
  '14': '雷注意報',
  '20': '濃霧注意報',
};

/// Warning `status` values that mean the warning is **in force**. The
/// windowless JSON lists a just-cancelled warning with status `解除`
/// for a short period; anything that is not a cancellation is treated
/// as active. (`発表` = newly issued, `継続` = continued.)
const String kJmaWarningStatusCancelled = '解除';

/// Snow / blizzard / icing advisory event names (JA verbatim) the
/// adapter surfaces. JMA's catalogue is broader (over 50
/// 警報・注意報 classes) — we explicitly opt the snow-class names
/// in here so adding a new one is a deliberate version bump.
///
/// Retained verbatim from 0.1.x for back-compat. Of these, the four
/// that the windowless warning JSON publishes a code for are in
/// [kJmaSnowWarningCodes]; `暴風雪注意報` has no bosai-JSON code (see
/// the note on [kJmaSnowWarningCodes]).
const Set<String> kJmaSnowAdvisoryEventNames = <String>{
  '大雪警報',
  '大雪注意報',
  '暴風雪警報',
  '暴風雪注意報',
  '着雪注意報',
  '大雪特別警報',
  '暴風雪特別警報',
};

/// Event-class identity for the synthetic **incomplete-read** meta-advisory
/// that [JmaAdvisoryProvider.fetchActiveAdvisoriesAtPoint] injects into a
/// NON-EMPTY border union when at least one containing prefecture could not be
/// fetched (see [buildIncompleteReadNotice]).
///
/// This is **not** a weather warning — it is an availability / completeness
/// notice. It is deliberately distinct from every real JMA warning name, so it
/// can never be confused with — or deduplicated against — a real advisory, and
/// it does **not** end in a `警報` / `注意報` / `特別警報` suffix, so the
/// severity-by-suffix mapping never classifies it as a hazard. Consumers that
/// want to filter the notice out (or render it differently from a weather
/// warning) can match `Advisory.eventClass == kJmaIncompleteReadEventClass`.
const String kJmaIncompleteReadEventClass = 'データ取得不可';

/// Bounding-box catalog for 6 snow-zone prefectures.
/// Bounding-box is approximate (axis-aligned rectangle in WGS84
/// decimal degrees). Used by [prefectureCodeForPoint] to resolve a
/// caller's lat/lon to one of the catalogued prefecture codes; points
/// outside the catalog return null (the aggregator's other providers
/// cover those points at this layer).
///
/// Code → (south, west, north, east). Bounding box widths are
/// generous enough to absorb minor coastal indentation; precision
/// finer than prefecture is not the JMA-feed's segmentation
/// granularity at this report family.
const Map<String, ({double south, double west, double north, double east})>
kJmaPrefectureBoundingBoxes =
    <String, ({double south, double west, double north, double east})>{
      // Hokkaido — office 010000 covers the prefecture overall.
      '010000': (south: 41.35, west: 139.33, north: 45.55, east: 148.90),
      '020000': (
        south: 40.21,
        west: 139.49,
        north: 41.56,
        east: 141.69,
      ), // Aomori
      '030000': (
        south: 38.74,
        west: 140.65,
        north: 40.45,
        east: 142.07,
      ), // Iwate
      '050000': (
        south: 38.87,
        west: 139.69,
        north: 40.51,
        east: 140.99,
      ), // Akita
      '060000': (
        south: 37.74,
        west: 139.50,
        north: 39.20,
        east: 140.62,
      ), // Yamagata
      '150000': (
        south: 36.74,
        west: 137.63,
        north: 38.55,
        east: 139.89,
      ), // Niigata
    };

/// Romaji / English prefecture NAMES for the snow-zone catalog codes — a
/// place LABEL for logs or a non-Japanese consumer UI, so a code never
/// renders as a bare numeric office code (e.g. '050000'). Codes mirror
/// [kJmaPrefectureBoundingBoxes]; any code outside the catalog returns null via
/// [jmaPrefectureName] (the caller falls back to a localized generic phrase).
///
/// For the **driver-facing** Japanese label used as
/// `Advisory.areaDescription` — the field a Japanese-reading driver reads to
/// tell their own prefecture's warning from an over-warned neighbour's at a
/// border — see [kJmaPrefectureNamesJa] / [jmaPrefectureNameJa].
const Map<String, String> kJmaPrefectureNames = <String, String>{
  '010000': 'Hokkaido',
  '020000': 'Aomori',
  '030000': 'Iwate',
  '050000': 'Akita',
  '060000': 'Yamagata',
  '150000': 'Niigata',
};

/// The romaji / English prefecture name for a JMA prefecture [code], or null
/// when the code is not in the catalog. For the driver-facing Japanese label
/// use [jmaPrefectureNameJa].
String? jmaPrefectureName(String code) => kJmaPrefectureNames[code];

/// Driver-facing **Japanese** prefecture names for the snow-zone catalog
/// codes. The JMA headline / event name are already verbatim Japanese, and at
/// a border the prefecture label is the load-bearing way a Japanese-reading
/// driver tells their own prefecture's warning from an over-warned
/// neighbour's — so the structured label is localized to Japanese too (used as
/// `Advisory.areaDescription`). Codes mirror [kJmaPrefectureBoundingBoxes];
/// any code outside the catalog returns null via [jmaPrefectureNameJa].
const Map<String, String> kJmaPrefectureNamesJa = <String, String>{
  '010000': '北海道',
  '020000': '青森県',
  '030000': '岩手県',
  '050000': '秋田県',
  '060000': '山形県',
  '150000': '新潟県',
};

/// The driver-facing Japanese prefecture name for a JMA prefecture [code], or
/// null when the code is not in the catalog. This is the label surfaced in
/// `Advisory.areaDescription` so a Japanese-reading driver can disambiguate a
/// border over-warn; for the romaji/English label (logs / non-JA UI) use
/// [jmaPrefectureName].
String? jmaPrefectureNameJa(String code) => kJmaPrefectureNamesJa[code];

/// Resolves a WGS84 lat/lon to the **FIRST** catalogued JMA prefecture
/// code whose bounding box contains the point (deterministic
/// [kJmaPrefectureBoundingBoxes] iteration order), or null if the point
/// falls outside every catalogued box.
///
/// The bounding boxes are crude axis-aligned rectangles over irregular
/// prefectures, so they **overlap at every shared border**: a point in a
/// border zone falls inside more than one box, and this "first match"
/// silently drops the neighbour(s). No single-prefecture tie-break is
/// correct at every border — e.g. a nearest-centroid guess merely trades
/// a north-Akita border error for a south-Akita (Chōkai / Nikaho coastal)
/// one. Callers that need border-correct (over-warn) behaviour —
/// surfacing every prefecture a border point could be in — should use
/// [prefectureCodesForPoint].
///
/// Retained for back-compat; equivalent to the first element of
/// [prefectureCodesForPoint] (null when that list is empty).
String? prefectureCodeForPoint({
  required double latitude,
  required double longitude,
}) {
  final codes = prefectureCodesForPoint(
    latitude: latitude,
    longitude: longitude,
  );
  return codes.isEmpty ? null : codes.first;
}

/// Resolves a WGS84 lat/lon to **ALL** catalogued JMA prefecture (office)
/// codes whose bounding box contains the point, in deterministic
/// [kJmaPrefectureBoundingBoxes] iteration order. Returns an empty list
/// when the point falls outside every catalogued box.
///
/// ## Why a list — conservative (over-warn) border handling
///
/// The catalogued bounding boxes are **approximate**: each is a crude
/// axis-aligned rectangle drawn generously over an irregular prefecture,
/// so adjacent prefectures' boxes **overlap along every shared border**.
/// A point in a border zone is therefore legitimately inside more than
/// one box, and there is no resolution guess that is correct at every
/// border (a nearest-centroid tie-break only moves the error from one
/// border to another).
///
/// Rather than guess a single prefecture, this function returns **every**
/// containing prefecture so the caller can fetch and surface all of their
/// in-force warnings. That is the conservative, over-warn handling of
/// border ambiguity — consistent with the package's conservative-on-
/// uncertain philosophy: a driver at a prefecture border never **misses**
/// a warning because the resolver guessed the wrong side. Bounding-box
/// granularity is coarser than prefecture geometry; surfacing the union
/// is the deliberate trade.
///
/// For a single best-guess code (back-compat) use [prefectureCodeForPoint].
List<String> prefectureCodesForPoint({
  required double latitude,
  required double longitude,
}) {
  final codes = <String>[];
  for (final entry in kJmaPrefectureBoundingBoxes.entries) {
    final box = entry.value;
    if (latitude >= box.south &&
        latitude <= box.north &&
        longitude >= box.west &&
        longitude <= box.east) {
      codes.add(entry.key);
    }
  }
  return codes;
}

/// One in-force surfaced-class warning extracted from a per-prefecture
/// warning JSON. Deduplicated to one record per distinct surfaced
/// warning code in the prefecture (the same code is repeated across
/// every sub-area / municipality in the JSON; for a prefecture-resolved
/// lat/lon lookup that detail is below this adapter's resolution).
class JmaWarningRecord {
  /// Bosai warning-JSON numeric `code`, e.g. `06`. Stable identifier;
  /// downstream consumers may key on this rather than the localized
  /// name.
  final String warningCode;

  /// Verbatim JMA event name, e.g. `大雪警報`. Relayed in
  /// `Advisory.eventClass`.
  final String eventName;

  /// The warning `status` verbatim (`発表` / `継続`). Cancellations
  /// (`解除`) are filtered out during parse and never become a record.
  final String status;

  /// The prefecture (office) code this warning was read for, e.g.
  /// `050000`.
  final String prefectureCode;

  /// Driver-facing prefecture name (e.g. `秋田県`) used as
  /// `Advisory.areaDescription`, or the bare code when not in the
  /// catalog. Localized to Japanese for a Japanese-reading driver so the
  /// border-disambiguation label matches the verbatim-JA headline / event
  /// name (see [jmaPrefectureNameJa]).
  final String areaName;

  /// `headlineText` from the warning JSON, verbatim.
  final String headline;

  /// `reportDatetime` from the warning JSON. Used as
  /// `Advisory.effective`.
  final DateTime? reportDateTime;

  const JmaWarningRecord({
    required this.warningCode,
    required this.eventName,
    required this.status,
    required this.prefectureCode,
    required this.areaName,
    required this.headline,
    required this.reportDateTime,
  });
}

/// Parses one per-prefecture warning JSON [body] into the in-force
/// surfaced-class [JmaWarningRecord]s for [prefectureCode].
///
/// The JSON shape (verified live 2026-06-26 against
/// `bosai/warning/data/warning/050000.json`):
/// ```json
/// {
///   "reportDatetime": "2026-05-28T06:11:00+09:00",
///   "publishingOffice": "秋田地方気象台",
///   "headlineText": "…",
///   "areaTypes": [
///     {"areas": [{"code": "050010", "warnings": [{"code": "14", "status": "発表"}]}, …]},
///     …
///   ],
///   "timeSeries": [ … ]   // forecast warnings — NOT current in-force; ignored
/// }
/// ```
///
/// Only `areaTypes[].areas[].warnings[]` (the current in-force state)
/// is consumed; `timeSeries` (the forecast outlook) is intentionally
/// ignored. Warnings are filtered to the surfaced codes
/// ([kJmaWarningCodes] — snow plus the 0.4.0 downpour / typhoon /
/// turmoil classes) and to non-cancelled status, then deduplicated to
/// one record per distinct code.
List<JmaWarningRecord> parseJmaWarningJson(
  String body, {
  required String prefectureCode,
  String? prefectureName,
}) {
  final dynamic decoded = json.decode(body);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('JMA warning JSON root is not a JSON object.');
  }

  final reportRaw = decoded['reportDatetime'];
  final DateTime? reportDateTime = reportRaw is String && reportRaw.isNotEmpty
      ? DateTime.tryParse(reportRaw)
      : null;
  final headlineRaw = decoded['headlineText'];
  final String headline = headlineRaw is String ? headlineRaw : '';
  // Driver-facing label: prefer the caller-supplied name, else the JA
  // prefecture name (the field a Japanese-reading driver reads to tell their
  // own prefecture's warning from an over-warned border neighbour's), else
  // the romaji name, else the bare code (never a null label).
  final areaName =
      prefectureName ??
      jmaPrefectureNameJa(prefectureCode) ??
      jmaPrefectureName(prefectureCode) ??
      prefectureCode;

  // Dedup to one record per distinct in-force surfaced code; keep first
  // encountered status. Iteration order is JSON document order so the
  // result is deterministic.
  final byCode = <String, JmaWarningRecord>{};
  final areaTypes = decoded['areaTypes'];
  if (areaTypes is List) {
    for (final at in areaTypes) {
      if (at is! Map) continue;
      final areas = at['areas'];
      if (areas is! List) continue;
      for (final area in areas) {
        if (area is! Map) continue;
        final warnings = area['warnings'];
        if (warnings is! List) continue;
        for (final w in warnings) {
          if (w is! Map) continue;
          final code = w['code'];
          final status = w['status'];
          if (code is! String || status is! String) continue;
          if (status == kJmaWarningStatusCancelled) continue;
          final eventName = kJmaWarningCodes[code];
          if (eventName == null) continue; // not a surfaced class
          byCode.putIfAbsent(
            code,
            () => JmaWarningRecord(
              warningCode: code,
              eventName: eventName,
              status: status,
              prefectureCode: prefectureCode,
              areaName: areaName,
              headline: headline,
              reportDateTime: reportDateTime,
            ),
          );
        }
      }
    }
  }
  return byCode.values.toList();
}

/// Maps a JMA warning record to a source-neutral [Advisory].
///
/// - `source` ← `AdvisorySource.jmaJapan`
/// - `eventClass` ← `JmaWarningRecord.eventName` verbatim
/// - `severity` ← derived from name suffix, in check order
///   (特別警報 → extreme; 危険警報 → extreme; 警報 → severe;
///   注意報 → moderate; otherwise unknown)
/// - `certainty` / `urgency` ← `unknown` (CAP-class mapping deferred)
/// - `areaDescription` ← `JmaWarningRecord.areaName` (prefecture label)
/// - `headline` / `description` ← `JmaWarningRecord.headline` verbatim
/// - `effective` ← `reportDateTime`
/// - `expires` ← null (the windowless feed declares no explicit
///   expiry; the next fetch reflects the then-current in-force state)
Advisory mapJmaWarningToAdvisory(JmaWarningRecord record) {
  return Advisory(
    source: AdvisorySource.jmaJapan,
    eventClass: record.eventName,
    severity: _severityForEventName(record.eventName),
    certainty: AdvisoryCertainty.unknown,
    urgency: AdvisoryUrgency.unknown,
    areaDescription: record.areaName,
    effective: record.reportDateTime,
    expires: null,
    headline: record.headline,
    description: record.headline,
  );
}

AdvisorySeverity _severityForEventName(String name) {
  if (name.endsWith('特別警報')) return AdvisorySeverity.extreme;
  // 危険警報 (JMA level 40 — 警戒レベル4相当; e.g. 大雨危険警報, code 43)
  // is checked BEFORE the bare 警報 suffix, which it also ends with —
  // falling through to 警報 would under-grade a JMA level-40 to severe.
  // [AdvisorySeverity] has no rung between severe and extreme, so
  // level 40 maps UP to extreme alongside 特別警報 (level 50): the
  // caution-add-only direction.
  if (name.endsWith('危険警報')) return AdvisorySeverity.extreme;
  if (name.endsWith('警報')) return AdvisorySeverity.severe;
  if (name.endsWith('注意報')) return AdvisorySeverity.moderate;
  return AdvisorySeverity.unknown;
}

/// Builds the synthetic, clearly-marked, LOW-severity **incomplete-read**
/// meta-advisory naming the [failedPrefectureCodes] that could not be fetched
/// for a border point whose reachable prefecture(s) DID return warnings.
///
/// Why this exists (HER-trace): at a border, returning only the reachable
/// prefecture's warnings while silently discarding an unreachable sibling
/// would present a PARTIAL read as a COMPLETE, fully-successful one — a silent
/// under-warn at the exact degraded-connectivity scenario this package exists
/// for (a mild reachable warning landing while an unreachable sibling could be
/// holding a 大雪特別警報). The aggregator only records a provider error when a
/// provider THROWS, and a non-empty union is (correctly) returned rather than
/// thrown — so to make the partial read available to the aggregator /
/// integrator the signal is carried IN-BAND, in the returned list. The
/// provider→caller layer guarantee is unconditional: a partial read is ALWAYS
/// surfaced to the caller, never silently dropped. Whether the notice then
/// reaches the DRIVER is the integrator's rendering choice — it is `minor`
/// severity (below `Advisory.isHighImpact`), so an integrator that renders only
/// high-impact items can filter it out; the package guarantees availability to
/// the caller, not a particular driver-facing presentation.
///
/// The notice is built so it can never masquerade as a weather warning:
///   * `severity` = [AdvisorySeverity.minor] — the lowest impact rung; **no**
///     real JMA advisory this adapter surfaces maps to `minor` (警報→severe /
///     注意報→moderate / 危険警報・特別警報→extreme), and `minor` is below the
///     `Advisory.isHighImpact` (severe / extreme) threshold;
///   * `certainty` / `urgency` = `unknown` — it is not a weather event, so a
///     CAP certainty / urgency does not apply;
///   * `eventClass` = [kJmaIncompleteReadEventClass] — a distinct identity that
///     does not collide with any real warning name (so the full-identity dedup
///     key keeps it distinct) and carries no warning suffix.
///
/// The human-readable [Advisory.headline] / `description` are JA-localized
/// (like the real advisories) and name the actually-unreachable prefecture(s).
/// `effective` / `expires` are null — an availability notice has no weather
/// validity window, and a null effective keeps `stalenessAt` honestly
/// "unknown" rather than fabricating a freshness timestamp.
Advisory buildIncompleteReadNotice(List<String> failedPrefectureCodes) {
  final names = <String>[
    for (final code in failedPrefectureCodes)
      jmaPrefectureNameJa(code) ?? jmaPrefectureName(code) ?? code,
  ];
  final joined = names.join('・');
  final text =
      '$joined の気象警報を確認できませんでした（通信不可）。'
      'この地域に警報が出ている場合でも、ここには表示されていない可能性があります。';
  return Advisory(
    source: AdvisorySource.jmaJapan,
    eventClass: kJmaIncompleteReadEventClass,
    severity: AdvisorySeverity.minor,
    certainty: AdvisoryCertainty.unknown,
    urgency: AdvisoryUrgency.unknown,
    areaDescription: joined,
    effective: null,
    expires: null,
    headline: text,
    description: text,
  );
}
