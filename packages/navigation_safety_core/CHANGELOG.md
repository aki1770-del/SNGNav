# Changelog

## 0.11.9

0.11.8 computed the braking part of the warning-visibility floor at 5.5 m/s²,
a dry-pavement figure, on every road, and there was no way to pass another
value. Its docs said that on snow or ice stopping can take more distance than
the floor it returned. At 120 km/h on readings that point to black ice, that
floor was up to 433 m shorter than the same formula gives with the ice figure
below. This release adds a field for the deceleration, uses an ice figure when
the readings you pass point to black ice, and raises the warning temperature
on those readings so that comparing the ambient reading with it warns. It also
changes five wet-ice strings that `AlertExplainer` and
`RoadSurfaceConditionGlossary` return, and it requires
`navigation_safety_calibration` 0.1.3 or later.

**If your lock holds `navigation_safety_calibration` 0.1.2, read this before
upgrading.** This release calls `isRadiativeFrostBlackIce`, which that package
added in 0.1.3, so it now depends on `navigation_safety_calibration: ^0.1.3`.
0.11.8 accepted `^0.1.2`.

- If your pubspec does not list `navigation_safety_calibration`, upgrading this
  package moves it too, and nothing else is needed.
- If your pubspec lists it with a range that allows 0.1.3, such as `^0.1.2`,
  `dart pub upgrade navigation_safety_core` stops at 0.11.8. It shows
  `(0.11.9 available)` on this package's line and reports no error. Upgrade
  both together:
  `dart pub upgrade navigation_safety_core navigation_safety_calibration`.
- If your pubspec allows only versions below 0.1.3, 0.11.8 is the newest
  version of this package that resolves with it. A pubspec that asks for
  `^0.11.9` fails to resolve, with a message naming
  `navigation_safety_calibration ^0.1.3`.

**If you pass both `ambientTempCelsius` and `humidityRH`, read this first.** On
readings this package classifies as black ice, two values can be higher than
0.11.8 gave you: `warningVisibilityMeters`, when you also pass `speedMps`, and
`warningTemperatureCelsius`. No value is ever lower than in 0.11.8. If you do
not pass both readings, and do not pass the new field, every config you get is
the one 0.11.8 gave you. If you pass both but the readings are not black-ice
readings, you also get what 0.11.8 gave you.

**If your app shows, speaks, compares or looks up the wet-ice text, read this
too.** The 0.11.8 entry said the wet-ice strings were not changed in that
release. Five of them change in this one. They no longer call wet ice the most
slippery condition, or the most dangerous one; the `RoadSurfaceCondition.wetIce`
docs say what the cited sources show. Code that compares these strings with the
old text, or looks up a recording, translation or cache entry by the old text,
no longer finds a match, and this package does not report that. The old and
new strings, exactly:

- `AlertExplainer.forConditionAndProfile(RoadSurfaceCondition.wetIce, ...)`
  `.action`:
  - `ageingRural`. Was:
    `アイスバーンです。最も滑りやすい路面状態です。可能であれば停車できる安全な場所を探してください。走行中は時速20km以下を目安に`
    Now:
    `アイスバーンです。最も滑りやすい路面の一つです。可能であれば停車できる安全な場所を探してください。走行中は時速20km以下を目安に`
    Only the second sentence changed: from "it is the most slippery road
    condition" to "it is one of the most slippery road surfaces", in
    translation.
  - `snowZoneExperienced`. Was: `アイスバーン、最危険、20km/h以下`
    Now: `アイスバーン、極めて危険、20km/h以下`
    (最危険, "most dangerous", became 極めて危険, "extremely dangerous", the
    words the `noviceUrban` string already uses).
  - `foreignTouristSnowZone`. Was:
    `Wet ice — most slippery condition. If possible, stop in a safe place. Otherwise drive below 20 km/h.`
    Now:
    `Wet ice — among the most slippery road surfaces. If possible, stop in a safe place. Otherwise drive below 20 km/h.`
- `RoadSurfaceConditionGlossary.forConditionAndProfile(RoadSurfaceCondition.wetIce, ...)`
  `.jaSpeakString`:
  - `ageingRural`. Was: `アイスバーンです。最も滑りやすい状態です`
    Now: `アイスバーンです。最も滑りやすい路面の一つです`
  - `foreignTouristSnowZone`. Was: `ぬれた凍結路面、最も滑ります`
    Now: `ぬれた凍結路面、最も滑りやすい路面の一つです`

No other string these two classes return has changed: every name, speak
string, action, verbosity and locale tag, for every condition and profile, is
the one 0.11.8 returned. `navigation_safety` shows the `AlertExplainer` text in
`AlertExplainerExpandableSheet` when it is expanded, and as
`NavigationState.alertMessage` when its bloc has a driver profile and the alert
carries a condition. `voice_guidance` speaks it when its bloc has a driver
profile and the navigation state carries a condition. Every `navigation_safety`
from 0.9.4 and every `voice_guidance` from 0.7.3 does this and accepts this
release, so what they show and say changes when your app resolves it, whichever
of those versions you hold.

**Which readings.** Those for which `isRadiativeFrostBlackIce(ambientCelsius:
..., humidityRHPercent: ...)` returns `true`: an ambient reading at or below
3.0 °C whose dew point is at or below 0 °C, with relative humidity of at least
5 %. That includes every ambient reading at or below 0 °C. To see whether a
config you got used them, call that function with the same readings, humidity
in percent.

- **Warning visibility, when you also pass `speedMps`.** On those readings, if
  you do not pass `brakingDecelerationMps2`, the braking distance is computed
  at 0.981 m/s² (0.10 × 9.81) instead of 5.5 m/s². 0.10 is the lower edge of
  "Ice 0.1 to 0.2" in TRB Special Report 115, whose table is for 30 to 40 km/h,
  and the upper edge of "Wet black ice 0.05–0.10" in VTI meddelande 911A. It is
  a figure this package chose from those ranges, not a measured stopping
  figure; flat, wet or near-melting ice can be lower. The floor in metres,
  0.11.8 then 0.11.9, on any such reading, without `timeSincePrecipitation`:

  | profile | 80 km/h | 100 km/h | 120 km/h |
  |---|---|---|---|
  | ageingRural | 300 → 308 | 300 → 463 | 300 → 650 |
  | noviceUrban | 320 → 332 | 320 → 493 | 320 → 686 |
  | snowZoneExperienced | 200 → 292 | 200 → 444 | 200 → 627 |
  | professional | 200 → 286 | 200 → 435 | 200 → 617 |
  | agriculturalForestry | 200 → 297 | 200 → 449 | 200 → 633 |
  | foreignTouristSnowZone | 400 → 400 | 400 → 491 | 400 → 683 |

  At 60 km/h and below nothing changes. Above 120 km/h the increase is larger.
  If you also pass `timeSincePrecipitation`, the increase can be smaller: the
  floor is the longer of this and the per-profile floor plus the drying margin,
  and that may already have been the longer one in 0.11.8.
  `forDriverContext` and vehicle-class overrides start from this floor. An app
  that warns when visibility is at or below the floor will warn at longer
  visibilities on these readings than it did.

- **New: `DrivingContext.brakingDecelerationMps2`**, in m/s², also a parameter
  of `DrivingContext.withPercentHumidity`. Optional; `null` means you have no
  value for the surface. **A value you pass can only lengthen the floor. It
  never gives a shorter floor than leaving it out.** It is taken in this order:
  1. `NaN`, `double.infinity`, `double.negativeInfinity`, zero and negative
     values are checked first and used as 0.4905 (0.05 × 9.81, the low end of
     "Wet black ice 0.05–0.10" in VTI meddelande 911A; TRB Special Report 115
     reports friction "dropping to near zero on completely flat surfaces",
     which no finite value represents), whatever the readings. The next two
     steps do not apply to them, so `double.infinity` does not count as a value
     above 5.5: at 120 km/h these values give a floor of 1,183 to 1,252 m, by
     profile. **Pass `null` when you have no value. Do not use 0, -1, `NaN` or
     `double.infinity` to mean "unknown".**
  2. Then a value above 5.5 is used as 5.5, so any other value of 5.5 or more
     gives the same floor as `null`, on any reading. A positive value below
     0.001 is used as 0.001. Other values are kept as given.
  3. Then, on black-ice readings, the lower of that value and 0.981 is used, so
     any value above 0.981 gives the same floor as `null` there and only a lower
     value lengthens it. **This includes a value you measured on the road. No
     value you can pass shortens the floor on those readings.** On other
     readings the value from step 2 is used.
  - The factories and `withPercentHumidity` do not throw on any of these
    values.
  - The README now lists this field, with the same rule: pass `null`, not a
    sentinel, when no value was measured.

- **Warning temperature, on black-ice readings.** `warningTemperatureCelsius`
  is now at least the ambient reading rounded up. It rises only where 0.11.8
  left it below that, and only for the four profiles whose baseline warning
  temperature is 0 °C: noviceUrban, snowZoneExperienced, professional and
  agriculturalForestry. It rises to at most 3 °C, before a vehicle-class
  override or the fatigued driver state adds its own degree. On a grid of
  every 0.1 °C from -10.0 to 6.0 °C and every 1 % from 5 to 100 % RH, for the
  six profiles, 700 of 92,736 combinations rise, all at ambient readings from
  1.1 to 3.0 °C, by 1 or 2 °C. The README and the `forProfileWithContext` docs
  use 3.0 °C and 70 % RH as their example. At those readings 0.11.8 gave the
  four profiles above 2 °C, and its README said a 3.0 °C reading "is still
  above it", although the same readings classify as black ice; 0.11.9 gives
  them 3 °C. `ageingRural` and `foreignTouristSnowZone`, whose baseline warning
  temperature is 2 °C, get 6 °C there, as in 0.11.8. The docs now say which
  profiles get which. At 3.0 °C and 75 % RH the four profiles go from 1 °C to
  3 °C. **Compare with `<=`:** `ambientTempCelsius <=
  warningTemperatureCelsius`. A strict `<` does not warn when the ambient
  reading is a whole degree, because 3.0 < 3 is false.

**What can turn your tests red after upgrading:** a test that pins
`warningVisibilityMeters` for a context with a speed and black-ice readings; a
test that pins `warningTemperatureCelsius` for black-ice readings; a test that
expects one of the five old wet-ice strings above, directly or through
`navigation_safety` or `voice_guidance`; a test that matches the whole string
of `DrivingContext.toString()`, which now lists six values instead of five; a
test that pins a `DrivingContext.hashCode` value, which differs from 0.11.8
even for a context that does not pass the new field. Contexts that do not pass
the new field compare equal exactly as before.

**Unchanged:** every other threshold and every score floor; every config
computed without both `ambientTempCelsius` and `humidityRH`, unless you pass
the new field; every warning visibility computed without `speedMps`; the drying
margin for `timeSincePrecipitation`; and `computeSpeedAdjustedVisibilityMeters`,
which still uses the deceleration you pass it as given and still throws
`ArgumentError` for zero or a negative value, unlike the new field.

**Tests:** four test files are new and ship with the package:
`braking_deceleration_on_ice_test.dart` and
`braking_on_ice_audit_vectors_test.dart` (the floor and the new field),
`effective_temperature_ambient_comparison_test.dart` (the warning temperature
against the ambient reading) and `residual_moisture_half_life_pin_test.dart`
(the drying margin at five times after precipitation).
`braking_deceleration_on_ice_test.dart` also has the test
`the black-ice classification uses the humidity as passed, not a rounded value`,
which fails if the factories round the humidity you pass before the black-ice
check: 2.8 °C at 81.6 % RH is a black-ice reading, and at 82 % it is not. No
existing test was renamed or removed.

**Docs:** the docs no longer give 3.0 m/s² for compacted snow or 1.5 m/s² for
glare ice. They give the friction ranges the cited surveys report, and
call 5.5 and 0.981 m/s² figures this package chose; see
`brakingDecelerationMps2` and `KNOWN_LIMITATIONS.md`. The README's list of live
driving conditions now includes the braking deceleration for the current
surface. 0.11.8's docs said the drying margin for `timeSincePrecipitation` adds
to the warning visibility floor. Neither 0.11.8 nor this release adds it to a
longer floor from speed: the floor is the longer of the floor from speed and the
per-profile floor plus the margin, as the docs now say. For
`snowZoneExperienced` at 150 km/h, with precipitation 0 minutes ago and no
temperature, humidity or braking deceleration passed, that is 400 m, not 233 m
plus 200 m.

## 0.11.8

A documentation release. No public API changes, and no value this package
computes has changed: no threshold, cap, reaction time, multiplier or alert
string. Outside comments and doc comments, `lib/` is unchanged except for one
debug-only assertion message (last item below).

**If you chose this package's defaults because the docs said they came from
published research, read this entry.** Earlier releases placed the default
values beside citations and called them "literature-anchored", "published
reference points" or "sourced from" named organisations. We read the cited
sources. None of them gives these values. The docs now say, for each, that it
is a recorded decision: a value this package chose, not one taken from a
study. The values themselves are the same as in 0.11.7.

- **The alerts-per-minute caps** in `AlertDensityThrottle.defaultCapFor`:
  professional 4.0, snowZoneExperienced 3.0, agriculturalForestry 2.0,
  noviceUrban 1.5, ageingRural 1.2, foreignTouristSnowZone 1.0. The docs no
  longer say the throttle prevents desensitization. It is meant to; that
  effect has not been measured.
- **The per-profile reaction times** used for the speed-dependent visibility
  floor: ageingRural 2.5 s, noviceUrban 3.58 s, snowZoneExperienced 1.8 s,
  professional 1.5 s, agriculturalForestry 2.0 s, foreignTouristSnowZone
  3.5 s. The 3.58 s and 1.32 s figures were attributed to PubMed 16313881.
  That paper (Sagberg and Bjørnskau 2006) gives no reaction times in seconds
  in its abstract, and found that the decrease in hazard-perception reaction
  time with experience "was not significant".
- **The 0.3.0 threshold changes**: noviceUrban's warning visibility of 320 m,
  and ageingRural's 4 °C info temperature and 2 °C warning temperature.
- **The state adjustments** in `forDriverContext` (fatigued +0.5 s and +1 °C,
  distracted +1.0 s), the **`CircadianPhase` boundaries and multipliers**
  (1.0 to 1.5) and the **confidence cap modifiers** (× 0.75 and × 1.25).
- **The 30 km/h and 20 km/h speeds** in `AlertExplainer` action strings. They
  are advisory reference points this package chose. JAF's snow-driving page
  gives no speed figure.
- **The Japanese wording** of `AlertExplainer` and
  `RoadSurfaceConditionGlossary`. The docs said this wording was sourced from
  JAF, MLIT, NEXCO and other public driver guidance. It is this package's own
  wording. JAF's page does use アイスバーン and ブラックアイスバーン.

**What your drivers hear about wet ice is unchanged, and its ranking is not
sourced.** For `RoadSurfaceCondition.wetIce`, the spoken and displayed strings
still call wet ice the most slippery condition: 最も滑りやすい and 最も滑ります
in Japanese, and "most slippery condition" in English. No source cited by this
package ranks wet ice that way, and JAF uses アイスバーン without defining it as
ice with a water film. The docs now say this. The strings are not changed in
this release, so the words your drivers hear stay the same.

If a default matters to your product, treat it as a starting value to check
against your own drivers and roads. `KNOWN_LIMITATIONS.md` lists, for each
value, what the cited sources show and what they do not.

**Citations that named the wrong authors or the wrong source.** Each is
corrected where it appears:

- PubMed 24642933 (Useful Field of View) is Wood and Owsley 2014, not "Ball et
  al".
- The rural-Japan frailty study was credited to "Kasama". It is Liu et al.
  2020.
- PMC4001671 was cited as Regan, Hallett and Gordon 2011. It is Regan and
  Strayer 2014, which describes the 2011 taxonomy. The trait/state split in
  `DriverContext` is this package's design. That paper lists driver conditions
  and driver states as factors in inattention and gives no magnitudes.
- PubMed 22664714 was credited to "Konstantopoulos et al". It is Mueller and
  Trick 2012, a driving-simulator study in which novice drivers had higher
  hazard response times and "were the only drivers to have collisions".
- PMC7283540 was cited as a Strayer study that anchors per-profile values. It
  is Cooper et al. 2020 (Strayer is its last author). It does not give this
  package's values.
- PubMed 38669900 was credited to "Bian et al". It is Xu and Bowers 2024, on
  hazard warning modality and timing for older drivers with impaired vision.
  Its citations are removed; see the list of removed citations below.
- The JAF link used a host that does not exist. It is now
  https://jaf.or.jp/common/attention/snow.
- A link described as MLIT's Hokkaido snow-road guide is the Hokuriku
  regional bureau's portal. It is removed.
- JIS D 0207 was given as a display-ergonomics standard. It is a general rule
  for dust tests of automobile parts. It is removed, with the other example
  standard numbers. The package has not mapped its text against any JIS or
  JASO document.
- Citations removed because the source, as far as we could read it, does not
  support the claim they were attached to. This is every citation this
  release removes from the package's docs and code comments, besides the
  standard numbers and the MLIT link above:
  - PubMed 38669900 (Xu and Bowers 2024) and PMC7283540 (Cooper et al.
    2020).
  - PMID 34111571 (a medication-adherence review) and an MDPI 2024 review of
    continuous glucose monitor alert design, both cited for `AlertExplainer`.
  - The AAA Foundation for Traffic Safety report on ADAS exposure and driver
    workload (2023).
  - An FHWA page on roadway-visibility research, cited for the
    `impairedVisibility` scale-up.
  - A Springer book chapter on ADAS visual and auditory interfaces.
  - A Powderlife blog post on Hokkaido winter driving, cited for
    `foreignTouristSnowZone`.
  - JARTIC and a Yahoo!カーナビ note, cited for the road-surface vocabulary.
  - OSHA 1928 and UNECE-FAO-ILO 2023 forestry literature, cited for the
    `agriculturalForestry` cap.
  - The use of arxiv 2410.06388, PMC12181921, PubMed 16313881 and PubMed
    22664714 as sources for the cap values. PMC12181921 is still cited, for
    alarm fatigue in health care. arxiv 2410.06388 is still cited, for alert
    fatigue from repeated false alarms in a simulator study. PubMed 16313881
    and 22664714 are still cited in `KNOWN_LIMITATIONS.md` for what they
    found about hazard perception.
- A statement with no source is removed: that engineering guidance gives 48
  to 72 hours for asphalt to dry, and that relative humidity above 80 %
  roughly doubles it.

**Other statements the docs made that were not accurate:**

- Black ice at air temperatures above 0 °C. The docs now give the condition
  their sources state: the air warms suddenly after a prolonged cold spell has
  left the road surface well below freezing, or radiative cooling under a clear
  night sky.
- A relative humidity reading between 100 % and 105 % is kept as saturated
  air. The docs called that "maximum caution". It is not: at 100 % the
  effective temperature equals ambient, so humidity adds the least warning
  margin. The code is unchanged; only the description was wrong.
- `foreignTouristSnowZone` was said to rest on published accident rates. The
  source is a Hokkaido driving guide that relays rental-car operators'
  accounts, with no rate.
- `AlertDensityThrottle`'s cold-start rule. The docs said only the first alert
  in a session skips the window check. Any alert that finds the rolling window
  empty skips it. The constructor already refuses a cap that is not greater
  than 0, so this changes no firing decision.
- The docs pointing to `navigation_safety_calibration` for citations now say
  that calibration's headers state which values are recorded decisions. That
  is true from `navigation_safety_calibration` 0.1.4. This package's
  constraint, `^0.1.2`, already allows 0.1.4.

**Debug builds only: the `assertUxDifferentiated` message is shorter.** When
no UX differentiator is registered for a profile, the `AssertionError` message
no longer ends with a sentence citing PubMed 38669900 and PMC7283540. The
registration instruction before it is unchanged. Release builds are not
affected, because Dart removes `assert`. A test that checks the message for
`'38669900'` or `'PMC7283540'` will fail.

Tests: some test names and comments no longer cite sources. No assertion
changed except the message check above.

## 0.11.7

A vehicle-class override may no longer change the critical thresholds, the
info thresholds or the alerts-per-minute cap. When a field of an override is
refused on the drive path, that field alone goes back to its un-overridden
value, and the rest of the override is checked on its own. This entry also
corrects two statements in the 0.11.6 entry; see **Correction to the 0.11.6
entry** below.

**Even if you use no override, read Earlier documentation that the code
contradicts, below.** It names four things that 0.11.6 and earlier releases
said and the code does not do. One of them can keep the ice advisory from
firing in an app that copied `example/can_bus_integration.dart`.

**If you use `VehicleThresholdOverrides`, read this first.** If you register
no override, or only `withKeiCarDefault()`, you receive exactly the configs
0.11.6 gave you, and nothing is printed. If your registry's class implements
`VehicleThresholdOverrides`, or extends it and replaces
`applyOverrideForToken`, then `forProfileWithContext` and `forDriverContext`
call your method, and the checks in this entry reach your registry only if
that method returns what this package's `applyOverrideForToken` returns.
Otherwise, as on 0.11.6, a field your method changes is applied as written in
every build mode, nothing is reported, and an exception your method throws
reaches whoever called those factories. To have the checks, build a registry
from your transforms with `VehicleThresholdOverrides.validated(...)` and
return its `applyOverrideForToken` result from your method.

- **The critical thresholds, the info thresholds and the cap may not be
  changed by an override, in either direction:** `criticalVisibilityMeters`,
  `criticalTemperatureCelsius`, `infoVisibilityMeters`,
  `infoTemperatureCelsius` and `alertsPerMinuteCapOverride`. A `null` cap must
  stay `null`, and NaN counts as a change. 0.11.6 did not check these fields.
  On the drive path each of them now comes back at its un-overridden value and
  the refusal is reported; nothing throws.
- **If you build your registry with `VehicleThresholdOverrides.validated(...)`**
  and a transform changes one of those five fields on any probe baseline, the
  call now throws `ArgumentError`, naming the token and the field. On 0.11.6 a
  registry whose transforms changed only these fields was accepted, and
  `validatedAtRegistration` returned `true`, although these fields were never
  checked. Two of the probe baselines carry a cap, 10.0 and 0.5, although the
  configs `forProfileWithContext` and `forDriverContext` pass to a transform
  carry a `null` cap. So a transform that leaves out the
  `alertsPerMinuteCapOverride` argument makes the call throw even if nothing
  else in it is refused; the message then shows `(10.0 -> null)`. Return the
  baseline's value for it. 0.11.6 accepted such a transform. If you build the
  registry at startup, you will meet the error on your first run. If you
  validate a registry built later from settings or remote configuration, it
  throws there, on the device, so catch `ArgumentError` at that call.
- **If your override moved a critical or info threshold, or set the cap, on
  purpose,** that value is no longer applied. If you raised a critical
  threshold, a reading between the un-overridden threshold and yours no longer
  meets the critical threshold, and by default only critical alerts bypass
  `AlertDensityThrottle`'s cap. Moving either threshold earlier has its own
  cost: critical alerts still take a slot in the throttle's rolling window,
  and info alerts take slots exactly as warnings do, so a later warning can be
  dropped. A transform is never shown the driver's profile, so a cap it writes
  replaces the per-profile default for every profile. In 0.11.5 and 0.11.6 a
  cap raised that way also came out of `forDriverContext` without the driver
  confirmation (`isHighConfidenceConfirmed`) that `forDriverContext` requires
  before it raises a cap itself. The `NavigationSafetyConfig` constructor does
  not check these five fields: if your integration needs a different value,
  build a config with it from the one this package's factory returns, knowing
  the above.
- **One refused field no longer discards the rest of the override.** 0.11.6
  returned the whole un-overridden config when any field was refused, so a
  legal raise of a warning floor in the same override was lost. That raise is
  now kept. Every refused field is reported, not only the first, so
  `onRejected` can be called more than once for a single call, and the default
  reporter can print one line for each refused field.
- **Refusals of these five fields are reported as
  `VehicleOverrideInvariant.severityNotProfile`.** No value was added to the
  enum, so an exhaustive `switch` over it still compiles, and a branch you
  wrote for `severityNotProfile` now also receives these fields.
- **Tests that expect your transform's critical, info or cap value in the
  result now fail;** expect the un-overridden value. Tests that expect the
  whole un-overridden config back from an override that also raises a warning
  floor now fail, because the raise is kept.

**If you construct `AlertDensityThrottle` with your own cap,** it now throws
`ArgumentError` for a NaN `alertsPerMinuteCap`, as it already did for zero or
below. On 0.11.6 a NaN cap was accepted without a report and made exactly the
decisions of a cap of 1.0, whatever cap the driver's profile was designed for:
after any alert, no info or warning alert fired until the rolling window had
emptied, while critical alerts still fired. The throw lands where you
construct the throttle. An infinite cap is still accepted, and then no alert
is dropped.

**Earlier documentation that the code contradicts.** 0.11.6 and earlier
releases shipped the statements below. This release does not change what the
package's code does in any of these cases.

- **If your app copied `example/can_bus_integration.dart`,** check which
  temperature it passes. The example passed engine coolant temperature as
  `ambientTempCelsius` and compared the coolant temperature with
  `warningTemperatureCelsius`. Wired as the example wires it, or with no
  registry, its ice advisory could not fire for any driver profile once the
  coolant was above 5 °C, whatever the temperature of the air outside. Pass a
  measured outside-air temperature. The example also passed a fixed 85 %
  relative humidity and a fixed 30 minutes since precipitation on every
  frame, which are not readings. In any weather, the fixed precipitation held
  its warning visibility at 409 m at 80 km/h, where its profile and registry
  give 250 m without those two. Leave out what you do not measure, and
  `DrivingContext` adds nothing for it.
- **If your app relies on the warning temperature to cover a road colder than
  the air,** the documentation of `forProfileWithContext` and the README said
  that the effective road-surface temperature "replaces ambient when it
  crosses the warning threshold earlier". It does not always. For
  `snowZoneExperienced` at 3.0 °C and 70 % relative humidity, the effective
  temperature is −1.9 °C, `warningTemperatureCelsius` comes back as 2, and
  3.0 °C is above it, although `isRadiativeFrostBlackIce` in
  `navigation_safety_calibration` 0.1.3 returns `true` for those readings. To
  warn whenever the effective temperature is at or below the per-profile
  warning temperature, also compare `computeEffectiveTemperatureCelsius`,
  which this package re-exports, with the `warningTemperatureCelsius` that
  `forProfileWithContext` returns. The README also said the effective
  temperature can be several degrees below the air temperature when humidity
  is high; it is further below when humidity is low: at 2.0 °C it is 1.3 °C
  at 95 % and −7.3 °C at 50 % relative humidity.
- **If your app relies on the warning visibility to cover the distance needed
  to stop on snow or ice,** `KNOWN_LIMITATIONS.md` said to pass a lower
  braking deceleration for those surfaces, but `forProfileWithContext`,
  `forDriverContext` and `DrivingContext` take none. The speed-adjusted
  warning visibility always uses 5.5 m/s², which the calibration package gives
  as a dry-pavement value and the README counted among its worst-case
  constants. In `forProfileWithContext`, speed raises the warning visibility
  only where the reaction and braking distance at 5.5 m/s² is longer than the
  per-profile floor, which for no profile happens below 133 km/h; below that,
  the README's "additional visibility margin" from speed is nothing. At
  100 km/h `snowZoneExperienced` gets 200 m, and the same formula at 1.5 m/s²,
  the calibration package's value for glare ice, gives 307 m.
  `forDriverContext` adds a margin at any speed: when its `DrivingContext`
  carries `speedMps`, it adds the speed times 0.5 s for `DriverState.fatigued`
  or 1.0 s for `DriverState.distracted`, rounded up to the metre, to what
  `forProfileWithContext` gives, so at 100 km/h `snowZoneExperienced` gets
  214 m or 228 m instead of 200 m.
- **If your app passes a `DriverState` or a `Confidence` to
  `forDriverContext`,** their documentation called these adjustments
  conservative-only or caution-adding. They never move a threshold later, but
  `DriverState.impairedVisibility` moves the info and critical visibility
  thresholds earlier along with the warning threshold, and `Confidence.low`
  lowers `effectiveAlertsPerMinuteCap`: a throttle built from it admits one
  advisory alert per window instead of two for `ageingRural`, and three
  instead of four for `professional`. Info and critical alerts take slots in
  `AlertDensityThrottle`'s window, so either can drop a later warning. For
  `ageingRural`, visibility readings of 1600 m, 1600 m and 250 m ten seconds
  apart fire the 250 m warning in `DriverState.alert`, while in
  `DriverState.impairedVisibility` the first two are info alerts and the
  warning is dropped; with `Confidence.low`, an info alert followed ten
  seconds later by a warning drops the warning.

**Correction to the 0.11.6 entry.** A published entry cannot be edited, so it
is corrected here.

- 0.11.6 said: *"If your release build has been running with a relaxing
  override, your warnings will move earlier after this upgrade."* That was
  true only for the fields your override relaxed. 0.11.6 refused an override
  whole whenever it lowered a warning floor or changed a score floor in either
  direction, so every other change in that override went back to its
  un-overridden value. That reached overrides that relaxed nothing: raising
  `warningScoreFloor` makes more scores critical, yet an override that raised
  it by 0.01 and raised `warningTemperatureCelsius` by 1 °C lost the
  temperature raise. Measured with the `ageingRural` profile against a 0.11.5
  build with assertions elided, reading the thresholds in order (critical,
  then warning, then info): in that override, 2.5 °C moved from the warning
  tier to the info tier; an override that raised `warningVisibilityMeters` by
  50 m and lowered `warningTemperatureCelsius` by 1 °C lost the raise, and
  320 m visibility moved from the warning tier to the info tier; an override
  that lowered `warningVisibilityMeters` by 150 m and raised
  `criticalVisibilityMeters` by 40 m lost the raise, and 100 m visibility
  moved from the critical tier to the warning tier. This release gives back
  the warning-floor raises. It does not give back the critical raise.
- 0.11.6 also said that a transform changing those five fields *"is not
  detected and is applied as written, as it was in 0.11.5"*. That held only
  when the same transform broke none of the checked fields; when it did, the
  five fields were discarded with the rest of the override. Neither of its
  descriptions of `.validated(...)` mentioned that limit.

**Bounds**

- Refusing an earlier critical or info threshold, and not only a later one,
  is a precaution: whether moving a given threshold earlier drops more
  warnings than it delivers alerts depends on the conditions on the road, and
  it has not been measured.
- On the two warning floors this release is never later than 0.11.6, or than
  a 0.11.5 build with assertions elided, for any transform: each warning floor
  is the higher of your transform's value and the un-overridden value.

## 0.11.6

A vehicle-class override is now refused where it is REGISTERED, not on the
drive path.

`VehicleThresholdOverrides.applyOverrideForToken` **no longer throws.** It can
run once per vehicle-bus frame while the car is moving — this package's own
`example/can_bus_integration.dart` derives its config inside an `await for` in
an `async*` body — and there an uncaught throw terminates the stream, ending
the driver's advisories for the rest of the journey. Measured on a per-frame
harness: **0 of 5 advisories delivered, nav surface dead.** A guard that
removes the warning is not a stronger halt; it is the absence of one.

**If you use `VehicleThresholdOverrides`, read this first.** If you register
no override, or only `withKeiCarDefault()`, you receive exactly the configs
0.11.5 gave you, and nothing is printed.

- **A relaxing override is now refused in every build mode.** In a 0.11.5
  release build it was silently applied, and the driver was warned later than
  this package designed. You now receive the un-overridden baseline and the
  refusal is reported. If your release build has been running with a relaxing
  override, your warnings will move earlier after this upgrade. That is the fix.
- **What that refusal checks: five fields.** `warningVisibilityMeters` and
  `warningTemperatureCelsius` may not decrease, and the three score floors may
  not change. A transform that changes `criticalVisibilityMeters`,
  `criticalTemperatureCelsius`, `infoVisibilityMeters`, `infoTemperatureCelsius`
  or `alertsPerMinuteCapOverride` is not detected and is applied as written, as
  it was in 0.11.5; for those fields the rule is kept by your transform, not by
  this release.
- **An exception thrown inside your transform no longer reaches your code.** In
  0.11.5 it propagated to whoever called `forProfileWithContext`,
  `forDriverContext` or `applyOverrideForToken`. It is now caught, the baseline
  is returned, and the exception is passed with its stack trace to
  `onRejected`. A `try`/`catch` you wrapped around those calls to handle a
  failing override will not fire; move that handling into `onRejected`. To meet
  a broken transform at startup instead, build the registry with
  `VehicleThresholdOverrides.validated(...)`, which throws `ArgumentError`
  there.
- **Tests that expect `AssertionError` from a relaxing override now fail,**
  because nothing on that path throws any more, in any mode. Test that
  `.validated(...)` throws `ArgumentError`, or that `onRejected` receives a
  `VehicleOverrideRejection`.
- **A refusal prints one line to stdout** (prefix `navigation_safety_core:`),
  once per token, field and invariant. If stdout carries data for you, pass
  `onRejected` or assign `VehicleThresholdOverrides.rejectionReporter`.

Three states of the same relaxing override, one harness, `dart run` with
assertions elided:

| | advisories | warning visibility | stream |
|---|---|---|---|
| published `0.11.5` (`assert`, elided) | 5/5 | **10 m — relaxation APPLIED** | alive |
| unreleased guard repair (`throw`) | **0/5** | — | **dead (`ArgumentError`)** |
| this release | 5/5 | **359 m — baseline, relaxation REFUSED** | alive, reported |

**Added**

- **`VehicleThresholdOverrides.validated(...)`** — a non-`const` factory that
  probes every registered transform against a battery of baselines and throws
  `ArgumentError` at registration, naming the token, the field and the probe.
  Registration is where the mistake is actually made, once, by a developer who
  can read the stack trace.
- **`VehicleOverrideRejection`** and **`VehicleOverrideInvariant`** — the
  refusal, reported rather than raised.
- **`onRejected`**, a named parameter on every registry constructor, plus
  the process-wide `VehicleThresholdOverrides.rejectionReporter` and
  `resetRejectionReporting()`.
- **`registrationProbeCount`** — the probe-battery size as a number an
  integrator can read.
- **`tool/release_mode_proof.dart`** — a plain Dart program that exercises the
  per-frame path with assertions ELIDED, and **refuses to run** when they are
  enabled. Through 0.11.5 the suite was green in the one mode the guards
  existed in; a check that can only run in that mode cannot see this defect.

**Changed**

- `applyOverrideForToken` refuses a violating override **whole**: it returns
  the un-overridden baseline and reports the rejection. It does not
  half-repair the config field-by-field — a transform that got one field wrong
  has not earned trust on the others, and a partial application looks nearly
  right, which makes the defect harder to notice. It does not silently apply
  the relaxation either; that is the `0.11.5` defect.
- A transform that **itself throws** is now caught on both paths. Through
  `0.11.5` nothing guarded this: the integrator's own exception escaped
  straight through and killed an `async*` caller exactly as an invariant throw
  did.
- An `onRejected` handler that throws is caught and swallowed — otherwise the
  stream-killing throw has merely moved into the integrator's logger.
- `withKeiCarDefault()` routes through `.validated()`. We do not ask
  integrators to validate what we decline to validate ourselves.
- `example/can_bus_integration.dart` builds the registry **once, at startup**,
  and memoises the per-frame config so it is re-derived only when a sample
  actually moves. The example teaches the pattern, and it taught the wrong
  one. The config itself cannot be fully hoisted — it is a function of live
  speed and temperature, which is the point of a CAN integration; what is
  hoisted is the part capable of being wrong.

**Honest bounds**

- Registration-time validation is a **strong filter, not a proof**. The probe
  battery is finite (`registrationProbeCount`): a transform that branches on a
  field the battery does not vary, or that is discontinuous between probe
  points, can pass registration and still violate an invariant on a live
  config. That is why the drive-path check remains — it refuses rather than
  crashes.
- The default reporter uses `print`, deliberately **not** `dart:developer`'s
  `log`: measured 2026-09-13 on Dart 3.11.1, `developer.log` emits nothing
  under either `dart run` or `dart compile exe` without an attached VM
  service. Routing the report there would have made it silent in exactly the
  shipped build where it matters.
- Reports de-duplicate per token, field and invariant on the default channel
  so a broken override cannot flood an IVI log for a whole journey. A
  supplied `onRejected` is **not** de-duplicated; the integrator owns that
  policy.

## 0.11.5

- Widen `latlong2` from `^0.9.1` to `>=0.9.1 <0.11.0`.

  `latlong2 0.10.0` shipped 2026-04-25 and `flutter_map 8.x` resolves it, so the old
  ceiling made this package **uninstallable alongside current `flutter_map`** —
  `version solving failed` for every published version. No source change; the cap was
  gratuitous. Verified on `latlong2 0.10.1`: analyze clean, **319/319 tests pass**.


## 0.11.4

An absent ambient temperature is no longer answered with a temperature.

**What you already have, and what it does.** In 0.11.3 and every release
before it, `NavigationSafetyConfig.forProfileWithContext` read an absent
`context.ambientTempCelsius` as `5.0` on one path — the residual-moisture
visibility margin taken when `context.timeSincePrecipitation` is set:

```dart
final ambient = context.ambientTempCelsius ?? 5.0; // 0.11.3
```

Seventeen lines below, the black-ice branch of the same function refused to
proceed at all without that field (`context.ambientTempCelsius != null`). One
function, two opposite treatments of one missing input, and the substituted
`5.0` was indistinguishable inside the calculation from a reading actually
taken. It was also the only place in that factory where an absent field was
filled in rather than skipped — `DrivingContext` documents that every absent
field falls back to the per-profile baseline.

**Your numbers do not change.** `computeSurfaceMoistureFraction` accepts
`ambientCelsius` "for forward-compatible API shape" and does not read it, so
the substituted `5.0` never reached a threshold. If you are on 0.11.3 today,
nothing you are seeing is wrong and there is nothing to undo. A test in this
release pins that parity: every profile, elapsed time, and ambient value —
present or absent — produces exactly the 0.11.3 result while the calibration
stays temperature-independent.

**What changes is what happens if that stops being true.** The calibration's
own documentation says a future revision "may modulate the half-life by
temperature *without an API break*", and this package depends on it through
`^0.1.2`. Such a release could arrive on your next `pub upgrade` with no
change here and no action by you — and the inert `5.0` would quietly become
load-bearing, deriving a driver-facing visibility floor from a temperature
nobody measured. To see what that would cost, the calibration was mutated to
lengthen the evaporation half-life in the cold — `90 min × (1 + (20 − T)/40)`,
a shape its own docs permit — and this package was run against it with
ambient absent, 30 minutes after precipitation ended:

| profile | baseline | 0.11.3 | 0.11.4 | honest, ambient −5 °C |
|---|---|---|---|---|
| `ageingRural` | 300 m | 554 m | **300 m** | **560 m** |
| `noviceUrban` | 320 m | 591 m | **320 m** | **598 m** |
| `foreignTouristSnowZone` | 400 m | 738 m | **400 m** | **747 m** |

From 0.11.4 the branch passes no invented temperature. When ambient is
absent it asks the calibration the same question at −40 °C, 0 °C and 40 °C
and uses the answer only if all three agree — agreement meaning the answer
does not depend on the missing measurement, so the absence costs nothing.
If they ever disagree, the margin is withheld and the per-profile baseline
stands, which is what every other absent field of `DrivingContext` already
does.

**Read the last two columns before you upgrade, because they do not say what
a release note usually says.** On a cold road — this package's entire
subject — withholding is *further* from the truth than the fabricated value
it replaces. For `ageingRural` at −5 °C the honest floor is 560 m; 0.11.3's
invented `5.0` reached 554 m, six metres short, and 0.11.4 returns the
300 m baseline, **260 m short**. Closer to the rain it is worse, not better:
one minute after precipitation ends the honest floor is 599 m and 0.11.4
still returns 300 m. Nor is this an artifact of one formula: under a steeper
Q10 mutation — half-life doubling per 10 °C of cooling,
`90 min × 2^((T_ref − T)/10)` — the same cell reads honest 576 m, 0.11.3
555 m, 0.11.4 300 m at **T_ref = 10 °C**, and honest 588 m, 0.11.3 576 m,
0.11.4 300 m at the 20 °C reference the linear shape above is written
around; the ranking is the same either way. The arithmetic is exact and
shape-independent: **withholding is short by the whole margin, while
inventing was short only by the difference between the temperature it
invented and the one that was real.** 0.11.4 buys an honest *input* at the
price of a less accurate *answer*, and on a cold road much less accurate.
The per-profile floor is never lowered below baseline — but that is a
smaller promise than it sounds, because on the day this branch diverges the
baseline is not the honest answer.

**None of this reaches you if you pass an ambient reading.** The divergence
lives only on the path where `timeSincePrecipitation` is set and
`ambientTempCelsius` is not. Set it and the margin is computed from your
measurement, unchanged. If you cannot measure it, commit `pubspec.lock` —
the pin this package's pubspec already asks for is what stops a calibration
revision arriving unannounced.

**The alternative that was considered and not taken: take the most adverse
probe instead of withholding** — absence assumes the worse road. It was
implemented and measured, not argued: it lands within about 20 m of the
honest answer in every cell above and never below it (`ageingRural`, 30 min:
574 m against an honest 560 m), and it is bit-identical to this release on
both calibrations in the `^0.1.2` range (0.1.2 and 0.1.3), with the full
319-test suite green. It is also the shape the sibling package ratified the
same day — *positive evidence fires on partial knowledge; negative
conclusions require whole knowledge* — and withholding a
hazard margin because a field is absent is a negative conclusion drawn from
absence. That inversion is sharper here than the general rule, because the
caller has *positively reported the hazard*: `timeSincePrecipitation` is
set, so we have been told the road is wet, and what is missing is only a
modifier of how fast it dried.

Two reasons it is not in 0.11.4, both stated so you can disagree with them.
It moves a driver-facing threshold, which is a decision for this family's
safety owner and not for the package author. And it costs the return type
its ability to say *"I could not look"*: a worst-case bound handed back as a
plain `double` is indistinguishable from a reading — the very defect this
release exists to remove, one level up. So the open question is not
withhold-or-not; it is whether the bound can be returned **as a bound**, and
that is an API change. It is recorded, and it is not settled here.

- No API changes. No behaviour change on any calibration published to date.
  The divergent cells in the table above are produced by a **mutated**
  calibration that has not been published. Run those same scenarios — each
  profile, ambient absent, 30 minutes after precipitation — against the two
  calibrations actually inside this package's `^0.1.2` range (0.1.2 and
  0.1.3, whose decay module is byte-identical), and 0.11.3 and 0.11.4 return
  the same warning-visibility floor in every one: 538 m, 574 m and 717 m for
  the three profiles, under both releases alike. This package's full
  319-test suite passes.
- **The tripwire, and its window.** The guard is not a runtime check, it is a
  test: `absent_ambient_not_invented_test.dart` asserts
  *"computeSurfaceMoistureFraction ignores ambientCelsius — if this fails,
  the residual-moisture branch must be rewritten"*. Run against the mutated
  calibration it goes red, printing the eight per-temperature fractions it
  expected to be one. The alarm therefore rings in **our** CI, where the
  author can act, and not in yours, where you could not. The exposure you
  are carrying is the gap between a calibration release and this package's
  next CI run: in that window your `pub upgrade` can pick the new
  calibration up and nobody is watching.
- Honest bounds: agreement across three probes is evidence of independence,
  not proof of it. The durable fix is a calibration signature that can
  express "not measured" — widening `ambientCelsius` to `double?` would be
  source-compatible for every existing caller — and that is a change in
  `navigation_safety_calibration`, which this package does not own.

## 0.11.3

One Japanese explainer string corrected — a caution the driver could not hear.

- **Fixed the `professional` WET explainer, which was spoken as silence.**
  The string was 「濡路、注意」. Measured through open_jtalk, 濡路 renders as
  SILENCE, so a professional-profile driver hears 「（無音）、注意」 — a caution
  with no hazard named at all. It was also the single outlier among six
  profiles that otherwise all say 「濡れた路面」. Terseness is right for this
  profile; an unpronounceable term is not. Now 「濡れた路面、注意」, which keeps
  the profile's brevity and names the hazard aloud. Terminology per 表記規準 v1
  (2026-07-21) §V2 — do not put a term in a spoken string whose reading is not
  certain. A regression test pins it.
- No API changes; only this one string changed.

**Note on provenance.** 0.11.2 was published from a working tree that never
reached git, so this repository's copy sat at 0.11.1 and carried the false
「気温0°C以下で薄氷ができています」 string that 0.11.2 had already corrected on
pub.dev. The 0.11.2 sources were reconstructed here from the published archive
and proven byte-identical to it before this change was applied on top, so
0.11.3 supersedes 0.11.2 rather than reverting it.

## 0.11.2

Two Japanese explainer strings corrected — ice does not need sub-zero air.

- **Fixed a false claim in the `ageingRural` ICE explainer.** The previous
  string said 「気温0°C以下で薄氷ができています」 — that ice forms only when
  the air temperature is at or below 0°C. That is wrong: road surfaces
  radiate heat and can drop below the air temperature, so thin ice forms
  while the air is above zero — bridges and tunnel exits first (JAF
  snow-driving guidance). The old wording taught a driver checking the
  thermometer on a clear cold morning that above-zero air means no ice —
  the exact misjudgement this package exists to prevent, and it
  contradicted the above-zero black-ice classification that
  `snow_rendering` 0.2.7+ already ships. The corrected string states that
  the surface can freeze even when the air is above 0°C and keeps the
  30 km/h speed advisory unchanged.
- **Fixed the `ageingRural` WET explainer** the same way (the road can
  freeze with above-zero air; bridge/tunnel-exit guidance kept) and aligned
  its terminology to the JAF authoritative term ブラックアイスバーン
  (previously bare ブラックアイス), matching `japanese_snow_vocabulary` and
  `snow_rendering` so the driver hears one consistent hazard name.
- Regression tests pin both corrections. No API changes; only these two
  strings changed.

## 0.11.1

The percent door — a correct home for percent-sourced humidity readings.

- **Added `DrivingContext.withPercentHumidity(humidityPercent: 95.0)`** —
  weather APIs (e.g. MET Norway `relative_humidity`) and forecast models
  carry relative humidity in PERCENT, while `DrivingContext.humidityRH` is a
  FRACTION in `(0.0, 1.0]` (and the downstream calibration throws on
  percent). The factory converts to the fraction contract and handles the
  dirty values real feeds deliver, caution-consistently:
  `1 <= p <= 100` converts; `100 < p <= 105` **saturates to 100%**
  (supersaturated RH is a documented NWP/sensor reality at peak icing and
  freezing fog — saturated air is maximum caution, so the reading is kept,
  never crashed on); `p <= 0` is treated as **unknown** (the common
  missing-data sentinel; no lift, no crash); `0 < p < 1` is **rejected** as
  an almost-certain mis-wired fraction; `p > 105`/`NaN`/`±inf` are
  **rejected** (surface the feed bug). Additive; no existing API changes.
  Raw feed values outside these rules must be sanitized by the caller.
- Unit-warning docs on `humidityRH` cross-referencing the percent door; the
  documented `humidityRH` range is corrected to `(0.0, 1.0]` (the shipped
  calibration has always rejected `0.0` — the previous `[0.0, 1.0]` doc
  overstated the left edge).
- Portability hardening: an explicit `.toInt()` where `int.clamp`'s declared
  `num` return is assigned to an `int` in the humidity-lift path (no behavior
  change on current SDKs; verified the published 0.11.0 compiles and runs
  clean in a Flutter consumer — this is hardening, not a bug fix).


## 0.11.0

Calibration single-source-of-truth — depend-on + re-export.

- The three calibration primitives (`computeEffectiveTemperatureCelsius`,
  `computeSurfaceMoistureFraction`, `computeSpeedAdjustedVisibilityMeters`)
  are no longer an internal byte-copy in `lib/src/calibration/`. Core now
  **depends on `navigation_safety_calibration` (^0.1.2)** and **re-exports**
  it from the package barrel, so the standalone package is the single
  source of truth for the meteorological / kinematic design-default
  baseline — kept in sync by a real dependency edge, not by hand.
- **Non-breaking / additive:** these functions were previously private to
  core (used only internally by `NavigationSafetyConfig`); the re-export
  now surfaces them publicly via
  `package:navigation_safety_core/navigation_safety_core.dart` in addition
  to their existing home in `package:navigation_safety_calibration`. No
  existing symbol changes or is removed. Behavior is identical (the copies
  were byte-identical at the time of consolidation).
- This fulfills the depend-on + re-export design the calibration package's
  own docs anticipated at extraction time.

## 0.10.5
- docs: correct stale README install pin to current version (no API change).

## 0.10.4

Conservative-on-uncertain hardening — a non-finite value must never
silently defeat a conservative alert.

- **SafetyScore (GAP-1):** `SafetyScore` now maps non-finite component
  inputs (`NaN` / `±Infinity`) to the worst-case `0` so they alert
  conservatively instead of slipping through unclamped. Without the
  guard a `NaN` overall compares `false` to every threshold in
  `toAlertSeverity` (no alert), and `+Infinity` clamped to `1` (no
  alert) — both inverting the "if uncertain, alert conservatively"
  intent.
- **NavigationSafetyConfig (GAP-2):** the constructor now rejects a
  non-finite score floor (`NaN` / `±Infinity`) with an `ArgumentError`.
  The previous `floor < 0 || floor > 1` range checks were
  NaN-permissive (`NaN` compares `false` to both bounds), so a
  non-finite floor passed construction silently and then poisoned
  `toAlertSeverity` on the *threshold* operand: `overall < NaN` is
  always `false`, so even a worst-case `overall == 0` yielded NO alert.
  This closes the same failure family as GAP-1 on the operand the
  score-side guard does not reach. Regression tests assert the
  worst-case score still alerts `critical`.

## 0.10.3

- Republish from the embedded-target Dart 3.10.1 SDK (Flutter 3.38.3) to correct a stale
  `^3.11.0` SDK floor in the previously-published artifact. No source or behavior change; the
  source already declared `sdk: ^3.10.0`. Restores `pub get` for embedded/automotive Dart
  consumers on Dart 3.10.x.

## 0.10.2 — 2026-05-10 — Pana score recovery (Theme α P4)

- Trim pubspec `description` to within the pana 60–180 character target.
- Apply `dart format` to clear any formatter findings.
- No SDK source changes; metadata + format pass only.


## 0.10.1 — 2026-05-10 — Vehicle-CAN composition example (j1939)

Adds an illustrative `example/can_bus_integration.dart` showing how
`navigation_safety_core` composes with the [`j1939`](https://pub.dev/packages/j1939)
package to translate SAE J1939 vehicle-bus events into a
`DrivingContext` and an `AlertExplainer` advisory action. Documents
two J1939/71 PGNs (CCVS1 0xFEF1 wheel-based vehicle speed; ET1 0xFEEE
engine coolant temperature) as composition anchors. Adds a
"Vehicle Data Integration" section to the README naming the j1939
+ NMEA 2000 cohorts as integrator-developer surfaces. No SDK source
changes; example-only release.

## 0.10.0 — 2026-05-05 — DriverState-axis scaffolding (#28+#29+#30)

Adds three additive opt-in inputs to the existing trait/state
`DriverContext` architecture (Regan-Hallett-Gordon 2011, PMC4001671)
as Wave 1 sub-bundle 2 NSC scaffolding for the #23 DriverState
complete-class graduation: time-of-day circadian-phase classification
(#28), driving-session-state with consecutive-day + cumulative-fatigue
classification (#29), and self-assessed-confidence with
cap-override-with-confirmation pattern (#30). All three compose into
the existing `forDriverContext` factory as caution-adding adjustments
applied AFTER the trait baseline AND AFTER the live-context +
vehicle-class layering AND AFTER the state-delta.

### Added

- **`CircadianPhase`** — enum partitioning the 24-hour clock into six
  phases (`earlyMorning` 04–07 / `morning` 08–11 / `afternoon` 12–15
  / `evening` 16–19 / `night` 20–23 / `lateNight` 00–03) with a
  caution-adding multiplier in `[1.0, 1.5]` exposed via the
  `CircadianPhaseMultiplier.multiplier` extension. `morning` is the
  baseline (`1.0`); `lateNight` is the cap (`1.5`,
  circadian-trough). Helper `circadianPhaseFromHour(int)` maps a
  24-hour clock hour to the corresponding phase.
- **`SessionStateProvider`** — abstract interface returning
  `SessionState? get sessionState`. The integrator owns persistence
  (consecutive-day counter across trips, day-rollover semantics,
  opt-in scope) and the privacy-class boundary; the package consumes
  only the typed value at the factory call-site.
- **`SessionState`** — immutable value class carrying
  `consecutiveDrivingDays` (integrator-tracked raw counter) +
  `cumulativeFatigue` (integrator-derived `CumulativeFatigueClass`).
- **`CumulativeFatigueClass`** — enum (`rested` 0–2 / `mild` 3–4 /
  `accumulated` 5–6 / `severe` 7+) determining the
  threshold-adjustment magnitude.
- **`ConfidenceProvider`** — abstract interface returning
  `Confidence? get confidence` AND `bool get
  isHighConfidenceConfirmed`. The two signals together form the
  cap-override-with-confirmation pattern.
- **`Confidence`** — enum (`high` / `medium` / `low`).
- **`NavigationSafetyConfig.forDriverContext`** — four new optional
  named parameters: `vehicleOverrides` (re-surfaced from 0.9.0 so
  `forDriverContext` callers can compose vehicle-class through the
  state-axis factory), `circadianPhase`, `sessionState`,
  `confidence`, and `isHighConfidenceConfirmed` (default `false`).
- Re-exported from `package:navigation_safety_core/navigation_safety_core.dart`.

### Cap-override-with-confirmation pattern (#30; load-bearing)

The `Confidence` signal modulates the alerts-per-minute cap under a
pattern that preserves the **driver-always-drives invariant**:

- `Confidence.low` → automatically TIGHTENS the cap (caution-add
  direction; effective cap = `defaultCapFor(profile) × 0.75`, floored
  at `1.0` alerts/min).
- `Confidence.medium` → no-op (no cap modification).
- `Confidence.high` → does NOT auto-loosen the cap. Without explicit
  integrator-supplied confirmation
  (`isHighConfidenceConfirmed == false`), `Confidence.high` is
  treated as `Confidence.medium` (no cap modification). The system
  never auto-relaxes the safety cap from a high-confidence reading
  alone; the driver must affirmatively confirm via an
  integrator-supplied confirmation surface (e.g. an explicit toggle).
  When `isHighConfidenceConfirmed == true`, the cap loosens by 25%
  (`defaultCapFor(profile) × 1.25`).

### UNVERIFIED-magnitude flags

All three input magnitudes are **design-default hypotheses** pending
field-measurement validation, flagged verbatim per the kei-car-cohort
precedent (CHANGELOG.md 0.9.0 entry):

- **`CircadianPhase` multipliers** (`earlyMorning` 1.2 / `morning`
  1.0 / `afternoon` 1.1 / `evening` 1.05 / `night` 1.3 / `lateNight`
  1.5). Phase boundaries follow standard four-hour-block
  partitioning used in driver-fatigue reporting; multiplier values
  qualitatively-anchored in chronobiology (sleep inertia post-wake,
  post-lunch dip, evening fatigue accumulation, circadian-low at
  night-into-late-night, circadian-trough 00–03) but not yet
  field-calibrated to a population study mapping
  hour-of-day → effective-RT-multiplier specifically. See
  `KNOWN_LIMITATIONS.md` (DriverState-scaffolding section, 0.10.0).
- **`CumulativeFatigueClass` day-thresholds** (`rested` 0–2 / `mild`
  3–4 / `accumulated` 5–6 / `severe` 7+) AND per-class visibility
  lifts (`mild` +25m / `accumulated` +50m / `severe` +100m). Both
  the day-bucket boundaries and the visibility-lift magnitudes are
  design-default hypotheses pending fleet-class field measurement.
- **`Confidence` cap modifiers** (low: -25%; high-confirmed: +25%).
  The 25% magnitude is engineering judgement; per-population
  calibration of the optimal cap-tighten ratio for low-confidence
  drivers is deferred.

### Why this exists

The trait + state separation per Regan-Hallett-Gordon 2011
(PMC4001671) maps onto a richer state-axis surface than the four
`DriverState` enum values alone. Three additional state-axis inputs
were surfaced as Wave 1 sub-bundle 2 scaffolding for the #23
DriverState complete-class graduation: time-of-day (circadian phase
shapes baseline alertness regardless of trait or live state), session
history (cumulative fatigue compounds across days even when the
driver self-reports as alert today), and self-assessed confidence
(the driver's own read on their current capability is information
the integrator has access to that the package does not). All three
are advisory inputs the integrator wires when the signal is
available; the per-profile + live-context + vehicle-class baseline
remains the operational floor.

### Discipline

- **Caution-add-only invariant preserved.** Circadian-phase + session
  -state adjustments may make warning thresholds fire EARLIER than
  the per-profile baseline + live-context + state-delta floor;
  NEVER later. The factory enforces the multiplier `>= 1.0` floor
  (circadian) and the lift `>= 0` floor (session-state) at runtime
  via debug-mode assertions in `forDriverContext`. Confidence cap
  modification is the ONLY exception to the warn-thresholds-only-add
  -caution rule and applies only to the alerts-per-minute cap; the
  cap-loosen direction is gated by the confirmation flag.
  Negative-test coverage in
  `test/circadian_phase_test.dart`,
  `test/session_state_provider_test.dart`,
  `test/confidence_provider_test.dart`, and
  `test/navigation_safety_config_driver_state_inputs_test.dart`
  confirms the assertions fire on relaxing inputs.
- **Severity-not-profile invariant preserved.** All three inputs
  tune warning TIMING + alert DENSITY only. They do NOT modify the
  score-floor tiers (`safeScoreFloor` / `infoScoreFloor` /
  `warningScoreFloor`), the critical thresholds, or the
  critical-bypass behaviour (`AlertSeverity.critical` always fires
  regardless of cap).
- **Driver-always-drives invariant preserved.** All three
  providers (`SessionStateProvider`, `ConfidenceProvider`) AND the
  `CircadianPhase` enum are advisory inputs; they do NOT actuate the
  vehicle, do NOT close any control loop, do NOT modulate alert
  severity. The cap-override-with-confirmation pattern explicitly
  encodes this invariant for #30: the system never auto-relaxes the
  safety cap from a high-confidence reading alone; the driver must
  affirmatively confirm. Runtime debug-assertion in
  `forDriverContext` catches any divergence.
- **Backward compatible.** Existing 0.9.x callers see no behaviour
  change. `forDriverContext` without the four new optional
  parameters produces identical output to the 0.9.x signature.
  No naming collision with sibling-package types (verified via
  `flutter analyze` from monorepo root); no breaking change to
  `forProfile` / `forProfileWithContext` / `forDriverContext`
  signatures (additive named parameters only).

### Tests

- New tests across four files:
  - `test/circadian_phase_test.dart` — multiplier bounds (every
    phase `>= 1.0`); `lateNight` = 1.5 cap; baseline `morning` =
    1.0; `circadianPhaseFromHour` mapping coverage; `RangeError` on
    out-of-range hour.
  - `test/session_state_provider_test.dart` — interface contract;
    null-fallback (provider returns null → no effect); `SessionState`
    equality + props; exhaustive `CumulativeFatigueClass` lift
    coverage.
  - `test/confidence_provider_test.dart` — interface; `.low`
    tightens cap; `.medium` no-op; `.high` without confirmation =
    no-op (defaults to `medium`); `.high` WITH confirmation loosens
    cap; cap floor at `1.0` alerts/min.
  - `test/navigation_safety_config_driver_state_inputs_test.dart`
    — cross-feature integration: all three inputs at once +
    caution-add-only invariant verification + composition with
    existing `DrivingContext` + `vehicleOverrides`.

Total NSC test count: 253 → 285.

## 0.9.0 — 2026-05-05 — vehicle-class threshold-override surface

Adds an integrator-supplied vehicle-class signal path through the
existing context-aware threshold-config factory. The threshold floor
for a known under-served cohort (kei-car driven by the over-65
rural-Japan demographic) can now be sharpened without changing alert
severity, alert ordering, or the existing per-profile baselines that
today's integrators already depend on.

### Added

- **`VehicleClassProvider`** — abstract interface with a single
  getter `String? get vehicleClassToken`. The integrator implements
  this to surface a stable token (e.g. `'kei-car'`,
  `'compact-sedan'`, `'4wd'`, `'commercial-light'`). The package
  does not prescribe a vehicle-class taxonomy at the type system
  level; the integrator picks the tokens that best describe the
  vehicle population they serve. Tokens are advisory strings, NOT
  control inputs.
- **`VehicleThresholdOverrides`** — value class wrapping a
  `Map<String, NavigationSafetyConfig Function(NavigationSafetyConfig baseline)>`.
  The integrator registers caution-adding-only transforms keyed by
  vehicle-class token. The factory enforces the caution-add-only +
  severity-not-profile invariants at runtime via debug-mode
  assertions in `applyOverrideForToken`. A
  `VehicleThresholdOverrides.withKeiCarDefault()` factory ships the
  built-in kei-car override.
- **`DrivingContext.vehicleClassToken`** — new optional field on the
  existing `DrivingContext` value-object. `null` (the default) means
  no vehicle-class signal; thresholds fall back to the per-profile
  baseline. Composes independently with the existing `speedMps` /
  `humidityRH` / `timeSincePrecipitation` / `ambientTempCelsius`
  fields.
- **`NavigationSafetyConfig.forProfileWithContext`** — new optional
  named parameter `vehicleOverrides`. When supplied AND
  `context.vehicleClassToken` is non-null AND the token matches a
  registered key, the registered transform applies AFTER the
  per-profile baseline AND AFTER the live-context adjustments.
- Re-exported from `package:navigation_safety_core/navigation_safety_core.dart`.

### Built-in kei-car override

`VehicleThresholdOverrides.withKeiCarDefault()` ships the built-in
`'kei-car'` token override. The deltas:

- `warningVisibilityMeters` += 50m (kei-car windscreen + headlight
  cluster smaller than compact-sedan baseline; warn earlier on
  visibility loss to preserve reaction-margin).
- `warningTemperatureCelsius` += 1°C (kei-car cabin lower thermal
  mass + faster glass condensation in winter; warn earlier on
  cold-temperature transitions).

**UNVERIFIED-magnitude flag**: these deltas are **design-default
hypotheses** pending field-measurement validation. Kei-car-specific
visibility and thermal-mass calibration is not yet anchored in
published literature at the vehicle-class layer specifically; the
deltas compose qualitatively-known kei-car geometry and thermal mass
with the existing literature-anchored
`forProfile(DriverProfile.ageingRural)` reaction-time baseline
(PubMed 16313881 + downstream). A kei-car-class
calibration-validation follow-up is queued; integrators running
fleet-class telemetry are encouraged to surface deviations from the
design-default through the existing `LoomFitTelemetry` emit-only
stream.

### Why this exists

The kei-car-driven-by-over-65 cohort composes two known under-served
dimensions: a smaller-windscreen vehicle class commonly driven in
Hokkaido and Tohoku rural areas where snow-zone visibility loss is
the load-bearing safety question, AND an over-65 driver with the
slower hazard-perception reaction time the existing
`DriverProfile.ageingRural` calibration already encodes. The
per-profile baseline alone does not see the vehicle dimension; the
live-context adjustments (speed / humidity / precipitation) do not
either. This release adds the third dimension as an opt-in surface
the integrator wires when they have the signal, with the existing
caution-add-only invariant preserved as the operational floor.

### Discipline

- **Caution-add-only invariant preserved.** Vehicle-class
  adjustments may make warning thresholds fire EARLIER than the
  per-profile baseline + live-context floor; NEVER later. The
  factory enforces this at runtime via debug-mode assertions in
  `VehicleThresholdOverrides.applyOverrideForToken`. Negative-test
  coverage in `test/vehicle_threshold_overrides_test.dart` confirms
  the assertions fire on relaxing transforms.
- **Severity-not-profile invariant preserved.** Vehicle-class tunes
  TIMING (warn-earlier-floors) only; it does NOT modify the
  score-floor tiers (`safeScoreFloor` / `infoScoreFloor` /
  `warningScoreFloor`), the critical thresholds, or the
  alerts-per-minute cap override. Score-floor preservation is
  asserted at runtime in the same `applyOverrideForToken` enforcer.
- **Driver-always-drives invariant preserved.** `VehicleClassProvider`
  returns advisory tokens consumed for threshold tuning. It does NOT
  actuate the vehicle, NOT close any control loop, NOT modulate
  alert severity. The driver retains full control authority.
- **Backward compatible.** Existing 0.8.x callers see no behaviour
  change. `forProfileWithContext` without `vehicleOverrides`
  produces identical output. `DrivingContext` with the new
  `vehicleClassToken: null` default produces identical equality +
  hash + `toString` output for callers that did not set the field.
  No naming collision with the existing `VehicleClass` enum in
  `package:driving_consent/src/instrumentation_event.dart`
  (driving_consent 0.4.1): `VehicleClassProvider` is a different
  name and serves a different role (NSC threshold-tuning advisory
  vs. driving_consent instrumentation-event payload).

### Tests

- 32 new tests across four files:
  - `test/vehicle_class_provider_test.dart` (4 tests) — interface
    contract + null-token-falls-back-to-baseline + arbitrary-token
    no-taxonomy-enforcement.
  - `test/vehicle_threshold_overrides_test.dart` (12 tests) —
    registry construction + null/unknown-token fall-back + kei-car
    default delta-shape + score-floor preservation + critical-tier
    preservation + caution-add-only assertion negative tests
    (visibility-relaxing + temperature-relaxing + score-floor-modifying
    + caution-equal-permitted).
  - `test/navigation_safety_config_vehicle_class_test.dart` (9 tests)
    — `forProfileWithContext` composition with `vehicleOverrides` +
    null-vehicle-overrides + null-token + unknown-token + kei-car
    composition with humidity-driven temperature lift + score-floor
    + critical-tier preservation + null-context edge + all-six-profile
    smoke.
  - `test/driving_context_vehicle_class_test.dart` (7 tests) — value
    class equality + props + `toString` + null-as-absent across all
    five fields.

Total NSC test count: 221 → 253.

## 0.8.0 — 2026-05-04 — emit-only telemetry stream for alert-firing observations

Adds `LoomFitTelemetry` — a Pure Dart, emit-only broadcast stream of
`LoomFitTelemetryRecord` observations covering the four disjoint
outcome classes (`fired` / `droppedByThrottle` / `criticalBypass` /
`coldStart`) of `AlertDensityThrottle.shouldFire` decisions. The
class is the package-boundary surface for the calibration loop that
asks *did the loom fit each driver-class?* — the package observes
its own firing decisions and surfaces them on a broadcast stream;
the consuming application's analytics layer owns classification
logic, the privacy-class boundary, and the threshold for "the loom
does not fit this driver-class."

### Added

- **`LoomFitTelemetry`** — broadcast stream of telemetry records;
  emit-only at the package boundary. Methods:
  - `records` — `Stream<LoomFitTelemetryRecord>` (broadcast).
  - `record(LoomFitTelemetryRecord r)` — emit a single record.
  - `dispose()` — close the stream; idempotent.
- **`LoomFitTelemetryRecord`** — immutable value-object carrying:
  - `profileClass` (`DriverProfile`)
  - `ambientThreshold` (nullable `String` identifier, e.g.
    `"icy_road_30km"`)
  - `alertSequence` (`List<DateTime>`; defensively unmodifiable)
  - `responseLatency` (nullable `Duration`)
  - `outcome` (`LoomFitOutcome`)
- **`LoomFitOutcome`** enum: `fired`, `droppedByThrottle`,
  `criticalBypass`, `coldStart`. Disjoint and exhaustive over
  `shouldFire` decisions.
- Re-exported from `package:navigation_safety_core/navigation_safety_core.dart`
  + the `lib/src/looms.dart` runtime-loom barrel.

### Why this exists

The throttle's per-profile cap defaults are literature-anchored
DEFAULTS, not population-validated. To know whether a per-profile
cap actually fits the driver-class it is nominally tuned for, the
consuming application needs to observe firing decisions in
operation: drop-rate, critical-share, cold-start-share. Those are
calibration-class questions only the integrator has the data to
answer. `LoomFitTelemetry` is the package-boundary surface for
those observations.

Anchors:
- Medical alarm-fatigue scoping review
  ([PMC12181921](https://pmc.ncbi.nlm.nih.gov/articles/PMC12181921/))
  — calibration discipline for alert-density bounds.
- AAA-FTS ADAS-exposure / driver-workload report — per-profile
  overwhelm differentials.
- Bian et al [PubMed 38669900](https://pubmed.ncbi.nlm.nih.gov/38669900/)
  — alert-magnitude × duration as one product; format-mismatch
  erases earlier-alert benefit.

### Discipline

- **Emit-only.** No detection logic, no policy enaction, no
  classification — those live in the integrator's analytics layer.
- **No driver-grading.** The schema names the OUTCOME of the loom,
  not the DRIVER. `responseLatency` (when supplied) is information
  about the loom's fit, not the driver's competence.
- **No data harvest.** An integrator that never subscribes incurs
  zero data-flow cost. The package ships no records anywhere by
  itself.
- **Pure Dart.** No Flutter dependency, no I/O, no platform
  channels.
- **Severity-not-profile invariant preserved.** The telemetry
  surface observes outcomes; it does not modulate severity-class.

### Tests

- 9 new tests in `test/loom_fit_telemetry_test.dart` covering:
  defensive copy of `alertSequence`; record + listen round-trip;
  multiple records arrive in order; broadcast stream allows
  multiple listeners; all four outcome enum values can be emitted;
  `dispose` closes the stream; `record` after dispose silently
  no-ops; `dispose` is idempotent; record with null
  `ambientThreshold` + null `responseLatency` works.

### Unchanged (back-compat)

- All 0.7.x / 0.6.x / 0.5.x / 0.4.x surface unchanged. The new
  class is purely additive; existing `AlertDensityThrottle` and
  `AlertExplainer` callers see no behaviour change.

## 0.7.1 — 2026-05-05 — SLUSH added to per-profile high-risk subset

Adds `SLUSH` (シャーベット) to the per-profile speak-string override
set in `RoadSurfaceConditionGlossary.forConditionAndProfile()`. The
high-risk subset now covers ICE / SNOW / WET_ICE / SLUSH; the lateral-
slip risk of partially-melted snow is documented by JAF guidance
materials as a distinct skid-class hazard, and drivers unfamiliar with
snow-zone road state underestimate it.

### Added

- Per-profile SLUSH speak-string overrides for all six profiles:
  - `ageingRural` — full kanji-native phrasing with brief action cue.
  - `snowZoneExperienced` — terse single-token (`シャーベット`).
  - `professional` — terse single-token (`シャーベット`).
  - `agriculturalForestry` — terse formal label (`シャーベット路面`).
  - `noviceUrban` — explicit hazard wording (slip-class warning).
  - `foreignTouristSnowZone` — simplified JA + EN-default
    (`Slush on road, slippery`).

### Tests

- 4 new tests in `test/road_surface_condition_test.dart` covering the
  four SLUSH per-profile classes (ageingRural action-cue;
  snowZoneExperienced + professional terse single-token; noviceUrban
  explicit-hazard wording; foreignTouristSnowZone EN-default policy).
  Existing exhaustive (profile × condition) coverage test continues
  to pass.

### Substrate anchor

- VSS PR #892 (canonical road-surface allowed-value set, includes
  SLUSH).
- JAF / MLIT / NEXCO / Yahoo!カーナビ public driver-guidance
  vocabulary (slush as distinct skid-class hazard).

### Discipline

- **Additive only.** No existing speak-string mapping changed; SLUSH
  was previously a fall-through to defaults; it now resolves through
  the per-profile override path. PATCH bump (0.7.0 → 0.7.1) reflects
  the additive vocab-map expansion with no API breakage.
- **Severity-not-profile invariant preserved.** The per-profile
  speak-string overrides shape rendering vocabulary; severity-class
  gating remains upstream at the `AlertSeverity` boundary.

### Unchanged (back-compat)

- API surface unchanged (no new public functions).
- 0.7.0 / 0.6.0 / 0.5.0 / 0.4.x callers see no behavior change for
  ICE / SNOW / WET_ICE; SLUSH callers previously got the default
  glossary entry, now get a profile-tuned one (additive enrichment).

## 0.7.0 — 2026-05-04 — UX differentiation hook activated

Activates the previously-stub `assertUxDifferentiated()` runtime hook
into a working registration-and-assertion mechanism. Closes the first
concrete operationalization of the package's architectural anchor:
*"the threshold layer is necessary but not sufficient for an alert
that arrives in time + makes sense + is calm enough to ignore safely;
the per-profile UX-differentiation layer is the second half."*

### Added

- **`registerUxDifferentiator(profile, tag)`** — consuming Flutter
  packages (`voice_guidance`, `navigation_safety`) call this at
  app-bootstrap time to record that they have wired profile-aware
  behavior for `profile` under a descriptive `tag`. Idempotent on
  `(profile, tag)` pairs; accumulates distinct tags per profile.
- **`registeredUxDifferentiators(profile)`** — returns the unmodifiable
  set of tags registered for `profile`. Empty set means no
  UX-differentiator is registered.
- **`debugClearUxDifferentiatorRegistry()`** — test-only helper for
  isolating cases.

### Changed

- **`assertUxDifferentiated(profile)`** is no longer a no-op stub. In
  a debug build, an unregistered profile throws an `AssertionError`
  with an actionable message naming the profile + naming where to
  register + citing the published evidence anchors (Bian et al PubMed
  38669900 / Strayer-AAA PMC7283540). In a release build, the
  assertion is erased — production driver-facing builds never crash on
  a misconfigured profile; the gap surfaces during integration
  testing.

### Tests

- 11 new tests in `test/ux_differentiation_test.dart` covering
  empty-registry behavior, single-profile registration, idempotency,
  multi-tag accumulation, unmodifiable-view discipline,
  AssertionError throw on unregistered profile, AssertionError
  message-content discipline (profile name + registration site +
  evidence anchors), and pass/fail isolation between profiles in the
  same registry run.

### Unchanged (back-compat)

- All 0.6.0 / 0.5.0 / 0.4.x surface unchanged. Existing call-sites
  that called the no-op stub continue to compile and run; in a debug
  build they now throw if no differentiator has been registered for
  the profile in question — the desired behavior, since a silent
  no-op gave integrators no signal that the architectural intent was
  being missed.

## 0.6.0 — 2026-04-30 — trait/state spike (NOT YET PUBLISHED)

Adds the trait/state matrix per Regan-Hallett-Gordon 2011 (PMC4001671)
as an additive, opt-in axis. Existing 0.5.0 callers see no behaviour
change; state-axis tuning is opt-in via the new factory only.

This is a **spike**: state-effect magnitudes are intentionally small
and flagged UNVERIFIED in `KNOWN_LIMITATIONS.md` (state-axis section).
The shape of the API is the load-bearing piece; magnitudes pending
state-axis literature anchoring.

### Added

- **`DriverState`** — enum with four values: `alert`, `fatigued`,
  `distracted`, `impairedVisibility`. Live (transient) axis,
  orthogonal to `DriverProfile` (trait).
- **`DriverContext`** — immutable value-object coupling a
  `DriverProfile` (trait) with a `DriverState` (state). Constructible
  via the default constructor or the named factory
  `DriverContext.combineWith(profile:, state:)`. Includes
  `withState(newState)` for mid-trip state updates without losing
  the trait.
- **`NavigationSafetyConfig.forDriverContext(context, {environmentalContext})`**
  — new factory tuning thresholds to both the trait baseline and the
  state-axis delta. Optionally composes with the v0.5.0
  `DrivingContext`. Conservative-only: warns earlier than the
  per-profile baseline, never later.

### Unchanged (back-compat)

- `NavigationSafetyConfig.forProfile(profile)` — identical behaviour to 0.5.0.
- `NavigationSafetyConfig.forProfileWithContext(profile, context:)` — identical behaviour to 0.5.0.
- All other 0.5.0 surface unchanged.

## 0.5.0 — 2026-04-30

Adds an additive context-aware factory and a driving-context value
object so consuming apps can pass live conditions (speed, humidity,
precipitation history, ambient temperature) into the threshold-config
factory and receive thresholds tuned to both the per-profile baseline
and the live conditions.

### Added

- **`DrivingContext`** — immutable value-object with four optional
  fields: `speedMps`, `humidityRH`, `timeSincePrecipitation`,
  `ambientTempCelsius`. Each field is optional; a null field means
  "context not available; fall back to the non-context baseline".
  Const-constructible and equatable.
- **`NavigationSafetyConfig.forProfileWithContext(profile, context: ...)`** —
  new factory alongside the existing `forProfile()`. When context is
  null, delegates to `forProfile(profile)` for backwards-compat. When
  context fields are non-null, adjusts the relevant thresholds:
  - Speed → warning visibility floor raises to fit reaction time +
    braking distance via standard kinematics.
  - Humidity + ambient → warning temperature raises to cover
    dew-point-driven black-ice risk via the Magnus formula.
  - Precipitation history → warning visibility raises by a residual
    surface-moisture margin via exponential decay (default half-life
    90 minutes; conservative).
- **`lib/src/calibration/` directory** with three formula modules:
  - `speed_dependent_visibility.dart` — speed + reaction time +
    braking deceleration → required visibility.
  - `humidity_dependent_temperature.dart` — Magnus formula for
    dew-point-based effective road-surface temperature.
  - `precipitation_history_decay.dart` — exponential surface-moisture
    decay with overridable half-life.

### Why this exists

Per-profile baseline thresholds tuned for typical commute conditions
can leave no margin at higher speeds, dry-air black-ice mornings, or
residual-wet-surface windows. Adding a context-aware factory lets a
consuming app raise the threshold floor when live conditions warrant
without changing the per-profile baseline used by apps that lack the
sensor inputs. The factory is additive: the existing `forProfile()`
factory and every existing call site behave identically.

Citations for each formula are documented in the module headers:

- Reaction-time defaults — [PubMed 16313881](https://pubmed.ncbi.nlm.nih.gov/16313881/)
  (novice 3.58s vs experienced 1.32s); other per-profile RTs are
  reasonable defaults pending field validation (UNVERIFIED — see
  `KNOWN_LIMITATIONS.md`).
- Braking-distance — standard kinematics; default deceleration 5.5
  m/s² for typical dry pavement.
- Magnus formula — modern parameter constants `a = 17.625`,
  `b = 243.04°C` per Alduchov & Eskridge 1996; black-ice formation
  envelope per [Wikipedia black ice](https://en.wikipedia.org/wiki/Black_ice).
- Exponential surface-moisture decay — first-order-evaporation model;
  90-minute half-life default is conservative (UNVERIFIED for
  population values).

### Backwards-compatibility

Pure addition. Every existing API is unchanged. `forProfile()`
returns the same configuration as in 0.4.x. Existing call sites
continue to work without modification.

### Known limitations not closed in 0.5.0

- Four of the six per-profile reaction-time defaults are UNVERIFIED
  specific cites (anchors derived from surrounding literature; not
  population-validated).
- The 90-minute precipitation-decay half-life is a conservative
  default; integrating apps with telemetry should override.
- The dew-point-based effective temperature is a conservative
  estimate, not a measured road-surface temperature; real surface
  temperature depends on emissivity, cloud cover, surface material,
  and time-of-night.
- See `KNOWN_LIMITATIONS.md` for the full list inherited from earlier
  versions, plus the new "Driving-context formulas (added in 0.5.0)"
  section.

## 0.4.2 — 2026-04-29

Documents the package's driving-automation-regime applicability at the
package boundary so consumers can ground their integration decisions
in the documented scope. Documentation patch — no API surface change.

### Added

- **`README.md` "Scope: driving automation regimes" section** — plain
  declaration that this package targets SAE J3016 Level 0 / Level 1
  supportive use and explicitly does not provide L2+ handover-class
  supervision; standards-mapping summary one-liner; concrete consumer
  guidance on when the package's alerts are appropriate vs.
  insufficient; equal-dignity invariant pointer.
- **`KNOWN_LIMITATIONS.md` "Standards mapping (current advisory
  framing)" section** — full paragraphs on:
  - **ISO 26262**: current QM-likely framing at the application layer
    under advisory-only intent; integrator owns the final ASIL
    determination for their integration; evidence supporting the
    framing cited (advisory-mood wording discipline,
    `bypassForCritical` invariant, public-corpus speed references).
  - **SAE J3016**: L0/L1 supportive mapping; explicit non-claim on L2+;
    re-classification trigger named for any consuming app evolving
    toward L2+ pilots.
  - **JIS / JASO**: explicit not-mapped at this scope; qualified
    Japanese-domestic functional-safety partner consultation required
    before any IVI-vendor / OEM-pilot integration targeting the
    Japanese-domestic certification surface.
  - **Equal-dignity invariant**: alert visibility, severity ordering,
    and plane-allocation priority MUST be severity-driven, never
    profile-driven; profile-aware behaviour belongs in verbosity,
    locale, and density-cap surfaces, not in visibility / preemption /
    plane-allocation paths.

### Why this exists

The package's surfaces are increasingly being considered as substrates
for HMI integrations (display-server, hardware-overlay-plane, IVI
vendor pilots). Without an explicit driving-automation-regime
declaration at the package boundary, integrators can mis-frame the
package as a supervision-loop input or as L2+-handover-capable, which
would be a misuse of its documented scope. This release adds the
declaration so future integrators and future package-internal cycles
can ground their work in the same intent. The standards-mapping detail
in `KNOWN_LIMITATIONS.md` is sourced from an internal standards
review.

### Backwards-compatibility

Pure documentation patch. No existing API changed. No file under
`lib/` modified.

### Known limitations not closed in 0.4.2

- ISO 26262 ASIL classification at the integration boundary remains
  with the integrator and depends on their hazard analysis; this
  package does not certify any specific ASIL outcome.
- JIS / JASO conformance is not mapped at this scope. Vendor / OEM
  integration targeting Japanese-domestic certification requires a
  qualified domestic functional-safety partner.
- See `KNOWN_LIMITATIONS.md` for the full list inherited from earlier
  versions.

## 0.4.1 — 2026-04-28

Names and documents what 0.4.0 already shipped as runtime guards.
Documentation patch — no API surface change.

### Added

- **`lib/src/looms.dart`** — category barrel re-exporting
  `AlertDensityThrottle` and `AlertExplainer` with a class-level
  doc-comment naming them as runtime looms. Either of these imports
  surfaces the same symbols; the barrel adds the runtime-loom
  category framing:
  ```dart
  import 'package:navigation_safety_core/navigation_safety_core.dart';
  // or
  import 'package:navigation_safety_core/src/looms.dart';
  ```
- **`LOOMS.md`** at the package root — a catalog naming each runtime
  guard and the failure mode it catches.
- **Design-rationale doc-comments** on `AlertDensityThrottle` and
  `AlertExplainer` class declarations, recording the failure mode each
  guard prevents and the literature anchors behind its embedded
  magnitudes.

### Why this exists

`AlertDensityThrottle` and `AlertExplainer` shipped in 0.4.0 are
runtime guards — pure-Dart classes that catch documented failure modes
(alert fatigue, condition-without-action) at the package boundary
inside the consuming app's process. 0.4.1 names them as such, so the
convention is discoverable from this package's own surface. This is
documentation work; the runtime behavior is unchanged from 0.4.0.

### Backwards-compatibility

Pure documentation patch. No existing API changed. Existing imports
of `AlertDensityThrottle` and `AlertExplainer` via
`package:navigation_safety_core/navigation_safety_core.dart` continue
to work unchanged. The new `src/looms.dart` barrel is additive.

### Known limitations not closed in 0.4.1

- No runtime registry. The catalog does not auto-discover its
  members; integrating apps instantiate each guard explicitly.
- See `KNOWN_LIMITATIONS.md` for the full list inherited from 0.4.0
  and earlier.

## 0.4.0 — 2026-04-28

Adds two driver-facing surfaces that together address the documented
alert-fatigue and condition-without-action failure modes in consumer
ADAS / nav advisory layers.

### Added

- **`AlertDensityThrottle`** — per-profile rolling-window rate limiter
  for advisory alerts. Prevents desensitization on info / warning tiers
  while preserving credibility of `AlertSeverity.critical` (which
  bypasses the throttle as a documented invariant).
  - `AlertDensityThrottle.forProfile(profile)` — constructs a throttle
    with the literature-anchored per-profile cap.
  - `AlertDensityThrottle.defaultCapFor(profile)` — exposes the cap
    table for integration with `NavigationSafetyConfig`.
  - `shouldFire(now, severity)` — gating method; returns the firing
    decision and (on permit) records the timestamp.
  - `currentWindowCount(now)` — test-only inspection.
  - Per-profile cap defaults (alerts/min):
    - `professional` 4.0
    - `snowZoneExperienced` 3.0
    - `agriculturalForestry` 2.0
    - `noviceUrban` 1.5
    - `ageingRural` 1.2
    - `foreignTouristSnowZone` 1.0
- **`NavigationSafetyConfig.alertsPerMinuteCapOverride`** — optional
  field for integrating apps to override the per-profile default with
  measured per-population data. Helper:
  `effectiveAlertsPerMinuteCap(profile)` returns the override if set,
  the profile default otherwise.
- **`AlertExplainer`** — pairs a `RoadSurfaceCondition` with a
  pre-localized recommended action in the verbosity that fits the
  active `DriverProfile`.
  - `AlertExplainer.forConditionAndProfile(condition, profile)` —
    returns the AAA-designed (condition, action) tuple, the verbosity
    level, and the locale tag.
  - 36 high-action cells (6 profiles × 6 high-action conditions: WET,
    SNOW, ICE, SLUSH, WET_ICE, LOOSE_GRAVEL); UNKNOWN and DRY are
    profile-flat per design brief.
  - `VerbosityLevel` enum: `terse`, `brief`, `standard`, `full`.
  - Verbosity mapping per profile: professional → terse;
    snowZoneExperienced → brief; noviceUrban + agriculturalForestry →
    standard; ageingRural + foreignTouristSnowZone → full.
  - Locale: `en` for `foreignTouristSnowZone`; `ja` for others.

### Why this exists

- **Alert-density throttle**: alarm-fatigue is the documented failure
  mode for systems that fire too many alerts. The medical alarm-fatigue
  scoping review ([PMC12181921](https://pmc.ncbi.nlm.nih.gov/articles/PMC12181921/))
  finds >60% of alarms get no timely response and 85% of clinicians
  report overwhelm. The [AAA-FTS ADAS-exposure / driver-workload
  report](https://aaafoundation.org/wp-content/uploads/2023/09/202309-AAAFTS-ADAS-Exposure-and-Driver-Workload.pdf)
  extends the same pattern to consumer ADAS;
  [arxiv 2410.06388](https://arxiv.org/html/2410.06388) frames
  over-warning as a silent safety failure. Per-profile caps reflect
  reaction-time and overwhelm differentials documented in
  [PubMed 16313881](https://pubmed.ncbi.nlm.nih.gov/16313881/) (novice
  hazard-perception RT 3.58s vs experienced 1.32s),
  [PMC7283540](https://pmc.ncbi.nlm.nih.gov/articles/PMC7283540/)
  (older drivers cost +8s eyes-off-road on identical voice formats),
  and [PubMed 22664714](https://pubmed.ncbi.nlm.nih.gov/22664714/)
  (novice-fog crash-rate elevation).
- **Action-coupled explainer**: alerts that name a condition without
  the implied action degrade compliance. Medication-adherence
  literature ([PMID 34111571](https://pubmed.ncbi.nlm.nih.gov/34111571/))
  shows action-coupled instructions improve adherence over
  condition-only; CGM (continuous glucose monitor) alert-design
  literature (MDPI 2024 review of CGM UX patterns) finds the same in
  ambient-monitoring contexts. Driving translation: "icy road" is
  incomplete; "icy road → reduce speed to 30 km/h" is actionable.
  Per [PubMed 38669900](https://pubmed.ncbi.nlm.nih.gov/38669900/)
  (Bian), earlier triggering reduces collisions only when alerts
  persist long enough to be processed — coupling the action with the
  condition gives the driver the second the alert needs to land.

### Action-text discipline

- Action verbs are advisory (「以下に減速」 / "reduce" / "avoid" /
  "maintain"), not imperative-on-control. Speed numbers are published
  reference points (JAF / MLIT vocabulary), not system-enforced limits.
- "Stop in a safe place" is the strongest action; phrased "if
  possible" / 「可能であれば」 — no implication that the system stops
  the vehicle.
- No action string promises an outcome.

### Backwards-compatibility

Pure addition. No existing API changed. The default constructor
`NavigationSafetyConfig()` still produces the historical defaults
unchanged. New `alertsPerMinuteCapOverride` field defaults to `null`
(use the per-profile literature default).

### Known limitations not closed in 0.4.0

- Per-profile alert/min caps are literature-anchored DEFAULTS, not
  population-validated. Integrating apps with measured per-population
  data should override.
- `bypassForCritical` defaults to `true` and is a documented
  invariant. Changing this default would alter the package's safety
  contract.
- Action-string speed references (30 km/h / 20 km/h) are advisory,
  not system-enforced.
- See `KNOWN_LIMITATIONS.md` for the full list inherited from earlier
  versions.

## 0.3.1 — 2026-04-28

Surfaces road-surface condition vocabulary aligned to the upstream VSS
`Vehicle.Exterior.RoadSurfaceCondition` signal landing via
[COVESA/vehicle_signal_specification PR #892](https://github.com/COVESA/vehicle_signal_specification/pull/892).

### Added

- **`RoadSurfaceCondition`** — enum aligned to VSS allowed-value set
  (`UNKNOWN`, `DRY`, `WET`, `SNOW`, `ICE`, `SLUSH`, `WET_ICE`,
  `LOOSE_GRAVEL`). Round-trip helpers `vssValue` and `fromVss` preserve
  the upstream string vocabulary verbatim so consuming code can
  interoperate with VSS-derived telemetry without re-mapping.
- **`RoadSurfaceConditionGlossary`** — display labels and TTS-ready
  phrases per condition, with optional per-profile overrides for the
  high-risk subset (`ICE` / `SNOW` / `WET_ICE`):
  - `forCondition(c)` — profile-neutral default
  - `forConditionAndProfile(c, profile)` — applies per-profile
    speak-string variants where vocabulary precision matters
- Per-profile vocabulary discipline:
  - `ageingRural` — kanji-native (凍結, 圧雪) per generational
    recognition reliability
  - `snowZoneExperienced` / `professional` — terse single-word phrases
  - `noviceUrban` — condition + hazard tag for explicit risk framing
  - `agriculturalForestry` — condition + off-road consideration where
    relevant
  - `foreignTouristSnowZone` — English-default TTS + simplified
    Japanese (no kanji-only output; non-native readers cannot parse
    mid-drive)

### Why this exists

Documented Japanese snow-zone driver pain point (literature review):
no major nav app provides an in-app glossary for road-surface terms
(凍結 / 圧雪 / シャーベット / ブラックアイス / アイスバーン), each with
distinct safe-driving semantic. Drivers learn through accidents or
YouTube. Sources: [JAF snow-driving safety](https://jaf.org.jp/common/attention/snow),
[MLIT Hokkaido snow-road guide](https://www.hrr.mlit.go.jp/hokugi/yukinavi/),
[JARTIC](https://www.jartic.or.jp/), [Yahoo!カーナビ winter
guidance](https://note.com/yahoo_carnavi/n/n0ecdc7700eb0).

### Backwards-compatibility

Pure addition. No existing API changed. The glossary is informational
(display labels + TTS phrases); it does not actuate any vehicle
behavior and is not safety-critical in the control sense. Bare
glossary text is conservative — no specific km/h advice (speed advice
belongs to a separate action-coupled explainer surface, planned for
a future minor release).

### Known limitations not closed in 0.3.1

- ブラックアイス (black ice) is documented as a sub-class of `ICE`; the
  upstream VSS signal does not expose it as a separate enum value, so
  this package does not invent one.
- Glossary text is informational only. Speed advisories, action-coupled
  explanations, and alert-density throttling are separate surfaces
  planned for the next minor release.
- See `KNOWN_LIMITATIONS.md` for the full list inherited from 0.3.0.

## 0.3.0 — 2026-04-27

Closes the V100 gap surfaced by post-0.2.0 autoresearch: the previous
5-profile taxonomy mis-mapped foreign-tourists-in-snow-zone, and two
threshold magnitudes were calibrated by intuition rather than published
literature.

### Added

- **`DriverProfile.foreignTouristSnowZone`** — sixth profile, closes the
  Hokkaido-foreign-tourist class. Combines novice-equivalent
  unfamiliarity with local conditions + likely non-winterised rental
  vehicle + language-localization gaps in road signage. Most-conservative
  defaults across every dimension; previously mis-mapped to either
  `snowZoneExperienced` (catastrophically wrong) or `noviceUrban`
  (location-wrong).
- **`assertUxDifferentiated(profile)`** — advisory hook stub for
  consuming Flutter packages. No-op in 0.3.0; v0.4+ will fire a runtime
  advisory when a profile is selected but the consuming UX layer has
  not registered profile-aware differentiation. Forward-compatible:
  integration code can call it today; it activates when v0.4+ ships.
- **`KNOWN_LIMITATIONS.md`** — honest disclosure of remaining defects
  the 0.3.0 ship does not close, with citations to public sources.

### Changed (calibration corrections per literature)

- **`ageingRural` `infoTemperatureCelsius`**: 5°C → 4°C. The 0.2.0
  value combined with `infoVisibilityMeters` 1500m fired the info tier
  on most autumn evenings in Hokkaido / Tohoku — an alert-fatigue
  risk per [arxiv 2410.06388](https://arxiv.org/html/2410.06388) +
  [AAA-FTS ADAS-exposure report](https://aaafoundation.org/wp-content/uploads/2023/09/202309-AAAFTS-ADAS-Exposure-and-Driver-Workload.pdf).
  Lowered to preserve information-tier signal without firing on
  routine cold autumn evenings.
- **`ageingRural` `warningTemperatureCelsius`**: 1°C → 2°C. Black ice
  forms with road-surface ≤0°C even when ambient air is several
  degrees warmer ([Wikipedia black ice](https://en.wikipedia.org/wiki/Black_ice)).
  1°C left no margin above the formation envelope. Raised for
  meaningful margin.
- **`noviceUrban` `warningVisibilityMeters`**: 250m → 320m. Novice
  hazard-perception RT is 3.58s vs 1.32s experienced
  ([PubMed 16313881](https://pubmed.ncbi.nlm.nih.gov/16313881/)); at
  60 km/h that's ~37m additional reaction-distance from RT alone, so
  +50m over standard left no braking margin. 320m gives RT-margin +
  braking margin per
  [Konstantopoulos PubMed 22664714](https://pubmed.ncbi.nlm.nih.gov/22664714/).

### Backwards-compatibility

Default constructor `NavigationSafetyConfig()` is unchanged. All five
0.2.0 profiles still exist and still resolve via `forProfile()`. Only
the *magnitudes* for `ageingRural` (two thresholds) and `noviceUrban`
(one threshold) shift; direction of every shift is preserved.

### Known limitations not closed in 0.3.0

See `KNOWN_LIMITATIONS.md`. Notably: sensory-disability axis,
trait/state separation (Regan-Hallett-Gordon 2011), frailty-vs-robust
split inside `ageingRural`, and the wrong-dimensions concern (UFOV /
glance-budget govern crash risk more strongly than score floors do —
both require coordination with consuming Flutter packages and are
deferred).

## 0.2.0 — 2026-04-27

Added `DriverProfile` enum + `NavigationSafetyConfig.forProfile()` factory
constructor for per-driver-class threshold defaults.

Five profiles in v1, each tuned to a coherent point in the cognitive-load /
experience / role / vehicle-type space:

- `DriverProfile.ageingRural` — older drivers (typically 65+) who may be
  commuting in rural areas; often novice with EV or modern ADAS-equipped
  vehicles. More conservative thresholds (warn earlier on weather +
  visibility; higher score floor for "safe" classification).
- `DriverProfile.snowZoneExperienced` — drivers experienced with
  snow-zone commute conditions. Standard thresholds (the historical
  default profile equivalent).
- `DriverProfile.noviceUrban` — newly-licensed or low-mileage drivers
  (typically first 3 years). Warn earlier on visibility; higher score
  floor; threshold-only shift (explainer-friendly UX surfaces are a
  downstream Flutter-package concern).
- `DriverProfile.professional` — commercial drivers (taxi, freight,
  delivery, rideshare). Standard thresholds; minimum-distraction UX
  optimization is a downstream concern.
- `DriverProfile.agriculturalForestry` — drivers operating off-road
  in agricultural or forestry contexts. Standard thresholds today;
  off-route-awareness semantic is a downstream extension.

Use:

```dart
final config = NavigationSafetyConfig.forProfile(DriverProfile.ageingRural);
```

Backwards-compatible: existing `NavigationSafetyConfig()` call sites
continue to work unchanged (returns the historical default profile
equivalent).

## 0.1.0 — 2026-04-27

Initial release.

Pure Dart core extracted from `navigation_safety` so non-Flutter
consumers (CLI tools, servers, test fixtures, pure-Dart packages
like `driving_conditions`) can depend on the safety-model vocabulary
without inheriting Flutter + flutter_bloc.

Exports:

- `AlertSeverity` (info / warning / critical; declaration order is load-bearing)
- `NavigationRoute`
- `NavigationSafetyConfig`
- `SafetyScenario`
- `SafetyScore`

The full `navigation_safety` Flutter package re-exports everything
here for back-compatibility.
