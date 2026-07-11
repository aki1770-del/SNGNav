# Changelog

## 0.4.0 — 2026-07-11 — Surfaced warning classes widened: downpour / typhoon-wind / thunder / fog turmoil classes added (snow-only → all-season)

**Warning-class widening (minor bump).** The surfaced warning-class table
widens from the six winter-snow classes to fifteen: nine downpour /
typhoon-wind / thunder / fog turmoil classes are added, so a driver caught in
sudden summer / typhoon turmoil (大雨・暴風-class events) sees JMA's in-force
warnings on the same path that already served the winter-snow classes.

reach-disposition(sngnav-app): pin-lift `^0.3.0` → `^0.4.0` queued behind the
Chair publish batch (hosted resolve; the app's 荒天ウォッチ warnings lane is
the consumer this widening exists for). The SNGNav monorepo pre-trip surface
consumes by path and keeps its winter-scoped road-condition merge — the
turmoil classes reach it as advisory-card work, recorded as a paired W3
follow-on on the portfolio board (its "no active winter warning" caption
stays true as written).

- **New surfaced classes (9), keyed on the bosai warning JSON numeric
  `code`:**
  - `33` → 大雨特別警報 (**extreme** — `level:50`)
  - `43` → 大雨危険警報 (**extreme** — `level:40`, 警戒レベル4相当; see the
    severity note below)
  - `03` → 大雨警報 (severe — `level:30`)
  - `10` → 大雨注意報 (moderate — `level:20`)
  - `35` → 暴風特別警報 (**extreme** — `level:50`)
  - `05` → 暴風警報 (severe — `level:30`)
  - `15` → 強風注意報 (moderate — `level:20`)
  - `14` → 雷注意報 (moderate — `level:20`)
  - `20` → 濃霧注意報 (moderate — `level:20`)
- **Verification provenance:** every code↔name pair above was verified
  directly against the JMA bosai warning frontend's own served
  `code2WarningInfo` lookup (`https://www.jma.go.jp/bosai/warning/`, page
  fetched and the inlined map extracted 2026-07-10 — entries shaped like
  `"03":{shortNameParts:s.rain[3],nameParts:e.rain[3],elem:"rain",level:30}`
  with `e.rain[3]=["レベル３","大雨","警報"]`; the rain-family `nameParts`
  carry a leading `レベルＮ` display part which the composed event name
  drops), and independently cross-checked against a second same-day read of
  the same source. **Both reads agree on every code**, and both reproduce the
  six existing snow codes (06/12/02/26/36/32) exactly.
- **New severity rung handled — 危険警報 (JMA `level:40`, 警戒レベル4相当)
  maps to `extreme`.** The suffix-derived severity mapping previously had no
  危険警報 rule, so 大雨危険警報 would have fallen through to the bare 警報
  suffix → `severe` — under-grading a JMA level-40 (strictly above 警報,
  level 30). A 危険警報 suffix check is added BEFORE the 警報 check;
  `AdvisorySeverity` has no rung between `severe` and `extreme`, so level 40
  maps UP to `extreme` alongside 特別警報 (level 50) — the caution-add-only
  direction.
- **API:** new `kJmaWarningCodes` — the complete surfaced map (6 snow + 9
  turmoil classes) that the parse filter now consumes. `kJmaSnowWarningCodes`
  is **retained unchanged** (its six snow entries only) for back-compat with
  consumers that key on the snow classes specifically; `kJmaSnowAdvisoryEventNames`
  is unchanged. No signature changes.
- **Behaviour change (deliberate):** codes that were previously dropped as
  non-snow now surface — e.g. a prefecture whose only in-force warning is a
  雷注意報 returned `[]` through 0.3.0 and now returns one `moderate`
  Advisory. Consumers that want the snow classes only should filter on
  `kJmaSnowWarningCodes` / `eventClass`. This also shifts one partial-border
  shape: a border read where the reachable prefecture holds ONLY a new
  turmoil class and a sibling fetch fails **threw** (`JmaAdvisoryFetchException`,
  empty-union-with-failure) through 0.3.0, and now returns the turmoil
  Advisory **plus the in-band incomplete-read notice** (the non-empty-union
  path); the truly-empty partial read still throws.
- **濃霧注意報 (fog) included deliberately** for the visibility mission: it
  renders as a moderate card; an integrator whose spoken channel gates at
  ≥warning severity surfaces it visually without adding audio cry-wolf.
- **雷注意報 (thunder) — same severity-gated modality guidance, stated for
  its own habituation profile:** 雷注意報 is near-chronically in force on
  the Sea-of-Japan coast in winter, so integrator UIs will now routinely
  show a moderate thunder card beside snow cards. An integrator whose
  spoken channel gates at ≥warning (`severe`) severity keeps it visual-only
  — the card informs without training the driver to tune out the voice
  lane (the cry-wolf dignity cost falls on the integrator's gating choice,
  which is why it is stated here).
- **Honest scope — NOT covered by this widening:**
  - **氾濫 (river-flood) classes are NOT included.** They ride JMA's separate
    served `code2FloodWarningInfo` map — its own code space
    (`20`/`21`/`22`/`30`/`31`/`40`/`41`/`51`/`53`), colliding with the main
    map's codes — and a different JSON branch, so they cannot be added to
    this table without a source-branch change. Recorded explicitly as out of
    scope.
  - **土砂災害 (landslide) classes were considered and deferred** — the
    driver-facing framing (what a driver should DO with a landslide warning
    while driving) needs domain sign-off before surfacing.
  - Other served classes (波浪 / 高潮 / 風雪 13 / 融雪 17 / 乾燥 21 /
    なだれ 22 / 低温 23 / 霜 24 / 着氷 25) remain unsurfaced at this version;
    adding any of them stays a deliberate version bump.
  - There is **no 暴風危険警報 / 大雪危険警報 / 暴風雪危険警報**: the served
    level-40 slot is populated only for the rain / landslide / flood / tide
    families (`e.wind[4]`, `e.snow[4]`, `e.wind_snow[4]` are all `[]`), so of
    the surfaced classes only 大雨 has a 危険警報 rung.
- **Tests:** every new code pinned to its verbatim name; 危険警報 → `extreme`
  (and 大雨警報 stays `severe` / 大雨注意報 stays `moderate`); the six snow
  codes pinned unchanged in BOTH maps; a realistic warning JSON carrying
  codes `03`+`15` produces the right Advisories; 解除 exclusion covered for
  the new classes; the fixtures that used 雷注意報 (code 14) as the
  "non-surfaced drop" proof updated — 雷注意報 now surfaces (that is the
  point of the widening), and the drop-proof role moved to a genuinely
  non-surfaced code (`21` 乾燥注意報).
- **Unchanged:** the public entrypoint, the prefecture bounding-box catalog
  (6 snow-zone prefectures — coverage widening is a separate, deliberate
  bump), the border-union / partial-read behaviour (0.3.0), `init()`, the
  politeness constants (30 s budget / 256 KiB cap / User-Agent requirement),
  and verbatim event-name relay (Article 17 β).

## 0.3.0 — 2026-06-29 — Conservative prefecture union at borders (over-warn on resolution; partial reads signalled)

**Border-resolution change (minor bump).** Prefecture resolution at a border
changes from **single-first-match** to a **conservative union**: when a lat/lon
falls inside more than one catalogued prefecture bounding box, the provider now
fetches **every** containing prefecture's warning JSON and surfaces the
**merged, deduplicated union** of their in-force warnings.

- **Why (safety — under-warn fix):** the catalogued bounding boxes are crude
  axis-aligned rectangles over irregular prefectures, so adjacent prefectures'
  boxes **overlap along every shared border**. The previous resolver returned
  only the *first* matching box, silently dropping the neighbour(s). No
  single-prefecture tie-break is correct at every border — e.g. a nearest-
  centroid guess merely trades a northern-border error for a southern coastal
  one. The result was that a driver near a prefecture border could **miss** a
  neighbouring prefecture's warning purely because of a resolution guess.
- **Fix:** at a border the provider surfaces **all** candidate prefectures'
  warnings (deduplicated). A driver near a prefecture border may now see a
  neighbouring prefecture's warning — the **safe, over-warn direction**,
  consistent with this package's conservative-on-uncertain philosophy. An
  interior point still resolves to exactly one prefecture (single fetch).
- **Concurrency + budget (single 30 s per prefecture, everywhere):** at a
  **border** (more than one containing prefecture) the prefectures are fetched
  **concurrently**; each per-prefecture fetch carries its **OWN per-request
  timeout** set to the single `kJmaFetchWallClockBudget` (30 s) and **always
  resolves to a captured result** rather than throwing, so **one hung endpoint
  cannot block, fail, or discard the whole batch**. The same 30 s value is used
  for an interior single fetch and for every border sibling — there is
  **deliberately no shorter border budget**. (An earlier draft used a shorter
  10 s per-request cap at borders; it was removed because it could time out
  **HER own slow-but-valid warning**: if her prefecture answers a real 大雪警報
  on a marginal 10–30 s link while the other containing prefecture answers
  fast-empty, the 10 s cap turned her warning into a captured failure → empty
  union + a failure → incomplete-read throw → she got **nothing**. Never drop a
  slow-but-valid warning.)
  - **Latency bound (honest cost):** per-prefecture isolation already prevents a
    hung sibling from blocking or discarding a fast sibling's success, so the
    only cost of the single budget is **latency** — a hung border neighbour can
    make the union take **up to ~30 s** before it returns (carrying the in-band
    incomplete-read notice). That pre-trip latency is **preferred over ever
    dropping a slow-but-valid warning**. The batch-level timeout is retained
    only as the outer backstop for the theoretical case where the `Future.wait`
    combinator machinery itself stalls.
- **Robustness hardening (worst-case / degraded-connectivity):**
  - **Hung-sibling isolation.** Previously a single hung endpoint blocked the
    `Future.wait` batch until the batch-level timeout fired and **threw** —
    discarding an already-successful sibling's warnings. At an Akita / Yamagata
    border with Akita succeeding fast and Yamagata hanging, the driver would
    have got **nothing** where the single-prefecture path gave Akita's
    大雪警報. Each fetch now self-bounds at one per-request budget and is
    captured as a failure, so the successful sibling's warnings are **still
    returned**.
  - **Captured-failure isolation.** Each per-prefecture fetch's catch was
    broadened from `JmaAdvisoryFetchException` to any error, so a raw
    `FormatException` (e.g. from `utf8.decode` of malformed bytes) is captured
    as a failed sibling rather than escaping and discarding a successful one.
  - **Timeout exception shape.** The timeout / all-failed exception now
    preserves a meaningful source `uri` (the per-request path carries it),
    restoring the field the single-prefecture path had.
- **Partial-failure policy (conservative; a partial read is never presented as
  complete):** the over-warn invariant is **unconditional** — whenever a
  containing border prefecture was not successfully checked, the caller (and the
  aggregator) **always learns it**, either by a thrown exception or by an
  in-band notice in the returned list.
  - The union collects every prefecture that fetched successfully; a
    successfully fetched warning is **never** withheld because a sibling fetch
    failed.
  - If **every** prefecture fetch fails, a `JmaAdvisoryFetchException` is thrown
    (the first failure's shape — uri / statusCode / message — is preserved).
  - If the union is **empty AND at least one** containing prefecture **failed**,
    a `JmaAdvisoryFetchException` (**incomplete read**) is thrown rather than
    returning `[]`. An empty list would be a false **'no warnings'** all-clear
    for a border where the unreachable prefecture could hold an active 大雪警報;
    the incomplete read tells the integrator 'could not fully determine', not
    'all clear'. (A genuine all-clear — every containing prefecture succeeded
    with no in-force snow warning — still returns `[]`.) The thrown exception
    preserves the failing sibling's `uri` + `statusCode`.
  - If the union is **non-empty AND at least one** containing prefecture
    **failed**, the real warnings are returned **plus a synthetic,
    clearly-marked, LOW-severity incomplete-read notice** (`Advisory` with
    `eventClass == kJmaIncompleteReadEventClass`, `severity` `minor`) naming the
    unreachable prefecture(s) in Japanese. Previously the captured failure was
    silently discarded here, so a partial border read (e.g. a mild reachable
    着雪注意報 while an unreachable sibling could hold a 大雪特別警報) landed as a
    **complete, fully-successful** result with no staleness signal — a silent
    under-warn at the exact scenario this border-union exists for. The notice
    carries the lowest severity + a distinct event identity, so it can never
    masquerade as — or be deduped against — a real weather warning.
  - **Residual (disclosed, narrowed):** a warning from an **unreachable**
    prefecture cannot be **surfaced** (we cannot read what we could not fetch) —
    but it is no longer silently dropped: a non-empty union with a failed
    sibling now carries the incomplete-read notice **flagging** that an
    unreachable containing prefecture exists. So the union is over-warn on the
    **resolution** guess (it never drops a neighbour because the resolver chose
    one side) **and** signals a partial read; it does **not** guarantee a
    warning held by an unreachable prefecture is shown — only flagged.
- **Driver-facing label localized to Japanese (`areaDescription`).** At a
  border the prefecture label is the load-bearing way a Japanese-reading driver
  tells their own prefecture's warning from an over-warned neighbour's; the
  headline / event name were already verbatim Japanese, so the structured
  `areaDescription` label is now Japanese too (e.g. `秋田県` / `山形県` rather
  than `Akita` / `Yamagata`). New `kJmaPrefectureNamesJa` / `jmaPrefectureNameJa`
  expose the map; the romaji `kJmaPrefectureNames` / `jmaPrefectureName` are
  retained for logs and non-Japanese consumer UIs.
- **Deduplication:** the union is deduplicated on the **full advisory identity**
  (source, event class, severity, certainty, urgency, area, effective, expires,
  headline, description), so two genuinely different warnings (e.g. the same
  snow class reported by two different prefectures, each carrying its own
  prefecture label) both survive, while a byte-identical record is never listed
  twice.
- **API additions (non-breaking):**
  - `prefectureCodesForPoint({latitude, longitude}) → List<String>` — all
    catalogued prefecture codes containing the point, in deterministic catalog
    order (empty when outside the catalog).
  - `prefectureCodeForPoint` is **retained** for back-compat; it now returns the
    **first** containing box (equivalent to the first element of
    `prefectureCodesForPoint`). Callers wanting border-correct behaviour should
    migrate to `prefectureCodesForPoint`.
  - `kJmaPrefectureNamesJa` / `jmaPrefectureNameJa(code)` — the driver-facing
    Japanese prefecture-name map / lookup used for `Advisory.areaDescription`.
    The existing romaji `kJmaPrefectureNames` / `jmaPrefectureName` are
    unchanged.
  - `kJmaIncompleteReadEventClass` — the `eventClass` of the synthetic
    incomplete-read notice (so consumers can match / filter / render it
    distinctly from a real warning).
  - `buildIncompleteReadNotice(List<String> failedPrefectureCodes)` — builds
    that notice (exposed for integrator-side replay / rendering tests).
- **Residual approximation (disclosed):** bounding-box granularity remains
  coarser than actual prefecture geometry. The union is the deliberate
  over-warn handling of that approximation, not a claim of exact prefecture
  geofencing.
- **Unchanged:** the public entrypoint `fetchActiveAdvisoriesAtPoint({latitude,
  longitude}) → Future<List<Advisory>>`, the bounding-box catalog (6 snow-zone
  prefectures), the snow-class code mapping, `init()`, the byte cap, and the
  `JmaAdvisoryFetchException` shape.

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
