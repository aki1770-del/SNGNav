# nav2_safety_layer — Safety-Class Boundary Record

**Package**: `nav2_safety_layer`
**Version**: 0.1.3 (published to pub.dev)
**Boundary record version**: 1.0
**Authoring skill**: FSE (functional-safety-engineer) — **NOT AAA-authored.**
**Date**: 2026-08-21
**Audit status**: ⚑ **UNAUDITED.** FSE is the producer; the producer is never its own auditor
(FSE bylaws C1; OPS-RULE-064(C), OPS-RULE-065(A)). This record is **owed an AAA + DIA audit**
and is not cleared until that audit returns. Nothing below declares any residual *acceptable* —
that judgement is not the producer's to make.
**Scope of this record**: ⚑ **published 0.1.3 as consumers have it on pub.dev.** Where the
working tree has since diverged, the row says so explicitly. **An unpublished fix has reached
nobody** — for every developer who ran `pub add nav2_safety_layer`, a finding marked
*LIVE (published)* is live today.
**Related**: `navigation_safety_core` SAFETY_BOUNDARY.md (direct dependency; its §6
severity-not-profile invariant is **inherited — and, as measured below, NOT upheld by this package**) ·
`rosbridge_dart_client` SAFETY_BOUNDARY.md (sibling ROS-surface record)

---

> ## ⚑ READ THIS FIRST — the name of this package over-claims what the code does.
>
> This package is named `nav2_safety_layer` and publishes under the pub.dev topic `safety`.
> It is **not a safety component.** It is a **one-way, lossy, best-effort advisory-text
> formatter** with no failure-signalling channel of any kind.
>
> **This package cannot tell an integrator that it failed.** Monitor quiet, link degraded,
> message malformed, and advisory throttled are **the same observable event** at its output:
> nothing is emitted. An integrator who treats silence on `advisories` as "no hazard" has
> been misled by the package name, and the code will not correct them.
>
> If you are wiring this into anything that gates a decision, stop and read §3.1.

## What this package does

Accepts `Nav2CollisionMonitorState` / `Nav2CollisionDetectorState` records that **the
integrator constructs and pushes in**, and emits localized driver-facing advisory strings
on a broadcast `Stream<String>`, rate-limited by an `AlertDensityThrottle`
(`lib/src/nav2_safety_layer.dart:44-66`).

## What this package does NOT do

- **Does not connect to ROS 2.** No transport, no subscription, no bridge. The integrator
  owns the transport entirely. Dependencies are exactly `equatable` + `navigation_safety_core`
  (`pubspec.yaml:21-23`) — this is the package's **only structurally-provable safety property**,
  and it is locked by test (see §9).
- **Does not actuate anything.** No steering, braking, accelerator, transmission, or any
  other control surface. Output is `String`.
- **Does not validate the message it was handed.** It has no schema check, no completeness
  check, and no cross-field consistency check. See §3.1.
- **Does not report its own failures.** There is no error channel, no `Stream<Error>`, no
  health signal, no sentinel value, and no exception on malformed input. Every failure mode
  it has is expressed as **silence**.
- **Does not distinguish upstream severity.** All four non-`DO_NOTHING` nav2 actions
  (`STOP`, `SLOWDOWN`, `APPROACH`, `LIMIT`) produce **byte-identical** advisory text — measured,
  §3.1 PI-05.
- **Does not relay `polygon_name` on the monitor path**, despite its own source comment saying
  it does (`lib/src/nav2_safety_mapper.dart:7-10` — **still uncorrected**). Measured, §3.1 D-08.
- **Does not know what kind of hazard it is describing.** `RoadSurfaceCondition` has no
  obstacle member, so an obstacle-in-polygon event cannot be named in the vocabulary this
  package emits. See §3.1 PI-06 residual.
- **Does not preserve the `navigation_safety_core` critical-bypass invariant.** Measured,
  §6 — a nav2 `STOP` can be silently discarded.
- **Does not perform, and cannot perform, the integrator's hazard analysis.** A reusable
  library has no item, no vehicle, no ODD. That analysis is the integrator's, at the
  closed-loop boundary.

## 1 — SAE J3016 driver-task regime

**Level**: L0 / L1 supportive use only. **No L2+ claim.**
**Driver-task assignment**: the driver performs the dynamic driving task at all times. This
package emits advisory strings for an integrator HMI to render; it holds no actuator authority
and closes no control loop.
**Foreseeable-misuse note (ISO 21448 in scope)**: the package name and the `safety` topic tag
invite an integrator to place this inside a safety path. **That placement is misuse**, it is
**foreseeable**, and the package provides no mechanism that would reveal it. See §3.1 PI-07.

## 2 — ISO 26262 ASIL classification

**Package boundary**: **QM** (Quality Management; not functional-safety scope).
**No ASIL-A..D claim is asserted, and none may be derived from this record.**
**Reasoning**: no item, no actuator, no control authority; the output is localized advisory
prose consumed by an integrator HMI.
**Integrator responsibility**: an integrator whose integration places nav2 Collision Monitor
state on a path that gates a decision performs their own hazard analysis at the closed-loop
boundary. This record does not pre-empt it and cannot substitute for it.
**What a QM ceiling cannot do**: it cannot certify this package for any safety-related use.
A QM classification is the statement that the package is **outside** functional-safety scope —
it is not a weaker grade of safety approval. There is no grade here to rely on.

## 3 — SOTIF (ISO 21448) posture

**Stance**: **advisory, not control** — and, more narrowly than the sibling records:
**this package is not even a faithful advisory relay**, because it cannot represent the
absence or corruption of the information it was given.

**The governing insufficiency**: the package renders the *safe-sounding* answer from a
message it could not read. `nav2_collision_monitor` is nav2's **reflexive** safety path —
it reads raw sensors and gates `cmd_vel` in the loop — and `CollisionMonitorState` is that
path's **only external voice**. Converting "I could not read that voice" into "no action
required" is the single conversion this channel must not perform.

The contract this package needed already exists elsewhere in this catalog —
`driving_weather`'s measured-or-absent discipline (*"Nothing was measured… It is NOT 'the
road is clear'"*). It was never applied here.

### 3.1 — Performance-insufficiency table (ISO 21448)

Measured 2026-08-21 against the shipped 0.1.3 source. **PI** = performance/specification
insufficiency (the code does exactly what it was specified to do; the specification is
insufficient — no fault present). **D** = functional defect (the code deviates from a
specification that exists).

| ID | Class | Triggering condition | Insufficiency | Observable effect at the HMI | Correct disposition |
|---|---|---|---|---|---|
| **PI-01** | PI | Truncated/partial frame drops `action_type` | ⚑ **REPAIRED 0.2.0 (2026-08-23)** — absent `action_type` → **`Nav2CollisionAction.unreadable`**, severity **critical**. The pre-repair text follows, kept per the D-07 convention because a consumer may have built on it: `(json['action_type'] as int?) ?? 0` → `DO_NOTHING` (`nav2_collision_msgs.dart:81`) | **Nothing.** Identical to a quiet monitor. | **fail-safe** — surface "unreadable". Currently **fail-silent**. |
| **PI-02** | PI | nav2 adds a 6th action code; or a bridge emits an out-of-range value | ⚑ **REPAIRED 0.2.0 (2026-08-23)** — unknown code → **`unreadable`** (never `doNothing`), severity **critical**. The pre-repair text follows, kept per the D-07 convention because a consumer may have built on it: `default: return doNothing` (`:55-56`), documented as a *"caution-add-only invariant"* | **Nothing**, on every deployment, forever, after an upstream change nobody here observes. | **fail-safe** — surface "unknown code N". Currently **fail-silent**. |
| **PI-03** | PI | `detections` array absent from the detector message | ⚑ **REPAIRED 0.2.0 (2026-08-23)** — absent `detections` → **`anyDetection == null`** (NOT KNOWN), `isReadable == false`. The pre-repair text follows, kept per the D-07 convention because a consumer may have built on it: `?? []` (`:110`) → `anyDetection == false` (`:117`) | **Nothing.** Reads as "no polygon detects anything". | **fail-safe** — surface "unreadable". Currently **fail-silent**. |
| **PI-04** | PI | `polygons` and `detections` lengths disagree (5 vs 2) | ⚑ **REPAIRED 0.2.0 (2026-08-23)** — length mismatch → **unreadable state holding NO pairs**; `triggeredPolygons` empty. The pre-repair text follows, kept per the D-07 convention because a consumer may have built on it: `i < polygons.length && i < detections.length` (`:122`) silently truncates to `min()` | **Partial advisory** naming only the polygons that fit. Corruption is invisible. | **fail-safe** — a length mismatch is proof of corruption. Currently **fail-silent**. |
| **PI-05** | PI | Any non-`DO_NOTHING` action | All four map to one `RoadSurfaceCondition.ice` advisory (`nav2_safety_mapper.dart:30-45`) | `STOP` and `LIMIT` produce **byte-identical** text (measured). Severity is unrecoverable downstream. | **fail-safe** — carry the action class. Currently **information-destroying**. |
| **PI-06** | PI | Any non-`DO_NOTHING` action | Obstacle-in-polygon rendered as a **road-ice claim** the message never made | Driver is told 「凍結路面です。気温0°C以下で薄氷ができています…急ブレーキは避けてください」 — *frozen surface, thin ice, avoid sudden braking* — **in response to an obstacle**. | ⚑ **LIVE (published 0.1.3). CORRECTED IN WORKING TREE 2026-08-21** → `RoadSurfaceCondition.unknown`, 「路面状況不明。慎重に運転してください」. Found by WDA. **Not released — consumers still receive the ice text.** |
| **PI-06-R** | PI | Any non-`DO_NOTHING` action, **after** the in-tree correction | `RoadSurfaceCondition` has **no obstacle member**; the honest value available says the *surface* is unknown | Driver is told the **surface** is unknown when the actual event was **an object in a collision polygon**. Honest, still wrong in domain. | **Residual, recorded not closed.** The vocabulary gap belongs to `navigation_safety_core`, not to this package. |
| **PI-07** | PI | Integrator reads the package name / `safety` topic tag | Name asserts a safety component; code is an advisory formatter with no failure channel | Integrator relies on stream silence as "clear". | **fail-safe** — the name must not out-claim the code. |
| **D-07** | **D** | Advisory burst consumes the throttle cap, then a nav2 `STOP` arrives | ⚑ **REPAIRED 2026-08-21 — the row below is the pre-repair text, kept because a consumer may have built on it.** It read: *"Severity is **hardcoded** `AlertSeverity.warning` (`nav2_safety_layer.dart:47`, `:59`); the core critical-bypass is never reached."* `nav2_safety_layer.dart:84` now passes `severityOf(state.actionType)`, mapping `stop`/`approach` to `AlertSeverity.critical`, which takes the throttle's non-negotiable critical-bypass (`alert_density_throttle.dart:18`). **A STOP after a cap-consuming burst reaches the driver.** Guarded by BI-9, which was INVERTED from a pin into a live regression guard the same day. **Caught by `scripts/stale-pin-check.py`, not by the pen that amended AoU-5 an hour earlier and missed this row.** |
| **D-08** | **D** | Any monitor-path advisory | Source comment claims `polygon_name` is relayed verbatim into advisory `areaDescription`; `toAdvisory` never reads `state.polygonName`, and **`areaDescription` does not exist** in resolved `navigation_safety_core` 0.11.1 | Polygon name absent from monitor-path advisories, contrary to the package's own documented Article 17 (β) discipline. | **README corrected in working tree 2026-08-21** (path-specific). ⚑ **The source comment at `nav2_safety_mapper.dart:7-10` is UNCORRECTED and still names a field that does not exist.** |

**Eight insufficiency rows (PI-01..PI-07, plus the PI-06-R residual) and two defects.** ⚑ **PI-01..PI-04 are REPAIRED in 0.2.0 and are no longer open insufficiencies; four rows remain open (PI-05, PI-06, PI-06-R, PI-07).** The
distinction is load-bearing and is not a matter of taste:

- ⚑ **REPAIRED 0.2.0.** The three tests named below were rewritten to assert the repair; the paragraph is kept because *how* the hazard was enshrined is the lesson. **The specification was the hazard, and the tests were the specification** — which is why fixing the code required rewriting seven tests that pinned the defect, including one asserting the whole channel stayed silent.
- **PI-01, PI-02, PI-04 WERE enshrined by passing tests.** `test/nav2_safety_layer_test.dart:21`
  (*"fromInt degrades unknown to doNothing (caution-add-only)"*), `:37` (*"tolerates missing
  fields"*), `:56` (*"triggeredPolygons handles length mismatch defensively"*). The suite is
  **green on all twelve**. The implementation matches its specification exactly. **The
  specification is the hazard.** That is the definition of a SOTIF insufficiency, and it means
  **a fix that leaves those three tests green is not a fix** — the tests must be inverted, and
  the words *"caution-add-only"* and *"defensively"* removed from behaviour that is neither.
- **D-07 and D-08 are ordinary defects**: each contradicts a specification that already exists
  — D-07 the inherited `navigation_safety_core` §6 critical-bypass invariant, D-08 the
  package's own source comment.

### 3.2 — SEooC assumptions-of-use (ISO 26262 Part 10) — what the integrator inherits

This package is a Safety Element out of Context. It has no item and no ODD of its own.
**If you integrate it, you inherit every assumption below, and you own each one.**

| # | Assumption the integrator must satisfy |
|---|---|
| **AoU-1** | **You do not treat silence on `advisories` as an all-clear.** The package cannot distinguish quiet from broken. If your design reads absence as safety, this package is the wrong component. |
| **AoU-2** | **You validate the ROS message before you hand it in.** Presence of `action_type`; `action_type ∈ {0..4}`; presence of `detections`; `polygons.length == detections.length`. This package performs **none** of these checks and will not fail if you skip them. |
| **AoU-3** | **You own liveness.** The package has no timeout, no staleness clock, no heartbeat. A bridge that dies mid-drive produces exactly the same output as a monitor with nothing to report: nothing. |
| **AoU-4** | **You do not recover severity from the advisory string.** It is not there (PI-05). If you need `STOP` distinguished from `LIMIT`, read `state.actionType` yourself before you call this package. |
| **AoU-5** | ⚑ **AMENDED 2026-08-21 — the previous text was FALSE as of the severity repair and is preserved here because a consumer may have built a workaround on it.** It read: *"You supply your own escalation path for `STOP`. This package will drop it under load (D-07). Do not route a reflexive-stop signal through this package alone."* **D-07 is repaired.** `Nav2SafetyLayer.severityOf` maps `stop`/`approach` to `AlertSeverity.critical`, and `AlertDensityThrottle`'s non-negotiable invariant fires critical regardless of in-window count (`alert_density_throttle.dart:18`). A `STOP` following a burst that consumed the cap **now reaches the driver**, guarded by BI-9. **What still holds:** this package remains QM (AoU-7) and single-path (AoU-3 — no liveness clock), so a reflexive-stop architecture should still not depend on it *alone*; the reason is now liveness and QM scope, **not** a dropped STOP. |
| **AoU-6** | ⚑ **AMENDED 2026-08-21 — the previous text was FALSE as of the mapper repair.** It read: *"You accept that the advisory text names road ice regardless of what the monitor actually reported (PI-06), and you decide whether that text may be shown to a driver. We would not show it."* **The fabrication is removed**: obstacle events now map to `RoadSurfaceCondition.unknown`, yielding 「路面状況不明。慎重に運転してください」 — which claims nothing about the surface. Guarded by BI-7. **The RESIDUAL is real and is NOT closed:** nav2 reported an *obstacle*; `RoadSurfaceCondition` has no obstacle member, so no value in that enum can say what actually happened. The text is now honest and still wrong in **domain**. You decide whether to show it. |
| **AoU-7** | **You perform the hazard analysis.** QM at this boundary. No ASIL is claimed, and none can be inherited from here. |
| **AoU-8** | **You own the transport, TLS, and authentication.** Nothing here touches a network. |
| **AoU-9** | **You verify the nav2 action-code set against the version you deploy.** `ActionType` is declared **twice upstream with nothing linking them** — the C++ enum (`nav2_collision_monitor/include/nav2_collision_monitor/types.hpp:68-74`) and the `.msg` constants (`nav2_msgs/msg/CollisionMonitorState.msg:2-6`). No static assertion, no generated binding, no test spans the two. A future divergence is silent both upstream and here (PI-02). |

## 4 — WP.29 cybersecurity touchpoint

**Touchpoint location**: **none at this package boundary.** No network surface, no ingress, no
OTA surface, no credential handling, no deserialization of untrusted bytes (the integrator
supplies already-decoded maps). Dependencies: `equatable`, `navigation_safety_core` — no native
code.
**Integrator responsibility**: the integrator's ROS-Dart bridge is the ingress and therefore the
WP.29 touchpoint owner. Note the interaction with §3.1: because this package cannot signal
malformed input, **a message-injection or corruption attack on the bridge presents here as
silence**, not as an error. Detection must live in the integrator's transport layer; it cannot
live here.

## 5 — JIS / JASO conformance

**Conformance status**: **not mapped at this scope.** Japanese-domestic certification is
integrator-class. Per the inherited `navigation_safety_core` boundary record: consult a
qualified Japanese-domestic functional-safety partner before any IVI-vendor or OEM-pilot
integration targeting that surface.
⚑ Note that this package **emits Japanese driver-facing text** (measured, §3.1 PI-06) while
mapping a non-Japanese-sourced obstacle signal. The wording is a driver-facing safety
communication and has had no domestic review — including the corrected
「路面状況不明。慎重に運転してください」 now in the working tree.

## 6 — Severity-not-profile invariant

**Status**: ⚑ **DECLARED BY THE DEPENDENCY, NOT UPHELD BY THIS PACKAGE.**

`navigation_safety_core/SAFETY_BOUNDARY.md:41-50` declares the invariant and its
critical-bypass: *"per-profile differentiation lives in `AlertExplainer` … + `AlertDensityThrottle`
(per-profile alerts/min cap with critical-bypass invariant) — never in the visibility or
preemption path."* The sibling `navigation_safety` record calls it **load-bearing**.

**This package defeats it by construction.** `lib/src/nav2_safety_layer.dart:47` and `:59` pass
`AlertSeverity.warning` **hardcoded, for every event**. `AlertSeverity.critical` is never
constructed anywhere in this package. The core's bypass therefore **never engages**, and the
density cap — designed to suppress advisory-tier chatter — is left gating the most severe
signal nav2 can send.

**Measured reproduction (2026-08-21)**: `AlertDensityThrottle(alertsPerMinuteCap: 2)`;
five `LIMIT` events consume the cap; a subsequent `STOP` on polygon `IMMINENT_FRONT`
→ **delivered to driver = false**. Independently, the same throttle instance returns
`true` for `AlertSeverity.critical` after cap exhaustion — the bypass works; this package
simply never asks for it.

**Consequence for HER**: the busier the monitor, the more likely the stop is discarded.
The failure is worst exactly when the road is worst.

## 7 — Driver-always-drives invariant

**Status**: **applies in scope, and is the one invariant this package holds by construction.**
The package emits `String`. It mounts no actuator, suppresses no input, locks no driver out,
and — provably — cannot reach ROS 2 at all, because it declares no transport dependency
(`pubspec.yaml:21-23`, locked by test; §9). The driver always drives.
**This is a real guarantee and it is narrow.** It says the package cannot make the vehicle do
anything. It says nothing about whether what the driver is told is true or timely; §3.1 and §6
say it is often neither.

## 8 — Driver-facing loom (D-VGC189-1) — what HER experiences

**Honestly stated, from measurement rather than intent:**

- When the monitor is quiet, HER sees nothing. **Correct.**
- When the bridge has died, the frame was truncated, the array was dropped, or nav2 shipped a
  new action code, HER sees **nothing — and it looks exactly like "correct"**. She has no way
  to know the channel went dark, and neither does the developer who built her HMI.
- When an obstacle is detected, HER is told — **in published 0.1.3, today** — that the **road is
  frozen and thin ice has formed**, and is advised **to avoid braking sharply**, for an obstacle.
  The advisory names a cause nobody measured and counter-instructs the manoeuvre the upstream
  `STOP` exists to demand. ⚑ **Corrected in the working tree on 2026-08-21 and NOT PUBLISHED**:
  she is now told 「路面状況不明」 — the surface is unknown — which claims nothing false, and
  still does not tell her an object is in the way, because no such word exists in this
  vocabulary (PI-06-R).
- When several low-urgency events precede a real `STOP`, **HER is told nothing about the stop.**

**Sakichi reading**: this loom does not stop when the thread breaks. It keeps weaving and the
cloth looks finished. Sakichi's loom was worth building because it **stopped and showed the
break** — a loom that hides the break is worse than no loom, because the weaver stops checking.
That is the defect class here, stated once: **every failure mode of this package is
indistinguishable from success.**

**Audible-to-edge-developer**: an integrator reading the current README sees *"caution-add-only
invariant"*, *"verbatim relay"*, and *"so the driver in unexpected snow does not face
alert-fatigue"* (README:23, :89-94). Measured against the code: the caution-add-only invariant
**adds no caution** — it removes it; the verbatim relay **does not occur on the monitor path**;
and the alert-fatigue throttle **discards `STOP`**. Until the README is corrected, the
documentation actively works against the developer's ability to see this. That is a D4 matter
and it is named here rather than left for them to discover.

## 9 — Code-enforced invariants (FSE bylaws C4 — the document is the byproduct)

Per FSE bylaws C4, a safety document with no code-enforced invariant behind it is papers-as-end
and is cut. This record is backed by an executable oracle:

**`test/safety_boundary_invariant_test.dart`** — pins every claim above that is mechanically
checkable, so that a future change which alters the boundary **fails a test instead of silently
invalidating this file**. It locks:

- **BI-1** — no transport dependency (`pubspec.yaml` deps == exactly `equatable`,
  `navigation_safety_core`). This is what makes §7's *"cannot actuate"* **provable** rather than
  asserted. Adding any ROS/HTTP/socket dependency fails the test and forces a boundary re-audit.
- **BI-2..BI-5** — ⚑ REPAIRED 0.2.0. Formerly the four silence-on-unreadable-input insufficiencies (PI-01..PI-04), pinned
  as **known-unsafe current behaviour**, each naming its table row. If any is fixed, the test
  fails — deliberately — and the fixer must update this record in the same change.
- **BI-6** — the severity collapse (PI-05): `STOP` and `LIMIT` advisory text byte-identical.
- **BI-7** — the false-cause attribution (PI-06) and its residual (PI-06-R). ⚑ **These two
  tests earned their keep during this audit**: written at 05:30 against published 0.1.3, they
  FAILED at 05:32 because another seat had corrected the mapper in between. The oracle caught a
  boundary record going stale within two minutes of being written, which is precisely the drift
  it exists to catch. Rewritten against the measured present; the published-0.1.3 text is
  preserved in the test's own header so the prior state is not lost.
- **BI-8** — the monitor path does not relay `polygon_name` (D-08).
- **BI-9** — **the `STOP`-droppable defect (D-07)**, reproduced end-to-end.

These tests **do not assert the behaviour is correct.** They assert it is *what is currently
shipped*, so the gap between this record and the code cannot widen silently. That is the only
honest form available without changing the behaviour of a published package — which is a
delivery decision (PDS/WDA), not a producer's.

## 10 — Cross-references

- `lib/src/nav2_collision_msgs.dart:43-58` (`fromInt` default), `:78-85` (`fromJson` defaults),
  `:106-114` (detector `fromJson`), `:117` (`anyDetection`), `:120-126` (`triggeredPolygons`)
- `lib/src/nav2_safety_layer.dart:44-49` (monitor path), `:47` `:59` (**hardcoded
  `AlertSeverity.warning`**), `:56-66` (detector path)
- `lib/src/nav2_safety_mapper.dart:7-10` (the `areaDescription` claim — D-08), `:23-47`
  (four-actions-to-one mapping — PI-05)
- `test/nav2_safety_layer_test.dart:21`, `:37`, `:56` — the three green tests that enshrine
  PI-02, PI-01, PI-04
- `test/defect_proof_absent_state_test.dart` — ⚑ re-run 2026-08-23 after the 0.2.0 repair: **+4 -0** (PI-01..PI-04 all REPAIRED). It read **+0 -4** on 2026-08-21, and that failure WAS the evidence; the same four tests are now the guard that the collapse cannot return.
- `test/well_formed_advisory_test.dart` — the concurrent seat's success-path suite (+48), which
  found PI-06 by feeding **well-formed** input where the four prove-it-fails tests fed only
  malformed input and were structurally incapable of catching it
- `test/safety_boundary_invariant_test.dart` — the §9 oracle
- `navigation_safety_core/SAFETY_BOUNDARY.md:41-50` — the severity-not-profile invariant this
  package inherits and does not uphold (§6)
- `rosbridge_dart_client/SAFETY_BOUNDARY.md` — sibling ROS-surface record
- Upstream contract: `nav2_msgs/msg/CollisionMonitorState.msg:1-10`,
  `nav2_msgs/msg/CollisionDetectorState.msg:1-4`,
  `nav2_collision_monitor/include/nav2_collision_monitor/types.hpp:68-74`
  ⚑ **read from a local checkout at `/home/komada/nav2ci/ws/src` that has NO `.git` directory
  and therefore NO verifiable upstream SHA.** The contract quoted here is UNVERIFIED against a
  named upstream revision. See the bounds note below.
- LICENSE: BSD-3-Clause

---

## Bounds of this record

- **Not audited.** FSE produced it. AAA + DIA audit is **owed**. Until it returns, every
  verdict here is a producer's verdict.
- **No residual is declared acceptable.** Nine findings are recorded; none is closed. Whether
  any is tolerable is an integrator's decision within their item, or an auditor's within ours.
- **QM ceiling.** This record certifies nothing. It cannot make this package fit for a safety
  function, and no ASIL is claimed or derivable.
- **Upstream contract unverified against a revision.** See §10.
- **No runtime, no vehicle, no integrator observed.** All findings are from source reading and
  local test execution against the shipped package. No claim here rests on a deployed system.

**Boundary record authored** by FSE (functional-safety-engineer). Subject = We / FSE.
Produced under the QM/advisory ceiling of the FSE charter — no ASIL-rated and no control claim
is made anywhere in this document. Producer ≠ auditor: this record is **UNVERIFIED until
AAA + DIA return.**
