# Changelog

> ⚑ **Three entries below describe versions that were never published.**
> Measured against the pub.dev API on 2026-08-28: **`0.1.6`, `0.4.0` and
> `0.6.0` have no release.** Published versions are `0.1.0`–`0.1.5`, `0.2.0`,
> `0.3.0`, `0.3.1`, `0.3.2`, `0.5.0`.
>
> Their entries are kept rather than deleted: the work described in them is real
> and later versions build on it, and `0.7.0`'s own text refers to "the path this
> package read from 0.2.0 through 0.6.0". **But you cannot install them, and a
> CHANGELOG that reads like a release history when it is partly a development
> log is its own defect.** Read a heading here as "this work happened", not as
> "this version exists".

## 0.7.0 — 2026-08-24 — The provider now reads the path JMA actually serves

**STAGED, NOT PUBLISHED.** Publishing is Chair-only voice.

**BREAKING.** The default feed path and its document schema both change, and a
catalogue code is removed. Read "Migration" below before upgrading.

### `AdvisoryFeedFreshnessReporting` is implemented again

`JmaAdvisoryProvider` implements `AdvisoryFeedFreshnessReporting` and exposes
`feedStaleness`. **0.3.2 implemented it; 0.5.0 and 0.6.0 silently dropped it**
while keeping the in-band notice.

The two are not substitutes. The in-band `kJmaStaleFeedEventClass` record is for
a human reading a list. `feedStaleness` is the channel
`AdvisoryAggregator.canAssertNoAdvisory` reads to decide whether it may assert a
calm road. The interface's own documentation states the consequence of dropping
it: an adapter that does not implement it *"can still serve a frozen document and
still satisfy `canAssertNoAdvisory`"*.

Measured on the 81-day-old Niigata fixture: `canAssertNoAdvisory` returned
**true** through 0.6.0 and returns **false** at 0.7.0.
`test/defect_proof_current_api_test.dart` pinned the old answer as an honest
bound labelled UPSTREAM-OWED; it was not owed upstream. `condition_aggregator`
0.0.10 had already shipped the interface — this package had stopped
implementing it.

**Because of that, `condition_aggregator` is now `>=0.0.10 <0.2.0`** (was
`>=0.0.5 <0.2.0`). Below 0.0.10 the interface does not exist.

### The switch

`JmaAdvisoryProvider` now reads
`https://www.jma.go.jp/bosai/warning/data/r8/{code}.json`.

The path it read from 0.2.0 through 0.6.0 was retired by JMA's **2026-05-29**
防災気象情報 restructure. It never failed — it has answered `200` with a
well-formed document frozen at **2026-05-28** ever since. Re-measured
2026-08-24: Akita `reportDatetime` `2026-05-28T06:11:00+09:00`, ~88 days, while
the live path was 83 minutes old and carried a **濃霧注意報 in force** — a class
this adapter already maps.

Verified live end-to-end through the real provider on 2026-08-24: Akita returns
雷注意報 + 濃霧注意報 effective `2026-08-24T04:14+09:00`, and no feed-health
notice fires, because the feed is genuinely fresh.

The old URL remains exported as `kJmaRetiredWarningJsonBaseUrl` — documentation
of what was replaced, not a fallback. **Do not fetch it.**

### Hokkaido was never actually served

The catalogue carried a single `010000` described as covering Hokkaido. **JMA
has no such office.** Measured against its own area master (frozen at
`test/fixtures/jma_area_offices.frozen_2026-08-24.json`), `'010000' in offices`
is FALSE, and the URL 404s on both the retired and the live path. Every point in
the snowiest prefecture in Japan resolved to a dead code.

It failed loudly rather than falsely — the provider throws, so no driver was
ever told a false all-clear — but Hokkaido was never served. Replaced with the
**eight real offices**: 宗谷 / 上川・留萌 / 網走・北見・紋別 / 十勝 / 釧路・根室 /
胆振・日高 / 石狩・空知・後志 / 渡島・檜山. Verified live: Sapporo, Asahikawa and
Wakkanai all now return in-force advisories.

### The loom for the NEXT migration

⚑ **The root cause was never "we were on the wrong URL". It was that JMA
migrated and nothing noticed for 87 days.** Switching the path closes this
instance and leaves the class open.

The 0.5.0 stale-feed loom worked exactly as designed — measured live, it emitted
「約87日更新されていません」and independently reproduced the 87-day figure. **And
nothing moved for 87 days.** The gap was not the alarm. It was the DIAGNOSIS:
「更新されていません」reads as *the publisher has gone quiet*, which an integrator
can only wait out. The real condition was *this path was retired*, which is a
one-line fix.

0.7.0 adds `kJmaPathRetirementEventClass`. Past
`pathRetirementThreshold` (default **7 days**, vs 6 hours for ordinary
staleness) the notice says a **different thing**, not a louder thing: this
configured path may no longer be served, and a successor should be looked for.
It would have fired on day 8 of 87.

**Its limit, stated because a loom whose bound is hidden is worse than none:**
it fires on absolute age on the path we read. It cannot see a migration on the
day it happens, and it cannot distinguish a retired path from a publisher
outage longer than the threshold — both look identical from one URL. A
cross-surface check against the always-busy national feed COULD separate them;
it was weighed and not built, because it doubles the network surface of every
fetch to sharpen a diagnosis this notice already points at, and this package's
own bearing is against widening the live-fetch perimeter.

### Migration

| was | now |
|---|---|
| `kJmaWarningJsonBaseUrl` = `…/data/warning/` | `…/data/r8/` (old value at `kJmaRetiredWarningJsonBaseUrl`) |
| document root: object | **list** of per-bulletin documents |
| `areaTypes[].areas[].warnings[]` | `warning.class10Items[]` ∪ `class20Items[]` |
| one `reportDatetime` | one per document — **newest** is the feed's freshness |
| catalogue code `010000` | eight real Hokkaido offices |
| feed-health = `kJmaStaleFeedEventClass` | **`kJmaFeedHealthEventClasses`** — key on the SET |

⚑ **Key on `kJmaFeedHealthEventClasses`, not on one member.** Which notice is
emitted now depends on how old the document is. A consumer matching only
`kJmaStaleFeedEventClass` silently stops seeing feed-health signals for exactly
the oldest — most dangerous — documents. This package walked into that trap in
its own test suite during this change, which is why the set is exported.

`parseJmaFeed` / `parseJmaWarningJson` still parse the **legacy** schema and are
still tested against a real legacy document — that is what proves the two
schemas can never be silently confused. Feeding an r8 document to the legacy
parser throws, and vice versa.

### Both granularities are read

`class10Items` and `class20Items` are unioned. Measured 2026-08-24 across 16
prefectures, zero documents carried a code in `class20Items` that
`class10Items` lacked — so class10 alone would have sufficed *in that sample*.
It was a quiet August with four distinct codes nationally: evidence, not proof.
Unioning costs one loop over a document already in memory and makes a
class20-only warning structurally impossible to drop. A sampling window does
not get to decide what a driver is allowed to be told.

### Not done

* **`condition_aggregator_jma` 0.6.0 was staged and never published.** Its work
  (the short-time tier) ships inside this release; pub.dev goes 0.5.0 → 0.7.0.
* No short-time fetch path; parser and mapper only.
* Sapporo resolves to two offices (石狩・空知・後志 and the adjacent 胆振・日高)
  because the boxes overlap. That is this package's documented over-warn
  posture, not a defect, but the boxes are approximate and a finer resolver
  would be an improvement.

## 0.6.0 — 2026-08-24 — The path we read was retired on 2026-05-29, and nobody told us

**STAGED, NOT PUBLISHED.** Publishing is Chair-only voice. This describes a
staged working tree.

### The headline defect: we have been reading a retired path for 87 days

On **令和8年5月29日 (2026-05-29)** JMA began operating its restructured
防災気象情報 system. This package reads
`bosai/warning/data/warning/{code}.json`. Measured 2026-08-23:

```
data/warning/050000.json  (Akita, ours)  reportDatetime 2026-05-28T06:11+09:00
data/r8/050000.json       (Akita, live)  reportDatetime 2026-08-23T23:51+09:00
```

Our path froze **the day before the migration** and has answered `200` with a
well-formed document ever since. At the moment of measurement the live path
carried a **濃霧注意報 in force in Akita** — a class this package already maps
(code `20`) — while the path we read served a 雷注意報 from May.

⚑ **The adapter was not missing a hazard class. It was reading a retired
path, and the retired path never failed — it kept answering, well-formed,
forever.** A frozen feed does not look absent. It looks calm. That is why
0.5.0's stale-feed notice is load-bearing and why it is not sufficient on its
own.

0.6.0 adds `parseJmaR8Feed` for the live r8 schema. **The provider is NOT yet
switched** — see "What is not done".

| | legacy | r8 |
|---|---|---|
| root | one object | **list** of per-bulletin documents |
| warnings | `areaTypes[].areas[].warnings[]` | `warning.class10Items[].kinds[]` |
| freshness | one `reportDatetime` | **one per document** |
| explicit all-clear | none | `status` = `発表警報・注意報はなし` |

The **warning code space is unchanged**, so `kJmaWarningCodes` carries across
the migration untouched. r8 also adds something this family has wanted since
it was founded: an affirmative publisher all-clear (`jmaR8DeclaresNoWarnings`),
which finally distinguishes *"the publisher says nothing is in force"* from
*"we could not read the publisher"*.

**Freshness is the NEWEST document, never the oldest.** Each bulletin family
updates on its own cadence. The negative control, run against an
oldest-document implementation, failed with:

```
Expected: '2026-08-23T14:51:00.000Z'
  Actual: '2026-07-15T21:30:00.000Z'
```

— reporting a feed 83 minutes old as **38 days dead**, firing a false
feed-death notice over a fog advisory genuinely in force.

### The short-time tier, across the same migration

JMA publishes an imminent-disruption tier the ladder does not carry. 0.6.0
parses it for both wire formats: legacy **VPOA50** (typed by `InfoKind`) and
current **VPBS50 府県気象防災速報** (typed by
`Headline/Information[@type="情報タグ"]/Item/Kind/Condition`).

⚑ **On VPBS50 neither `Control/Title` nor `InfoKind` identifies the product** —
both are shared across 記録雨 / 短時間大雪 / 線状降水帯発生 /
線状降水帯直前予測. Keying on either silently accepts the wrong product.

⚑ **Both families are published in parallel, at the same second**, and the
VPBS50 EventID is the legacy one with a leading `K`. A naive whole-feed
consumer double-counts every event; `dedupeShortTimeRecords` collapses the
twins, keeping the VPBS50 record because it carries the typed measurement.

Severity is an **explicit table**, never the ladder's suffix rule. Every
short-time product ends in **情報**; the negative control against a
suffix-delegating implementation failed with:

```
Expected: AdvisorySeverity:<AdvisorySeverity.extreme>
  Actual: AdvisorySeverity:<AdvisorySeverity.unknown>
```

`unknown` sits below `isHighImpact`, so an integrator rendering only
high-impact advisories would have dropped JMA's most urgent products while
faithfully rendering a 注意報.

### ⚑ This tier does not fire earlier than the ladder, and does not reach Akita

Two claims worth stating plainly, because both are easy to assume and both are
wrong:

* **It is not an earlier warning.** JMA's rain criterion is
  「大雨時の災害に関する警報発表中に、キキクルの「危険」（紫）が出現している場合に
  発表するもの」— the warning must already be in force. Measured on the real
  Tokyo timeline of 2026-08-22: 大雨警報 06:19:10Z, short-time product
  08:09:31Z — the ladder **1h50m earlier**. What the tier adds is rarity,
  locality and a measured number, not lead time.
* **短時間大雪 is not issued in this adapter's northern prefectures.** Per JMA
  `introduction_bosaisokuho.pdf` (※R8.2現在) it runs in 14 府県予報区:
  新潟・富山・石川・福井・福島(会津)・山形・滋賀・京都・兵庫・広島・岡山・鳥取・
  島根・岐阜(関ケ原). **秋田 and 北海道 are not among them.** Overlap with this
  package's six prefectures is **山形 and 新潟 only**. Recorded in code as
  `kJmaShortSnowIssuedPrefecturesJa` with tests, because the failure mode is
  silent: an integrator expecting northern snow coverage would wait for a
  bulletin that is never published.

### What is NOT done, and why

* **The provider still reads the retired path.** `parseJmaR8Feed` is complete
  and tested; `JmaAdvisoryProvider` is untouched. Switching it changes the
  live behaviour of a safety adapter across a breaking schema change and
  deserves its own verification cycle rather than riding on this one. Until
  then 0.5.0's stale-feed notice remains the only thing standing between a
  frozen feed and a driver — it works, and it is not enough.
* **No short-time fetch path.** Parser and mapper only.
* **The legacy snow bulletin (VPFJ50) is deliberately unsupported.** It never
  had a typed identity — `InfoKind` was `同一現象用平文情報` for every
  phenomenon and its `Body` was inert — so consuming it would mean matching a
  Japanese headline. Refused, with a test.
* **Snow support is format-verified, not event-verified.** It is built against
  JMA's own published wire-format sample. The May 2026 cutover has not yet
  been exercised by a snow season; winter 2026-27 will be the first.
* **`010000` (Hokkaido) is still catalogued and still 404s** on both the
  legacy and r8 paths. JMA's area master has no such office; Hokkaido is eight
  offices. Every Hokkaido point resolves to a dead code. Left unfixed here
  because repairing it changes which areas resolve, which is out of this
  change's scope. It fails loudly rather than falsely — the provider throws
  instead of returning an all-clear.

### Doc-honesty fix

0.5.0 refuted the claim that the windowless JSON "always reflects the current
in-force state" and corrected `jma_advisory_provider.dart` — but the
correction never reached `lib/condition_aggregator_jma.dart` or `pubspec.yaml`,
the two surfaces an edge developer actually reads. Both now carry it.

## 0.5.0 — 2026-08-16 — A frozen feed can no longer read as a clear road

**Safety fix.** This adapter could not tell the difference between a publisher
that says "no warnings" and a publisher that has stopped saying anything. Both
produced an empty list. It now says which.

### What was measured (all live, 2026-08-16 JST)

* `bosai/warning/data/warning/050000.json` (Akita) — `reportDatetime`
  **2026-05-28T06:11+09:00**, still listing 雷注意報 `status=発表`. ~80 days.
* `150000.json` (Niigata) — **2026-05-26T15:45+09:00**, zero warnings. ~81 days.
  This one rendered as a **clear road**.
* `060000.json` (Yamagata) — **2026-05-28T09:48+09:00**. The feeds did **not**
  freeze in lockstep; any single "frozen at T" figure is wrong.
* The freeze is **nationwide**, not regional: Tokyo, Osaka, Fukuoka and the
  58-entry `map.json` are all frozen in a late-May window.
* **Not a cache artifact.** The origin objects carry
  `last-modified: Wed, 27 May 2026 21:11:58 GMT` behind a `max-age=60`
  CloudFront object with `age: 4` — the current object is 80 days old at
  origin. The sibling `bosai/forecast/` path on the same host was minutes old
  the same second.
* **JMA is not down.** Its official developer feed
  `www.data.jma.go.jp/developer/xml/feed/extra.xml` was **updated one minute
  before the measurement and carried 515 警報・注意報 entries.** The path this
  adapter reads is the website's internal JSON, and it has gone dark while the
  official channel stayed live. **See "Known limitation" below — this release
  does not fix that, and it is the larger defect.**
* Consequence in our own winter instrument: **307 advisories served across 624
  hourly records, 100% with `expires: null`** — 230 from the Akita feed and 77
  from the Yamagata border feed, over HER mother's prefecture.

### ⚑ BEHAVIOUR CHANGE — read this before upgrading

**A returned `List<Advisory>` may now contain a non-weather notice, so
`advisories.isEmpty` is no longer equivalent to "no warnings".**

When a prefecture's document has not been updated for
`staleFeedThreshold` (**default 6 hours**), the provider appends an in-band
`kJmaStaleFeedEventClass` (`気象情報の更新停止`) advisory. It is
`AdvisorySeverity.minor`, below `Advisory.isHighImpact`, with an event class
carrying no 警報/注意報 suffix, so it can never be graded or deduped as
weather. But it **does** flip `isEmpty`, and code shaped like

```dart
if (advisories.isEmpty) showAllClear();   // <-- no longer fires on a dead feed
```

changes behaviour — deliberately, because that branch firing on an 81-day-old
document is the defect. Filter on `eventClass`, or pass a very large
`staleFeedThreshold` to opt out entirely (the fact stays readable via
`parseJmaFeed`). Our own 34 pre-existing provider tests hit this flip and were
updated to opt out; that is disclosed here rather than left for you to find.

*The same property already existed undocumented for
`kJmaIncompleteReadEventClass` since 0.3.0. It is disclosed here too.*

### Added

* **`JmaFeedSnapshot`** + **`parseJmaFeed`** — the whole read, warnings **and**
  the document's own `reportDatetime`, with `ageAt(now)` / `isStaleAt(now, t)`.
  The timestamp now **survives an empty warning list**, which is the entire
  point: `parseJmaWarningJson` parsed `reportDatetime` and discarded it in
  exactly the case where it decides whether a road reads as clear.
* **`buildStaleFeedNotice` / `kJmaStaleFeedEventClass`** — the in-band signal,
  built as the deliberate sibling of `buildIncompleteReadNotice`: that one says
  *"we could not look"*, this one says *"we looked, and what answered is
  stale"*. Carried in band for the same reason — a successful fetch of a dead
  document records no provider error, so there is no error channel to use.
* **`JmaAdvisoryProvider.staleFeedThreshold`** (default
  `kJmaDefaultStaleFeedThreshold` = 6 h) and an injectable `now` clock.

### Deliberately NOT changed — `expires` stays `null`

`expires` means *"the publisher declared it expires at T"*. JMA declares no
machine-readable expiry, so we write none. **We considered and rejected**
deriving one, from either a fixed TTL or the headline's own
「２８日昼過ぎから２８日夜のはじめ頃まで」 — that text has no month and uses a
JMA-defined time band, and parsing it would write **our inference into a field
consumers read as JMA's word**. A fabricated publisher declaration is a worse
defect than the one being fixed. `Advisory.isExpiredAt` therefore still returns
`false` forever for this source, **and that is correct** — judge validity from
feed age, via `JmaFeedSnapshot` or the long-standing `Advisory.stalenessAt`.

### Corrected documentation — statements that were false

* `jma_advisory_mapper.dart` said `expires` was null because *"the next fetch
  reflects the then-current in-force state"*. **Not true.** 80 days of next
  fetches reflected nothing. Withdrawn in place, not quietly deleted.
* Both library headers and the README said the windowless endpoint *"always
  reflects the current in-force state"*. **Windowless is not live.** Corrected.
* The README said *"An empty list means no active surfaced-class warning for
  that point."* **False in the exact case that matters.** Corrected — and note
  its quick-start uses Akita city, the prefecture that was serving the dead
  雷注意報 while that sentence stood.

### Known limitation — NOT fixed here, and it is the bigger one

**This release makes a dead feed self-declaring. It does not make the feed
live.** The `bosai/warning/` path appears abandoned while JMA's official
developer XML feed is current. Migrating this adapter to the official feed is a
larger change (different schema, different area-code space, and it reintroduces
the publication-window problem 0.2.0 moved away from — so it needs a windowless
strategy of its own, not a straight swap). It is recorded as the next work, with
the measurement above as its basis. Until then this adapter will, correctly,
tell you its source is stale.

### Reach — stated plainly

`condition_aggregator_jma` has **0 dependents on pub.dev**; its 30-day download
count sits inside the range our packages register with no human attached. The
known holders of the defective 0.3.1 are **our own** shadow-watch instrument
(`^0.3.1`) and **our own app** (`^0.3.0`). Under Dart's caret rule for
`0.x`, `^0.3.0` and `^0.3.1` both mean `>=x <0.4.0`, so **neither admits 0.4.0
or this 0.5.0.** A `0.3.2` backport is the only vehicle that reaches either.
That decision, and any publish, is the Chair's.


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
