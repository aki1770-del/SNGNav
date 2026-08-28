/// JMA **R8 warning-JSON** parsing — the path that replaced the one this
/// package has been reading since 0.2.0.
///
/// ## Why this file exists
///
/// On **2026-05-29** JMA began operating its restructured 防災気象情報
/// system (令和8年5月29日, "新たな防災気象情報"). This package reads
/// `bosai/warning/data/warning/{code}.json`. Measured 2026-08-23, that path
/// still answers `200` — and every prefecture on it is frozen in a
/// **2026-05-28** window, the day before the migration:
///
/// ```
/// data/warning/050000.json  (Akita)  reportDatetime 2026-05-28T06:11+09:00
/// data/r8/050000.json       (Akita)  reportDatetime 2026-08-23T23:51+09:00
/// ```
///
/// At the moment of that measurement the live path carried a 濃霧注意報
/// **in force in Akita** — a class this package already maps (code `20`) —
/// while the path we read served a 雷注意報 from May. The adapter was not
/// missing a hazard class. It was reading a retired path.
///
/// ⚑ **The old path did not fail. It kept answering, well-formed, forever.**
/// That is why 0.5.0's stale-feed notice is load-bearing and why it is not
/// enough on its own: a frozen feed does not look absent, it looks calm.
///
/// ## What changed in the shape
///
/// | | legacy | r8 |
/// |---|---|---|
/// | root | one object | **list** of per-bulletin documents |
/// | warnings | `areaTypes[].areas[].warnings[]` | `warning.class10Items[].kinds[]` |
/// | freshness | one `reportDatetime` | **one per document** |
/// | explicit all-clear | none | `status` = `発表警報・注意報はなし` |
///
/// The **warning code space is unchanged** — code `20` is still 濃霧注意報 —
/// so [kJmaWarningCodes] carries across the migration untouched. Verified
/// against the frozen fixture `jma_warning_r8_050000.frozen_2026-08-23.json`.
///
/// ⚑ **Freshness is the NEWEST document, never the oldest.** Each bulletin
/// family updates on its own cadence: in the frozen Akita fixture the
/// newest document is 2026-08-23T23:51 and the oldest is 2026-07-16T06:30,
/// 38 days earlier — both entirely normal. Taking the oldest (the
/// instinctively "conservative" choice) reports a live feed as ~38 days
/// dead and fires a false feed-death notice over real warnings. That
/// failure was observed, not reasoned about — see the negative control in
/// `test/jma_r8_warning_test.dart`.
library;

import 'dart:convert';

import 'package:condition_aggregator/condition_aggregator.dart';

import 'jma_advisory_mapper.dart';

/// `status` value meaning the publisher affirmatively declares that no
/// warning or advisory is in force for the area.
///
/// This has no legacy counterpart, and the difference matters to this
/// package more than most: it distinguishes **"the publisher says nothing
/// is in force"** from **"we could not read the publisher"**. The first is
/// an all-clear we are entitled to relay; the second is UNKNOWN. Until r8
/// there was no way to tell them apart from the document alone.
const String kJmaR8StatusNoWarnings = '発表警報・注意報はなし';

/// Parses an r8 per-prefecture warning document list into a
/// [JmaFeedSnapshot].
///
/// Throws [FormatException] when the root is not a JSON list — which is
/// exactly what a legacy document is. The two schemas cannot be silently
/// confused in either direction, and both directions are covered by tests.
JmaFeedSnapshot parseJmaR8Feed(
  String body, {
  required String prefectureCode,
  String? prefectureName,
}) {
  final dynamic decoded = json.decode(body);
  if (decoded is! List) {
    throw const FormatException(
      'JMA r8 warning JSON root is not a JSON list. A legacy '
      'bosai/warning/data/warning/{code}.json document is an object and is '
      'NOT parseable here — that path was superseded 2026-05-29.',
    );
  }

  final areaName =
      prefectureName ??
      jmaPrefectureNameJa(prefectureCode) ??
      jmaPrefectureName(prefectureCode) ??
      prefectureCode;

  DateTime? newest;
  String headline = '';
  final byCode = <String, JmaWarningRecord>{};

  for (final doc in decoded) {
    if (doc is! Map) continue;

    final rawDt = doc['reportDatetime'];
    final dt = rawDt is String && rawDt.isNotEmpty
        ? DateTime.tryParse(rawDt)
        : null;
    // NEWEST wins. Measured against the frozen Akita fixture: taking the
    // oldest returned 2026-07-15T21:30Z for a feed whose newest document
    // was 2026-08-23T14:51Z — reporting a feed 83 minutes old as 38 days
    // dead, and firing a false feed-death notice over a 濃霧注意報 that was
    // genuinely in force. Observed, not reasoned about.
    if (dt != null && (newest == null || dt.isAfter(newest))) {
      newest = dt;
      final h = doc['headlineText'];
      headline = h is String ? h : '';
    }

    final warning = doc['warning'];
    if (warning is! Map) continue;
    // Read BOTH granularities and take the union.
    //
    // ⚑ Measured 2026-08-24 across 16 prefectures: zero documents carried a
    // code in `class20Items` that `class10Items` lacked — so class10 alone
    // would have been sufficient *in that sample*. It was a quiet August with
    // only four distinct codes in the whole national picture, which is
    // evidence, not proof. Unioning costs one extra loop over a document
    // already in memory and makes a class20-only warning structurally
    // impossible to drop. This is the caution-add-only direction this package
    // already takes elsewhere: never let a sampling window decide what a
    // driver is allowed to be told.
    final items = <dynamic>[
      ...?(warning['class10Items'] is List
          ? warning['class10Items'] as List
          : null),
      ...?(warning['class20Items'] is List
          ? warning['class20Items'] as List
          : null),
    ];

    for (final item in items) {
      if (item is! Map) continue;
      final kinds = item['kinds'];
      if (kinds is! List) continue;
      for (final kind in kinds) {
        if (kind is! Map) continue;
        final status = kind['status'];
        final code = kind['code'];
        // An explicit all-clear and a cancellation are both "not in force".
        // A null code is never a warning — it is the carrier of the
        // all-clear marker.
        if (code is! String || code.isEmpty) continue;
        if (status == kJmaWarningStatusCancelled) continue;
        if (status == kJmaR8StatusNoWarnings) continue;
        final name = kJmaWarningCodes[code];
        if (name == null) continue;
        byCode.putIfAbsent(
          code,
          () => JmaWarningRecord(
            warningCode: code,
            eventName: name,
            status: status is String ? status : '',
            prefectureCode: prefectureCode,
            areaName: areaName,
            reportDateTime: dt,
            headline: headline,
          ),
        );
      }
    }
  }

  final records = byCode.values.toList(growable: false);
  return JmaFeedSnapshot(
    prefectureCode: prefectureCode,
    reportDateTime: newest,
    headline: headline,
    advisories: <Advisory>[for (final r in records) mapJmaWarningToAdvisory(r)],
    records: records,
  );
}

/// True when EVERY area in the document affirmatively declares no warning
/// in force — a publisher all-clear, distinct from an unread feed.
bool jmaR8DeclaresNoWarnings(String body) {
  final dynamic decoded = json.decode(body);
  if (decoded is! List || decoded.isEmpty) return false;
  var sawMarker = false;
  for (final doc in decoded) {
    if (doc is! Map) continue;
    final warning = doc['warning'];
    if (warning is! Map) continue;
    final items = warning['class10Items'];
    if (items is! List) continue;
    for (final item in items) {
      if (item is! Map) continue;
      final kinds = item['kinds'];
      if (kinds is! List) continue;
      for (final kind in kinds) {
        if (kind is! Map) continue;
        if (kind['status'] == kJmaR8StatusNoWarnings) {
          sawMarker = true;
        } else if (kind['status'] != kJmaWarningStatusCancelled) {
          return false;
        }
      }
    }
  }
  return sawMarker;
}
