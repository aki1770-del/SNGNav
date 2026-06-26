/// JMA warning-record → source-neutral [Advisory] mapping plus the
/// parse helper (windowless per-prefecture warning JSON) and the
/// bounding-box prefecture-code resolution that the
/// [JmaAdvisoryProvider] composes.
///
/// All winter-snow advisory event names are passed through
/// `Advisory.eventClass` verbatim per AAA Article 17 (β) verbatim-relay
/// discipline. The CAP-class severity mapping is conservative
/// (警報 → severe; 注意報 → moderate; 特別警報 → extreme).
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
/// ## Severity mapping
/// - 警報 (warning) suffix → `AdvisorySeverity.severe`
/// - 注意報 (advisory) suffix → `AdvisorySeverity.moderate`
/// - 特別警報 (emergency warning) suffix → `AdvisorySeverity.extreme`
/// - any other → `AdvisorySeverity.unknown`
///
/// Certainty / urgency are `unknown` — JMA's classification does not
/// map cleanly to CAP's certainty/urgency scales without a
/// per-event-class table; the publisher's authoritative term is
/// preserved verbatim in `eventClass` either way.
library;

import 'dart:convert';

import 'package:condition_aggregator/condition_aggregator.dart';

/// JMA warning-code → verbatim event-name for the snow classes this
/// adapter surfaces, keyed on the **bosai warning JSON** numeric
/// `code` value (NOT the jmaxml report `<Kind><Code>`; the two code
/// systems differ — e.g. in the bosai JSON `06` = 大雪警報, whereas the
/// jmaxml report XML uses `33` for the same event name).
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

/// Readable prefecture NAMES for the snow-zone catalog codes — for a
/// place LABEL in a driver-facing surface, so a destination area never renders
/// as a bare numeric office code (e.g. '050000'). Codes mirror
/// [kJmaPrefectureBoundingBoxes]; any code outside the catalog returns null via
/// [jmaPrefectureName] (the caller falls back to a localized generic phrase).
const Map<String, String> kJmaPrefectureNames = <String, String>{
  '010000': 'Hokkaido',
  '020000': 'Aomori',
  '030000': 'Iwate',
  '050000': 'Akita',
  '060000': 'Yamagata',
  '150000': 'Niigata',
};

/// The readable prefecture name for a JMA prefecture [code], or null when the
/// code is not in the catalog (so the caller never renders a bare code).
String? jmaPrefectureName(String code) => kJmaPrefectureNames[code];

/// Resolves a WGS84 lat/lon to a JMA prefecture code in the catalog.
/// Returns null if the point falls outside every catalogued bounding
/// box. Iteration is deterministic over `Map` iteration order so a
/// point on a shared edge resolves consistently across calls.
String? prefectureCodeForPoint({
  required double latitude,
  required double longitude,
}) {
  for (final entry in kJmaPrefectureBoundingBoxes.entries) {
    final box = entry.value;
    if (latitude >= box.south &&
        latitude <= box.north &&
        longitude >= box.west &&
        longitude <= box.east) {
      return entry.key;
    }
  }
  return null;
}

/// One in-force snow-class warning extracted from a per-prefecture
/// warning JSON. Deduplicated to one record per distinct snow warning
/// code in the prefecture (the same code is repeated across every
/// sub-area / municipality in the JSON; for a prefecture-resolved
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

  /// Readable prefecture name (e.g. `Akita`) used as
  /// `Advisory.areaDescription`, or the bare code when not in the
  /// catalog.
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
/// snow-class [JmaWarningRecord]s for [prefectureCode].
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
/// ignored. Warnings are filtered to the snow-class codes
/// ([kJmaSnowWarningCodes]) and to non-cancelled status, then
/// deduplicated to one record per distinct snow code.
List<JmaWarningRecord> parseJmaWarningJson(
  String body, {
  required String prefectureCode,
  String? prefectureName,
}) {
  final dynamic decoded = json.decode(body);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException(
      'JMA warning JSON root is not a JSON object.',
    );
  }

  final reportRaw = decoded['reportDatetime'];
  final DateTime? reportDateTime = reportRaw is String && reportRaw.isNotEmpty
      ? DateTime.tryParse(reportRaw)
      : null;
  final headlineRaw = decoded['headlineText'];
  final String headline = headlineRaw is String ? headlineRaw : '';
  final areaName =
      prefectureName ?? jmaPrefectureName(prefectureCode) ?? prefectureCode;

  // Dedup to one record per distinct in-force snow code; keep first
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
          final eventName = kJmaSnowWarningCodes[code];
          if (eventName == null) continue; // not a snow class
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
/// - `severity` ← derived from name suffix (警報 → severe;
///   注意報 → moderate; 特別警報 → extreme; otherwise unknown)
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
  if (name.endsWith('警報')) return AdvisorySeverity.severe;
  if (name.endsWith('注意報')) return AdvisorySeverity.moderate;
  return AdvisorySeverity.unknown;
}
