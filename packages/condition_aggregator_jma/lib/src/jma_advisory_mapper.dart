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
/// which has no publication window to scroll off. **It is not, however,
/// guaranteed to be current**: measured 2026-08-16 every document on this
/// path was frozen nationwide since late May, so a windowless read can still
/// be eighty days old. Feed age is exposed by [parseJmaFeed] /
/// [JmaFeedSnapshot] and surfaced in band by the provider. It is also tiny
/// (~7 KB for
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

/// Bounding-box catalog for 13 snow-zone offices (8 Hokkaido + 5 Tohoku/Niigata).
/// Bounding-box is approximate (axis-aligned rectangle in WGS84
/// decimal degrees). Used by [prefectureCodeForPoint] to resolve a
/// caller's lat/lon to one of the catalogued prefecture codes; points
/// outside the catalog resolve to nothing.
///
/// ⚑ **13 of the 58 offices JMA publishes — the other 45 are UNSERVED**, and
/// no sibling provider covers them (`condition_aggregator_nws` is the United
/// States, Digitraffic is Finland, MET Norway is Norway). A point in an
/// unserved office therefore gets [buildOutsideCoverageNotice] from the
/// provider, never silence — see [kJmaOutsideCoverageEventClass] for what the
/// silence used to cost. The served-vs-published split is pinned against
/// JMA's own frozen area master in `test/outside_coverage_test.dart`, which
/// fails if either side drifts.
///
/// Code → (south, west, north, east). Bounding box widths are
/// generous enough to absorb minor coastal indentation; precision
/// finer than prefecture is not the JMA-feed's segmentation
/// granularity at this report family.
const Map<String, ({double south, double west, double north, double east})>
kJmaPrefectureBoundingBoxes =
    <String, ({double south, double west, double north, double east})>{
      // ⚑ Hokkaido is EIGHT offices, not one. Through 0.6.0 this catalogue
      // carried a single '010000' described as "the prefecture overall".
      // JMA has no such office: measured against its own area master
      // (`bosai/common/const/area.json`, frozen at
      // `test/fixtures/jma_area_offices.frozen_2026-08-24.json`),
      // `'010000' in offices` is FALSE, and the URL 404s on BOTH the retired
      // and the live path. Every point in Hokkaido — the snowiest prefecture
      // in Japan — resolved to a dead code. It failed loudly rather than
      // falsely (the provider throws), so no driver was told a false
      // all-clear; but Hokkaido was never served.
      //
      // Boxes are approximate axis-aligned WGS84 rectangles and OVERLAP at
      // shared boundaries by design — [prefectureCodesForPoint] returns the
      // union, which is this package's documented over-warn posture: a driver
      // near a boundary receives both neighbours' warnings rather than the
      // resolver guessing one side.
      '011000': (south: 44.65, west: 141.55, north: 45.55, east: 142.65),
      '012000': (south: 43.30, west: 141.35, north: 45.05, east: 143.35),
      '013000': (south: 43.45, west: 142.75, north: 44.95, east: 145.45),
      '014030': (south: 42.25, west: 142.35, north: 43.65, east: 144.15),
      '014100': (south: 42.85, west: 143.55, north: 43.95, east: 145.95),
      '015000': (south: 41.85, west: 140.35, north: 43.15, east: 143.05),
      '016000': (south: 42.55, west: 139.65, north: 44.05, east: 142.35),
      '017000': (south: 41.35, west: 139.30, north: 42.65, east: 141.55),
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
  '011000': 'Hokkaido (Soya)',
  '012000': 'Hokkaido (Kamikawa/Rumoi)',
  '013000': 'Hokkaido (Abashiri/Kitami/Monbetsu)',
  '014030': 'Hokkaido (Tokachi)',
  '014100': 'Hokkaido (Kushiro/Nemuro)',
  '015000': 'Hokkaido (Iburi/Hidaka)',
  '016000': 'Hokkaido (Ishikari/Sorachi/Shiribeshi)',
  '017000': 'Hokkaido (Oshima/Hiyama)',
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
  '011000': '北海道 宗谷地方',
  '012000': '北海道 上川・留萌地方',
  '013000': '北海道 網走・北見・紋別地方',
  '014030': '北海道 十勝地方',
  '014100': '北海道 釧路・根室地方',
  '015000': '北海道 胆振・日高地方',
  '016000': '北海道 石狩・空知・後志地方',
  '017000': '北海道 渡島・檜山地方',
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

/// A whole read of one prefecture's warning document — the warnings AND the
/// document's own timestamp, together.
///
/// **Why this type exists.** [parseJmaWarningJson] returns only the warnings.
/// It parses `reportDatetime` and then loses it: when the document holds no
/// in-force warning the timestamp is discarded entirely, and when it does hold
/// one the timestamp survives only as each advisory's `effective`. So the
/// single most important question about a feed — *how old is what it just told
/// me?* — is unanswerable in exactly the case where the answer decides
/// whether a road reads as clear.
///
/// That is not hypothetical. Measured 2026-08-16: the JMA
/// `bosai/warning/data/warning/` documents were frozen nationwide in late May
/// — Akita at 2026-05-28T06:11+09:00 still listing 雷注意報 `status=発表`,
/// Niigata at 2026-05-26T15:45+09:00 listing nothing at all. The first shape
/// renders as an 80-day-old thunderstorm advisory shown as in force. The
/// second renders as a clear road. Both are the same defect: **absence of
/// information rendering as absence of hazard.**
///
/// [reportDateTime] is the document's own `reportDatetime`, carried out
/// whether or not any warning was in force.
class JmaFeedSnapshot {
  /// The prefecture office code this document was fetched for.
  final String prefectureCode;

  /// The document's own `reportDatetime`, or null when the field was absent
  /// or unparseable. Survives an EMPTY [advisories] list — that is the point
  /// of this type.
  final DateTime? reportDateTime;

  /// The publisher's `headlineText`, verbatim (may be empty).
  final String headline;

  /// The in-force surfaced-class advisories, mapped. Same content and order
  /// as `parseJmaWarningJson(...).map(mapJmaWarningToAdvisory)`.
  final List<Advisory> advisories;

  /// The in-force surfaced-class records, unmapped.
  final List<JmaWarningRecord> records;

  const JmaFeedSnapshot({
    required this.prefectureCode,
    required this.reportDateTime,
    required this.headline,
    required this.advisories,
    required this.records,
  });

  /// How long ago the publisher wrote this document, at [now]. Null when the
  /// document declared no `reportDatetime` — unknown age, which the caller
  /// MUST treat as a third case, never as fresh.
  ///
  /// Negative values are clamped to [Duration.zero] (publisher clock ahead of
  /// ours), mirroring `Advisory.stalenessAt`.
  Duration? ageAt(DateTime now) {
    final r = reportDateTime;
    if (r == null) return null;
    final d = now.difference(r);
    return d < Duration.zero ? Duration.zero : d;
  }

  /// True iff the document's age is known AND at least [threshold].
  ///
  /// False when the age is unknown — an unknown age is not asserted stale
  /// here, exactly as `Advisory.isStaleAt` does not assert staleness on a null
  /// `effective`. Callers that must not treat unknown as fresh should test
  /// [ageAt] for null themselves.
  bool isStaleAt(DateTime now, Duration threshold) {
    final a = ageAt(now);
    if (a == null) return false;
    return a >= threshold;
  }
}

/// Parses one per-prefecture warning JSON [body] into a whole
/// [JmaFeedSnapshot] — the in-force warnings **and** the document's own
/// timestamp, so the timestamp survives an empty warning list.
///
/// [parseJmaWarningJson] is the older, records-only view of the same parse and
/// is unchanged; it now delegates here.
JmaFeedSnapshot parseJmaFeed(
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

  final records = parseJmaWarningJson(
    body,
    prefectureCode: prefectureCode,
    prefectureName: prefectureName,
  );
  return JmaFeedSnapshot(
    prefectureCode: prefectureCode,
    reportDateTime: reportDateTime,
    headline: headline,
    advisories: records.map(mapJmaWarningToAdvisory).toList(growable: false),
    records: records,
  );
}

/// Parses one per-prefecture warning JSON [body] into the in-force
/// surfaced-class [JmaWarningRecord]s for [prefectureCode].
///
/// **Prefer [parseJmaFeed].** This function returns warnings only, so when the
/// document holds none it returns `[]` and the document's `reportDatetime` is
/// lost — an 81-day-old silence becomes indistinguishable from a calm day.
/// Retained unchanged for back-compat.
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
/// - `expires` ← null — **and this stays null on purpose.** JMA's warning
///   JSON carries no machine-readable expiry field, and we will not write our
///   own inference into a field the consumer reads as the publisher's word.
///   (The payload is not truly windowless: Akita's own `headlineText` names
///   「２８日昼過ぎから２８日夜のはじめ頃まで」. That window is Japanese prose
///   with no month and a JMA-defined time band, and parsing it into a typed
///   expiry would manufacture a false publisher declaration — a worse defect
///   than the one this note corrects.)
///
///   ⚑ **The sentence that used to stand here was false and is withdrawn.**
///   It read: *"the windowless feed declares no explicit expiry; the next
///   fetch reflects the then-current in-force state."* The second half is not
///   true. Measured 2026-08-16, the JMA `bosai/warning/data/warning/`
///   documents were frozen nationwide since late May — 80 days of "next
///   fetches" reflected nothing, while Akita kept reporting a 雷注意報 as
///   `status=発表`. A null `expires` therefore does NOT mean "valid until the
///   next fetch corrects it"; it means **the publisher declared no expiry, and
///   you must judge validity from the feed's own age.**
///
///   Use [JmaFeedSnapshot.ageAt] / [JmaFeedSnapshot.isStaleAt] for the feed's
///   age, or `Advisory.stalenessAt` / `Advisory.isStaleAt` for this
///   advisory's, which is derived from the same `reportDatetime`. An advisory
///   from this source is never self-expiring; **`Advisory.isExpiredAt` returns
///   false for it forever.**
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

/// Identity for the **out-of-coverage** meta-advisory built by
/// [buildOutsideCoverageNotice].
///
/// ⚑ **Why this exists, and why none of the other three could say it.**
///
/// Through 0.7.x, a lat/lon that fell outside every box in
/// [kJmaPrefectureBoundingBoxes] made the provider return `const <Advisory>[]`
/// — **the same value it returns for a prefecture it fully covers, fetched
/// successfully, with no warnings in force.** Measured against JMA's own area
/// master (frozen at `test/fixtures/jma_area_offices.frozen_2026-08-24.json`,
/// 58 offices) this catalogue serves 13. So for **45 of 58 offices** —
/// 長野県, 富山県, 石川県, 福井県, 群馬県, 宮城県, 福島県 among them — the
/// adapter answered *"we do not cover this place"* with the bytes that mean
/// *"nothing is wrong"*. A driver in a Nagano blizzard was told the road was
/// clear, and there was no signal anywhere in the returned value for an
/// integrator to render differently.
///
/// The branch defended itself in a comment: the aggregator's other providers
/// "(e.g. NWS)" cover points outside the catalog. Measured, that is false for
/// Japan — `condition_aggregator_nws` wraps NOAA/NWS (United States),
/// Digitraffic is Finland, MET Norway is Norway. **No sibling provider covers
/// those 45 offices.** The empty list was the driver's entire answer.
///
/// Like the path-retirement notice, this says a DIFFERENT thing rather than a
/// louder thing. [kJmaIncompleteReadEventClass] means *"we could not look"* —
/// it is raised when a **containing** prefecture failed to fetch, and so
/// presupposes the point is inside coverage. [kJmaStaleFeedEventClass] means
/// *"we looked, and what answered is stale"*. This one means *"we never had a
/// code for this place"*: no request was made, none could be, and the fix is
/// neither a retry nor a path migration but a bounding box this package does
/// not yet ship.
///
/// Carries no 警報 / 注意報 suffix, so the severity-by-suffix mapping can never
/// grade it as a hazard, and it is `minor` — below `Advisory.isHighImpact`.
const String kJmaOutsideCoverageEventClass = '気象警報の提供対象外地域';

/// Builds the **out-of-coverage** meta-advisory for a point this adapter's
/// bounding-box catalogue does not serve.
///
/// The point itself is the only identity available — there is no office code
/// to name, which is precisely the condition being reported — so the notice
/// carries the coordinates in [Advisory.areaDescription] rather than
/// fabricating a prefecture label.
///
/// `effective` / `expires` are null: a coverage notice has no weather validity
/// window, and a null `effective` keeps `stalenessAt` honestly "unknown"
/// instead of inventing a freshness timestamp.
Advisory buildOutsideCoverageNotice({
  required double latitude,
  required double longitude,
}) {
  final where =
      '北緯${latitude.toStringAsFixed(3)}度／'
      '東経${longitude.toStringAsFixed(3)}度';
  final text =
      'この地点（$where）は本アダプターの提供対象外の地域です。'
      '気象庁はこの地域にも警報・注意報を発表していますが、'
      'この配信経路では取得していません。'
      '警報が表示されていないことは、安全であることを意味しません。';
  return Advisory(
    source: AdvisorySource.jmaJapan,
    eventClass: kJmaOutsideCoverageEventClass,
    severity: AdvisorySeverity.minor,
    certainty: AdvisoryCertainty.unknown,
    urgency: AdvisoryUrgency.unknown,
    areaDescription: where,
    effective: null,
    expires: null,
    headline: text,
    description: text,
  );
}

/// Every **feed-health** meta-advisory identity this adapter can emit.
///
/// These are not weather. They report on the CHANNEL: that the document is
/// old ([kJmaStaleFeedEventClass]), that its path may have been retired
/// ([kJmaPathRetirementEventClass]), that a containing prefecture could
/// not be read at all ([kJmaIncompleteReadEventClass]), or that the point
/// lies outside the bounding-box catalogue entirely
/// ([kJmaOutsideCoverageEventClass]).
///
/// ⚑ **Key on this set, not on one member.** Which of the first two is
/// emitted depends on HOW old the document is, and that boundary moved in
/// 0.7.0 when the path-retirement diagnosis was added. A consumer that
/// matched only `kJmaStaleFeedEventClass` silently stopped seeing feed-health
/// signals for exactly the documents most likely to be dangerous — the very
/// oldest. That is a trap this package walked into in its own test suite, so
/// the set is exported rather than left for each consumer to assemble.
///
/// Every member is `minor` severity, carries no 警報 / 注意報 suffix, and can
/// never be graded as a hazard by the severity-by-suffix mapping.
const Set<String> kJmaFeedHealthEventClasses = <String>{
  kJmaStaleFeedEventClass,
  kJmaPathRetirementEventClass,
  kJmaIncompleteReadEventClass,
  kJmaOutsideCoverageEventClass,
};

/// Identity for the **path-retirement** meta-advisory built by
/// [buildPathRetirementNotice].
///
/// ⚑ **Why this is distinct from [kJmaStaleFeedEventClass], and why a bigger
/// number on the existing notice would not have done.**
///
/// The 0.5.0 stale-feed loom worked exactly as designed. Measured live on
/// 2026-08-23 it emitted 「秋田県 の気象警報・注意報の情報が約87日更新されて
/// いません」— correct, honest, and independently reproducing the 87-day
/// figure. **And nothing moved for 87 days.**
///
/// The gap was not the alarm. It was the DIAGNOSIS. 「更新されていません」
/// reads as *the publisher has gone quiet* — a condition an integrator can do
/// nothing about and will reasonably wait out. The actual condition was *JMA
/// migrated on 2026-05-29 and this path was retired*, which an integrator can
/// fix in one line. A loom that reports the wrong cause is not a smaller loom;
/// it points the reader away from the fix.
///
/// So this notice says a different thing, not a louder thing: the path may
/// have been retired, and a successor should be looked for.
///
/// ⚑ **Its limit, stated because a loom whose bound is hidden is worse than
/// none.** This fires on ABSOLUTE AGE on the path we read. It cannot see a
/// migration on the day it happens, and it cannot distinguish a retired path
/// from a publisher outage lasting longer than the threshold — both look
/// identical from one URL. What it does is convert a defect that ran 87 days
/// undiagnosed into one that names its own likely cause within a week.
/// A cross-surface check (comparing against the always-busy national feed
/// `developer/xml/feed/extra.xml`) COULD distinguish those two and was
/// considered; it is not built here because it doubles the network surface of
/// every fetch to sharpen a diagnosis this notice already points at, and this
/// package's own §12 bearing is against widening the live-fetch perimeter.
/// Recorded so the next reader knows it was weighed, not missed.
const String kJmaPathRetirementEventClass = '気象情報の提供経路が変更された可能性';

/// Default [JmaAdvisoryProvider.pathRetirementThreshold] — seven days.
///
/// Chosen against the measurement that motivated it: the retired path was
/// frozen for 87 days. Seven days would have fired on day 8. It sits well
/// above [kJmaDefaultStaleFeedThreshold] (six hours) so an ordinary quiet
/// spell is never diagnosed as a retirement.
const Duration kJmaDefaultPathRetirementThreshold = Duration(days: 7);

/// Builds the synthetic, clearly-marked, LOW-severity **path-retirement**
/// notice for a prefecture whose feed has not moved in
/// [kJmaDefaultPathRetirementThreshold] or more.
///
/// Like the other meta-advisories it carries no 警報 / 注意報 suffix, so the
/// severity-by-suffix mapping can never grade it as a hazard, and it is
/// `minor` — below `Advisory.isHighImpact`.
Advisory buildPathRetirementNotice({
  required String prefectureCode,
  required Duration age,
  required String sourceUrl,
}) {
  final label =
      jmaPrefectureNameJa(prefectureCode) ??
      jmaPrefectureName(prefectureCode) ??
      prefectureCode;
  final days = age.inDays;
  final text =
      '$label の気象警報・注意報が約$days日更新されていません。'
      'この配信経路（$sourceUrl）の提供が終了し、'
      '新しい経路に移行した可能性があります。'
      'ここに表示されている内容は最新ではない可能性があり、'
      '警報が出ていない場合でも安全とは限りません。';
  return Advisory(
    source: AdvisorySource.jmaJapan,
    eventClass: kJmaPathRetirementEventClass,
    severity: AdvisorySeverity.minor,
    certainty: AdvisoryCertainty.unknown,
    urgency: AdvisoryUrgency.unknown,
    areaDescription: label,
    effective: null,
    expires: null,
    headline: text,
    description: text,
  );
}

/// Identity for the synthetic **stale-feed** meta-advisory built by
/// [buildStaleFeedNotice].
///
/// Carries no 警報 / 注意報 suffix, so `_severityForEventName` can never grade
/// it as a hazard, and is distinct from [kJmaIncompleteReadEventClass] so the
/// full-identity dedup keeps the two apart. An integrator filtering on
/// `Advisory.eventClass == kJmaStaleFeedEventClass` can render it as a
/// feed-health banner rather than as weather.
const String kJmaStaleFeedEventClass = '気象情報の更新停止';

/// Builds the synthetic, clearly-marked, LOW-severity **stale-feed**
/// meta-advisory stating that the JMA warning document for
/// [prefectureCodes] has not been updated for [age].
///
/// **Why this exists (HER-trace, one hop).** A JMA warning document that stops
/// being rewritten fails in two directions and the package could express
/// neither:
///
///   * it keeps reporting a warning that ended months ago as `status=発表` —
///     measured 2026-08-16, Akita served a 2026-05-28 雷注意報 as in force,
///     and our own winter instrument recorded that dead advisory as an ACTIVE
///     hazard 230 times over HER mother's prefecture;
///   * or it reports **nothing**, and an empty list is the identical value a
///     genuinely clear sky produces — measured the same day, Niigata's
///     document was 81 days old and carried no warnings at all.
///
/// The second is the worse of the two. A false alarm is contradicted by the
/// windscreen; a false all-clear removes the prompt to look out of it. That
/// ranking is this package's settled position, already load-bearing in
/// [buildIncompleteReadNotice].
///
/// This notice is the same instrument as [buildIncompleteReadNotice], pointed
/// at a different absence: that one says *"we could not look"*, this one says
/// *"we looked, and what answered is stale"*. Carried IN-BAND in the returned
/// list for the same reason — a successful fetch of a dead document records no
/// provider error, so the aggregator has no error channel to carry it, and a
/// field the caller can ignore will be ignored.
///
/// It is built so it can never masquerade as a weather warning:
///   * `severity` = [AdvisorySeverity.minor] — below `Advisory.isHighImpact`,
///     and no real JMA advisory this adapter surfaces maps to `minor`;
///   * `certainty` / `urgency` = `unknown` — it is not a weather event;
///   * `eventClass` = [kJmaStaleFeedEventClass] — no warning suffix.
///
/// `effective` is the [asOf] instant this staleness was determined (defaulting
/// to now), so the notice itself carries a real timestamp and a downstream TTL
/// can bound it. `expires` is null: the notice is true until the feed moves,
/// and we do not know when that will be.
Advisory buildStaleFeedNotice({
  required List<String> prefectureCodes,
  required Duration age,
  DateTime? asOf,
}) {
  final names = <String>[
    for (final code in prefectureCodes)
      jmaPrefectureNameJa(code) ?? jmaPrefectureName(code) ?? code,
  ];
  final joined = names.join('・');
  final days = age.inDays;
  final hours = age.inHours;
  final ageText = days >= 1 ? '約$days日' : '約$hours時間';
  final text =
      '$joined の気象警報・注意報の情報が$ageText更新されていません。'
      'ここに表示されている内容は最新ではない可能性があり、'
      '警報が出ていない場合でも安全とは限りません。';
  return Advisory(
    source: AdvisorySource.jmaJapan,
    eventClass: kJmaStaleFeedEventClass,
    severity: AdvisorySeverity.minor,
    certainty: AdvisoryCertainty.unknown,
    urgency: AdvisoryUrgency.unknown,
    areaDescription: joined,
    effective: asOf ?? DateTime.now(),
    expires: null,
    headline: text,
    description: text,
  );
}
