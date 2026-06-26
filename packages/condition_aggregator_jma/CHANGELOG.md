# Changelog

## 0.2.0 — 2026-06-26 — Windowless per-prefecture warning JSON (fixes scroll-off false-negative)

**Source-architecture change (minor bump).** The default data source moves from
the JMA disaster-info **atom feed** (`extra.xml` + per-prefecture report XML) to
the **windowless per-prefecture warning JSON**
(`https://www.jma.go.jp/bosai/warning/data/warning/{areacode}.json`).

- **Why (safety — false-negative fix):** an independent safety audit (AAA) found
  that **both** JMA atom feeds (`extra.xml` and `extra_l.xml`) carry a
  window / scroll-off false-negative for a snow-WARNING package. The atom feed is
  a recent-*publication* window (a stream of the latest reports). A warning that
  is **still in force** but was last re-issued **before** the window opens scrolls
  off the feed and is silently missed — so an active-but-not-recently-re-issued
  大雪警報 could return no advisory, the worst failure for a winter-safety
  adapter. (0.1.6 had already shown the atom-feed path was fragile for a separate
  reason — `extra_l.xml` outgrew the byte cap.)
- **Fix:** the per-prefecture warning JSON has **no window** — it always reflects
  the prefecture's **current in-force** warning state. It is also tiny (~7 KB for
  Akita, verified live 2026-06-26 at 7,424 bytes, HTTP 200) vs ~0.6 MB for the
  national atom feed, so it is lighter on constrained in-vehicle hardware.
- **Snow-class mapping by code.** The bosai warning JSON keys warnings on a
  numeric `code`. The snow codes were verified against the JMA bosai warning code
  taxonomy (cross-checked across three independent references, 2026-06-26) and
  are consistent with the live Akita feed (`14` = 雷注意報, observed in force):
  - `06` → 大雪警報 (severe)
  - `12` → 大雪注意報 (moderate)
  - `02` → 暴風雪警報 (severe)
  - `26` → 着雪注意報 (moderate)
  - `36` → 大雪特別警報 (**extreme** — 特別警報 / emergency level)
  - `32` → 暴風雪特別警報 (**extreme** — 特別警報 / emergency level)

  NOTE — the bosai warning JSON code system is **distinct** from the jmaxml
  report `<Kind><Code>` used by the old path (e.g. `06`=大雪警報 here, vs `33` in
  the report XML), so the codes were re-derived, not carried over.
- **特別警報 (emergency) snow codes added — worst-case coverage.** An independent
  safety audit (AAA) flagged that the catalog mapped 警報 / 注意報 but **not** the
  highest-severity 特別警報 (emergency / `level:50`) snow class — strictly more
  dangerous than 警報, and an unacceptable silent gap for a worst-case
  winter-safety package. Codes `36` (大雪特別警報) and `32` (暴風雪特別警報) were
  added, each verified directly against the JMA bosai warning frontend's own
  served `code2WarningInfo` lookup (2026-06-26): the page inlines
  `36:{nameParts:e.snow[5],elem:"snow",level:50}` with
  `e.snow[5]=["大雪","特別警報"]`, and
  `32:{nameParts:e.wind_snow[5],elem:"wind_snow",level:50}` with
  `e.wind_snow[5]=["暴風雪","特別警報"]` (`level:50` = 特別警報). Both map to
  `AdvisorySeverity.extreme` via the existing 特別警報-suffix rule (checked before
  the bare 警報 suffix, so they do not mis-map to severe).
- **着雪 has no 特別警報 level — none added.** The served `e.snow_accretion` array
  has only the advisory slot populated (`[[],[],["着雪","注意報"],[],[],[]]`), so 着雪
  has no 警報 or 特別警報 level; there is no 着雪特別警報 to add.
- **`暴風雪注意報` has no bosai-JSON code.** JMA's official 注意報 taxonomy has no
  `暴風雪注意報`; the advisory-level counterpart of `暴風雪警報` is `風雪注意報`
  (code `13`), which is outside this version's snow catalog. The name is retained
  in `kJmaSnowAdvisoryEventNames` for back-compat, but the windowless JSON source
  never emits it, so no Advisory is produced for it.
- **Preserved:** the public entrypoint `fetchActiveAdvisoriesAtPoint({latitude,
  longitude}) → Future<List<Advisory>>`, the lat/lon → prefecture bounding-box
  catalog (6 snow-zone prefectures, unchanged), `init()` (still validates the
  User-Agent), `source` / attribution, the severity-by-suffix mapping
  (警報→severe / 注意報→moderate / 特別警報→extreme), and verbatim event-name
  relay (Article 17 β).
- **API changes:**
  - Added: `kJmaWarningJsonBaseUrl`, `kJmaWarningJsonMaxBytes`,
    `kJmaSnowWarningCodes`, `parseJmaWarningJson`, `JmaWarningRecord`,
    `mapJmaWarningToAdvisory`.
  - Removed (atom-path-specific): `kDefaultJmaAtomFeedUrl`,
    `kJmaPrefectureWarningReportTitles`, `kJmaAtomFeedMaxBytes`,
    `kJmaReportXmlMaxBytes`, `parseJmaAtomFeed`, `parseJmaReportXml`,
    `JmaAtomEntry`, `JmaForecastRecord`, `mapJmaForecastToAdvisory`.
  - Constructor: `atomFeedUrl` → `warningJsonBaseUrl` (default
    `https://www.jma.go.jp/bosai/warning/data/warning/`); `userAgent` and
    injectable `client` unchanged.
  - Dropped the `xml` dependency — the JSON path parses via `dart:convert`.
- **Result deduplication:** the same warning code repeats across every
  sub-area / municipality in the JSON; results are deduplicated to one Advisory
  per distinct in-force snow code, with `areaDescription` set to the prefecture
  name (e.g. `Akita`) — the lat/lon resolution is prefecture-level.
- Tests rewritten for the JSON path, including a fixture asserting a `06` code
  maps to a verbatim `大雪警報` Advisory (severity `severe`) and a fixture of the
  real live Akita 雷注意報-only state asserting the snow filter returns `[]`.

## 0.1.6 — 2026-06-26 — Fix: live feed exceeded byte cap (returned no advisories)

- **Bug fix (live-feed-breaking):** the default atom feed was the long-history
  `extra_l.xml`, which has grown past 5 MB (observed 2026-06-26 at 5,356,952 bytes)
  and exceeded the 4 MB `kJmaAtomFeedMaxBytes` cap. As a result **every live
  `fetchActiveAdvisoriesAtPoint(...)` call threw `JmaAdvisoryFetchException:
  response exceeded 4194304-byte cap` and returned NO advisories** — the package
  was non-functional against the live JMA feed.
- **Fix:** switch the default feed to the regular `extra.xml`
  (`https://www.data.jma.go.jp/developer/xml/feed/extra.xml`), observed 2026-06-26
  at 635,035 bytes. It carries the same prefecture-class 気象警報・注意報
  (`VPWW54`) warning entries the adapter needs (verified live, including Akita
  `050000`), in a recent-window (~10 h) form that is what a current-conditions
  lookup wants — JMA re-issues active warnings at its standard update cycles well
  inside that window, and the shorter feed surfaces fewer superseded/cancelled
  reports. It is also lighter to fetch and parse on constrained in-vehicle
  hardware. The 4 MB cap now sits ~6x above the live default-feed size.
- Integrators that explicitly need a longer history can still override
  `atomFeedUrl` at construction time (and raise the cap accordingly).
- Added a regression test asserting the cap accommodates a live-national-feed-sized
  body and pinning the default-feed choice to `extra.xml`.
- No change to the advisory mapping, prefecture filter, or per-report parse path.

## 0.1.5 — 2026-06-24 — Public API: jmaPrefectureName

- Add public `jmaPrefectureName(String code)` (exported via the barrel) — maps a JMA
  prefecture code (e.g. `050000`) to its name, so a consumer UI can show an honest
  place label instead of a raw numeric code.
- No behaviour change to the advisory-mapping path.

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
