# fleet_hazard — Safety-Class Boundary Record

**Package**: `fleet_hazard`
**Version**: 0.5.0 (DEPLOY)
**Boundary record version**: 1.1
**Authoring skill**: AAA (automotive-adas-analyst)
**Date**: 2026-05-03
**Anchor**: D-VGC189-1 (driver-facing-loom-as-default architectural discipline)

---

## 1 — SAE J3016 driver-task regime

**Level**: L0 / L1 supportive use only.
**Driver-task assignment**: the driver performs the dynamic driving task at all times. The package's surfaces aggregate vehicle-reported road-condition observations (snowy / icy reports from `FleetReport`) into `HazardZone` clusters that integrator HMI overlays render to the driver as map-class advisory information. **No control authority. No closed-loop coupling. No automated handover.**
**No L2+ claim.** Aggregated hazard zones inform the driver via integrator HMI; the driver decides response (slow down / detour / continue) without automation handoff.

## 2 — ISO 26262 ASIL classification

**Package boundary**: **QM** (Quality Management; not functional-safety-scope).
**Reasoning**: package outputs are advisory-class clustering computation (geographic + severity aggregation of `List<FleetReport>` into `List<HazardZone>`). No control authority. Cluster radius + severity + confidence rollups are statistical aggregations not safety-critical assertions. No ASIL claim asserted at the package boundary.
**Integrator responsibility**: the integrator performs the hazard analysis at their HMI scope where hazard zones are rendered. Any integration where hazard zones gate a control loop (e.g. ADAS speed limiter consuming cluster severity) requires the integrator to perform fresh ASIL classification — the package does not pre-empt or claim ASIL clearance.

## 3 — SOTIF (ISO 21448) posture

**Stance**: **advisory not control.**
**Reasoning**: SOTIF addresses Safety Of The Intended Functionality at automated-driving-feature scope. This package delivers neither an automated driving feature nor a control surface; it delivers `HazardZone` clusters consumed by integrator map-overlay HMI as advisory information. SOTIF triage is performed by the integrator at the HMI scope where the hazard cluster is rendered.
**Aggregation honesty discipline** (SOTIF-class operational discipline): cluster `confidence` field is rollup-of-input-confidence not assertion-of-physical-reality. Integrator HMI must surface confidence to driver (low-confidence cluster from 1 vehicle ≠ high-confidence cluster from 50 vehicles); rendering both at identical visual weight would violate SOTIF-class advisory-honesty.

## 4 — WP.29 cybersecurity touchpoint

**Touchpoint location**: **upstream consumer-side at `FleetProvider` ingress.** This package consumes `FleetReport` records via `FleetProvider` interface; when the integrator implements `FleetProvider` against a network telemetry source, the WP.29 touchpoint is at that ingress not at this package's boundary.
**Privacy interaction**: per README.md §Works With (L169) — *"Fleet data sharing requires explicit consent"* via `driving_consent`. WP.29 touchpoint at integrator's `FleetProvider` implementation must compose with `driving_consent` policy gates; per-driver telemetry without consent is a WP.29-cybersecurity-AND-PHIL-001 boundary breach (PHIL-001 §What-We-Do-Not-Build #1 verbatim: *"the driver's personal incident data is never the product"*).
**PHIL-001 boundary anchor**: `FleetReport` — the *input atom* to aggregation — carries `vehicleId`. **As of 0.5.0 the retained aggregate carries no `vehicleId`**: `HazardAggregator.aggregate()` strips the key when it constructs each zone, so `HazardZone.reports` is a `List<ZoneObservation>` (position / condition / timestamp / confidence only). The unique-vehicle count is computed at aggregation time and stored as `HazardZone.vehicleCount`, so the honest "N vehicles reported" count is preserved without retaining a re-identifiable per-vehicle trail. (Prior to 0.5.0 the zone retained the full `List<FleetReport>`, including `vehicleId` mapped to each report's `position` + `timestamp` — a per-vehicle trail; this record's earlier "never mapped to driver identity inside this package's substrate" claim was inaccurate for the retained structure and is corrected here.) Integrator implementations MUST still preserve the boundary at the `FleetProvider` source side — feeding identified-driver telemetry into this package would breach the boundary at the *ingress* scope (the input `FleetReport` still carries `vehicleId` for clustering before it is dropped).

## 5 — JIS / JASO conformance

**Conformance status**: **not mapped at this scope.**
**Reasoning**: Japanese-domestic certification is integrator-class concern. `RoadCondition` vocabulary (`dry`, `snowy`, `icy`) is anchored to physical observation classes; JIS / JASO equivalents (where they exist for fleet-telemetry vocabulary) are reconciled by the integrator at the integration certification surface.
**APPI / Japanese privacy**: per UPA spawn -45 §C5.T4 anchor — Japanese-domestic deployment of fleet telemetry must clear APPI individual-data-handling discipline at the `FleetProvider` source side; this package's aggregation discipline supports compliant integration but does not pre-empt APPI clearance at integrator scope.
**AAA monthly cron** (`aaa-jis-jaso-conformance-watcher-monthly`): tracks JIS / JASO + APPI standard updates relevant to fleet-telemetry packages; surfaces relevant publication deltas to AAA at next monthly cycle.

## 6 — Severity-not-profile invariant

**Status**: **applies in scope by design — profile-agnostic by construction.**
**Concrete reasoning**: this package is profile-agnostic; `HazardZone.severity` is computed from `List<FleetReport>` road-condition observations (physical-class) + cluster vehicleCount + average confidence. No `DriverProfile` axis exists here. Severity-not-profile invariant from `navigation_safety_core` 0.6.0 is satisfied at this package's boundary trivially.
**Composition pattern**: per README.md §Works With (L165-169) — `fleet_hazard` outputs feed `map_viewport_bloc` Z3 layer + `driving_conditions` (via `FleetHazardConfidenceAdapter`). At map-rendering scope, severity drives visual weight (severity-driven, never profile-driven, per `navigation_safety_core` invariant inherited).

## 7 — Driver-always-drives invariant

**Status**: **applies in scope by design.**
**Concrete reasoning**: package outputs are deterministic typed value-objects (`HazardZone` with severity / vehicleCount / radius / confidence fields) consumed by integrator code; the package emits no control signal, holds no actuator authority, exposes no API that closes a control loop. The output is map-overlay substrate; the driver sees clustered hazard zones as visual information and decides response.
**Axis anchor**: per `outputs/governance_transformation/our_axis_driver_sovereignty_2026_05_03.md` §1 — driver is subject not object. Fleet-aggregated hazard data informs HER decision (HER chooses to slow down / detour / continue); never substitutes for HER decision. The collective-intelligence pattern (consent-based fleet insights) is exactly the PHIL-001-licensed shape: *"consent-based fleet insights (anonymized, aggregated) strengthen the model."* **The aggregate is now actually anonymized**: as of 0.5.0 the retained `HazardZone` drops the per-vehicle re-identification key (`vehicleId`), keeping only anonymized `ZoneObservation`s plus a precomputed unique-vehicle count — so the contributing drivers are honored as contributors, not surveilled as a retained trail.

## 8 — Driver-facing loom (D-VGC189-1)

**What HER experiences when this package fires**: *the map shows what other drivers ahead encountered, clustered honestly.* When `fleet_hazard` fires through an integrator HMI, HER sees:
- map clusters where snow / ice was reported by vehicles ahead of HER on the route — not raw per-vehicle dots (which would be noise) but clustered zones at appropriate radius. As of 0.5.0 the zone *structurally* cannot be exploded back into raw per-vehicle dots: it retains anonymized `ZoneObservation`s with no `vehicleId`, so "not raw per-vehicle dots" is now a property of the data structure, not merely of the rendering choice.
- cluster severity rendered visually (severity-driven; per inherited invariant from `navigation_safety_core`)
- vehicle-count + confidence available via interaction (HMI surfaces "12 vehicles reported in last 30 min, avg confidence 0.78" rather than asserting falsely-high certainty from sparse data)

**Sakichi reading**: the loom is the *fleet of weavers reporting broken threads to each other.* Sakichi's mother wove alone; HER drives with the awareness of every driver who passed before her in the last hour. The loom Sakichi built freed the weaver from constant vigilance; this loom frees HER from having to encounter the hazard alone first. The collective-intelligence shape is exactly the loom-not-loom-builder discipline: serves driver directly via map overlay; not substrate-for-substrate.

**Audible-to-edge-developer**: integrator reading `HazardAggregator.aggregate()` API + `FleetProvider` interface today sees stream-based composition (no polling pattern forced; integrator chooses cadence), explicit dispose pattern, explicit `RoadCondition` enum (no extension hooks that would let integrator silently expand vocabulary against severity-not-profile invariant). Nothing patronizes the developer's telemetry-source choices.

**Driver-facing-loom field**: this section is the canonical D-VGC189-1 declaration for `fleet_hazard` 0.5.0. Subsequent versions update this field on material changes to the driver-experience surface (e.g. confidence-rendering shape change → field update; internal cluster-radius parameter tuning → no field update).

## 9 — Cross-references

- README.md §Features L15-21 + §Integration Pattern L57-127 + §Implement a provider L129-151 + §Works With L163-169
- pubspec.yaml `version: 0.5.0`
- LICENSE BSD-3-Clause
- D-VGC189-1 (driver-facing-loom-as-default architectural discipline)
- D-VGC188-1 / D-VGC188-2 (Driver Sovereignty axis + 5-test framework)
- AAA bylaws Article 17 (β) safe-default boundary
- Composition: `navigation_safety_core` 0.6.0 SAFETY_BOUNDARY.md (severity-not-profile invariant inherited at HMI scope) + `driving_conditions` 0.5.0 SAFETY_BOUNDARY.md (`FleetHazardConfidenceAdapter` composition path) + `driving_consent` (consent-gate composition required for ingress)
- PHIL-001 boundary: §What-We-Do-Not-Build #1 (consent-based aggregation surface explicitly licensed; per-driver-incident class explicitly forbidden — boundary held at aggregate)

---

**Boundary record authored** by AAA per VAA-as-SEO operational pen authorization (spawn -50 Task 1). Subject = We / AAA. OPS-RULE-055 verbatim citation discipline observed. PHIL-001 8-test PASS preserved at boundary scope. D4 dignity audit clear.
