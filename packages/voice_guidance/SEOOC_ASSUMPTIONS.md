# voice_guidance — SEooC assumptions of use

**Package**: `voice_guidance`
**Applies from**: 0.7.6
**Author**: FSE (functional-safety-engineer), 2026-09-02
**Form**: ISO 26262 Part 10 Safety-Element-out-of-Context assumptions of use —
the structurally honest form for a component that has **no item**.
**Status**: PRODUCER artifact. Not self-audited — see "Audit" at the foot.

> **ATTACHES TO, does not replace, `SAFETY_BOUNDARY.md`** (AAA's record, v1.3).
> Companion to `SOTIF_INSUFFICIENCIES.md`, which tabulates the insufficiencies
> these assumptions bound.

## Ceiling

QM / advisory / information-only. **No ASIL, no item, no actuator.** This
package closes no control loop and this document asserts none — consistent with
`SAFETY_BOUNDARY.md:65` and with eighteen of the nineteen boundary records in
this repo. The driver hears; the driver decides; the driver always drives.

**An assumption of use is a debt, not a disclaimer.** Each one below is a thing
the integrator must supply or verify. Stating it does not discharge it — it
moves it somewhere it can be seen.

---

## The assumption that was silent

Until 0.7.6 this package's records described its output as a chain that
**terminates in her hearing it**. `SAFETY_BOUNDARY.md:86`, in the §8
driver-impact chain:

```
    -> TtsEngine -> device audio
      -> driver in unexpected snow region hears the announcement
```

*Hears* is written there as a link in a chain — a thing that happens — rather
than as an assumption the integrator must underwrite. Nothing in the package
observed it, and nothing in the package said it was unobserved.

**AoU-VG-000 (the parent assumption, now explicit).**

> **The package assumes that issuing an utterance constitutes delivering it,
> and it cannot verify this.** Every downstream statement of the form "she was
> warned" rests on that assumption and inherits it whether or not the
> integrator has noticed.

This is a **Vision 14** shape: *a function that returns a success-shaped value
while the operation failed.* `Future<void> speak(String)`
(`lib/src/tts_engine.dart:59`) is success-shaped by its return type; before
0.7.6 it returned normally even when the platform never received the utterance.
`SpeechDelivery` (0.7.5) began to answer this, and 0.7.6 makes its answer
trustworthy — but only on one of the two shipped engines. The rest of AoU-VG-000
remains the integrator's, itemised below.

---

## Assumptions the integrator must underwrite

### AoU-VG-001 — Delivery observation is opt-in and engine-specific

`DeliveryObservable` is deliberately a side interface, not a member of
`TtsEngine`: adding a member there breaks every existing `implements TtsEngine`.
An engine that does not implement it is **unobserved**, which is the truth
rather than a silent pass.

- **The integrator must test for it**: `if (engine is DeliveryObservable)`.
- **Absence of the interface is not evidence of delivery.** An engine that
  cannot be asked has not answered "yes".
- Of the four engines shipped here, **one** implements it: `FlutterTtsEngine`.
  `LinuxTtsEngine`, `NoOpTtsEngine` and any integrator engine do not.

### AoU-VG-002 — `delivered` is the synthesiser's word, not the driver's

`SpeechDelivery.delivered` means **the engine reported the utterance finished.**
It does not mean audio reached her. It is silent on device volume, a muted or
ducked stream, audio focus held by another app, a Bluetooth handoff mid-utterance,
and a failed IVI amplifier. No TTS API exposes acoustic confirmation; this is the
honest ceiling of the observation, not a defect to be fixed in a later version.

- **Never render `delivered` to a driver or an operator as "warning heard".**
- The equivalent honesty already published for the haptic channel applies here
  verbatim in spirit (`KNOWN_LIMITATIONS.md`): *available* means the platform
  did not report itself missing, never that the signal was perceived.

### AoU-VG-003 — On Linux (the IVI target) there is no observation at all

`createDefaultTtsEngine()` returns `LinuxTtsEngine` for `Platform.isLinux`
(`default_tts_engine_io.dart:10-12`). That engine spawns `spd-say` and returns
once the **process is started**; `spd-say` hands text to the `speech-dispatcher`
daemon and exits, so its exit code would not evidence audio either.

- **An integrator deploying to embedded Linux inherits zero delivery
  observation** and must not carry a mobile-derived assurance argument onto that
  target.
- 0.7.6 does make `isAvailable()` honest there: it now resolves the executable
  against `PATH` instead of returning its argument unchanged, so a Yocto image
  without `speech-dispatcher` reports `false` rather than `true`. **Resolving a
  binary proves it exists, never that it speaks.**
- Tracked as `SOTIF-VG-007` (OPEN), routed to EIE + YRA + CT.

### AoU-VG-004 — The verdict is per-engine state, not per-utterance history

`lastDelivery` describes the most recent `speak()` call only. It is not a log,
not a queue, and not addressable by utterance. An integrator that needs an audit
trail of which advisories were confirmed must record it at its own boundary, at
the moment it issues each utterance.

- Read it **after** the `speak()` future completes, and **before** issuing the
  next utterance; a later read describes a later utterance.
- 0.7.6 guarantees it never describes an *earlier* one (INV-1).

### AoU-VG-005 — An unobserved delivery must never suppress a warning

**This is a constraint on the integrator, not a capability of the package.**

The package will never withhold speech because a previous utterance was
unconfirmed, and an integrator must not build that behaviour on top of it. A
driver whose only channel is audio must not lose it because we could not confirm
the last utterance. **Record, never gate.**

- Legitimate responses to `unknown` / `failed`: add a channel (haptic, visual),
  persist rather than clear the hazard indication, repeat at the next safe
  opportunity, surface a "voice unavailable" indicator, log it.
- Illegitimate: suppress, defer, or downgrade the warning itself.

### AoU-VG-006 — Escalation is redundancy, not confirmation

If an integrator escalates modality on `unknown` or `failed`, it must know that
the channel it escalates **to** is also unobserved: `HapticEngine.cue` returns
`Future<void>` and is contractually forbidden to throw
(`haptic_engine.dart:17, 38`), and the bloc fires it `unawaited`
(`voice_guidance_bloc.dart:304`). Adding a channel raises the probability she is
reached; it does not produce a confirmation.

- An assurance argument may claim **redundancy**. It may not claim **coverage**.

### AoU-VG-007 — The observation never extends past the transducer

The package observes *"did the utterance complete?"* and nothing beyond it. It
does not observe, infer, or model whether she slowed, braked, turned, or agreed.

- **Her response must never become an error signal.** A component that adjusted
  its output based on her compliance would be a different product with a
  different classification, and this one is not it.
- The purpose is to keep the choice hers, informed. It is not to verify her.

### AoU-VG-008 — The system state does not yet carry the verdict

As of 0.7.6, `VoiceGuidanceBloc` does not read `lastDelivery`, and
`VoiceGuidanceStatus` is `{ idle, speaking, muted }` — no vocabulary for an
unconfirmed announcement. The bloc emits `idle` after every `speak()` regardless
of outcome, and writes `lastHazardMessage` before speaking without later
revision.

- **An integrator reading only `VoiceGuidanceState` cannot tell a confirmed
  hazard announcement from an unconfirmed one.** To observe delivery today, hold
  a reference to the engine and read it directly.
- Tracked as `SOTIF-VG-008` (OPEN), routed to AAA + CT + WDA.

---

## What this document does not do

It performs no vehicle-level HARA, assigns no ASIL, and makes no control or
actuation claim. The integrator owns the hazard analysis at their item boundary;
these assumptions exist so that analysis is not built on something we never
earned.

## Audit

FSE produces; **AAA + DIA audit**. Submitted for audit and not cleared until
they say so. Where they have not read, this document is **UNVERIFIED, not
cleared**.
