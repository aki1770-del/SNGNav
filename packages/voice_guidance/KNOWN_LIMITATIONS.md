# Known Limitations

> **0.7.0. Adds the tactile (haptic) accessibility hazard channel
> (`HapticEngine` / `NoOpHapticEngine` / `FlutterHapticEngine`). The
> sections below bound what the haptic channel does and does not
> guarantee.**

## The motor-less-device gap (haptic, 0.7.0)

A haptic pattern is **felt**, not asserted. The package can verify the
cue *logic* (which pattern fires for which severity, the pulse grammar,
honest degradation) but it cannot verify that a driver actually *felt*
anything — that depends on a physical vibration motor the package has no
way to observe.

- **`isAvailable()` cannot guarantee a felt motor.** flutter/services
  `HapticFeedback` exposes no API to probe for a physical motor.
  `FlutterHapticEngine.isAvailable()` therefore reports the
  honest-degradation flag only: it returns `false` once the haptic
  platform channel has reported itself missing
  (`MissingPluginException`), and `true` otherwise. On a desktop /
  motor-less host where `HapticFeedback` silently no-ops, `isAvailable()`
  may report `true` while producing **no sensation**. "Available" means
  "the platform channel did not report missing", NOT "a motor is present
  and felt".
- **No desktop / host haptic.** On this development host (Linux desktop,
  `flutter test`) there is no vibration motor; the Flutter impl resolves
  to no sensation. The integrator selects `NoOpHapticEngine` for hosts
  known to lack a motor, exactly as it selects the no-op TTS engine for
  headless audio. Do not interpret a passing test suite as
  "verified by feel" — it is not, and was never claimed to be.
- **On-device feel is the integrator's verification.** Confirming that
  the warning double-pulse and the critical triple-pulse are
  *distinguishable by touch* on a given device's motor is an on-device
  test the integrator owns. The package guarantees the cues differ in
  count (2 vs 3) and requested intensity (medium vs heavy); whether a
  specific motor renders that difference perceptibly is device-class.

## Channel coupling

- **The haptic follows the voice-enabled state.** The tactile cue is
  fired in the hazard dispatch alongside the audio speak, which the bloc
  reaches only while voice guidance is enabled. A deployment that mutes
  voice guidance also suppresses hazard *events*, so the haptic does not
  fire while muted. An integrator serving a driver who wants tactile
  hazards with audio off should keep voice guidance enabled and select a
  no-op / silent audio engine, rather than disabling voice guidance.
- **Additive-only, never gating.** The haptic channel never gates,
  delays, or silences audio. A haptic failure is swallowed (the engine's
  `cue` never throws) so it cannot affect the audio path. The cue is
  advisory; it adds a channel, it never removes one.

## General

- **API may change.** The `HapticEngine` interface, the cue grammar, and
  the pulse counts may evolve in a future minor version. Do not pin
  application logic to specific pulse counts without reading the current
  CHANGELOG entry.
- **Cue is a pure function of severity.** The cue is derived from
  `AlertSeverity` only; it takes no driver profile. Severity decides
  whether/what; a profile only ever decides how. This is by construction
  and is not a tunable.

## When this file changes

These constraints are current at 0.7.0. Re-evaluate them against the
shipped artifact whenever the haptic surface or its degradation behaviour
changes; until then, treat every section here as a binding constraint.
