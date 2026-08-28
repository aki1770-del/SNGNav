/// JMA **short-time / imminent-disruption tier** parsing + mapping, across
/// the 2026-05-29 bulletin migration.
///
/// ## What this tier is, and why it is not the ladder
///
/// The `bosai/warning` path carries the standing ladder — 注意報 → 警報 →
/// 特別警報 — as a *state snapshot*. The short-time products are
/// *instantaneous events*: issued once, for a moment already measured, never
/// "in force" in the ladder's sense, and absent from the warning JSON
/// entirely.
///
/// ⚑ **This tier does NOT fire earlier than the ladder, and any claim that
/// it does should be checked before it is repeated.** JMA's own criterion
/// for the rain product is 「大雨時の災害に関する警報発表中に、キキクルの
/// 「危険」（紫）が出現している場合に発表するもの」— the warning must
/// ALREADY be in force. Measured on the real Tokyo timeline of 2026-08-22:
/// 大雨警報 issued 06:19:10Z, the short-time product 08:09:31Z — the ladder
/// **1h50m earlier**. What this tier adds is not earliness but *rarity*,
/// *locality* and *measurement*: a rate or depth at a named station, in a
/// named municipality, that the ladder never carries.
///
/// ## The 2026-05-29 migration — two wire formats, both live
///
/// On 令和8年5月29日 JMA restructured 防災気象情報. The short-time products
/// moved into a new family, **VPBS50 (府県気象防災速報)**, and the legacy
/// bulletins entered 経過措置 with 廃止 scheduled for 令和10年度. Both are
/// published **in parallel, at the same second** — measured across every
/// occurrence in the long feed on 2026-08-23:
///
/// ```
/// 20260822082746_0_VPOA50_130000.xml   EventID  JPTK202608221709_202608221727
/// 20260822082746_0_VPBS50_130000.xml   EventID KJPTK202608221709_202608221727
/// ```
///
/// ⚑ **A naive whole-feed consumer double-counts every such event.** The
/// VPBS50 EventID is the VPOA50 EventID with a leading `K`;
/// [JmaShortTimeRecord.dedupKey] normalizes it so the twins collapse to one.
///
/// ## Identity is TYPED in both formats — but by DIFFERENT elements
///
/// | | legacy VPOA50 | current VPBS50 |
/// |---|---|---|
/// | `Control/Title` | `記録的短時間大雨情報` | `府県気象防災速報` *(shared by all sub-types)* |
/// | `InfoKind` | `記録的短時間大雨情報` | `気象解説情報` *(shared)* |
/// | discriminator | `InfoKind` | **`Headline/Information[@type="情報タグ"]/Item/Kind/Condition`** |
/// | rate / depth | prose only | **typed** (`jmx_eb:Precipitation` / `jmx_eb:SnowfallDepth`) |
/// | station | prose only | **typed** (`Station/Name` + AMeDAS code) |
/// | area code | 府県予報区 (`130000`) | 一次細分区域 (`130010`, `250020`) |
///
/// ⚑ **On VPBS50 neither `Control/Title` nor `InfoKind` identifies the
/// product** — both are shared across 記録雨 / 短時間大雪 / 線状降水帯発生 /
/// 線状降水帯直前予測. Keying on either would silently accept the wrong
/// product. The discriminator is `Condition`.
///
/// ⚑ **The area codes are NOT the same code space.** VPOA50 carries the
/// 6-digit 府県予報区 code this package's prefecture catalogue uses; VPBS50
/// carries the finer 一次細分区域 code. They are both six digits, which is
/// exactly why this is worth stating: a consumer that assumes they are
/// interchangeable will mis-resolve a point. [JmaShortTimeRecord.areaCode] is
/// relayed verbatim with [JmaShortTimeRecord.areaCodeKind] naming which it is.
library;

import 'package:condition_aggregator/condition_aggregator.dart';
import 'package:xml/xml.dart';

/// The short-time products this package surfaces.
enum JmaShortTimeProduct {
  /// 記録的短時間大雨情報 / 気象防災速報（記録的短時間大雨）.
  recordShortRain,

  /// 顕著な大雪に関する気象情報 / 気象防災速報（短時間大雪）.
  shortHeavySnow,
}

/// Which bulletin family a record was parsed from.
enum JmaBulletinFamily {
  /// VPOA50 / VPFJ50 — 経過措置, 廃止予定 令和10年度.
  legacy,

  /// VPBS50 府県気象防災速報 — current, from 2026-05-29.
  bosaiSokuho,
}

/// Which JMA code space an [JmaShortTimeRecord.areaCode] belongs to.
enum JmaAreaCodeKind { prefectureForecastArea, primarySubdivision }

/// Typed `Condition` values (VPBS50 情報タグ) → product.
const Map<String, JmaShortTimeProduct> kJmaShortTimeConditions =
    <String, JmaShortTimeProduct>{
      '記録雨': JmaShortTimeProduct.recordShortRain,
      '短時間大雪': JmaShortTimeProduct.shortHeavySnow,
    };

/// Typed legacy `InfoKind` values → product.
///
/// ⚑ **顕著な大雪 is absent here on purpose, and its absence is a FACT about
/// JMA, not a gap in this package.** The legacy snow product never had a
/// bulletin code or a typed identity: it rode inside VPFJ50 (府県気象情報)
/// with `InfoKind` fixed at `同一現象用平文情報` for every phenomenon, and its
/// only discriminator was the free-text `Head/Title` string
/// 「顕著な大雪に関する○○県気象情報」. Its `Body` was inert
/// (`<Text type="本文">なし</Text>`). Consuming the legacy snow product would
/// mean prose-matching a headline — the rot this tier was audited to avoid.
/// It is therefore **not supported**, deliberately. The successor (VPBS50,
/// `Condition=短時間大雪`) is typed and IS supported.
const Map<String, JmaShortTimeProduct> kJmaShortTimeInfoKinds =
    <String, JmaShortTimeProduct>{
      '記録的短時間大雨情報': JmaShortTimeProduct.recordShortRain,
    };

/// ⚑ **府県予報区 where 気象防災速報（短時間大雪） is actually issued.**
///
/// Verbatim, JMA 「気象防災速報の運用と伝え方について」
/// (`keiho-update2026/tech-info/pdf/introduction_bosaisokuho.pdf`, read
/// 2026-08-23), ※R8.2現在:
///
/// > 短時間の大雪と大規模な交通障害の関係性が明らかとなった地域において運用。
/// > 北陸地方の4県（新潟、富山、石川、福井）、東北地方の２県（福島（会津地方）、
/// > 山形）、近畿地方の３府県（滋賀、京都、兵庫）、中国地方の４県（広島、岡山、
/// > 鳥取、島根）、東海地方の１県（岐阜（関ケ原町付近））で運用を行っている。
///
/// **秋田県 is NOT on this list. 北海道 is NOT on this list.**
///
/// This package's prefecture catalogue is 北海道・青森・岩手・秋田・山形・新潟.
/// The overlap is **山形 and 新潟 only — 2 of 6.** A consumer in Akita,
/// Aomori, Iwate or Hokkaido will never receive a 短時間大雪 advisory from
/// this adapter, because JMA does not issue one there — not because the
/// adapter failed to read it.
///
/// It is recorded in code, not only in a report, because the failure mode is
/// silent: an integrator that adds this tier expecting snow coverage in the
/// northern snow belt would wait for a bulletin that is never published, and
/// nothing in an empty result would ever say why.
const Set<String> kJmaShortSnowIssuedPrefecturesJa = <String>{
  '新潟県',
  '富山県',
  '石川県',
  '福井県',
  '福島県',
  '山形県',
  '滋賀県',
  '京都府',
  '兵庫県',
  '広島県',
  '岡山県',
  '鳥取県',
  '島根県',
  '岐阜県',
};

/// Driver-facing event class per product.
const Map<JmaShortTimeProduct, String> kJmaShortTimeEventClass =
    <JmaShortTimeProduct, String>{
      JmaShortTimeProduct.recordShortRain: '記録的短時間大雨情報',
      JmaShortTimeProduct.shortHeavySnow: '顕著な大雪に関する気象情報',
    };

/// Explicit severity per product — never derived from a name suffix.
///
/// ⚑ Every short-time product ends in **情報**, matching none of the ladder's
/// suffix rules (特別警報 / 危険警報 / 警報 / 注意報). Run against a
/// suffix-delegating implementation, the negative control in
/// `test/jma_shorttime_test.dart` failed with:
///
/// ```
/// Expected: AdvisorySeverity:<AdvisorySeverity.extreme>
///   Actual: AdvisorySeverity:<AdvisorySeverity.unknown>
/// ```
///
/// `unknown` sits below `Advisory.isHighImpact`, so an integrator rendering
/// only high-impact advisories — the documented behaviour — would drop JMA's
/// most urgent products while faithfully rendering a 注意報.
///
/// `extreme` for both: the rain product issues only when 大雨警報 is already
/// in force and キキクル has reached 危険 (at or above the 警戒レベル4相当
/// rung this package already maps to `extreme`); the snow product exists
/// specifically to signal 「大規模な交通障害」/「深刻な交通障害」 imminence.
const Map<JmaShortTimeProduct, AdvisorySeverity> kJmaShortTimeSeverity =
    <JmaShortTimeProduct, AdvisorySeverity>{
      JmaShortTimeProduct.recordShortRain: AdvisorySeverity.extreme,
      JmaShortTimeProduct.shortHeavySnow: AdvisorySeverity.extreme,
    };

const String kJmaInfoTypeAnnounce = '発表';
const String kJmaInfoTypeCancel = '取消';
const String kJmaInfoTypeCorrect = '訂正';

/// Thrown when a document carries no readable short-time identity.
///
/// ⚑ A THROW, never an empty list. `[]` from a parser is byte-identical to a
/// verified all-clear, and an all-clear this package did not verify is the
/// false negative that reaches HER as silence.
class JmaShortTimeParseException implements Exception {
  final String message;
  const JmaShortTimeParseException(this.message);
  @override
  String toString() => 'JmaShortTimeParseException: $message';
}

/// A typed measurement carried by a VPBS50 body. Null on legacy bulletins,
/// where the number exists only inside prose and is deliberately not parsed.
class JmaShortTimeMeasurement {
  /// Numeric value as published, e.g. `100` (mm) or `37` (cm).
  final num value;

  /// Unit verbatim, e.g. `mm` / `cm`.
  final String unit;

  /// Accumulation window verbatim, e.g. `前１時間解析雨量` /
  /// `６時間の降雪深さ`.
  final String window;

  /// JMA's own display string, e.g. `約１００ミリ` / `３７センチ`.
  final String description;

  /// Observing station name when the bulletin names one.
  final String? stationName;

  const JmaShortTimeMeasurement({
    required this.value,
    required this.unit,
    required this.window,
    required this.description,
    required this.stationName,
  });
}

/// One parsed short-time report.
class JmaShortTimeRecord {
  final JmaShortTimeProduct product;
  final JmaBulletinFamily family;

  /// `Head/InfoType` — `発表` / `取消` / `訂正`.
  final String infoType;

  /// Area code verbatim. See [areaCodeKind] — the two families use
  /// DIFFERENT code spaces and both are six digits.
  final String areaCode;
  final JmaAreaCodeKind areaCodeKind;
  final String areaName;

  /// `Head/EventID` verbatim.
  final String eventId;

  final DateTime reportDateTime;

  /// `Head/Headline/Text` verbatim — relayed, never mined for a number.
  final String headline;

  /// Typed measurement (VPBS50 only); null on legacy bulletins.
  final JmaShortTimeMeasurement? measurement;

  const JmaShortTimeRecord({
    required this.product,
    required this.family,
    required this.infoType,
    required this.areaCode,
    required this.areaCodeKind,
    required this.areaName,
    required this.eventId,
    required this.reportDateTime,
    required this.headline,
    required this.measurement,
  });

  bool get isActive => infoType != kJmaInfoTypeCancel;

  /// Key that collapses the dual-published VPOA50/VPBS50 twins into one.
  ///
  /// The VPBS50 EventID is the legacy one with a leading `K`
  /// (`JPTK…` / `KJPTK…`), so stripping it makes the pair equal. Without
  /// this a whole-feed consumer reports every event twice.
  String get dedupKey {
    final e = eventId.startsWith('K') ? eventId.substring(1) : eventId;
    return '${product.name}|$e';
  }
}

Iterable<XmlElement> _els(XmlDocument d) =>
    d.descendants.whereType<XmlElement>();

String? _first(XmlDocument d, String local) {
  for (final e in _els(d)) {
    if (e.name.local == local) {
      final t = e.innerText.trim();
      if (t.isNotEmpty) return t;
    }
  }
  return null;
}

/// Parses a JMA short-time report (VPOA50 legacy or VPBS50 current).
///
/// Throws [JmaShortTimeParseException] on a malformed document, an
/// unrecognised product, or a missing field this package will not fabricate.
JmaShortTimeRecord parseJmaShortTimeReport(String body) {
  final XmlDocument doc;
  try {
    doc = XmlDocument.parse(body);
  } on XmlException catch (e) {
    throw JmaShortTimeParseException('not well-formed XML: $e');
  }

  // VPBS50 first: its Condition is the only reliable discriminator, and its
  // InfoKind (気象解説情報) is shared across unrelated products.
  final condition = _first(doc, 'Condition');
  final JmaShortTimeProduct product;
  var family = JmaBulletinFamily.bosaiSokuho;
  var areaKind = JmaAreaCodeKind.primarySubdivision;

  final byCondition = condition == null
      ? null
      : kJmaShortTimeConditions[condition];
  if (byCondition != null) {
    product = byCondition;
  } else {
    final infoKind = _first(doc, 'InfoKind');
    if (infoKind == null) {
      throw const JmaShortTimeParseException('no <InfoKind> element');
    }
    final byInfoKind = kJmaShortTimeInfoKinds[infoKind];
    if (byInfoKind == null) {
      throw JmaShortTimeParseException(
        condition == null
            ? 'InfoKind "$infoKind" is not a surfaced short-time product'
            : 'Condition "$condition" is not a surfaced short-time product',
      );
    }
    product = byInfoKind;
    family = JmaBulletinFamily.legacy;
    areaKind = JmaAreaCodeKind.prefectureForecastArea;
  }

  final infoType = _first(doc, 'InfoType');
  if (infoType == null) {
    throw const JmaShortTimeParseException('no <InfoType> element');
  }

  // Area under the 情報タグ / Warning block (never the Body's municipality).
  String? areaCode;
  String? areaName;
  for (final e in _els(doc)) {
    if (e.name.local != 'Areas') continue;
    for (final a in e.descendants.whereType<XmlElement>()) {
      if (a.name.local != 'Area') continue;
      for (final c in a.children.whereType<XmlElement>()) {
        if (c.name.local == 'Code') areaCode ??= c.innerText.trim();
        if (c.name.local == 'Name') areaName ??= c.innerText.trim();
      }
      if (areaCode != null) break;
    }
    if (areaCode != null) break;
  }
  if (areaCode == null) {
    for (final e in _els(doc)) {
      if (e.name.local != 'Area') continue;
      for (final c in e.children.whereType<XmlElement>()) {
        if (c.name.local == 'Code') areaCode ??= c.innerText.trim();
        if (c.name.local == 'Name') areaName ??= c.innerText.trim();
      }
      if (areaCode != null) break;
    }
  }
  if (areaCode == null || areaCode.isEmpty) {
    throw const JmaShortTimeParseException('no <Area><Code> element');
  }

  final reportRaw = _first(doc, 'ReportDateTime');
  if (reportRaw == null) {
    throw const JmaShortTimeParseException('no <ReportDateTime> element');
  }
  final reportDateTime = DateTime.tryParse(reportRaw);
  if (reportDateTime == null) {
    throw JmaShortTimeParseException('unparseable ReportDateTime "$reportRaw"');
  }

  return JmaShortTimeRecord(
    product: product,
    family: family,
    infoType: infoType,
    areaCode: areaCode,
    areaCodeKind: areaKind,
    areaName: areaName ?? areaCode,
    eventId: _first(doc, 'EventID') ?? '',
    reportDateTime: reportDateTime,
    headline: _first(doc, 'Text') ?? '',
    measurement: _measurement(doc),
  );
}

JmaShortTimeMeasurement? _measurement(XmlDocument doc) {
  for (final e in _els(doc)) {
    final n = e.name.local;
    if (n != 'Precipitation' && n != 'SnowfallDepth') continue;
    final v = num.tryParse(e.innerText.trim());
    if (v == null) continue;
    String? station;
    for (final s in _els(doc)) {
      if (s.name.local != 'Station') continue;
      for (final c in s.children.whereType<XmlElement>()) {
        if (c.name.local == 'Name') station ??= c.innerText.trim();
      }
    }
    return JmaShortTimeMeasurement(
      value: v,
      unit: e.getAttribute('unit') ?? '',
      window: e.getAttribute('type') ?? '',
      description: e.getAttribute('description') ?? '',
      stationName: station,
    );
  }
  return null;
}

/// Maps a short-time record to a source-neutral [Advisory].
Advisory mapJmaShortTimeToAdvisory(JmaShortTimeRecord record) {
  return Advisory(
    source: AdvisorySource.jmaJapan,
    eventClass: kJmaShortTimeEventClass[record.product]!,
    severity: kJmaShortTimeSeverity[record.product]!,
    certainty: AdvisoryCertainty.observed,
    urgency: AdvisoryUrgency.immediate,
    areaDescription: record.areaName,
    effective: record.reportDateTime,
    expires: null,
    headline: record.headline,
    description: record.headline,
  );
}

/// Collapses dual-published VPOA50/VPBS50 twins, preferring the VPBS50
/// record because it carries the typed measurement the legacy twin lacks.
List<JmaShortTimeRecord> dedupeShortTimeRecords(
  Iterable<JmaShortTimeRecord> records,
) {
  final best = <String, JmaShortTimeRecord>{};
  for (final r in records) {
    final k = r.dedupKey;
    final existing = best[k];
    if (existing == null || existing.family == JmaBulletinFamily.legacy) {
      best[k] = r;
    }
  }
  return best.values.toList(growable: false);
}

/// Event-class identity for the notice that the short-time tier could not be
/// read. Carries no 警報 / 注意報 suffix, so no severity rule can grade it as
/// a hazard.
const String kJmaShortTimeUnavailableEventClass = '短時間情報の取得不可';

/// Builds the honest-absence notice for an UNREAD short-time surface.
///
/// The tier is a hazard channel; a channel we could not read is UNKNOWN,
/// never "no hazard". Without this, an integrator that reads the ladder and
/// not this tier renders a confident all-clear over a channel never opened.
Advisory buildShortTimeUnavailableNotice({required String areaLabel}) {
  final text =
      '$areaLabel の短時間気象情報は取得できませんでした（通信不可）。'
      '記録的短時間大雨や短時間大雪の情報が出ている場合でも、'
      'ここには表示されていない可能性があります。';
  return Advisory(
    source: AdvisorySource.jmaJapan,
    eventClass: kJmaShortTimeUnavailableEventClass,
    severity: AdvisorySeverity.minor,
    certainty: AdvisoryCertainty.unknown,
    urgency: AdvisoryUrgency.unknown,
    areaDescription: areaLabel,
    effective: null,
    expires: null,
    headline: text,
    description: text,
  );
}
