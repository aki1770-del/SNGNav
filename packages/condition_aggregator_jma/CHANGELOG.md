# Changelog

## 0.1.4 — 2026-06-14 — Dependency hygiene

- Track latest `condition_aggregator` (`^0.0.4`→`^0.0.5`).
- No source or behaviour change.


## 0.1.3

- Republish from the embedded-target Dart 3.10.1 SDK (Flutter 3.38.3) to correct a stale
  `^3.11.0` SDK floor in the previously-published artifact. No source or behavior change; the
  source already declared `sdk: ^3.10.0`. Restores `pub get` for embedded/automotive Dart
  consumers on Dart 3.10.x.

## 0.1.2 — 2026-05-10 — Pana score recovery (Theme α P3)

- Trim pubspec `description` to within the pana 60–180 character target.
- Add minimal `example/main.dart` for pana documentation scoring.
- Apply `dart format` to clear any formatter findings.
- No SDK source changes; metadata + format pass only.


## 0.1.1 — 2026-05-04 — atom-feed byte cap raised to 4 MB

The 0.1.0 byte cap on the atom feed (`50 KiB`) was set conservatively
without a real-world measurement. Observation against the live JMA
`extra_l.xml` endpoint shows the feed is approximately 1.6 MB during
normal cadence — it lists all recent JMA reports across Japan, not
per-point. A 50 KiB cap aborts the fetch at the size guard before
any parsing can run.

`kJmaAtomFeedMaxBytes` raised to `4 * 1024 * 1024` (4 MB), which gives
generous headroom for busy weather days while still preventing a
runaway publisher response from exhausting integrator memory. The
per-report cap (`kJmaReportXmlMaxBytes`, 200 KiB) is unchanged —
prefecture warning XML reports are typically well under that.

No other behavior change. No API change.

## 0.1.0 — 2026-05-04 — first deploy via direct-Dart-XML-parse path

**Status: DEPLOYED** to pub.dev. The provider fetches the JMA
disaster-info atom feed (`extra_l.xml`), filters to the
prefecture-class warning report families
(`気象警報・注意報（Ｈ２７）`, `気象特別警報・警報・注意報`), parses each
linked per-prefecture report XML directly with the canonical Dart
`xml` package, and surfaces winter-snow-class advisories
(大雪警報 / 大雪注意報 / 暴風雪警報 / 暴風雪注意報 / 着雪注意報) as
source-neutral `Advisory` records.

The jmaxml engagement-shape election (alpha/beta/gamma) for an
upstream typed binding remains a separate open question (OQ-1) and
does not block this version's publish.

### Added

- `JmaAdvisoryProvider` now performs real HTTP I/O against the JMA
  atom feed (default
  `https://www.data.jma.go.jp/developer/xml/feed/extra_l.xml`) +
  per-prefecture report XML; the constructor accepts an
  injectable `http.Client` for testing and a configurable
  `userAgent` (default
  `(sngnav-class app, https://github.com/aki1770-del/sngnav)`).
- `JmaAdvisoryFetchException` for transport / non-2xx / oversize-body
  failures (caps: 50 KB atom feed, 200 KB per report, 30 s wall
  clock).
- `parseJmaAtomFeed(String)` + `parseJmaReportXml(String)`
  exposed for direct consumer use against fixture payloads (e.g.
  integrator-side replay tests).
- `JmaAtomEntry` projection of the atom-feed entry fields the
  provider keys on (`title`, `updated`, `author`, `reportUrl`).
- `JmaForecastRecord` re-shaped to carry per-`<Item>` × per-`<Area>`
  publisher fields verbatim (`eventName`, `eventCode`, `headline`,
  `areaName`, `areaCode`, `reportDateTime`, `targetDateTime`).
- `kJmaSnowAdvisoryEventNames` const set — 5 event names the
  adapter surfaces at this version.
- `kJmaPrefectureBoundingBoxes` + `prefectureCodeForPoint` —
  bounding-box catalog for 6 snow-zone prefectures
  (Hokkaido / Aomori / Iwate / Akita / Yamagata / Niigata).
  Points outside the catalog return empty without an HTTP fetch.
- Severity mapping: 警報 → `severe`; 注意報 → `moderate`;
  特別警報 → `extreme`. JMA's verbatim event name is preserved in
  `Advisory.eventClass` either way per Article 17 (β).
- ≥6 new tests covering: prefecture-code resolution, atom-feed
  parse, report-XML parse, snow-class filter, prefecture filter,
  HTTP 5xx → exception, body-cap → exception, no-fetch on
  out-of-catalog point.

### Changed

- `pubspec.yaml`: removed `publish_to: none`; bumped
  `version: 0.0.1` → `0.1.0`; added `http: ^1.0.0`; bumped
  `condition_aggregator: ^0.0.2` → `^0.0.3` (matching
  pub.dev-latest).
- README "Status" replaced "explore-phase scaffold" with the
  direct-parse deploy posture.
- Library doc + provider doc + mapper doc updated to reflect the
  direct-parse path; the placeholder JMA-report-family code
  (`VPWW54`) language replaced with the publisher's per-event
  name (`大雪警報` etc.).

### Open questions retained from 0.0.1

- **OQ-1 jmaxml engagement-shape election** (alpha/beta/gamma) —
  separate from this version's deploy. A future major version may
  swap the direct-parse path for the elected upstream binding;
  the public API is shaped so the swap does not produce churn.
- Per-event-class CAP severity / certainty / urgency table
  validation against multiple JMA sample feeds — 0.1.0 ships a
  conservative suffix-based severity mapping; a richer table
  lands at the same time as the engagement-shape election or
  later if validated against expanded fixtures.
- Prefecture catalogue expansion past 6 (currently
  Hokkaido / Aomori / Iwate / Akita / Yamagata / Niigata) — adding
  prefectures is a deliberate version bump.

## 0.0.1 — 2026-05-06 — Explore-phase scaffold

**Status: superseded by 0.1.0.** This version was never published
(`publish_to: none`); it shipped on disk as the API-shape lock so
consuming packages could wire against the interface during
explore-phase. See 0.1.0 for the first deployed shape.
