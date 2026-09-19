# adaptive_reroute — Safety-Class Boundary Record

**Package**: `adaptive_reroute`
**Version**: 0.2.0 (DEPLOY; early-deployment candidate)
**Boundary record version**: 1.2
**Authored by**: the SNGNav maintainers (safety-boundary review)
**Date**: 2026-05-03 (record v1.0); corrected 2026-06-29 (record v1.1); **corrected 2026-07-12 (record v1.2 — honest-absence / Measured-or-Absent contract)**
**Design rule**: this record states, in §8, what the driver experiences when the package's output reaches her.

---

> **CORRECTION NOTICE — record v1.2 (2026-07-12), safety-class.**
>
> Record versions 1.0 and 1.1 described this package's driver-facing surface as a **two-outcome** advisory (reroute / no-reroute) and did not disclose a defect present in code through 0.1.5: **a route whose conditions were entirely unknown was presented to the driver as a clear route, at maximum confidence.** `RerouteEvaluator.evaluate()` returned `RerouteDecision.clear()` — reason *"Route is clear"*, `confidence = 1.0` — whenever no hazard fired, and a hazard cannot fire on data that was never measured (upstream, `driving_weather` ≤ 0.4.4 resolved absent readings into a fabricated clear condition: +5.0 °C, 10 km visibility, `iceRisk = false`).
>
> §1, §3 and §8 below are corrected **downward** to what the code now does, in the same change as the code. The prior record did not state a false property so much as omit a true failure mode — but on a safety record that omission is the same defect class, and it is recorded here rather than quietly overwritten. See CHANGELOG 0.2.0.

## 1 — SAE J3016 driver-task regime

**Level**: L0 / L1 supportive use only.
**Driver-task assignment**: the driver performs the dynamic driving task at all times. The package's `RerouteEvaluator.evaluate()` returns a `RerouteDecision` containing `shouldReroute` (boolean) + `reason` (string) + `confidence` (**`double?` — `null` means the route could not be assessed**) + `isAssessed` (boolean) + `detourWaypoints` (List); the integrator HMI **surfaces this to the driver as advisory; the driver chooses to accept the reroute or override**. The package never autonomously commits a reroute against driver intent.
**Three outcomes, not two (0.2.0)**: the decision reports *reroute* / *no hazard found on the assessed route* / **_could not assess the route_**. The third is a first-class outcome, not a degenerate case of the second. `shouldReroute == false` therefore does **not** mean "safe" — it is also returned when the package had no conditions to judge. **Integrator obligation**: read `RerouteDecision.isAssessed` and surface an unassessed route to the driver as *unknown*, never as an all-clear. A `shouldReroute`-only integration is not a conforming integration at this boundary.
**No L2+ claim.** The detour-waypoint output is consumed by the integrator's routing engine to compute an alternate route — but **the driver decides whether to follow it**. There is no automated handover; no minimum-risk-manoeuvre fallback claim; no take-over-request. The integrator HMI presents the decision; the driver acts.

## 2 — ISO 26262 ASIL classification

**Package boundary**: **QM** (Quality Management; not functional-safety-scope).
**Reasoning**: package outputs are advisory-class decision logic (threshold-driven evaluation of `RouteForecast` against config-tuned hazard thresholds). No control authority. No ASIL-A through ASIL-D claim asserted at the package boundary.
**Integrator responsibility**: any integration where the reroute decision gates a control loop (e.g. autonomous lane-change to detour exit) requires the integrator to perform fresh ASIL classification — the package outputs typed advisory data, not commit-class decisions.
**Early-deployment consideration**: at 0.1.0 the test surface + threshold-magnitudes anchoring + literature-citation discipline are **light** (measured on the README: 88 lines; minimal calibration documentation). The calibration substrate should expand at 0.2.0, before broader deployment. This record does not block 0.1.0 early use, but flags the gap for the next package release cycle.

## 3 — SOTIF (ISO 21448) posture

**Stance**: **advisory not control.**

**Absent-input performance insufficiency (SOTIF-class; the load-bearing entry — added record v1.2, 2026-07-12).** The dominant performance insufficiency of an advisory route-condition layer is not a mis-classified hazard; it is a **confidently-reported absence of hazard on inputs that were never observed**. Through 0.1.5 this package exhibited exactly that: absent conditions resolved to `"Route is clear"` at `confidence = 1.0` — the specification-class SOTIF failure (the function performed as specified; the *specification* could not represent "unknown"). **Mitigated in 0.2.0 at the type level**: measured inputs are tri-state (`SafetyVerdict`), the negative verdict requires complete knowledge, and an unassessable route returns `RerouteDecision.cannotAssess` with `confidence == null`.

**Cry-wolf / alarm-fatigue counter-insufficiency (SOTIF-class)**: the naive mitigation — treat unknown as hazardous ("fail safe") — is **explicitly rejected** and is NOT what this package does. Every coverage gap and offline moment would raise a hazard alert; the driver would learn within one trip that the alert carries no information and would then discount it on the night it is real. The mitigation is the **asymmetry**: positive evidence fires on partial data; only the negative claim requires complete data; unknown is *reported as unknown*. Residual risk is transferred to the integrator HMI, which must render the unknown state distinguishably from the clear state (see §1 integrator obligation).

**Reasoning**: SOTIF addresses Safety Of The Intended Functionality at automated-driving-feature scope. This package delivers an advisory decision layer ("do we reroute now, around what?") consumed by integrator HMI for driver presentation; SOTIF triage is performed by the integrator at the HMI scope where the reroute prompt is rendered to the driver.
**Reroute-thrashing / alarm-fatigue mitigation** (SOTIF-class operational concern): **NOT mitigated in this package.** *(Correction 2026-06-29: a prior version of this record claimed `AdaptiveRerouteConfig` included "minimum-progress-before-reroute logic" providing an explicit SOTIF-class anti-alarm-fatigue mitigation. No such field or logic exists in code — `RerouteEvaluator` evaluates each forecast independently with no minimum-progress or debounce gate. The fabricated mitigation claim is struck.)* Suppressing rapid re-reroute prompts (alarm-fatigue-class driver-confusion failure mode) is the **integrator's responsibility** at the HMI scope, OR a documented carry-forward gap for a future version (see README "Not yet implemented"). The only prompt-gating this package performs is the look-ahead window (`hazardWindowSeconds`) and minimum-confidence-to-act (`minConfidenceToAct`) thresholds in §3's evaluation rules — these limit *which* hazards trigger a reroute, not the *re-prompt cadence*.

## 4 — WP.29 cybersecurity touchpoint

**Touchpoint location**: **upstream consumer-side at `RouteForecast` ingress.** This package consumes `RouteForecast` from `route_condition_forecast` (upstream, per pubspec.yaml dependency); WP.29 touchpoint is at the integrator's forecast-source ingress not at this package's boundary. Package itself ingests no external network data.
**Detour-waypoint output**: the output `detourWaypoints` is fed back to the integrator's routing engine; routing-engine WP.29 surface is at the integrator's `RoutingEngine` implementation (per `routing_engine` package dependency). This package neither holds nor expands the cybersecurity surface.

## 5 — JIS / JASO conformance

**Conformance status**: **not mapped at this scope.**
**Reasoning**: Japanese-domestic certification is integrator-class concern. Reroute-decision logic is geographically-agnostic (consumes typed `RouteForecast` from any region); JIS / JASO equivalents (where they exist for ADAS-routing-class advisory packages) are reconciled by the integrator at the integration certification surface.
**JIS / JASO updates**: not tracked on a schedule. Earlier versions of this record said a monthly watch tracked them for advisory-class navigation packages; no such watch was ever scheduled. The mapping above is revisited when this record is revised.

## 6 — Severity-not-profile invariant

**Status**: **applies in scope by design — profile-agnostic by construction.**
**Concrete reasoning**: this package consumes `RouteForecast` (already-aggregated route hazard data) and `currentPosition`; no `DriverProfile` axis exists at this package's API surface. Reroute decision is computed from threshold-driven evaluation of forecast hazards, not profile-class differentiation. Severity-not-profile invariant from `navigation_safety_core` 0.6.0 is satisfied at this package's boundary trivially.
**Future-version consideration**: if 0.2.0+ introduces profile-class differentiation for reroute thresholds (e.g. `noviceUrban` reroutes earlier than `professional`), the integration MUST flow through `navigation_safety_core` `DriverProfile` factories and MUST preserve severity-not-profile-driven HMI-presentation invariant — verbosity / locale / density may differ; the *visibility and preemption path* of the reroute prompt itself MUST stay severity-driven. This record pre-flags it for the next version's design review.

## 7 — Driver-always-drives invariant

**Status**: **applies in scope by design.**
**Concrete reasoning**: package outputs are deterministic `RerouteDecision` value-objects consumed by integrator HMI; the integrator surfaces the decision to the driver who chooses whether to follow the detour. The package emits no commit-class signal; the integrator's routing engine recomputes route from `detourWaypoints` only when invoked by integrator code (which integrator implements per their UX choice — typically driver-confirms-prompt class).
**Driver agency**: the driver is the subject, not the object. Adaptive routing serves the driver's moment of choice when conditions ahead change. The package surfaces *"should we reroute now? Around what? Why?"* to the integrator HMI; the driver decides. The evaluator (`RerouteEvaluator`) measures the route; the driver chooses how to go around the problem section.

## 8 — What the driver experiences

**What the driver experiences when this package fires**: *the map suggests an alternate route with a clear reason, when conditions ahead actually warrant it — and tells her plainly when it cannot see the road ahead at all.* When `adaptive_reroute` fires through an integrator HMI, the driver sees:
- a reroute prompt only when a hazard falls within the look-ahead window and forecast confidence clears the configured threshold — not on every forecast tick (window + confidence gating; **note**: there is no minimum-progress / anti-thrashing debounce — re-prompt cadence is the integrator's responsibility, see §3 and README "Not yet implemented")
- a reason in plain language (`decision.reason`) — *"black ice 4km ahead, detour adds 8 min"* class — not opaque scoring
- **when the route conditions are unknown — an honest "we could not assess this route", never a green light** (`isAssessed == false`; added 0.2.0). This is the worst case the package is built for: when the feed is gone, the driver is TOLD the road ahead is unknown, rather than shown "Route is clear". *(Record v1.0/v1.1 could not say this, because through 0.1.5 the driver was shown "Route is clear" at confidence 1.0 in exactly that situation. See the correction notice.)*
- an option to accept or decline — the driver's agency preserved at every decision point

**In plain terms**: the package is *the foreman who watches the road ahead and proposes a new route before the driver reaches the problem.* A well-built machine stops when its input breaks — **and does not keep producing when it cannot see its input at all.** Through 0.1.5 this package kept producing: with no input in view it reported a result of perfect quality (`confidence = 1.0`). 0.2.0 restores the stop: an unassessable route halts the claim and says why (`cannotAssess`) — *it tells the driver WHY*. The agency-preservation remains the load-bearing reading: the package does not autonomously redirect the driver; it *informs her decision* — and it does not inform her with a number it never measured.

**For the integrating developer**: integrator reading `RerouteEvaluator` + `DetourPlanner` + `RerouteDecision` API today sees a clean separation (evaluator decides whether; planner decides waypoints; decision wraps both). `AdaptiveRerouteConfig` exposes the hazard look-ahead window (`hazardWindowSeconds`), minimum-confidence-to-act (`minConfidenceToAct`), and detour-offset distance (`detourOffsetMeters`) as integrator-tunable knobs — the integrator decides the magnitudes; the package does not pre-empt those choices. *(The `maxDetourFraction` field is also exposed but is **declared, not yet enforced** — no code path consumes it; see README "Not yet implemented". There is no minimum-progress knob.)* This respects the integrator's domain knowledge.

**Driver-experience section**: this section is the package's declaration of what the driver experiences, first written for `adaptive_reroute` 0.1.0. Subsequent versions update this field on material changes to the driver-experience surface (e.g. introducing profile-class threshold differentiation → field update with severity-not-profile composition discipline; internal threshold-evaluation algorithm change → no field update).

**Calibration substrate at 0.1.0**: the threshold magnitudes (hazard severity → reroute-justified boundary) are **explicitly UNVERIFIED at this version** per README minimal-calibration-documentation state. Flagged for 0.2.0: calibration substrate (literature-citation for justified-reroute thresholds: the `hazardWindowSeconds` and `minConfidenceToAct` magnitudes) should expand before the package is recommended beyond early deployment. Current 0.1.0 deployment depends on integrator providing config that fits their context.

## 9 — Cross-references

- README.md §What it gives you L21-32 + §Use L46-73 + §When to use this L75-84
- pubspec.yaml `version: 0.1.0`
- LICENSE BSD-3-Clause
- Composition: `route_condition_forecast` (upstream input) + `routing_engine` (downstream consumer of detour waypoints) + `navigation_safety_core` 0.6.0 SAFETY_BOUNDARY.md (severity-not-profile invariant inherited if profile-axis introduced 0.2.0+)
- Open item: calibration-substrate expansion for 0.2.0 (literature-citation for reroute thresholds)

---

**Boundary record authored** by the SNGNav maintainers as part of the package's safety review. Quotations in this record are verbatim. At the scope of this boundary, the record passed the project's design review and its equal-treatment review.
