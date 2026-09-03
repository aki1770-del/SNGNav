## 0.7.7

**Three things this package told you that were not true.** All three were about
its own state, and all three were asserted from what we sent rather than read
back from the authority. No API is removed; `SpeechDelivery` is added.

**1 — the critical warning could be spoken in the wrong voice.** The bloc set the
override locale and queued the utterance as two independent futures:

```dart
unawaited(_ttsEngine.setLanguage(overrideLocaleTag));
add(HazardAnnounced(...));            // can win the race
```

Measured: an English critical black-ice warning went out through the Japanese
engine, `setLanguage(en)` landing after it — foreign-tourist profile,
`AlertSeverity.critical`. Worse, `setLanguage(_config.languageTag)` appeared
exactly once, in `init`, so **nothing restored the base locale**: one override
left the engine on the override locale for the life of the session, and Japanese
turn text was then spoken by an English voice permanently. The locale now rides
on the `HazardAnnounced` event, so the ordering is structural rather than hoped
for.

**2 — "she was warned" was asserted from having CALLED `speak()`.** `speak()`
returns `void` and `flutter_tts` resolves it when the utterance is **queued**, not
when it is spoken. This package had `awaitSpeakCompletion` 0, `setCompletionHandler`
0, `onComplete` 0, `isSpeaking` 0 — nothing ever read back that anything was
spoken. For a driver at ten metres' visibility, *queued* and *heard* are not the
same event. Adds `SpeechDelivery { delivered, failed, unknown }` — and `unknown`
is a first-class state, never folded into success.

**3 — `LinuxTtsEngine.isAvailable()` returned `true` on hosts that cannot speak.**
The default executable resolver returned its argument unchanged, so the
`resolved == null` guard in `isAvailable()` could never fire: **on any Linux host,
with or without a speech binary installed, this package reported that it could
speak.** It now resolves against `PATH` (or the filesystem for a qualified path)
and returns `null` when the executable is absent. If you relied on `isAvailable()`
being true on Linux, it will now correctly be false where no engine exists.

**Not shipped, deliberately.** An earlier form of (2) carried two breaks, caught
before publication and removed: it called `awaitSpeakCompletion(true)`, which
mutates `flutter_tts`'s **process-global** `static const MethodChannel` and would
have changed the resolution contract of every `FlutterTts` in the host app —
including instances you built yourself — which no version number of ours could
honestly describe; and it silently changed `speak()` to resolve on completion
under an 8 s bound while keeping the same signature, which widened a false-idle
window on the hazard path. Both were removed at the work rather than documented.

## 0.7.6

- Widen `latlong2` from `^0.9.1` to `>=0.9.1 <0.11.0`.

  `latlong2 0.10.0` shipped 2026-04-25 and `flutter_map 8.x` resolves it, so the old
  ceiling made this package **uninstallable alongside current `flutter_map`** —
  `version solving failed` for every published version. No source change; the cap was
  gratuitous. Verified on `latlong2 0.10.1`: analyze clean, **86/86 tests pass**.

## 0.7.5

**Unblocks `routing_engine 0.6.0` for every consumer of this package.** No API,
no behaviour and no code change: every file under `lib/` is byte-identical to
0.7.4.

**What was wrong.** This package declared `routing_engine: '>=0.4.0 <0.6.0'` as a
runtime dependency **and never imported it.** Measured before the change: the 19
Dart files under `lib/` import exactly six packages — `equatable`, `flutter`,
`flutter_bloc`, `flutter_tts`, `navigation_safety`, `navigation_safety_enums`.
`routing_engine` appears in **zero** of them. This package speaks
`NavigationManeuver` from `navigation_safety`; `RouteManeuver` from
`routing_engine` is a type it has never touched. Only the *example* used it, and
an example is not a dependency of the library.

**Why an unused line mattered.** `routing_engine 0.6.0` carries a *safety* fix — a
route point that failed to parse no longer silently becomes `LatLng(0, 0)`, ten
degrees off the coast of Ghana, rendered to a driver as a confident position.
Because of the cap above, **no application that used `voice_guidance` was allowed
to take that fix.** The resolver said so in its own words:

```
Because vg_cap_proof depends on voice_guidance 0.7.4 which depends on
routing_engine >=0.4.0 <0.6.0, routing_engine >=0.4.0 <0.6.0 is required.
So, because vg_cap_proof depends on routing_engine 0.6.0, version solving failed.
```

**The fix, and it is a removal, not a widening.** The unused `routing_engine`
line is gone. A cap widened to `<0.7.0` would have unblocked today's release and
re-blocked the next one, for a package that is still not imported. The same
proof after the change resolves `routing_engine 0.6.0 (source: hosted)`, and the
86-test suite passes unchanged.

**Nothing you depend on is removed.** In Dart you cannot import a package you do
not declare, so no consumer was ever able to reach `routing_engine` through this
one. If your app uses `routing_engine`, declare it directly — you almost
certainly already do.

## 0.7.4

Removes build artifacts that 0.7.3 published by mistake. No API or behaviour
change: every file under `lib/` is byte-identical to 0.7.3.

**What 0.7.3 contained, and what you already have.** The 0.7.3 archive was
16,023,777 bytes, of which about 99.9% was a `build/` directory that should
never have been in a published package. It held nine files, the largest a
Flutter kernel cache (`build/test_cache/build/*.cache.dill.track.dill`,
49,014,912 bytes uncompressed) that embedded 1,323 absolute filesystem paths
from the machine that published it, of the form
`/home/<user>/.pub-cache/hosted/pub.dev/<package>-<version>/...`, plus 24
references to the temporary directory the release was staged in.

If you pulled 0.7.3, those bytes are in your pub cache. They disclose the
publishing machine's account name, its pub-cache and staging-directory
locations, and the exact set and versions of the 45 packages resolved there at
build time. We checked for credentials and found none — no private keys, SSH
keys, or API tokens; the payload is a compiler cache and dependency source, not
configuration. Nothing about *consumers* of this package was included, and the
files were inert: no code under `lib/` reads anything in `build/`, so nothing
you ran was affected.

Upgrading to 0.7.4 (in range for any `^0.7.x` constraint) replaces the archive.
Removing `.pub-cache/hosted/pub.dev/voice_guidance-0.7.3/` clears the old copy.
**0.7.3 remains downloadable from pub.dev — published versions are immutable and
cannot be withdrawn**; this release supersedes it, it does not recall it.

**Cause, and why it should not recur.** `build/` has been ignored by the
repository's root `.gitignore` since 2026-03-04, and `pub publish` honours that
when run from inside the work tree. 0.7.3 was published from a staging copy
*outside* the work tree, where a repo-root `.gitignore` does not apply; pub then
included every file on disk and reported "0 warnings". This release adds a
`.pubignore` to the package itself, so the exclusion travels with the package
directory wherever it is copied or staged. Verified by reproducing the fault:
with `build/` present on disk, the publish dry-run produced 15 MB without the
`.pubignore` and 40 KB with it.

## 0.7.3

Widens the `navigation_safety_core` constraint to `>=0.10.0 <0.12.0`.

The previous `^0.10.0` constraint excluded core 0.11.x, so a project that asked
for the current core could not also take this package at its current version.
The resolver silently selected an older release of this package instead, with no
error and no warning. Core 0.11.0 and 0.11.1 are additive (a re-export, and a
percent-to-fraction humidity factory); this package compiles and its full test
suite passes against 0.11.1.

Also removes a `dependency_overrides` block that referenced sibling packages by
relative path. It was inert for consumers, but it prevented this package from
resolving standalone from its published archive.

No API or behaviour change.

# Changelog

## 0.7.2

- Widen the `routing_engine` constraint to `>=0.4.0 <0.6.0` so voice guidance
  can speak `routing_engine` 0.5.0's language-honoring instructions (Japanese
  by default) — the voice lane must not be the link that blocks the narration
  from reaching the driver. No library code change (lib/ is byte-identical
  to 0.7.1).


## 0.7.1
- docs: correct stale README install pin to current version (no API change).

## 0.7.0 — 2026-06-14 — add the tactile (haptic) accessibility hazard channel

Adds an opt-in tactile hazard channel so a deaf / hard-of-hearing
driver — or HER in a roaring-wind whiteout where speech cannot
carry — receives the **same hazard warning** a hearing driver gets,
off the **same severity gate**, via a tactile channel, with a
grammar that **distinguishes severity** (a single undifferentiated
buzz is worse than honest). Disabled by default; preserves 0.6.x
back-compat byte-for-byte on the audio path.

### Added

- **`HapticEngine`** (`lib/src/haptic_engine.dart`) — abstract
  tactile engine: `isAvailable()` / `cue(HapticCuePattern)` /
  `stop()` / `dispose()`. Additive + advisory by contract; `cue`
  must not throw (honest degradation), so it can never gate, delay,
  or silence the audio channel.
- **`NoOpHapticEngine`** (`lib/src/noop_haptic_engine.dart`) —
  silent engine that records the cues it is asked to render
  (`cues` / `tactileCues`). For tests and headless / motor-less
  hosts. Never throws.
- **`FlutterHapticEngine`** (`lib/src/flutter_haptic_engine.dart`) —
  wraps flutter/services `HapticFeedback`. Renders the pure
  `HapticCuePattern.pulseCount` grammar: warning → a measured
  double-pulse (2 medium impacts), critical → an urgent triple-pulse
  (3 heavier impacts), doubly distinguishable by count (2 vs 3) and
  intensity (medium vs heavy). Guarded with the **same
  `MissingPluginException` → unavailable** honest-degradation
  pattern as `FlutterTtsEngine`: `pluginAvailable` flips false and
  `isAvailable()` returns false once the platform reports missing;
  any other haptic error is swallowed. Injectable impact seam for
  tests.
- **`VoiceGuidanceBloc({HapticEngine? hapticEngine})`** — new
  optional constructor parameter. Defaults to null preserving 0.6.x
  back-compat. When supplied, the bloc fires a tactile cue
  ADDITIVELY beside the existing TTS speak in the hazard dispatch
  (`_onHazardAnnounced`), fire-and-forget so the haptic channel
  never affects audio timing. The cue is derived from the hazard
  event's `AlertSeverity` via `navigation_safety_enums`
  `hapticCueForSeverity` (bridged from the core severity through an
  exhaustive, compile-checked switch). No event-shape change.

### Why this exists

The audio channel is not a universal channel. An audio-only hazard
warning reaches nothing to a deaf or hard-of-hearing driver, and
nothing to a hearing driver inside a roaring-wind whiteout where
speech cannot carry. The tactile channel carries the same warning
off the same severity gate. Grounded in recorded driver voices (see
`DRIVER_VOICES.md`, the deaf / hard-of-hearing entry: SafeDrive4Deaf
n=25/100%, Bauman 2009, Gaffary & Lécuyer 2018): differentiated
cues are both wanted and effective — a single static buzz a driver
cannot act on is worse than honest.

### Discipline

- **Same-gate / set-parity invariant** (load-bearing, locked by
  test): the haptic fires off the same `AlertSeverity` gate the
  audio uses; the deaf driver's cue SET equals the hearing driver's
  warning SET `{warning, critical}` — no reduced subset that
  silently drops the most serious warnings for the driver who can
  least afford to miss them.
- **Severity-not-profile invariant**: the cue is a pure function of
  severity via `hapticCueForSeverity`. It takes no `DriverProfile`
  by construction. Severity decides whether/what; a profile only
  ever decides how.
- **Additive-only**: the haptic NEVER gates, delays, or silences
  audio. It is fired fire-and-forget; `cue` never throws. An
  integrator supplying no haptic engine sees the 0.6.x audio path
  unchanged.
- **Advisory-not-control**: QM / advisory / severity-gated /
  non-fabricating. No actuator authority. See the
  `SAFETY_BOUNDARY.md` §10 addendum.

### Honesty bound

A haptic pattern is FELT, not asserted. This release is verified by
logic / widget tests + `NoOpHapticEngine` recording + injectable
impact-seam tests of the Flutter engine's degradation and pulse
grammar. It is **NOT** verified by feel: on this host the Flutter
impl resolves to no sensation (desktop / motor-less). The
motor-less-device gap — that "available" cannot guarantee a felt
physical motor — is documented in `KNOWN_LIMITATIONS.md`. No
desktop haptic is fabricated.

### Tests

- New `test/flutter_haptic_engine_test.dart`: pulse grammar
  (warning → 2 / critical → 3 / none → 0); `MissingPluginException`
  → `pluginAvailable` false + `isAvailable()` false; other errors
  swallowed (no throw); dispose prevents further cues.
- New `test/noop_haptic_engine_test.dart`: records cues; tactile
  subset; dispose clears + reports unavailable.
- New `test/voice_guidance_bloc_haptic_test.dart`: severity-coupling
  lock (warning hazard → warning cue; critical hazard → critical
  cue); **deaf-cue-set == hearing-warning-set** off the same gate;
  haptic fired ADDITIVELY beside the TTS speak (audio unchanged);
  back-compat (no haptic engine → no behaviour change).

### Bumped

- New dependency `navigation_safety_enums: ^0.1.3` (the pure-Dart
  home of `HapticCuePattern` + `hapticCueForSeverity`).

### Unchanged (back-compat)

- All 0.6.x audio surface unchanged. `VoiceGuidanceBloc` with no
  `hapticEngine` runs the 0.6.x code path identically.
- `TtsEngine` interface unchanged. Hazard event shape unchanged.

## 0.6.3

- Republish from the embedded-target Dart 3.10.1 SDK (Flutter 3.38.3) to correct a stale
  `^3.11.0` SDK floor in the previously-published artifact. No source or behavior change; the
  source already declared `sdk: ^3.10.0`. Restores `pub get` for embedded/automotive Dart
  consumers on Dart 3.10.x.

## 0.6.2 — 2026-05-10 — Pana score recovery (Theme α P3)

- Trim pubspec `description` to within the pana 60–180 character target.
- Add minimal `example/main.dart` for pana documentation scoring.
- Apply `dart format` to clear any formatter findings.
- No SDK source changes; metadata + format pass only.


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

