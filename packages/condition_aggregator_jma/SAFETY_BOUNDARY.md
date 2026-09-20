# condition_aggregator_jma — Safety-Class Boundary Record

**Package**: `condition_aggregator_jma`
**Version**: 0.7.1 — re-derived against the 0.7.0 code, which 0.7.1 ships
unchanged (compared file by file, comments excluded)
**Boundary record version**: 2.0 (2026-09-20)
**Boundary record template**: shared across the sibling adapter packages
**Date**: 2026-09-20

---

## 0 — What changed since this record was written for 0.1.0

Record 1.1 described a stub: it accepted a latitude and longitude, fetched
nothing, and returned an empty list. That is not what this package does. If
you read the earlier record, six things are different:

- **It fetches.** The adapter is the network edge: it reads one JSON
  document per prefecture office over HTTPS. The earlier record said this
  layer performed no network I/O.
- **An uncatalogued point is answered, not silently empty.** The adapter
  covers 13 of the 58 offices JMA publishes. A point outside those 13 now
  returns one notice saying so. Up to and including 0.5.0 it returned an
  empty list — the same value a covered prefecture returns when nothing is
  in force. That changed in 0.7.0.
- **This adapter now writes advisories of its own.** They report on the
  channel, not on the weather. See §3.
- **Severity is mapped.** The earlier record said every severity was
  `unknown` until a later version.
- **`init()` is no longer a no-op.** It refuses an empty User-Agent.
- **The conformance audit the earlier record promised "before graduation"
  is not recorded**, and the package has been published since 0.1.0. See §5.

## 1 — SAE J3016 driver-task regime

**Level**: L0 / L1 supportive use only.
**Driver-task assignment**: the driver performs the dynamic driving task at
all times. `JmaAdvisoryProvider.fetchActiveAdvisoriesAtPoint(lat, lon)`
returns typed `Advisory` records consumed by the integrator's
weather/condition pipeline; the integrator's HMI surfaces them; the driver
decides the response.
**No L2+ claim.** The package fetches and maps published data and emits
notices about its own read. No automation, no handover, no control
authority anywhere in the dependency chain ending at this adapter.

## 2 — ISO 26262 ASIL classification

**Package boundary**: **QM** (Quality Management; not functional-safety
scope).
**Reasoning**: the output is JMA's published warning data as Dart objects,
plus this adapter's own notices about the state of the read. No
safety-critical assertion is added to the publisher's data: the event term
is JMA's, and the severity is derived from that term by a fixed suffix rule
(§6). The adapter's own notices are the lowest severity and carry event
identities that the suffix rule can never grade as a hazard.
**Integrator responsibility**: any integration where JMA advisory data
gates a control loop requires the integrator to perform a fresh ASIL
classification. This adapter does not pre-empt that classification.

## 3 — SOTIF (ISO 21448) posture

**Stance**: **advisory not control.**
**Reasoning**: SOTIF addresses Safety Of The Intended Functionality at
automated-driving-feature scope. This package delivers neither feature nor
control; it delivers published advisory data, and it states plainly when it
could not look.

**What passes through unchanged, and what this adapter supplies**:
- `eventClass` is JMA's own term for the warning (e.g. `大雪警報`). The
  document carries a numeric code; the term comes from a 15-entry table
  this package ships. A warning whose code is not in that table is dropped.
- `headline` is the document's own `headlineText`, verbatim, and may be
  empty. `description` carries the same string: the source has no separate
  description field, and this adapter does not write one.
- `areaDescription` is the prefecture (office) label this adapter supplies,
  in Japanese — not a per-area name from the document.
- `effective` is the document's own timestamp. **`expires` is always
  `null`**: the publisher declares no expiry here, so an advisory from this
  source never expires by itself and `isExpiredAt` answers `false` forever.
  Judge currency from the feed's age (below), never from `expires`.
- Nothing is translated, summarised or re-worded. Cancellations (`解除`) and
  the feed's own "no warnings in force" marker are filtered out.

**Advisories this adapter writes itself.** Four report on the channel:
the point is outside the catalogue, the document has stopped being updated,
the path it is read from may have been retired, and a containing prefecture
could not be read. They are exported as `kJmaFeedHealthEventClasses` —
**key on the set, not on one member**, because which one is emitted depends
on how old a document is. Each is `AdvisorySeverity.minor`, carries no
警報 / 注意報 suffix, and is in Japanese, like the warnings beside it. They
say *what is not known*; they are never a statement about the weather. The
short-time tier carries a fifth notice of the same kind on its own surface
(below).

**Coverage, stated as a limit**: this adapter ships bounding boxes for 13
offices — eight Hokkaido regional offices, Aomori, Iwate, Akita, Yamagata
and Niigata. **For the other 45 offices it has no data at all**, and says
so in band rather than returning an empty list. An empty list from this
adapter means a covered prefecture was read and nothing was in force.

**Border points over-warn by design**: the boxes are rectangles that
overlap along shared borders, so a point can sit in more than one. Every
containing prefecture is fetched and the deduplicated union returned, so a
driver near a border never misses the neighbour's warning.

**Feed liveness is measured, and reported twice.** Each document's own
timestamp is compared against a threshold this adapter owns (6 hours by
default). When it is exceeded, the age is reported to the aggregator
through `feedStaleness` — which makes `AdvisoryAggregateResult.canAssertNoAdvisory`
false — **and** as an in-band notice, because a frozen feed's worst shape is
an empty answer, and an empty answer cannot carry a field. Past a second
threshold (7 days by default) the notice changes identity: it stops saying
"not updated" and says the path may have been retired, which points at a
fix rather than at waiting.

**When a read fails, nothing is presented as an all-clear**: if every
containing prefecture fails, the fetch throws. If some succeed and some
fail, the warnings are returned with an incomplete-read notice. If the
union is empty and any containing prefecture failed, it throws rather than
answer with a silence.

**No retry, no cache, no stream, no polling.** The consumer owns the
refresh cadence. The provider holds one HTTP client (release it with
`close()`), an initialised flag, and the staleness reading of the most
recent query only.

## 4 — WP.29 cybersecurity touchpoint

**Touchpoint location**: **at this package.** This is a change from record
1.1, which delegated it to a parser binding that was never built.

**The concrete surface**:
- Network: HTTPS `GET` to `https://www.jma.go.jp/bosai/warning/data/r8/`,
  one document per office code. No credentials, no API key, no cookies.
  The path this package read through 0.6.0 was retired by the publisher in
  May 2026; it is kept in the source as a named constant so a reader can
  see what was replaced, and it is not fetched.
- Location privacy: the driver's latitude and longitude are resolved to
  office codes **on the device**. Only the office code appears in the URL.
  The publisher never receives the point.
- Identity: a non-empty User-Agent is required by `init()` and is sent with
  every request. It carries whatever the integrator puts in it; treat it as
  deployment configuration, not as a secret.
- Response handling: a 256 KiB cap per document, a 30-second budget per
  request and for the whole border batch, and strict UTF-8 decoding
  (malformed bytes are rejected, not replaced). Parsing is `dart:convert`
  on JSON; the short-time tier parses XML with `xml ^6.5.0`.
- Output integrity: `Advisory` is an equatable value object. No executable
  content, no deserialisation of code.
- Supply chain: `condition_aggregator` (`>=0.0.10`, the version that
  introduced the freshness contract), `http`, `xml`.

**Operational discipline**: integrators deploying this adapter perform
their own WP.29 audit at their app boundary, including the User-Agent they
configure and their own TLS trust store.

## 5 — JIS / JASO conformance

**Conformance status**: **not mapped at this scope.**
**Reasoning**: Japanese-domestic certification is an integrator-class
concern. A Japanese-domain adapter is the natural seat for a JIS / JASO
audit of the meteorological-advisory leg, and this adapter is that seat —
but record 1.1 said such an audit would fire "before deploy-graduation",
and **no audit is recorded.** The package has been published since 0.1.0
(2026-05-04). Until one is run, treat this section as unmapped, not as
cleared.
**Character encoding**: the JSON path is decoded as strict UTF-8 at this
layer; the short-time tier honours the XML declaration of the document the
integrator supplies.
**JIS / JASO updates**: earlier versions of this record said a monthly
watch tracked them for weather-data-adapter packages. No output from that
watch has been found, so this record no longer says so.

## 6 — Severity-not-profile invariant

**Status**: **applies in scope by design — profile-agnostic by
construction.**
**Concrete reasoning**: `Advisory.severity` is derived from the suffix of
JMA's own term — 特別警報 is extreme, 危険警報 is checked before the bare
警報 so a level-4 warning is not under-graded, 警報 is severe, 注意報 is
lower. It is a fixed rule over the publisher's vocabulary, not a judgment
about a driver: no `DriverProfile` axis exists at this package's API, and
nothing branches on one. `certainty` and `urgency` are `unknown`, because
the source states neither and this adapter will not invent them. The
adapter's own notices are always `minor`.
**Composition pattern**: JMA warning code → this adapter's term table →
`Advisory.severity` by suffix → `AdvisoryAggregator` typed merge →
`driving_conditions` / `navigation_safety_core` profile-tuned presentation
→ integrator HMI. The profile axis enters downstream, never here.

## 7 — Driver-always-drives invariant

**Status**: **applies in scope by design.**
**Concrete reasoning**: the package emits typed `Advisory` records and
nothing else. It holds no actuator authority and exposes no API that closes
a control loop. The driver decides the response — continue, slow down,
detour, abort. The publisher's wording is carried unchanged; where this
adapter speaks in its own words, it speaks about the read, not about the
road.

## 8 — What the driver experiences

**What the driver experiences when this package fires**: inside the 13
covered offices, when JMA has a warning in force for her point, she sees a
typed advisory through the integrator's HMI carrying JMA's own term for the
warning and the document's own headline, in Japanese, with the prefecture
named. Near a prefecture border she may see the neighbouring prefecture's
warning too; that is deliberate over-warning, not a duplicate.

She may also see a sentence this package wrote, not the publisher: that her
point is outside what this adapter covers, that the document has not been
updated, that its path may have been retired, or that one prefecture could
not be read. Those say that something is **not known**. The one that
matters most is the first: for 45 of the 58 offices JMA publishes, this
adapter has nothing, and until 0.7.0 it said nothing — an empty list, the
same answer a quiet, covered prefecture gives. A driver in a Nagano
blizzard was told exactly what a driver on a clear Akita road was told.
That is the defect this record now describes as closed in 0.7.0.

**In plain terms**: this adapter is *the postman for one publisher's
letters in thirteen prefectures, who also tells you when the letterbox is
empty because he was never sent there.* It does not rewrite the letter, and
it does not pretend an unvisited street is quiet.

**For the integrating developer**: read `kJmaFeedHealthEventClasses` to
tell this adapter's own notices from the publisher's warnings, and key on
the whole set. Read `feedStaleness` for the measured age of what you were
just served, and gate any "no warnings" message on
`canAssertNoAdvisory` rather than on an empty list. `expires` is always
`null` here, so do not age advisories with it. Supply a real User-Agent;
`init()` will refuse an empty one. Call `close()` when you are done with
the provider. The short-time bulletin tier is a parser you feed with a
document you fetched yourself — this package does not fetch it.

**Driver-experience section**: this section is the package's declaration of
what the driver experiences, re-derived for 0.7.x against the shipped code.
Subsequent versions update it on material changes to the driver-experience
surface.

## 9 — Cross-references

- `condition_aggregator` interface package: defines the `AdvisoryProvider`
  contract this adapter satisfies, and the freshness-reporting contract it
  implements from `0.0.10`.
- `condition_aggregator_nws`: sibling adapter for the NOAA / NWS publisher
  leg of the same `Advisory` envelope; `noaa_nws_adapter` is the lower-level
  HTTP wrapper beneath it. There is no equivalent lower-level package on
  the JMA side: this adapter reads the publisher's JSON directly.
- `test/outside_coverage_test.dart`, `test/jma_r8_warning_test.dart`,
  `test/frozen_feed_test.dart`, `test/jma_shorttime_test.dart`: the
  behaviours this record describes, as executable checks.
- Package `SAFETY_BOUNDARY.md` siblings: `condition_aggregator`,
  `condition_aggregator_nws`, `noaa_nws_adapter`, `voice_guidance`,
  `driving_weather`, `navigation_safety_core` — per-package boundary-record
  discipline at the data-fusion class.

---

**Boundary record authored** by the SNGNav maintainers as part of the
package's safety review. Quotations in this record are verbatim. At the
scope of this boundary, the record passed the project's design review and
its equal-treatment review.
