# condition_aggregator_jma

A JMA (気象庁 / Japan Meteorological Agency) adapter that fetches live
Japanese weather warnings — the winter-snow classes (大雪 / 暴風雪 / 着雪)
plus, from 0.4.0, the downpour / typhoon-wind / thunder / fog turmoil
classes (大雨 / 暴風・強風 / 雷 / 濃霧) — for a lat/lon point and returns
them as source-neutral `Advisory` records.

## Install

```sh
dart pub add condition_aggregator_jma condition_aggregator
```

`condition_aggregator` is the peer package that defines the shared
`Advisory` type; you need both.

## Quick start

```dart
import 'package:condition_aggregator/condition_aggregator.dart';
import 'package:condition_aggregator_jma/condition_aggregator_jma.dart';

Future<void> main() async {
  final jma = JmaAdvisoryProvider(
    userAgent: '(condition_aggregator_jma example, https://example.com)',
  );
  await jma.init();
  try {
    final advisories = await jma.fetchActiveAdvisoriesAtPoint(
      latitude: 39.7186, // Akita city
      longitude: 140.1024,
    );
    print(jma.source.attributionString);
    if (advisories.isEmpty) {
      print('No active JMA warnings for this point right now.');
    }
    for (final a in advisories) {
      print('${a.eventClass} (${a.severity.name}) — ${a.areaDescription}');
    }
  } on JmaAdvisoryFetchException catch (e) {
    print('Could not reach JMA (offline?): $e');
  } finally {
    jma.close();
  }
}
```

You get back a `List<Advisory>` — each record carries JMA's verbatim
event name (`eventClass`, e.g. `大雪警報`), a normalized `severity`, and
the area name (`areaDescription`). An empty list means no active
surfaced-class warning for that point. The provider does real HTTPS I/O against the
public JMA feed, so it can fail offline — handle
`JmaAdvisoryFetchException` as shown. The same snippet is in
[`example/main.dart`](example/main.dart); run it with
`dart run example/main.dart`.

> Coverage at this version: 6 snow-zone prefectures (Hokkaido / Aomori /
> Iwate / Akita / Yamagata / Niigata). Points outside that catalog
> return an empty list without an HTTP fetch.

---

## Background & provenance

This adapter maps the JMA windowless per-prefecture warning JSON to
the source-neutral `Advisory` typed event shape so integrators consume
one shape across publishers (NWS / JMA / etc.) without caring which
publisher authored which advisory.

### Status

Deployed via the windowless per-prefecture warning JSON path. The
provider resolves the caller's lat/lon to the snow-zone prefecture
(office) code(s) whose bounding box contains the point, fetches each
prefecture's
`https://www.jma.go.jp/bosai/warning/data/warning/{areacode}.json`,
parses the current in-force warnings, and surfaces the surfaced-class
advisories (`kJmaWarningCodes` — the winter-snow classes 大雪警報 /
大雪注意報 / 暴風雪警報 / 着雪注意報 / 大雪特別警報 / 暴風雪特別警報
plus the 0.4.0 turmoil classes 大雨特別警報 / 大雨危険警報 / 大雨警報 /
大雨注意報 / 暴風特別警報 / 暴風警報 / 強風注意報 / 雷注意報 /
濃霧注意報) as source-neutral `Advisory` records.

**Border behaviour (over-warn at prefecture borders).** The catalogued
bounding boxes are crude axis-aligned rectangles over irregular
prefectures, so adjacent boxes overlap along every shared border. A
point in a border zone is legitimately inside more than one box; rather
than guess a single prefecture, the provider fetches **every** containing
prefecture **concurrently** and returns the **deduplicated union** of
their in-force warnings, each labelled with its own (Japanese)
prefecture name. An interior point resolves to exactly one prefecture (a
single fetch). This is the safe, over-warn direction **at the resolution
step**: a driver near a prefecture border never has a neighbouring
prefecture **dropped because the resolver guessed one side** — every
containing prefecture is fetched. (A warning from a prefecture that
cannot be *fetched* is a separate, network-level case, handled below: it
cannot be surfaced, but it is flagged rather than silently dropped.)

**Robustness at the border.** Every per-prefecture fetch — at a **border**
(more than one containing prefecture) and at an **interior** point (exactly
one) alike — carries its own request timeout at the single
`kJmaFetchWallClockBudget` (30 s) and always resolves to a **captured
result**, so one hung or failing endpoint can neither block nor fail the
whole batch. There is deliberately **no shorter border budget**: a single
30 s budget everywhere never times out a slow-but-valid warning arriving on
a marginal link (the false-negative a shorter cap would reintroduce). The
honest trade is **completeness over latency** — because the union waits for
every containing prefecture, a single hung border neighbour can delay the
union up to ~30 s before it returns; that is preferred over ever dropping a
slow-but-valid warning. A successfully fetched warning is
never withheld because a sibling fetch failed. The call throws
`JmaAdvisoryFetchException` only when **every** containing prefecture
fetch fails, or when the union is **empty and at least one** containing
prefecture failed (an incomplete read that must not be presented as a
false 'no warnings' all-clear). When the union is **non-empty and a
sibling failed**, the real warnings are returned **plus a synthetic,
low-severity incomplete-read notice** (`eventClass ==
kJmaIncompleteReadEventClass`) naming the unreachable prefecture(s), so a
partial read is never presented as complete. The disclosed residual: a
warning held by a prefecture that could not be **fetched** cannot be
**surfaced** — but it is now **flagged** by that notice rather than
silently dropped. See CHANGELOG 0.3.0.

**Why the windowless JSON replaced the 0.1.x atom-feed path.** Through 0.1.x the
adapter read the JMA disaster-info atom feed (`extra.xml`) and walked
each linked per-prefecture report XML. An independent safety audit
found a **window / scroll-off false-negative**: the atom feed is a
recent-publication *window*, so a warning that is still in force but
was last re-issued before the window opens scrolls off the feed and is
silently missed — exactly the wrong failure for a snow-WARNING
package, where a stale-but-active 大雪警報 is what the driver must
still see. The windowless `warning/{areacode}.json` always reflects
the *current in-force* state with no window to scroll off (and is
~7 KB per prefecture vs ~0.6 MB for the national atom feed). See
CHANGELOG 0.2.0.

### What this package does

When JMA has issued a surfaced-class warning or advisory — 大雪 /
暴風雪 / 着雪 in winter, or 大雨 / 暴風・強風 / 雷 / 濃霧 in sudden
summer / typhoon turmoil (0.4.0) — for the driver's current point in
Japan:

1. The caller's lat/lon resolves to the snow-zone prefecture (office)
   code(s) whose bounding box contains the point, via a bounding-box
   catalog (6 snow-zone prefectures:
   Hokkaido / Aomori / Iwate / Akita / Yamagata / Niigata). An interior
   point yields exactly one code; a border point can yield more than one
   (the boxes overlap at shared borders). Points outside the catalog
   return empty without an HTTP fetch.
2. The provider fetches each containing prefecture's warning JSON
   (`warning/{areacode}.json`) over HTTPS **concurrently** with a
   contactable User-Agent. Each fetch self-bounds with its own request
   timeout, so one slow or failing prefecture cannot block the others.
3. The current in-force warnings (`areaTypes[].areas[].warnings[]`)
   are parsed; the `timeSeries` forecast block is ignored, and
   cancelled (`解除`) warnings are dropped.
4. Warnings whose numeric `code` matches the surfaced catalog
   (`kJmaWarningCodes`: 06 大雪警報 / 12 大雪注意報 / 02 暴風雪警報 /
   26 着雪注意報 / 36 大雪特別警報 / 32 暴風雪特別警報 /
   33 大雨特別警報 / 43 大雨危険警報 / 03 大雨警報 / 10 大雨注意報 /
   35 暴風特別警報 / 05 暴風警報 / 15 強風注意報 / 14 雷注意報 /
   20 濃霧注意報) are mapped to source-neutral
   `Advisory` records via `mapJmaWarningToAdvisory`, deduplicated to
   one record per distinct in-force code per prefecture. The
   prefecture label (`areaDescription`) is the Japanese prefecture name
   (e.g. `秋田県`), so at a border a driver can tell their own
   prefecture's warning from an over-warned neighbour's.
5. The `AdvisoryAggregator` merges the JMA records with sibling
   adapters' records (e.g. `condition_aggregator_nws` records when
   the driver crosses an international boundary or relies on
   multi-source corroboration).
6. The integrator HMI surfaces the typed `Advisory` event with
   severity / certainty / urgency / area / effective / expires
   normalized at the boundary, with JMA's exact wording preserved
   verbatim per Article 17 (β) verbatim-relay discipline.

> **Note on `暴風雪注意報`.** The JMA bosai warning JSON has no code
> for `暴風雪注意報`; JMA's official 注意報 taxonomy has no such class.
> The advisory-level counterpart of `暴風雪警報` is `風雪注意報`
> (code 13), which is outside this version's snow catalog. The name is
> kept in `kJmaSnowAdvisoryEventNames` for back-compat but the source
> never emits it.

### Driver-facing loom

When JMA has issued a surfaced-class warning — snow / blizzard in
winter, or downpour / typhoon-wind / thunder / fog in sudden summer
turmoil — for the driver's current point on a Japanese road, the
integrator HMI
surfaces a typed `Advisory` event normalized into the same shape as
NWS records. The driver sees JMA's authoritative wording verbatim
(event name, area name, headline) without aggregator-class
re-summarization. The driver always drives.

### HER-trace (≤4 hops)

```
JMA windowless per-prefecture warning JSON (気象庁防災情報)
  → JmaAdvisoryProvider (this package; HTTP + JSON parse + filter)
  → AdvisoryAggregator (typed merge with sibling adapters)
  → integrator HMI surfaces advisory to driver in unexpected snow.
```

4 hops. D3 anchor: helps the driver in unexpected snow on a
Japanese road. D5 value chain: evidence → contribution →
architecture → edge developer → driver.

### What this package does NOT do

- **No retry inside this adapter.** Transient failure handling
  belongs to the integrator's polling cadence; the aggregator's
  `warn-and-continue` posture captures the error through
  `AdvisoryAggregateResult.providerErrors`.
- **No cache, no stream, no polling at this layer.** Stateless
  beyond construction-time configuration; consumer owns refresh
  cadence.
- **No app-class re-summarization.** JMA's `headline` and event
  name pass through verbatim.
- **No profile-driven branching.** Profile-aware UX rendering
  composes downstream against `navigation_safety_core` thresholds.
- **No road-surface inference.** JMA's domain at this warning
  family is meteorological-advisory; road-surface measurement
  lives in JARTIC / NEXCO / prefectural feeds.
- **No prefecture catalog past 6.** Points outside the
  6-prefecture catalog return empty without an HTTP fetch.
  Catalog expansion is a deliberate version bump.
- **No sub-prefecture resolution.** The lat/lon resolves to
  prefecture (office) code(s) — one for an interior point, or the
  containing set at a border; results are deduplicated to one record
  per distinct in-force code per prefecture. Finer sub-region
  targeting is below this adapter's resolution.
- **No CAP-class certainty / urgency mapping.** `certainty` and
  `urgency` are `unknown`; the publisher's authoritative term is
  preserved verbatim in `eventClass` either way.

### Severity mapping

- `特別警報` (emergency warning) suffix → `AdvisorySeverity.extreme`
- `危険警報` (danger warning, JMA `level:40` / 警戒レベル4相当, e.g.
  大雨危険警報) suffix → `AdvisorySeverity.extreme` — checked before the
  bare `警報` suffix, which would under-grade a JMA level-40 to severe;
  `AdvisorySeverity` has no rung between severe and extreme, so level 40
  maps UP (caution-add-only)
- `警報` (warning) suffix → `AdvisorySeverity.severe`
- `注意報` (advisory) suffix → `AdvisorySeverity.moderate`
- otherwise → `AdvisorySeverity.unknown`

The publisher's authoritative event name is preserved in
`Advisory.eventClass` either way per Article 17 (β).

**Spoken-channel gating guidance (habituation / cry-wolf).** 雷注意報 is
near-chronically in force on the Sea-of-Japan coast in winter, and
濃霧注意報 can be similarly persistent — both render as `moderate` cards.
An integrator whose spoken channel gates at ≥`severe` severity surfaces
them visually without adding audio cry-wolf: the card informs without
training the driver to tune out the voice lane she must trust when a
警報-class event speaks.

### Composition with the NWS sibling adapter

```dart
final aggregator = AdvisoryAggregator(providers: <AdvisoryProvider>[
  jma,
  nws,
]);
await aggregator.init();
final result = await aggregator.fetchActiveAdvisoriesAtPoint(
  latitude: 39.7186,
  longitude: 140.1024,
);
// result.advisories carries records from both publishers in the
// source-neutral envelope; result.providerErrors surfaces any
// per-publisher transient failure honestly.
```

## License

BSD-3-Clause. See `LICENSE`.

## Publisher attribution

JMA disaster-info XML feed is open public-data class. Per the
publisher's Terms of Use
(`https://www.jma.go.jp/jma/en/copyright.html` linked from the
feed's `<rights>` element), credit is recommended. The
`AdvisorySource.jmaJapan.attributionString` extension renders the
canonical credit line for driver-facing surfaces.
