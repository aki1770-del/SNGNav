# voice_guidance — Safety-Class Boundary Record

**Package**: `voice_guidance`
**Version**: 0.5.0 (DEPLOY)
**Boundary record version**: 1.1 (0.5.0 addendum: action-coupled hazard rendering driver-facing loom)
**Authoring skill**: AAA (automotive-adas-analyst)
**Date**: 2026-05-04
**Anchor**: D-VGC189-1 (driver-facing-loom-as-default architectural discipline)

---

## 1 — SAE J3016 driver-task regime

**Level**: L0 / L1 supportive use only.
**Driver-task assignment**: the driver performs the dynamic driving task at all times. The package's `VoiceGuidanceBloc` consumes `NavigationState` transitions from a navigation state stream and emits voice announcements (maneuver lead-in, arrival, deviation, hazard) through a pluggable `TtsEngine`. The driver hears the announcement and decides response.
**No L2+ claim.** The package emits speech only; it holds no actuator authority, no automation, no handover. Per-profile speaking-rate (added 0.4.0) tunes the voice's pace per `DriverProfile`; it does not change the J3016 regime.

## 2 — ISO 26262 ASIL classification

**Package boundary**: **QM** (Quality Management; not functional-safety-scope).
**Reasoning**: `voice_guidance` produces an advisory voice channel — the driver hears, the driver decides. No safety-critical assertion is added at this layer; the package's restraint is its discipline. Voice-guidance text is composed by `ManeuverSpeechFormatter` / `formatHazard` from publisher- or app-class strings (route maneuvers, alert messages); the package does not invent severity or threshold semantics.
**Integrator responsibility**: any integration where voice guidance gates a control loop (it does not in SNGNav today, and the package would refuse a closed-loop client per its API surface) requires the integrator to perform fresh ASIL classification at the closed-loop boundary.

## 3 — SOTIF (ISO 21448) posture

**Stance**: **advisory not control.**
**Reasoning**: SOTIF addresses Safety Of The Intended Functionality at automated-driving-feature scope. This package delivers neither feature nor control; it delivers an audible-channel rendering of route + hazard advisories the integrator already produced. The driver hears it; the driver decides; the driver always drives.
**Honesty discipline at adapter boundary** (SOTIF-class operational discipline):
- **Hazard announcements interrupt maneuver speech for safety priority** (`voice_guidance_bloc.dart` `_onHazardAnnounced`): a hazard line preempts a maneuver line, never the reverse — the driver hears the hazard before the routing detail.
- **Min-announcement interval** (`VoiceGuidanceConfig.minAnnouncementIntervalSeconds`): the integrator's policy on cool-down between announcements is configurable at the boundary; the package does not invent a cool-down.
- **Per-profile speaking-rate** (`VoiceGuidanceConfig.forProfile()` 0.4.0): tunes pace per `DriverProfile` so a foreign-tourist driver in unexpected snow hears the announcement at a pace they can act on, while an experienced snow-zone driver hears it at engine-base pace. Threshold layer (`navigation_safety_core`) ensures **arrives in time**; per-profile rate ensures **calm enough to act on** for the profile.
- **Engine pluggability** (`TtsEngine` interface): production builds choose `FlutterTtsEngine` (mobile) or `LinuxTtsEngine` (desktop); CI / headless choose `NoOpTtsEngine` (silent). Engine choice is integrator-class; the package does not lock in a vendor.
- **Rate clamping at engine boundary**: each engine clamps speaking-rate to its own sane range so a config-class out-of-range value cannot produce an unintelligible announcement.
These five disciplines collectively form the package's SOTIF-class advisory-honesty posture.

## 4 — WP.29 cybersecurity touchpoint

**Touchpoint location**: **integrator-class; package boundary minimal.**
**Status**: **out of scope at this package's boundary.**
**Concrete WP.29 surface at this package**:
- Inputs: `NavigationState` value-objects from a navigation state stream (consumed by integrator), maneuver text strings, hazard message strings, alert severity enums. No network I/O.
- Outputs: TTS engine method calls; `VoiceGuidanceState` BLoC updates. No external sink.
- Authentication: none; the audio channel is the device's local audio output.
- Input validation: text strings pass through `ManeuverSpeechFormatter`; the package does not parse external bytes (no JSON / no protobuf / no YAML / no binary).
- Privacy: zero PII handled; the announcements are about route-class events at the device, not driver-class identifiers.
- Supply-chain: depends on `flutter_tts` (mobile TTS); `flutter_bloc` (state management); `equatable` (value-object semantics); `navigation_safety` (which transitively re-exports `navigation_safety_core`); `routing_engine` (route models). All published packages.

**WP.29-class operational discipline**: integrators deploying this package perform WP.29 audit at their app boundary (local-audio-class output is the smallest-attack-surface I/O channel; no attack-surface-class concern at this adapter).

## 5 — JIS / JASO conformance

**Conformance status**: **applies at the integrator's HMI surface, not at this package.**
**Reasoning**: Japanese-region driver-facing audio rendering surfaces in the integrator's HMI; this package emits the audio but does not specify display-class signage / icon-class HMI vocabulary that JIS / JASO standards regulate. Where a JIS / JASO standard regulates audio-class HMI directly (e.g. emergency-tone class), the integrator owns the audit at deployment.
**AAA monthly cron** (`aaa-jis-jaso-conformance-watcher-monthly`): tracks JIS / JASO standard updates; surfaces relevant publication deltas to AAA at next monthly cycle. Cron findings inform the integrator-class HMI rather than this audio-emission package directly.

## 6 — Severity-not-profile invariant

**Status**: **applies in scope by design.**
**Concrete reasoning**: hazard announcements are gated by `AlertSeverity` (`shouldAnnounceAlert` predicate at `voice_guidance_bloc.dart`). Per-profile speaking-rate (0.4.0) tunes the *pace* of the rendering, NOT whether-to-announce or what-severity-class. Severity drives the gate; profile drives the rendering pace. The package preserves the severity-not-profile-driven HMI-presentation invariant per `navigation_safety_core` SAFETY_BOUNDARY.md §6 verbatim — *severity decides whether/what; profile only decides how*.
**Composition pattern**: `navigation_safety_core` per-profile threshold-class config → integrator HMI calls `VoiceGuidanceConfig.forProfile(profile)` → `voice_guidance` renders at per-profile rate. The threshold layer determines when the alert fires; the rate layer determines the pace at which the rendered line lands on the driver's ear. Both axes are conservative-only (earlier-warn + slower-speak for vulnerable profiles).

## 7 — Driver-always-drives invariant

**Status**: **applies in scope by design.**
**Concrete reasoning**: package outputs are TTS engine method calls (audible channel) + BLoC state updates. The package emits no control signal, holds no actuator authority, exposes no API that closes a control loop. The driver hears the announcement; the driver decides response; the driver always drives.
**Axis anchor**: per the unit's driver-sovereignty axis substrate — driver is subject not object. The voice arrives in time + makes sense + is calm enough to ignore safely; the driver decides what to do with the information. The pace differentiation (0.4.0) is about respect for cognitive-load differences across `DriverProfile`s, not about removing the driver's agency.

## 8 — Driver-facing loom (D-VGC189-1)

**What HER experiences when this package fires**: *voice arrives at a pace each driver-class can hear without losing context.* When `voice_guidance` fires through an integrator HMI:
- HER hears the maneuver lead-in announcement ahead of the maneuver, at a pace tuned to HER `DriverProfile`. An older rural driver hears it at 0.70× engine-base; an experienced snow-zone driver hears it at engine-base (1.00×); a foreign-tourist driver in unexpected snow hears it at 0.70× engine-base.
- HER hears the hazard announcement preempt a routing maneuver line — safety-priority interrupt is built into the BLoC's hazard handler.
- HER hears arrival + deviation transitions at the same per-profile pace.

**Sakichi reading**: the loom is *the announcer who matches HER hearing-pace, not who shouts at HER on a one-pace-fits-all schedule*. The pace differentiation closes the dignity gap that the threshold layer alone cannot close: earlier thresholds without matching speaking-pace can produce earlier-but-incomprehensible announcements for the slower-cognitive-load profiles, erasing the threshold-layer benefit. The loom restores the second half of the architectural anchor: *alert that arrives in time + makes sense + is calm enough to ignore safely*. With per-profile rate, the rate matches the profile; the announcement is calm enough to ignore safely if the conditions don't actually require action; it is fast enough for HER to act on if they do.

**Audible-to-edge-developer**: integrator reading `VoiceGuidanceConfig.forProfile()` API today sees the profile-class differentiation surfaced explicitly + the per-profile multiplier table published in `kSpeakingRateMultiplierByProfile` + the rationale anchored on Strayer-AAA PMC7283540 in package documentation. Nothing patronizes the developer.

**Driver-facing-loom field**: this section is the canonical D-VGC189-1 declaration for `voice_guidance` 0.4.0. Subsequent versions update this field on material changes to the driver-experience surface (rate-axis extensions, new profile classes, voice-actor differentiation, etc.).

**Driver-impact chain (≤4 hops)**:
```
navigation state stream + alert source (integrator)
  -> VoiceGuidanceBloc (this package)
    -> TtsEngine -> device audio
      -> driver in unexpected snow region hears the announcement
```
Four hops; HER is terminal beneficiary; satisfies HER-trace ≤4-hop discipline.

## 8.1 — Integrator-side driver-facing loom (D-VGC189-1; new in 0.5.0)

**Operational discipline**: *the explainer ships the (condition, action) tuple at the package boundary so the integrator-developer is not silently absorbed responsibility for action-coupling.*

**What HER experiences when 0.5.0 fires**: when an integrator supplies a `DriverProfile` to `VoiceGuidanceBloc` and the `NavigationState` carries an `alertCondition`, the hazard branch resolves `AlertExplainer.forConditionAndProfile(condition, profile)` and speaks the explainer's action string at the explainer's locale tag. HER hears:

- the per-(condition, profile) action coupled to the road-surface condition (e.g. `RoadSurfaceCondition.ice` + `DriverProfile.foreignTouristSnowZone` → *"Icy road. Slow to 30 km/h. Avoid sudden braking."*) instead of a free-form alert string an integrator might compose ad-hoc;
- the announcement at the explainer's locale (`en` for foreign-tourist; `ja` for others) — the bloc switches the TTS engine language for the announcement so the EN-locale variant speaks in English without the integrator switching the bloc-wide config;
- the announcement at the per-profile speaking-rate the 0.4.0 axis already supplies (the 0.5.0 integration does not regress the per-profile rate axis).

**Composition with 0.4.0 per-profile rate**: the 0.4.0 axis tunes pace; the 0.5.0 axis tunes content + locale. Together: the foreign-tourist driver in unexpected snow hears the action-coupled English line at a slower pace; the experienced snow-zone driver hears the terse Japanese line at engine-base pace. Both axes are conservative-only: per-profile rate ≤ 1.0 for vulnerable profiles; action-coupled text never promises an outcome (advisory mood preserved per `AlertExplainer` source discipline).

**Driver-always-drives preserved**: the explainer's action verbs are advisory (*"reduce", "avoid", "maintain", "if possible"*); speed numbers (30 km/h / 20 km/h) are published reference points, not system-enforced limits. The bloc speaks the line; the driver decides response.

**Audible-to-edge-developer**: integrator reading `VoiceGuidanceBloc` constructor today sees the new optional `profile` parameter — defaults to null preserving pre-0.5.0 back-compat. An integrator that supplies no profile sees the historical free-form `alertMessage` rendering. The 0.5.0 wiring is opt-in at the integrator's choice.

**Driver-impact chain (≤4 hops)** — preserved with action-coupled rendering:
```
navigation state stream + alertCondition + driver profile (integrator)
  -> VoiceGuidanceBloc (this package; resolves AlertExplainer)
    -> TtsEngine -> device audio (explainer.action at explainer.localeTag)
      -> driver in unexpected snow region hears the action-coupled announcement
```

## 9 — Cross-references

- `lib/src/voice_guidance_config.dart` (per-profile speakingRate + multiplier table; 0.4.0)
- `lib/src/voice_guidance_bloc.dart` (`_initializeTts` calls `setSpeechRate`; hazard preempts maneuver)
- `lib/src/tts_engine.dart` (`setSpeechRate` interface method; 0.4.0)
- `lib/src/flutter_tts_engine.dart` / `linux_tts_engine.dart` / `noop_tts_engine.dart` (engine implementations of `setSpeechRate`)
- `pubspec.yaml` `version: 0.4.0` (published-live to pub.dev 2026-05-04 morning JST)
- LICENSE: BSD-3-Clause (matches the rest of SNGNav)
- D-VGC189-1 (driver-facing-loom-as-default architectural discipline)
- D-VGC188-1 / D-VGC188-2 (driver-sovereignty axis + 5-test framework)
- AAA bylaws Article 17 (β) safe-default boundary
- Composition: `navigation_safety_core` 0.7.0 SAFETY_BOUNDARY.md §6 (severity-not-profile invariant verbatim) + `navigation_safety_core` `assertUxDifferentiated()` activated 0.7.0 (the runtime hook this package's `voice_guidance:speakingRate` tag answers to)
- Strayer-AAA auditory-load study (PubMed Central PMC7283540) — per-profile-rate multiplier anchor
- Bian et al PubMed 38669900 — format-mismatch erases earlier-alert benefit anchor

---

**Boundary record authored** by AAA per VAA-as-SEO operational pen authorization. Subject = We / AAA. Verbatim citation discipline observed. PHIL-001 8-test PASS preserved at boundary scope. D4 dignity audit clear.
