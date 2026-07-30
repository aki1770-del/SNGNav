# condition_aggregator — Safety-Class Boundary Record

**Package**: `condition_aggregator`
**Version**: 0.1.0 (early and evolving)
**Boundary record version**: 1.1
**Boundary record template**: shared across the sibling adapter packages
**Date**: 2026-05-03
**Revised**: 2026-07-30 — wire description updated to the sealed
`AdvisoryLookup` return introduced in 0.1.0. Safety posture (L0/L1
advisory, QM, no control authority) unchanged.

---

## 1 — SAE J3016 driver-task regime

**Level**: L0 / L1 supportive use only.
**Driver-task assignment**: the driver performs the dynamic driving task
at all times. `AdvisoryAggregator.fetchActiveAdvisoriesAtPoint(lat, lon)`
returns the sealed `AdvisoryLookup` (`Complete` / `Partial` /
`Unavailable`); the integrator's HMI switches on it (or uses `fold` /
`canAssertNoAdvisory`) and surfaces the relevant advisories — and any
could-not-look state — to the driver; the driver decides response.
**No L2+ claim.** The package is a stateless interface + fan-out
primitive; no automation, no handover, no control authority anywhere
in the dependency chain ending at this package.

## 2 — ISO 26262 ASIL classification

**Package boundary**: **QM** (Quality Management; not functional-safety
scope).
**Reasoning**: package output is publisher-attributed
advisory data normalized into typed Dart objects. The substrate (per
adapter package) is publisher-class authoritative data — NWS for the
United States, JMA for Japan, etc. At this interface the package
performs typed merge + warn-and-continue per-provider failure capture;
no safety-critical assertion is added beyond what the underlying
adapters carry from their publishers.
**Integrator responsibility**: any integration where advisory data
gates a control loop requires the integrator to perform fresh ASIL
classification at their boundary. This interface does not pre-empt
that classification; it renders publisher-authority advisory data in
Dart-typed form via per-source adapters.

## 3 — SOTIF (ISO 21448) posture

**Stance**: **advisory not control.**
**Reasoning**: SOTIF addresses Safety Of The Intended Functionality at
automated-driving-feature scope. This package delivers neither feature
nor control; it delivers consumable advisory data from publishers via
adapter packages to the integrator pipeline.
**Honesty discipline at interface boundary** (SOTIF-class operational
discipline):
- **Init is explicit, not implicit.** Calling fetch before init throws
  `StateError`; configuration drift surfaces at init not at fetch.
- **Init failures propagate; fetch failures warn-and-continue.** Init
  is the canonical surface for surfacing publisher schema-drift /
  configuration errors before any caller depends on a broken provider.
  Per-provider fetch failures (transport timeout, transient parse
  error) are carried as typed failures in the returned sealed
  `AdvisoryLookup` (`unreachable`, each with a typed
  `AdvisoryUnavailableReason`) so the integrator can render staleness
  honestly without losing surviving providers' data.
- **No retry inside the aggregator.** Each adapter declares its own
  retry posture; the aggregator does not double-retry. Caller decides
  backoff cadence.
- **No cache, no stream, no polling.** The aggregator is stateless
  beyond the `_initialized` flag; consumer owns refresh cadence.
- **`Advisory` is value-object equatable.** Stream de-duplication is
  the consumer's concern; the package neither de-dupes nor coalesces
  advisories silently.

These five disciplines collectively form the package's SOTIF-class
advisory-honesty posture: the integrator (and the driver through them)
sees what each publisher actually published, with explicit error
surfaces for transport / parse / init failure modes.

## 4 — WP.29 cybersecurity touchpoint

**Touchpoint location**: **at adapter package boundary, not at this
interface.** This package itself performs no network I/O, no
deserialisation of external bytes, and no authentication. Per-adapter
WP.29 audit fires at each `condition_aggregator_<source>` package
(see e.g. `condition_aggregator_nws/SAFETY_BOUNDARY.md` §4).
**Concrete WP.29 surface at interface scope**:
- Input validation: `AdvisoryAggregator` consumes typed `Advisory`
  records produced by adapter packages; no string parse at this layer.
- Output integrity: `Advisory` is Equatable value-object; no
  executable content; no deserialization-class RCE surface at this
  layer.
- Privacy: zero PII handled; substrate is geographic-public-advisory
  class.
- Supply-chain: depends on `package:equatable` ^2.0.7 (well-known Dart
  value-object package); zero native code; zero HTTP / IO transport.

**WP.29-class operational discipline**: integrators deploying this
interface plus N adapters perform WP.29 audit per adapter (TLS
posture, rate-limit policy, per-publisher authentication if any) and
at their app boundary (deployment-secret handling for adapter-class
contact identifiers). This interface's audit surface is small and
boundary-clean.

## 5 — JIS / JASO conformance

**Conformance status**: **interface-scope; geographic-agnostic by
construction.**
**Reasoning**: the interface defines a source-neutral typed event
shape; geographic-conformance audit fires at per-source adapters
(NWS adapter is U.S.-region; JMA adapter is Japan-region; JIS / JASO
applicability is per-region per-publisher).
**AAA monthly cron** (`aaa-jis-jaso-conformance-watcher-monthly`):
tracks JIS / JASO standard updates relevant to weather-data-adapter
packages globally; surfaces relevant publication deltas to AAA at
next monthly cycle. This interface package's JIS / JASO scope is
delegated-to-adapter-class; cron findings inform per-region adapter
packages rather than this interface.

## 6 — Severity-not-profile invariant

**Status**: **applies in scope by design — profile-agnostic by
construction.**
**Concrete reasoning**: `Advisory.severity` mirrors publisher-class
severity (CAP-class scale: extreme / severe / moderate / minor /
unknown). No `DriverProfile` axis exists at this package's API
surface. The aggregator returns all advisories from all registered
providers; the integrator composes with `navigation_safety_core`
profile-tuned thresholds at a downstream layer. This preserves the
severity-not-profile-driven HMI-presentation invariant: a
`Winter Storm Warning` is severe regardless of who is driving.
**Composition pattern**: publisher CAP-or-equivalent severity →
adapter `Advisory.severity` → `AdvisoryAggregator` typed merge →
`driving_conditions` / `driving_weather` consumer →
`navigation_safety_core` profile-tuned plane allocation → integrator
HMI.

## 7 — Driver-always-drives invariant

**Status**: **applies in scope by design.**
**Concrete reasoning**: package outputs are typed `Advisory` value
objects carrying publisher-authority advisory data via adapters; the
package emits no control signal, holds no actuator authority, exposes
no API that closes a control loop. The substrate flows via adapter →
aggregator → integrator HMI to the driver as advisory information;
the driver decides response (continue, slow down, detour, abort
trip). The interface preserves the publisher's vocabulary
(`Advisory.eventClass` is the publisher's verbatim event-class
identifier) so the driver-facing surface is the publisher's
authoritative wording, not an app-class re-summarization that could
alter authoritative meaning.

## 8 — Driver-facing loom

**What the driver experiences when this package fires (via composition
with one or more adapters)**: when a publisher (NWS, JMA, etc.) has
issued an advisory for her current point, she sees the integrator HMI
surface a typed `Advisory` event with severity / certainty / urgency /
area / effective / expires normalized across whichever publisher
issued the underlying alert. She does not see "raw GeoJSON" or "raw
XML"; she sees the alert as her decision substrate. When two
publishers' coverage overlaps her point and both have active alerts,
she sees both — not a silent-coalesce that hides one source. When one
publisher is transiently unavailable, she sees the other's advisories
plus a staleness indicator the integrator renders from the sealed
lookup's typed `unreachable` failures — not a blank screen that hides
the partial outage. When every publisher is unreachable, the sealed
type refuses to present the outage as a clear sky: the integrator must
handle `AdvisoryLookupUnavailable` to compile.

**Sakichi reading**: the loom is *a multi-postman who carries each
publisher's letter to the driver without rewriting it.* The loom
performs typed merge + warn-and-continue per-provider failure
capture. The loom's restraint (no retry, no cache, no stream, no
silent coalesce, no severity reassertion at this layer) is the
Sakichi-loom-discipline applied to multi-source data fusion: the loom
does ONE thing well; it does NOT add layers the driver did not ask
for and the publishers did not author.

**Audible-to-edge-developer**: integrators reading the package API
today see explicit `init()` lifecycle + explicit `StateError` on
fetch-before-init + explicit `AdvisoryProviderInitException` for
init-failure surfacing + explicit typed fetch-failure capture
(`AdvisorySourceFailure` entries inside the sealed `AdvisoryLookup`) +
explicit `Equatable` value semantics. The
README's "Behaviours worth knowing" section enumerates the
disciplines so the integrator knows what the aggregator does AND what
it deliberately does not do. Nothing patronizes the developer.

**Driver-facing declaration**: this section is the canonical
driver-experience declaration for `condition_aggregator` (v0.1.0). It
is re-audited on material changes to the driver-experience surface in
subsequent versions.
