# Changelog

## 0.3.2 — 2026-08-16 — The adapter can finally say the feed stopped moving, and says it OUT OF BAND

**The defect, measured live.** On 2026-08-16 the JMA warning document for
**Akita** (`bosai/warning/data/warning/050000.json`) answered HTTP 200 with
`reportDatetime` `2026-05-28T06:11:00+09:00` — **80.3 days old** — and one
in-force `雷注意報` (thunder advisory, code 14, status 発表). **Niigata**
(`150000`) answered with a document **81.9 days old** carrying
`発表警報・注意報はなし` — no warnings at all.

Up to and including 0.3.1 this adapter could express **neither** shape:

* It relayed the dead thunder advisory as a current `moderate` hazard, because
  the JMA JSON still lists it as `発表` and the package has no way to say the
  document itself has stopped being written. Our own winter-evidence instrument
  recorded that dead advisory as an **ACTIVE hazard 355 times** over Akita,
  Yokote and Yuzawa — **198 of them while the measured air temperature was at
  or above 25 °C, the hottest at 34.9 °C.** A thunder advisory from May,
  rendered as in force, at 34.9 °C.
* Worse, when a frozen document lists **nothing**, the adapter returns an empty
  list — the **identical value a genuinely clear sky produces**. A false alarm
  is contradicted by the windscreen. A false all-clear removes the reason to
  look out of it.

**What 0.3.2 adds.** `JmaAdvisoryProvider` now implements
`AdvisoryFeedFreshnessReporting` (condition_aggregator 0.0.10) and reports, from
the publisher's own `reportDatetime`, how old the document it just read actually
is:

```dart
import 'package:condition_aggregator_jma/condition_aggregator_jma.dart';

Future<void> main() async {
  final jma = JmaAdvisoryProvider(userAgent: '(myapp, https://example.com)');
  await jma.init();
  try {
    final advisories = await jma.fetchActiveAdvisoriesAtPoint(
      latitude: 39.7186,
      longitude: 140.1024,
    );
    final stale = jma.feedStaleness; // null when the document is current
    if (stale != null) {
      // stale.documentTime, stale.age, stale.detail
      // Any "no warnings" from this read is NOT evidence of a calm road.
      print('stale by ${stale.age!.inDays} d: ${stale.detail}');
    }
    print('${advisories.length} advisory/advisories');
  } finally {
    jma.close();
  }
}
```

Through `AdvisoryAggregator` it lands on `AdvisoryAggregateResult.staleSources`
/ `.hasStaleSource`, and **`canAssertNoAdvisory` becomes `false`** over a frozen
feed. An integrator that already gates its all-clear on `canAssertNoAdvisory`
gets the correction with **no code change at all**.

**New API (additive; nothing removed, nothing renamed):**

- `JmaAdvisoryProvider.feedStaleness` → `AdvisoryFeedStaleness?`
- `JmaAdvisoryProvider.staleFeedThreshold` (constructor, defaults to 6 h)
- `kJmaDefaultStaleFeedThreshold`
- `jmaFeedReportDatetime(String body)` → the document-level timestamp, readable
  even when the document lists zero warnings

**What 0.3.2 deliberately does NOT change — read this before upgrading.**

- **The returned `List<Advisory>` is byte-for-byte what 0.3.1 returned.** No
  synthetic "feed is stale" advisory is appended to it. That shortcut was built
  and rejected: an integrator that grades hazard by taking the maximum
  `Advisory.severity` across the returned list — with no filter on `eventClass`
  — would convert a statement about the **feed** into a positive assertion of
  small **weather**, and would flip its `isEmpty` branch in the same step.
  `minor` is not a floor at such a consumer; it is a rung on the ladder. A
  feed-health fact must not enter the severity ladder, so it travels out of
  band. `test/frozen_feed_out_of_band_test.dart` fails loudly if anyone later
  reaches for the in-band route.
- **`Advisory.expires` is still `null`.** JMA's warning JSON carries no expiry
  field. Synthesising one would write our inference into a field you read as the
  publisher's word. Use `Advisory.effective` (the document's `reportDatetime`)
  and now `feedStaleness` to age an advisory yourself.
- **The dead advisory is still returned.** Suppressing a stale warning would
  convert a false alarm into a false all-clear, which is the worse failure.

**Honest bounds — what is still broken after this release.**

- **Hokkaido throws.** The catalogued office code `010000` returns **HTTP 404**
  from JMA (verified live 2026-08-16; `011000` returns 200, so the probe is
  sound). Every query from a Hokkaido point therefore raises
  `JmaAdvisoryFetchException`. This is **unchanged from 0.3.1 and is not fixed
  here.** It is left as a loud failure rather than repaired by guessing
  replacement bounding boxes we have not verified — a fabricated box would be a
  silent wrong answer, and this package prefers a thrown exception to a
  confident lie. Hokkaido is the snowiest prefecture in Japan and this is the
  most consequential open gap in the package.
- **`null` from `feedStaleness` is not proof of freshness.** It means "no
  positive evidence of staleness" — which includes a document with no parseable
  timestamp and a fetch that failed.
- **The six-prefecture coverage catalog is unchanged.** A point outside it still
  returns an empty list by design; that empty list is a coverage gap, not a
  measured calm.
- **A release reaches a version *range*, not a lockfile.** If you pin
  `^0.3.0` or `^0.3.1`, `dart pub get` will keep handing you 0.3.1 until you run
  `dart pub upgrade`. If you ship a built application, your users get this only
  when you rebuild.
- **0.3.1 remains on pub.dev.** It was published 2026-07-15; the 7-day
  retraction window closed 24.6 days before this release. It cannot be
  withdrawn, and anyone who pins it and never upgrades keeps the frozen-feed
  blindness.

**Requires `condition_aggregator: ^0.0.10`** (up from `^0.0.5`) — the version
that introduced `AdvisoryFeedFreshnessReporting`. Checked on the real solver
against both known consumer constraints (`^0.0.9` and `>=0.0.3 <0.1.0`): both
intersect to `>=0.0.10 <0.1.0`, so the upgrade resolves.


## 0.3.1 — 2026-07-15 — Surfaced warning classes widened: downpour / typhoon-wind / thunder / fog added (snow-only → all-season)

**The defect.** Up to and including 0.3.0 this adapter recognised only **six
winter-snow warning codes**. Every other JMA warning class was filtered out and
silently discarded. A **大雨特別警報 (torrential-rain emergency warning)** or a
**暴風特別警報 (typhoon-wind emergency warning)** in force over the driver's
point produced an **empty advisory list** — indistinguishable, to a caller, from
a clear sky. A package that reads JMA's warning feed and returns "nothing" while
JMA is broadcasting its highest-level emergency warning is worse than one that
does not read the feed at all: the absence renders as calm.

0.3.1 widens the surfaced set from six codes to fifteen. This is **additive
within 0.3.x**: no signature, type or constant is removed or changed, and the
adapter emits **more** advisories for the same input, never fewer. Callers on
`^0.3.0` receive it as a patch.

- **Newly recognised classes (9),** keyed on the bosai warning JSON numeric
  `code`:
  - `33` → 大雨特別警報 (extreme) · `43` → 大雨危険警報 (extreme, JMA level 40)
  - `03` → 大雨警報 (severe) · `10` → 大雨注意報 (moderate)
  - `35` → 暴風特別警報 (extreme) · `05` → 暴風警報 (severe)
  - `15` → 強風注意報 (moderate) · `14` → 雷注意報 (moderate)
  - `20` → 濃霧注意報 (moderate)
- **The six winter-snow codes behave exactly as before** (06 大雪警報 /
  12 大雪注意報 / 02 暴風雪警報 / 26 着雪注意報 / 36 大雪特別警報 /
  32 暴風雪特別警報), and `kJmaSnowWarningCodes` is retained **unchanged** —
  still the six snow entries — for callers that key on the snow classes
  specifically.
- **New:** `kJmaWarningCodes` — the complete surfaced code→verbatim-name map,
  and the map the parse filter now consumes. Exported.
- **Severity:** 危険警報 (level 40) is checked **before** the bare 警報 suffix,
  which it also ends with; falling through would have under-graded a level-40 to
  `severe`. There is no rung between `severe` and `extreme`, so level 40 maps up
  to `extreme` alongside 特別警報 (level 50) — the caution-adding direction.
- **Behaviour change to be aware of:** a point with, e.g., only a 雷注意報 in
  force previously returned an **empty** list and now returns **one** `Advisory`
  (`moderate`). Callers that treated "empty" as "no weather at all" will now see
  non-snow advisories on the same path. Event names are relayed verbatim, so a
  caller can filter on `eventClass` or on `kJmaSnowWarningCodes` if it wants the
  old snow-only behaviour.
- **Code↔name provenance:** every pair above was read directly from the JMA
  bosai warning frontend's own served `code2WarningInfo` lookup
  (`https://www.jma.go.jp/bosai/warning/`), and cross-checked against a second
  read of the same source. Both reads agree on every code, and both reproduce
  the six existing snow codes exactly.
- **Out of scope:** 氾濫 (river-flood) classes are **not** included — they ride
  JMA's separate `code2FloodWarningInfo` lookup, whose code space collides with
  this map's, on a different JSON branch. They cannot be added without a
  source-branch change.

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
