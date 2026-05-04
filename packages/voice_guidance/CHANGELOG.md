# Changelog

## 0.5.0 — 2026-05-04 — wire AlertExplainer at hazard-branch

Wires the `navigation_safety_core` `AlertExplainer` at the
`_onNavigationStateObserved` hazard branch in `VoiceGuidanceBloc`.
When an integrator supplies a `DriverProfile` and the
`NavigationState` carries an `alertCondition`, the bloc resolves
the per-(condition, profile) action string + locale tag and speaks
the action-coupled text at the explainer's locale — overriding the
raw `alertMessage` for the hazard branch.

### Added

- **`VoiceGuidanceBloc({DriverProfile? profile})`** — new optional
  constructor parameter. Defaults to null preserving 0.4.0
  back-compat.
- Hazard-branch action-coupled rendering: when `(profile,
  alertCondition)` are both available, the bloc resolves
  `AlertExplainer.forConditionAndProfile(condition, profile)` and
  passes `explainer.action` to the formatter at
  `explainer.localeTag`. The TTS engine language is switched to
  the explainer locale when the locale differs from the bloc-wide
  config (so the EN-locale variant for the foreign-tourist profile
  speaks in English without the integrator switching the
  bloc-wide config).
- Composes additively with 0.4.0 per-profile `speakingRate`: the
  0.4.0 axis tunes pace; 0.5.0 axis tunes content + locale.

### Why this exists

`navigation_safety_core` 0.4.0 shipped `AlertExplainer` at the
core-package boundary, but voice rendering still spoke the raw
free-form `alertMessage`. The 0.5.0 wiring brings the
per-(condition, profile) action vocabulary to the audio channel
HER actually hears, so the integration is action-coupled in the
driver's register at the locale appropriate to the profile.

### Tests

- 3 new tests in `test/voice_guidance_bloc_test.dart` covering:
  `condition + profile -> explainer.action spoken (JA profile)`;
  `condition + profile -> localeTag passed to engine (EN profile)`;
  `fallback to alertMessage when condition+profile absent`.

### Discipline

- **Driver-always-drives preserved.** The explainer's action verbs
  are advisory mood (`reduce`, `avoid`, `maintain`, `if possible`);
  speed numbers are published reference points, not system-enforced
  limits.
- **Severity-not-profile invariant preserved.** The hazard branch
  remains gated by `AlertSeverity` (`shouldAnnounceAlert`
  predicate); profile + condition tune content + locale, never
  whether-to-announce.
- **Back-compat.** All 0.4.0 callers see no behaviour change. An
  integrator that does not supply a profile sees the historical
  free-form message rendering.

### Unchanged (back-compat)

- `VoiceGuidanceBloc(ttsEngine:, navigationStateStream:)` four-arg
  construction works without the new `profile` parameter.
- 0.4.0 per-profile `speakingRate` axis unchanged.
- All other 0.4.0 surface unchanged.

## 0.4.0 — 2026-05-04 — Per-profile speakingRate

Adds a per-`DriverProfile` speaking-rate axis to voice guidance so the
voice arrives at a pace each driver-class can hear without losing
context. The rationale: the standard Japanese-announcer pace is too
fast for an older rural driver and a foreign-tourist driver in
unexpected snow; per-profile rate lets each driver hear the line at a
pace they can act on.

The multipliers mirror the `navigation_safety_core` per-profile
threshold differentiation (earlier-warn → matching slower-speak so
the format does not erase the earlier-warn benefit), anchored on the
Strayer-AAA auditory-load study (PMC7283540).

### Added

- **`VoiceGuidanceConfig.speakingRate`** field (double; default `1.0`
  engine-base; valid range `(0.0, 2.0]`). Engines clamp to per-engine
  ranges; the config validates the broad sanity range only.
- **`VoiceGuidanceConfig.forProfile(DriverProfile)`** — copies the
  config with `speakingRate` set to the per-profile multiplier.
  Other fields preserved.
- **`VoiceGuidanceConfig.speakingRateForProfile(DriverProfile)`** —
  static helper returning the per-profile multiplier.
- **`kSpeakingRateMultiplierByProfile`** — published per-profile
  multiplier table:

  | profile                  | multiplier |
  |--------------------------|-----------:|
  | `snowZoneExperienced`    |       1.00 |
  | `professional`           |       1.00 |
  | `agriculturalForestry`   |       1.00 |
  | `noviceUrban`            |       0.85 |
  | `ageingRural`            |       0.70 |
  | `foreignTouristSnowZone` |       0.70 |
- **`TtsEngine.setSpeechRate(double rate)`** abstract method.
  Implementations clamp to per-engine ranges. Implemented in
  `FlutterTtsEngine`, `LinuxTtsEngine`, `NoOpTtsEngine`.
- `VoiceGuidanceBloc._initializeTts()` now calls `setSpeechRate` so
  per-profile (or per-config) rate takes effect at bootstrap and on
  every voice-enable transition.

### Tests

- 7 new tests covering: per-profile multiplier table; copy-with rate;
  forProfile preserves other fields; speakingRate validation
  (asserts on ≤0 / >2.0); all DriverProfile values mapped.

### Unchanged (back-compat)

- `VoiceGuidanceConfig` const-default still produces `speakingRate
  == 1.0` (engine-base). Existing callers with no rate change behave
  identically to 0.3.0.
- All other 0.3.0 surface unchanged.

## 0.3.0

- Harmonize package version to 0.3.0 for Sprint 80 Direction F.
- Align internal ecosystem dependency constraints to ^0.3.0 where applicable.
- No breaking API changes in this package for this release.

