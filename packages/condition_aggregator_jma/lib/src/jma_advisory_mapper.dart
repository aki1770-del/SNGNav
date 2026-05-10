/// JMA forecast-record → source-neutral [Advisory] mapping plus the
/// direct-parse helpers (atom feed + per-prefecture report XML +
/// bounding-box prefecture-code resolution) that the
/// [JmaAdvisoryProvider] composes.
///
/// All four winter-snow advisory event names are passed through
/// `Advisory.eventClass` verbatim per AAA Article 17 (β) verbatim-relay
/// discipline. The CAP-class severity / certainty / urgency mapping
/// is conservative at 0.1.0 (警報 → severe; 注意報 → moderate).
///
/// Severity mapping at 0.1.0:
/// - 警報 (warning) suffix → `AdvisorySeverity.severe`
/// - 注意報 (advisory) suffix → `AdvisorySeverity.moderate`
/// - 特別警報 (emergency warning) suffix → `AdvisorySeverity.extreme`
/// - any other → `AdvisorySeverity.unknown`
///
/// Certainty / urgency are `unknown` at 0.1.0 — JMA's classification
/// does not map cleanly to CAP's certainty/urgency scales without a
/// per-event-class table; the publisher's authoritative term is
/// preserved verbatim in `eventClass` either way.
library;

import 'package:condition_aggregator/condition_aggregator.dart';
import 'package:xml/xml.dart';

/// Snow / blizzard / icing advisory event names (JA verbatim) the
/// adapter surfaces at 0.1.0. JMA's catalogue is broader (over 50
/// 警報・注意報 classes) — we explicitly opt the snow-class names
/// in here so adding a new one is a deliberate version bump.
const Set<String> kJmaSnowAdvisoryEventNames = <String>{
  '大雪警報',
  '大雪注意報',
  '暴風雪警報',
  '暴風雪注意報',
  '着雪注意報',
};

/// Bounding-box catalog for 6 snow-zone prefectures at 0.1.0.
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
      // Hokkaido — sub-region 010000 covers the prefecture overall at the
      // VPWW54 family (the per-sub-region breakdowns surface inside the
      // report XML's `<Information>` blocks).
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

/// Resolves a WGS84 lat/lon to a JMA prefecture code in the 0.1.0
/// catalog. Returns null if the point falls outside every catalogued
/// bounding box. Iteration is deterministic over `Map` iteration
/// order so a point on a shared edge resolves consistently across
/// calls.
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

/// One atom-feed entry — minimal projection of the fields the provider
/// needs to filter + traverse to the per-prefecture report XML.
class JmaAtomEntry {
  /// `<title>` text — e.g. "気象警報・注意報（Ｈ２７）" or
  /// "気象特別警報・警報・注意報".
  final String title;

  /// `<updated>` ISO-8601 timestamp string verbatim.
  final String updated;

  /// `<author><name>` — e.g. "長野地方気象台".
  final String author;

  /// `<link type="application/xml" href="…">` — URL of the per-prefecture
  /// report XML. The filename suffix encodes the publisher area code
  /// (e.g. `_200000.xml` for Nagano).
  final String reportUrl;

  const JmaAtomEntry({
    required this.title,
    required this.updated,
    required this.author,
    required this.reportUrl,
  });
}

/// Parses one atom feed body into a list of [JmaAtomEntry]. Entries
/// without all four fields are skipped (the publisher's regular shape
/// always populates them; any missing field signals a malformed entry
/// we'd rather drop than partially-render).
List<JmaAtomEntry> parseJmaAtomFeed(String body) {
  final doc = XmlDocument.parse(body);
  final feed = doc.rootElement;
  final out = <JmaAtomEntry>[];
  for (final entry in feed.findElements('entry', namespace: '*')) {
    final title = entry
        .findElements('title', namespace: '*')
        .firstOrNull
        ?.innerText;
    final updated = entry
        .findElements('updated', namespace: '*')
        .firstOrNull
        ?.innerText;
    final authorEl = entry.findElements('author', namespace: '*').firstOrNull;
    final author = authorEl
        ?.findElements('name', namespace: '*')
        .firstOrNull
        ?.innerText;
    String? reportUrl;
    for (final link in entry.findElements('link', namespace: '*')) {
      final type = link.getAttribute('type');
      if (type == 'application/xml') {
        reportUrl = link.getAttribute('href');
        break;
      }
    }
    if (title == null ||
        updated == null ||
        author == null ||
        reportUrl == null) {
      continue;
    }
    out.add(
      JmaAtomEntry(
        title: title,
        updated: updated,
        author: author,
        reportUrl: reportUrl,
      ),
    );
  }
  return out;
}

/// Forecast-record extracted from one per-prefecture report XML. Each
/// `<Item><Kind>` × `<Areas><Area>` cross-product produces one record
/// (so a single report can yield multiple records — different event
/// classes across different sub-regions of the same prefecture).
class JmaForecastRecord {
  /// `<Kind><Name>` — e.g. "大雪警報". Verbatim-relayed in
  /// `Advisory.eventClass`.
  final String eventName;

  /// `<Kind><Code>` — JMA's numeric event-class code, e.g. "33" for
  /// 大雪警報. Surfaced for downstream consumers that key on the
  /// stable code rather than the localized name.
  final String eventCode;

  /// `<Headline><Text>` — multi-paragraph publisher headline.
  final String headline;

  /// `<Areas><Area><Name>` — e.g. "北部". Surfaced verbatim as
  /// `Advisory.areaDescription`.
  final String areaName;

  /// `<Areas><Area><Code>` — e.g. "200010". Stable identifier;
  /// downstream consumers may key on this for region-aware UI.
  final String areaCode;

  /// `<ReportDateTime>` — when the publisher emitted the report.
  /// Used as `Advisory.effective` until a more granular per-event
  /// effective timestamp is exposed at the schema layer.
  final DateTime? reportDateTime;

  /// `<TargetDateTime>` — when the conditions described take effect.
  /// Returned as a candidate `effective` for callers that prefer
  /// content time over publishing time. (At 0.1.0 we use
  /// reportDateTime as the canonical effective; this field is
  /// surfaced for forward-compat.)
  final DateTime? targetDateTime;

  const JmaForecastRecord({
    required this.eventName,
    required this.eventCode,
    required this.headline,
    required this.areaName,
    required this.areaCode,
    required this.reportDateTime,
    required this.targetDateTime,
  });
}

/// Parses one per-prefecture report XML body into a list of
/// [JmaForecastRecord]. The cross-product of `<Item><Kind>` ×
/// `<Item><Areas><Area>` produces one record per pair so downstream
/// filtering on event-name + area is straightforward.
///
/// Only the most-granular `<Information type="気象警報・注意報（市町村等をまとめた地域等）">`
/// block is consumed when present; the prefecture-level + sub-region
/// blocks are intentionally skipped to avoid double-counting the
/// same advisory at multiple resolutions. If the granular block is
/// absent, the next-most-granular present block is used.
List<JmaForecastRecord> parseJmaReportXml(String body) {
  final doc = XmlDocument.parse(body);
  final report = doc.rootElement;

  // Head → ReportDateTime + TargetDateTime + Headline/Text.
  DateTime? reportDateTime;
  DateTime? targetDateTime;
  String headline = '';

  final headEl = _findFirstByLocalName(report, 'Head');
  if (headEl != null) {
    final rdt = _findFirstByLocalName(headEl, 'ReportDateTime')?.innerText;
    if (rdt != null && rdt.isNotEmpty) {
      reportDateTime = DateTime.tryParse(rdt);
    }
    final tdt = _findFirstByLocalName(headEl, 'TargetDateTime')?.innerText;
    if (tdt != null && tdt.isNotEmpty) {
      targetDateTime = DateTime.tryParse(tdt);
    }
    final headlineEl = _findFirstByLocalName(headEl, 'Headline');
    if (headlineEl != null) {
      headline =
          _findFirstByLocalName(headlineEl, 'Text')?.innerText ?? headline;
    }
  }

  // Pick the most-granular Information block present.
  final informationEls = _findAllByLocalName(
    headEl ?? report,
    'Information',
  ).toList();
  XmlElement? chosenInfo;
  // Prefer 市町村 granularity > 一次細分区域 > 府県予報区.
  const granularityOrder = <String>[
    '気象警報・注意報（市町村等をまとめた地域等）',
    '気象警報・注意報（一次細分区域等）',
    '気象警報・注意報（府県予報区等）',
  ];
  for (final preferredType in granularityOrder) {
    for (final info in informationEls) {
      if (info.getAttribute('type') == preferredType) {
        chosenInfo = info;
        break;
      }
    }
    if (chosenInfo != null) break;
  }
  if (chosenInfo == null && informationEls.isNotEmpty) {
    chosenInfo = informationEls.first;
  }

  final out = <JmaForecastRecord>[];
  if (chosenInfo == null) return out;

  for (final item in _findAllByLocalName(chosenInfo, 'Item')) {
    final kinds = _findAllByLocalName(item, 'Kind').toList();
    final areasEl = _findFirstByLocalName(item, 'Areas');
    if (areasEl == null) continue;
    final areas = _findAllByLocalName(areasEl, 'Area').toList();
    if (kinds.isEmpty || areas.isEmpty) continue;
    for (final kind in kinds) {
      final eventName = _findFirstByLocalName(kind, 'Name')?.innerText ?? '';
      final eventCode = _findFirstByLocalName(kind, 'Code')?.innerText ?? '';
      if (eventName.isEmpty) continue;
      for (final area in areas) {
        final areaName = _findFirstByLocalName(area, 'Name')?.innerText ?? '';
        final areaCode = _findFirstByLocalName(area, 'Code')?.innerText ?? '';
        out.add(
          JmaForecastRecord(
            eventName: eventName,
            eventCode: eventCode,
            headline: headline,
            areaName: areaName,
            areaCode: areaCode,
            reportDateTime: reportDateTime,
            targetDateTime: targetDateTime,
          ),
        );
      }
    }
  }
  return out;
}

/// Maps a JMA forecast record to a source-neutral [Advisory].
///
/// - `source` ← `AdvisorySource.jmaJapan`
/// - `eventClass` ← `JmaForecastRecord.eventName` verbatim
/// - `severity` ← derived from name suffix (警報 → severe;
///   注意報 → moderate; 特別警報 → extreme; otherwise unknown)
/// - `certainty` / `urgency` ← `unknown` (CAP-class mapping deferred)
/// - `areaDescription` ← `JmaForecastRecord.areaName` verbatim
/// - `headline` ← `JmaForecastRecord.headline` verbatim
/// - `description` ← `JmaForecastRecord.headline` (the granular
///   `<Text>` is repeated as description so consumers that key on
///   description still see the publisher wording verbatim)
/// - `effective` ← `reportDateTime`
/// - `expires` ← null (JMA report family does not declare an
///   explicit expiry; the next report supersedes the previous)
Advisory mapJmaForecastToAdvisory(JmaForecastRecord record) {
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

XmlElement? _findFirstByLocalName(XmlElement parent, String localName) {
  for (final child in parent.descendants.whereType<XmlElement>()) {
    if (child.name.local == localName) return child;
  }
  return null;
}

Iterable<XmlElement> _findAllByLocalName(XmlElement parent, String localName) {
  return parent.descendants.whereType<XmlElement>().where(
    (e) => e.name.local == localName,
  );
}
