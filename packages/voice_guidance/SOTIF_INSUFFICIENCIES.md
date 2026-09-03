# voice_guidance — SOTIF (ISO 21448) performance-insufficiency table

**Package**: `voice_guidance`
**Applies from**: 0.7.6 (the version the SOTIF-VG-001..006 mitigations land in)
**Author**: FSE (functional-safety-engineer), 2026-09-02
**Status**: PRODUCER artifact. Not self-audited — see "Audit" at the foot.

> **ATTACHES TO, does not replace, `SAFETY_BOUNDARY.md`** (AAA's record, v1.3).
> That record states the package's SOTIF *posture* and enumerates five
> advisory-honesty disciplines at §3. This file tabulates the insufficiencies
> that posture leaves. **Delivery observation is not among AAA's five**, which
> is the gap this table exists to name. Nothing here re-authors that record.

## Scope and ceiling

QM / advisory / information-only. **No ASIL, no item, no actuator.** This is not
a vehicle-level HARA and cannot be one: a reusable library has no vehicle. The
integrator performs the hazard analysis; this table tells the integrator what
our part of it cannot do, so their analysis is not built on an assumption we
never earned.

**This package closes no control loop, and this table asserts none.** Per
`SAFETY_BOUNDARY.md:65` — *"exposes no API that closes a control loop. The
driver hears the announcement; the driver decides response; the driver always
drives."* Eighteen of the nineteen `SAFETY_BOUNDARY.md` records in this repo
assert the same thing, and this table is consistent with all of them.

**The error term stops at the transducer.** Every observation tabulated here
answers *"did the utterance complete?"* — never *"did she comply?"* Her response
is not our signal and must never become one. The choice stays hers.

## Intended function (the thing whose insufficiency is tabulated)

> Render a hazard or maneuver advisory into a channel the driver can perceive,
> **and state truthfully whether that rendering was observed to complete.**

The second clause is the safety-relevant half. The first clause failing is
audible. The second clause failing is not — it is a **Vision 14 silent
failure**: *"a function that returns a success-shaped value while the operation
failed is a loom weaving through a broken warp."* `Future<void> speak(String)`
(`lib/src/tts_engine.dart:59`) is success-shaped by its return type. Until
0.7.6 it returned normally in every case, including cases in which the platform
never received the utterance at all.

## Standing constraint on every mitigation in this table

**Record, never gate.** No insufficiency here is mitigated by withholding a
warning. A driver who has only one channel must not lose it because we could not
confirm the last utterance. Every 0.7.6 change alters only *what we claim*,
never *whether we speak* — verifiable in the diff: no mitigation adds a `return`
on the speak path.

---

## Insufficiency rows

### SOTIF-VG-001 — an utterance the platform never received reads as delivered

| field | value |
|---|---|
| **ID** | SOTIF-VG-001 |
| **Class** | Performance insufficiency (of the delivery predicate, not of the audio path) |
| **Triggering condition** | The TTS platform channel dies mid-drive — hot restart, plugin teardown, host process recycle — **after** at least one utterance completed successfully. `_guardPluginCall` catches `MissingPluginException` and latches `_pluginAvailable = false`. |
| **Insufficiency** | `speak()` returned at its first guard **before** resetting `_lastDelivery`. The field therefore still held the *previous* utterance's `delivered`. |
| **Output to the integrator** | `lastDelivery == SpeechDelivery.delivered` for a critical warning that was never handed to the platform. Indistinguishable from a warning she actually heard. |
| **Foreseeable misuse it invites** | None required. The failure needs no misuse: the documented reading (`if (engine.lastDelivery == delivered)`) produces the wrong answer. That is what makes it an insufficiency rather than a usage error. |
| **Detectability before mitigation** | **Nil at this interface.** No test in the package exercised `lastDelivery` at all — 0 of 13 test files referenced it on the day it shipped. |
| **Measured occurrence** | 2026-09-02, reproduced against `936fb2b` in `test/fse_delivery_red_proof_test.dart` (RED PROOF A): after a completed utterance and a latched `MissingPluginException`, `speak('Black ice. Slow down now.')` issued **no** platform call (`verifyNever`) and `lastDelivery` read `delivered`. |
| **Mitigation (code, 0.7.6)** | **INV-1 (freshness)**: `_abandonOpenUtterance()` + `_lastDelivery = unknown` are now the **first two statements** of `speak()`, ahead of every early return. `lastDelivery` describes the current call or nothing. |
| **Verifying test** | `test/delivery_observation_invariants_test.dart` — *"an utterance the platform never received is NOT delivered"*. Proven RED against `936fb2b` before the guard landed. |
| **Residual** | None for this row. |

### SOTIF-VG-002 — a no-op utterance inherits the previous success

| field | value |
|---|---|
| **ID** | SOTIF-VG-002 |
| **Class** | Performance insufficiency (same predicate, second entry path) |
| **Triggering condition** | An upstream formatter yields empty or whitespace-only text — an unmapped locale key, a missing explainer string, a stripped SSML payload. |
| **Insufficiency** | The `text.trim().isEmpty` guard also preceded the reset, so a suppressed utterance carried the prior verdict forward. |
| **Output to the integrator** | `delivered` for an advisory whose text was empty — the case where she most needs to know nothing was said. |
| **Measured occurrence** | 2026-09-02, RED PROOF B against `936fb2b`. |
| **Mitigation (code, 0.7.6)** | Same INV-1 reordering closes both entry paths from one place. |
| **Verifying test** | *"a blank utterance does not inherit the prior success"*. |
| **Residual** | None for this row. |

### SOTIF-VG-003 — a late verdict credits the wrong utterance

| field | value |
|---|---|
| **ID** | SOTIF-VG-003 |
| **Class** | Performance insufficiency (attribution) |
| **Triggering condition** | An utterance exceeds `deliveryBound` (8 s) — platform stall, audio-focus contention, a long ja-JP string on a loaded IVI SoC — and its verdict arrives after the next utterance has begun. |
| **Insufficiency** | **The platform verdict carries no utterance identity.** `flutter_tts-4.2.5` invokes `completionHandler!()` with no arguments (`lib/flutter_tts.dart:614-618`). The handler assigned `_lastDelivery` unconditionally, so utterance N's late completion marked utterance N+1 delivered. The 8 s timeout wrote `unknown` and then had that write silently overturned. |
| **Output to the integrator** | A maneuver line's success laundering a hazard line's silence. The **more** severe utterance is the one falsely credited, because hazards preempt maneuvers (`_onHazardAnnounced`). |
| **Detectability before mitigation** | Nil. Identity is held on our side or nowhere — the plugin cannot supply it. |
| **Measured occurrence** | 2026-09-02, RED PROOF C against `936fb2b`: two sequential utterances, then utterance 1's completion → `lastDelivery == delivered`. |
| **Mitigation (code, 0.7.6)** | **INV-2 (attribution)** + **INV-3 (no upgrade after giving up)**: an `_openUtterance` sequence number scopes each verdict; abandoned utterances increment `_unclaimedVerdicts`, and the next verdict is consumed and discarded rather than allowed to resolve anything. A timed-out utterance can never be revived into `delivered`. |
| **Verifying test** | *"a late verdict for utterance 1 does not credit utterance 2"*, *"a second verdict cannot re-resolve a closed utterance"*, plus a positive control — *"the CURRENT utterance still resolves normally"* — so the guard is not passing by refusing to observe anything. |
| **Residual** | **AoU-VG-002.** Attribution is by sequence, not by platform id. A verdict arriving for an abandoned utterance is discarded, which is safe; but if the platform drops a verdict entirely, the discard budget is consumed by the *next* verdict. The failure direction is toward `unknown`, never toward `delivered`. |

### SOTIF-VG-004 — a cancelled utterance reads as unobservable rather than failed

| field | value |
|---|---|
| **ID** | SOTIF-VG-004 |
| **Class** | Functional insufficiency (specification gap in the verdict vocabulary) |
| **Triggering condition** | Any `stop()`. This is not rare: `_onHazardAnnounced` calls `stop()` on **every hazard** to preempt maneuver speech, and the OS cancels on audio-focus loss (a call, a nav app taking focus). |
| **Insufficiency** | The platform reports cancellation on its own channel — `speak.onCancel` → `cancelHandler` (`lib/flutter_tts.dart:634-638`) — which **neither** the completion nor the error handler receives. `cancelHandler` was never set. A **known** non-delivery therefore reported as `unknown`, whose documented meaning is *"Not observable on this engine"*. |
| **Output to the integrator** | The two states an integrator would act on differently — *"we could not observe"* and *"we observed it did not finish"* — collapsed into the weaker one. |
| **Measured occurrence** | 2026-09-02, verified in plugin source and by the absence of any `setCancelHandler` call at `936fb2b`. |
| **Mitigation (code, 0.7.6)** | **INV-5 (cancel is not silence)**: `setCancelHandler` wired to `_resolve(SpeechDelivery.failed)`. |
| **Verifying test** | *"INV-5 a cancelled utterance is failed, not unknown"*. |
| **Residual** | None for this row. |

### SOTIF-VG-005 — a disposed engine still reports a delivery

| field | value |
|---|---|
| **ID** | SOTIF-VG-005 |
| **Class** | Performance insufficiency (terminal state) |
| **Triggering condition** | Bloc `close()` → `_ttsEngine.dispose()` at end of drive or on route teardown, followed by any read of `lastDelivery`. |
| **Insufficiency** | `dispose()` set `_disposed` and left the last verdict readable, so a torn-down engine answered `delivered` about a drive that had ended. |
| **Measured occurrence** | 2026-09-02, RED PROOF D against `936fb2b`. |
| **Mitigation (code, 0.7.6)** | **INV-4 (terminal state)**: `dispose()` abandons any open utterance and resets to `unknown`. |
| **Verifying test** | *"INV-4 a disposed engine reports nothing delivered"*. |
| **Residual** | None for this row. |

### SOTIF-VG-006 — `isAvailable()` was a tautology on the IVI target

| field | value |
|---|---|
| **ID** | SOTIF-VG-006 |
| **Class** | Performance insufficiency (of the availability predicate) |
| **Triggering condition** | Any Linux host — **which is HER IVI target** (`default_tts_engine_io.dart:10-12` returns `LinuxTtsEngine` for `Platform.isLinux`) — on which `speech-dispatcher` is not installed. A Yocto image ships only what a recipe puts in it. |
| **Insufficiency** | `_defaultResolveExecutable` **returned its argument unchanged** (`linux_tts_engine.dart:38-40` at `936fb2b`). `isAvailable()` therefore returned `true` for every non-disposed engine on every Linux host, regardless of whether any speech binary existed. The subsequent `ProcessException` was caught and swallowed by `speak()`, so the only downstream signal was silence. |
| **Output to the integrator** | An integrator asking *"can this device speak?"* received `true` from a device that cannot. |
| **Detectability before mitigation** | **Nil, and the test suite actively concealed it.** All five `LinuxTtsEngine` tests inject `resolveExecutable`; the test named *"isAvailable returns false when executable is missing"* injects `(_) => null` and therefore exercises the stub, not the product. The default resolver — the only one that runs in production — was covered by nothing. *Per CLAUDE.md §0: if the method could not have surfaced a counter-example, it has measured nothing.* |
| **Measured occurrence** | 2026-09-02, RED PROOF E against `936fb2b`: `LinuxTtsEngine(executable: 'spd-say-does-not-exist-xyz').isAvailable()` returned `true`. |
| **Mitigation (code, 0.7.6)** | **INV-6 (availability is not a tautology)**: the default resolver now resolves against `PATH`, or checks the file for a path-qualified executable, and returns `null` when nothing exists. |
| **Verifying test** | Three tests exercising the **default** resolver — absent-on-PATH, absent absolute path, and a positive control (`sh`) so the guard cannot pass by always answering `false`. |
| **Residual** | **AoU-VG-003** (below). Resolving the binary proves it exists, never that it speaks. |

---

## OPEN rows — named, not mitigated in 0.7.6

### SOTIF-VG-007 — the IVI target has no delivery observation at all (OPEN)

| field | value |
|---|---|
| **Class** | Functional insufficiency (specification gap) |
| **Triggering condition** | Any deployment on Linux — HER IVI target. |
| **Insufficiency** | `LinuxTtsEngine` does not implement `DeliveryObservable`. It has no verdict of any kind. `speak()` spawns `spd-say` via `Process.start` and returns as soon as the **process is spawned** (`linux_tts_engine.dart:88-103` **at `936fb2b`**; the file shifted when INV-6 landed); the exit code is awaited only to null out the handle. `spd-say` is a *client* that hands text to the `speech-dispatcher` daemon and exits, so even its exit code would not evidence audio. |
| **Consequence** | Every mitigation above applies to `FlutterTtsEngine` — the **mobile** engine. On the target D2 names as the invariant (*"a scene she understands in a glance, on her real IVI target, offline"*), delivery observation is **absent**, not merely imperfect. |
| **Status** | **OPEN. Not fixed in 0.7.6.** Closing it means either a `speech-dispatcher` client that subscribes to `SSIP` `END`/`CANCEL` index-mark events, or replacing `spd-say` with a library binding — a dependency and packaging decision that is EIE's and YRA's (Yocto image contents), not FSE's unilateral edit. |
| **Guard in place meanwhile** | `test/delivery_observation_invariants_test.dart` asserts `isNot(isA<DeliveryObservable>())`. When the engine becomes observable that test goes RED and forces this row and `SEOOC_ASSUMPTIONS.md` to be revised in the same change. |
| **Routed to** | EIE (embedded/on-target) + YRA (recipe) + CT (build-track lead). |

### SOTIF-VG-008 — the observation is not read by anything (OPEN)

| field | value |
|---|---|
| **Class** | Functional insufficiency (the observation terminates in a private field) |
| **Measured** | 2026-09-02. `lastDelivery` is read by **zero** call sites outside the two files that define it — repo-wide `grep` across all `*.dart`. `VoiceGuidanceBloc` calls `await _ttsEngine.speak(...)` and then emits `VoiceGuidanceStatus.idle` **unconditionally** (`voice_guidance_bloc.dart:318-320`, and `:284-286` for maneuvers). |
| **Insufficiency** | `VoiceGuidanceStatus` is `{ idle, speaking, muted }` (`voice_guidance_state.dart:6`) — **there is no vocabulary for "we tried to warn her and could not confirm it."** Worse, `lastHazardMessage` is written *before* the speak (`:313-315`) and never revised, so the bloc's own state records the hazard as announced whatever the outcome. The 0.7.6 engine now knows the truth and the system still discards it. |
| **Status** | **OPEN by design of this change.** Adding a state to a published state model consumed by our own app (`example/lib/main.dart:605, 776, 970`) is a driver-facing-loom change, which is AAA's record and CT's build-track call — not FSE's to make unilaterally. **Named here so it is not inherited silently.** |
| **Recommended shape** (FSE assessment, not a decision) | Additive and back-compatible: carry the verdict onto `VoiceGuidanceState` beside `lastHazardMessage`, so an integrator can *render* an unconfirmed warning differently — persist the hazard chip rather than clearing it, repeat at the next safe opportunity, or surface a "voice unavailable" indicator. **Not** by suppressing anything: see the standing constraint above. |
| **Routed to** | AAA (boundary record §8 driver-facing loom) + CT + WDA (any consumer-visible change). |

### SOTIF-VG-009 — delivered ≠ audible; the escalation channel is unobserved too (OPEN)

| field | value |
|---|---|
| **Class** | Functional insufficiency (bound of the strongest verdict we can produce) |
| **Insufficiency** | `SpeechDelivery.delivered` means *the engine reported the utterance finished*. It does not mean audio reached her: device volume at zero, a muted or ducked stream, audio focus held elsewhere, a Bluetooth handoff mid-utterance, a failed IVI amplifier. **No TTS API exposes acoustic confirmation.** The honest ceiling of this package's observation is the transducer boundary, and `delivered` must be read as *"the synthesiser finished"*, never *"she heard it."* |
| **Compounding** | The channel one would escalate *to* has the same shape. `HapticEngine.cue` returns `Future<void>` and is contractually forbidden to throw (`haptic_engine.dart:17, 38`); the bloc fires it `unawaited` (`voice_guidance_bloc.dart:304`). It is success-shaped by construction — **Vision 14 in the fallback**. `KNOWN_LIMITATIONS.md` already states this honestly for haptic (*"'Available' means 'the platform channel did not report missing', NOT 'a motor is present and felt'"*); **no equivalent statement existed for audio** until this table. |
| **Consequence for the escalation question** | Escalating modality on an unobserved audio delivery raises the probability she is reached. It does **not** close anything, because the second channel returns a success-shaped value too. An escalation policy built on either verdict must be honest that it is redundancy, not confirmation. |
| **Status** | **OPEN and, at the acoustic layer, not closable by this package.** Mitigation is bounded honesty: state the ceiling (done here and in `SEOOC_ASSUMPTIONS.md`), and never let `delivered` be read as *heard*. |
| **Routed to** | AAE (on-device modality/accessibility lens) + AAA. |

---

## What this table does not do

No ASIL rating, no ASIL decomposition, no FFI, no FMEDA, no safety goals, no
FSC/TSC, no vehicle-level HARA. Severity / exposure / controllability ratings
are deliberately absent — those are vehicle-level and belong to the integrator.

## Audit

FSE is a producer and is never its own auditor. This table and the 0.7.6 code
changes it describes are submitted for audit to **AAA** (dignity / standards
mapping, and holder of the `SAFETY_BOUNDARY.md` record this file attaches to)
and **DIA** (propagation and temporal integrity). Nothing here is cleared until
they say so; where they have not read, this table is **UNVERIFIED, not cleared**.
