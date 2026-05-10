# Changelog

## 0.6.1 — 2026-05-10 — Refresh cascade-stale dependency constraint

- `routing_engine: ^0.3.0` → `^0.4.0` (consumer-side refresh after
  routing_engine 0.4.0 release earlier the same day).
- No source changes; pubspec dep-constraint refresh only.

## 0.6.0 — 2026-05-06 — add BudgetAwarePaceProfile (glance-budget-aware speech pacing)

Adds an opt-in, glance-budget-aware voice-pace adjustment. When an
integrator supplies a `GlanceBudgetTracker` (from `navigation_safety`
0.9.0) and a non-null `VoiceGuidanceConfig.budgetAwarePace`, the
bloc subscribes to budget events and dynamically modulates the
effective TTS speaking-rate as the off-road glance budget is
consumed. Disabled by default; preserves 0.5.0 back-compat.

### Added

- **`BudgetAwarePaceProfile`** in
  `lib/src/budget_aware_pace_profile.dart` — value class with
  `minPace` (default 0.7), `maxPace` (default 1.0), `curve`
  (default linear; smoothstep available). Caution-add-only
  invariant: pace ≤ 1.0× baseline (constructor asserts
  `minPace > 0.0 && minPace <= maxPace && maxPace <= 1.0`). Method
  `paceForRemainingRatio(double)` returns the interpolated pace
  multiplier given a remaining-budget ratio in `[0.0, 1.0]`.
- **`InterpolationCurve`** enum (`linear` / `smoothstep`).
- **`VoiceGuidanceConfig.budgetAwarePace`** optional field.
  Defaults to null (back-compat: no behaviour change for 0.5.0
  consumers). When non-null, opt-in glance-budget-aware pacing
  activates if the bloc is also constructed with a
  `GlanceBudgetTracker`.
- **`VoiceGuidanceBloc({GlanceBudgetTracker? glanceBudgetTracker})`**
  optional constructor parameter. When supplied alongside a
  non-null `config.budgetAwarePace`, the bloc subscribes to the
  tracker's `budgetEvents` stream and reapplies the effective TTS
  rate via `_ttsEngine.setSpeechRate(...)`.

### Why this exists

`voice_guidance` 0.4.0 shipped per-`DriverProfile` speaking-rate
multipliers — a static per-cohort baseline. That baseline does not
respond to live cognitive-load state. When the driver's cumulative
off-road glance time approaches the NHTSA Phase 2 12-second budget,
the same baseline-pace voice announcement competes for attention
against an already-overloaded cognitive channel. 0.6.0 closes this
loom by composing the static baseline with a dynamic budget-aware
multiplier; the result is slower-speak under high cognitive load,
preserved baseline-speak when the budget has barely been consumed.

### Discipline

- **Caution-add-only invariant** (load-bearing): pace ≤ 1.0×
  baseline. Constructor asserts in `BudgetAwarePaceProfile`
  enforce `maxPace <= 1.0` so the dynamic adjustment can only
  SLOW speech, never speed it up. The composed effective rate
  in `VoiceGuidanceBloc._effectiveSpeakingRate()` is therefore
  always ≤ `config.speakingRate` (the per-profile baseline).
- **Driver-always-drives invariant**: voice pace is presentation-
  class only. The bloc modulates the TTS speaking-rate parameter;
  no actuator, no input suppression, no control loop.
- **Severity-not-profile invariant** preserved: pace adjustment
  does not change severity. The hazard-branch severity gate
  (`shouldAnnounceAlert`) remains upstream; pace adjustment
  affects only the rendered audio rate.
- **Back-compat**: 0.5.0 callers see no behaviour change. The
  new constructor parameter and config field default to null.
  An integrator that supplies neither `glanceBudgetTracker` nor
  `budgetAwarePace` runs the 0.5.0 code path identically.

### UNVERIFIED-magnitude flags

- Default `minPace = 0.7` (effective rate floor when budget is
  fully exhausted) is a design-default-hypothesis pending field
  evidence on whether 0.7× is the right floor across cohorts.
- Default `curve = InterpolationCurve.linear` is a design-default;
  smoothstep alternative is available for graduation if integrator
  UX evidence supports it.

### Tests

- 5 new tests in `test/budget_aware_pace_profile_test.dart`
  covering: linear interpolation correctness at boundaries
  (0% / 50% / 100% remaining); smoothstep interpolation;
  pace ≤ 1.0× invariant assert (negative-assertion); minPace
  floor enforced; equality / props.
- 3 new tests in `test/voice_guidance_bloc_budget_aware_test.dart`
  covering: bloc subscribes to tracker stream and reapplies rate
  on budget events; effective-rate composition correctness; back-
  compat preserved when `glanceBudgetTracker` or `budgetAwarePace`
  is null.

### Bumped

- `navigation_safety` dependency `^0.8.0` -> `^0.9.0`.
- `navigation_safety_core` dependency `^0.8.0` -> `^0.10.0`.

### Unchanged (back-compat)

- 0.5.0 hazard-branch action-coupled rendering unchanged.
- 0.4.0 per-profile `speakingRate` axis unchanged.
- `TtsEngine` interface unchanged.

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

