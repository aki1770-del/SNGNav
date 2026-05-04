# condition_aggregator_jma

Japan Meteorological Agency (気象庁 / JMA) adapter for the
`condition_aggregator` interface. Maps JMA disaster-info XML feeds
to the source-neutral `Advisory` typed event shape so integrators
consume one shape across publishers (NWS / JMA / etc.) without
caring which publisher authored which advisory.

## Status

**0.1.0 — deployed via direct-Dart-XML-parse path.** The provider
fetches the JMA atom feed
(`https://www.data.jma.go.jp/developer/xml/feed/extra_l.xml` by
default), filters to prefecture-class
気象警報・注意報 reports, parses each linked per-prefecture XML
directly with the canonical Dart `xml` package, and surfaces
winter-snow-class advisories
(大雪警報 / 大雪注意報 / 暴風雪警報 / 暴風雪注意報 / 着雪注意報)
as source-neutral `Advisory` records.

The jmaxml engagement-shape election (alpha/beta/gamma) for an
upstream typed binding remains a separate open question (OQ-1) and
does not block this version's publish. A future major version may
swap the direct-parse path for the elected binding; the public API
is shaped so the swap does not produce churn.

## What this package does

When JMA has issued a 大雪 / 暴風雪 / 着雪 advisory for the driver's
current point in Japan:

1. The provider fetches the JMA atom feed (extra_l) over HTTPS
   with a contactable User-Agent.
2. Atom entries are filtered to the prefecture-class warning
   report titles and to the caller's prefecture code (resolved
   from lat/lon via a bounding-box catalog at 0.1.0; 6 snow-zone
   prefectures: Hokkaido / Aomori / Iwate / Akita / Yamagata /
   Niigata).
3. The linked per-prefecture report XML is fetched and parsed for
   `<Information type="気象警報・注意報（市町村等をまとめた地域等）">`
   (most-granular block) `<Item><Kind><Name>` events.
4. Events whose JA name matches the snow-class catalog
   (`kJmaSnowAdvisoryEventNames`) are mapped to source-neutral
   `Advisory` records via `mapJmaForecastToAdvisory`.
5. The `AdvisoryAggregator` merges the JMA records with sibling
   adapters' records (e.g. `condition_aggregator_nws` records when
   the driver crosses an international boundary or relies on
   multi-source corroboration).
6. The integrator HMI surfaces the typed `Advisory` event with
   severity / certainty / urgency / area / effective / expires
   normalized at the boundary, with JMA's exact wording preserved
   verbatim per Article 17 (β) verbatim-relay discipline.

## Driver-facing loom

When JMA has issued a snow / heavy-snow / blizzard advisory for the
driver's current point on a Japanese road, the integrator HMI
surfaces a typed `Advisory` event normalized into the same shape as
NWS records. The driver sees JMA's authoritative wording verbatim
(event name, area name, headline) without aggregator-class
re-summarization. The driver always drives.

## HER-trace (≤4 hops)

```
JMA disaster-info atom feed (気象庁防災情報XML)
  → JmaAdvisoryProvider (this package; HTTP + XML parse + filter)
  → AdvisoryAggregator (typed merge with sibling adapters)
  → integrator HMI surfaces advisory to driver in unexpected snow.
```

4 hops. D3 anchor: helps the driver in unexpected snow on a
Japanese road. D5 value chain: evidence → contribution →
architecture → edge developer → driver.

## What this package does NOT do

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
- **No road-surface inference.** JMA's domain at this report
  family is meteorological-advisory; road-surface measurement
  lives in JARTIC / NEXCO / prefectural feeds.
- **No prefecture catalog past 6.** Points outside the
  6-prefecture catalog return empty without an HTTP fetch.
  Catalog expansion is a deliberate version bump.
- **No CAP-class certainty / urgency mapping.** `certainty` and
  `urgency` are `unknown` at 0.1.0; the publisher's authoritative
  term is preserved verbatim in `eventClass` either way.

## Severity mapping

- `特別警報` (emergency warning) suffix → `AdvisorySeverity.extreme`
- `警報` (warning) suffix → `AdvisorySeverity.severe`
- `注意報` (advisory) suffix → `AdvisorySeverity.moderate`
- otherwise → `AdvisorySeverity.unknown`

The publisher's authoritative event name is preserved in
`Advisory.eventClass` either way per Article 17 (β).

## Getting started

```dart
import 'package:condition_aggregator/condition_aggregator.dart';
import 'package:condition_aggregator_jma/condition_aggregator_jma.dart';

final jma = JmaAdvisoryProvider(
  userAgent: '(myappname.example, https://example.com/contact)',
);
await jma.init();
final advisories = await jma.fetchActiveAdvisoriesAtPoint(
  latitude: 39.7186, // Akita-shi
  longitude: 140.1024,
);
for (final a in advisories) {
  print('${a.eventClass} (${a.severity.name}) — ${a.areaDescription}');
  // → 大雪警報 (severe) — 秋田中央
}
```

Composition with the NWS sibling adapter:

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
