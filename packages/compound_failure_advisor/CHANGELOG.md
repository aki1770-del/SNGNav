# Changelog

## 0.1.2

Additive and non-breaking. No existing API changes, no behaviour changes, no
change to `adviseInDrive` or to any threshold; English remains the default. The
enums remain the API — if you already localize them yourself, nothing here is
imposed on you.

### Japanese safety-word strength — corrected (read this if you render ja)

Two ja strings were materially WEAKER than the English they translate. A
mis-calibrated Japanese safety word is worse than English: the driver reads it,
believes she has understood, and under-reacts.

- **`DriveAction.considerStopping` said 休憩 — the FATIGUE word.** In Japanese
  driving usage 休憩 is the coffee/rest-stop word (休憩所, 2時間ごとに休憩); it
  does NOT carry "get off this road, conditions are dangerous". It also
  contradicted this package's own `actionLabel` for the same enum value, which
  correctly says **停車**. A driver in a whiteout told 「休憩するという選択肢も
  あります」 hears an optional comfort break, not a safety escalation — and this
  is the CEILING rung, the strongest thing this package may say. It now reads
  「安全に行える場合は、安全な場所に**停車**するという選択肢もあります。判断は
  あなたが行ってください。」 Still an invitation she owns; never a command.
  (The English was tightened to match the label's weight: "whenever you want
  one" drained the ceiling rung of urgency.)
- **`CautionReason.severeAdvisory` under-named the top band.** That reason covers
  BOTH `AdvisoryLevel.severe` and `AdvisoryLevel.extreme`, and in Japan 警報
  (warning) and **特別警報** (emergency warning — the once-in-decades band, a
  real thing in Akita snow) are distinct terms of art. Rendering both as a bare
  警報 lets a driver under-react while a 大雪特別警報 is in force. The band word
  now admits the top: 「この地域に重大な気象警報（特別警報を含む場合があります）
  が発表されています。」

  This is a stopgap, and it is named as one: the honest fix is to split
  `CautionReason.extremeAdvisory` out of `severeAdvisory` (the advisor already
  holds `AdvisoryLevel.extreme` at the call site). That is a breaking enum change
  and is deliberately NOT smuggled into a patch release.

Both strings are now pinned by tests that assert their STRENGTH, not merely the
absence of a command — so a future edit cannot quietly soften the ceiling rung
again.

- feat: `DriveAdviceMessages` — driver-facing text for the whole advisory
  vocabulary (`DriveAction`, `CautionReason`, `Unknown`, the compounding note,
  and the sight-stopping-speed hint), in **English and Japanese**. Resolve with
  `DriveAdviceMessages.forLanguage('ja')`; unsupported languages fall back to
  English, never to silence.
- **Why.** `Unknown`'s own dartdoc said these were "an enum, not prose, so the
  integrator localizes for HER Japanese mother." That was right, and it left
  every integrator hand-rolling the hardest strings in the catalog, alone, in a
  language most of them do not read. The wording of a caution at the wheel in a
  whiteout is not boilerplate to invent under deadline: get one verb wrong and
  the package that structurally REFUSES to tell her to turn back suddenly tells
  her to turn back. This release ships the default wording with the package's
  discipline already baked in.
- **The wording discipline is enforced by tests, not by good intentions:**
  - `continueDriving` is the ABSENCE of a raised concern and never an assertion
    of safety — it says so out loud
    (「これは路面が安全であることを示すものではありません」).
  - The ceiling `considerStopping` is an invitation she owns
    (「選択肢もあります。判断はあなたが行ってください」), never 「停車してください」,
    and no string in any locale may contain turn-back / abort language.
  - An unknown is never rendered as clear: 「視界の観測データがありません。視界が良い
    という意味ではなく、データ自体がないという意味です。」
  - 警報 (warning, severe/extreme) and 注意報 (advisory, moderate) are JMA terms of
    art and are pinned to their correct severities — swapping them would either
    cry wolf or under-warn a real severe advisory, a defect invisible to an
    English-reading reviewer.
  - Measured numbers pass through verbatim; the sight-stopping hint states it is
    a guide and not a guarantee of a safe speed.
- No new i18n mechanism: the hand-rolled locale-table idiom already used by
  `pretrip_decision_advisor`'s `PretripMessages`. Pure Dart — the zero-runtime-
  dependency / 32-bit-ARM contract is untouched.
- test: exhaustive coverage guards (every `DriveAction` / `CautionReason` /
  `Unknown` has text in every carried locale, so a future enum value cannot ship
  as a blank caution); a Latin-residue guard that fails if untranslated English
  leaks into a Japanese safety string; and an end-to-end render of a real
  compound-failure moment (position lost + whiteout + severe advisory).

## 0.1.1

- **Tests only — the `lib/` is byte-identical to the published 0.1.0** (verified
  by diff against the pub.dev 0.1.0 archive); this release adds regression
  coverage and changes no production behaviour. (The behaviour bullets that an
  earlier draft of this entry listed under 0.1.1 in fact shipped in 0.1.0 and are
  re-attributed there below — they were not new in 0.1.1.)
- Added regression guards on every threshold and the two safety-critical
  invariants of this D3-worst-case advisor, so a future relaxing tweak fails
  loudly: (a) exact band-boundary tests pinning each `k*` edge inclusive/exclusive
  (visibility 1000/999, 500/499, 200/199 m; freshness 300 s; suspect/degraded
  radius 150 m; stale-fix 60 s; fast-speed 13.4 m/s); (b) an **exhaustive
  non-deterrence** sweep over the full input space including `null`/NaN/±infinity/
  out-of-range values (211,200 combinations) asserting NO input ever produces an
  action beyond `considerStopping` — the package is structurally incapable of
  telling her to turn back; (c) an **exhaustive no-under-warn** sweep asserting
  every KNOWN position-concern ≥ 2 paired with a KNOWN visibility-concern ≥ 2
  reaches `considerStopping` AND sets `compounding` (the D3 stacked-danger core
  never stays calm); (d) a pin on the deliberate under-confirmation boundary
  (degraded position + UNKNOWN/STALE visibility holds at `heightenedCaution`,
  surfacing both uncertainties, never over-warning a whiteout it cannot confirm);
  (e) a speed-axis monotonicity guard; and a constants-pinned test that catches
  any relaxation of the calibration values.

## 0.1.0

Initial release.

- `adviseInDrive(DriveSituation) -> DriveAdvice`: one total, deterministic,
  synchronous pure function that fuses position-trust × visibility (with
  advisory severity + speed as escalators) into a single honest, immutable
  in-drive caution record.
- The load-bearing **compounding** rule: an uncertain position AND low
  visibility *together* yields the strongest caution (`considerStopping`) and
  sets `compounding == true` — worse than either alone.
- Three-rung action ladder (`continueDriving` / `heightenedCaution` /
  `considerStopping`). Structurally **no** turn-back / abort / do-not-drive
  rung — the package cannot deter a needed trip.
- Every raised action carries a statable WHY: each escalated action has a
  non-empty `reasons` set. The mild single-axis bands each emit one reason —
  `reducedVisibility` (~500–1000 m, milder counterpart to `lowVisibility`) and
  `moderateAdvisory` (the moderate level, milder counterpart to `severeAdvisory`)
  — and each axis emits exactly one reason (mild XOR hard, never double-counted).
- Sight-stopping hint calibrated to the worst-credible winter surface: it assumes
  glare/black-ice grip (`kWinterDecelMps2` 1.0 m/s²) and a winter see-then-react
  time (`kReactionTimeSeconds` 2.5 s), plans to stop within HALF the visible
  distance, and is capped at a winter ceiling (`kSightHintCeilingMps`, ~48 km/h).
  It is surfaced ONLY in the low/whiteout band (`null` in the clear/reduced
  bands), so it can never emit an "all-clear-ish" figure that overstates the
  speed at which she could actually stop on ice.
- First-class unknowns: `null`/NaN/stale visibility (including a reading whose
  age is `null`), missing position, and unknown speed surface as explicit
  `Unknown` values and distinct `CautionReason`s, held at a non-zero caution
  floor and never coerced to "clear".
- `suspect` position tracks its confidence radius and fix-staleness: a suspect
  dot at neighbourhood scale, or with no trusted fix for a long blind period,
  bumps from concern 1 → 2 (matching `degraded`); a small/fresh suspect fix is
  unchanged.
- Mirror enums (`PositionTrust`, `AdvisoryLevel`) restated locally so the
  package carries zero runtime dependencies and the integrator maps across the
  `localization_fallback` / `condition_aggregator` / `pretrip_source_*` seams
  with one switch per axis.
- Pure Dart, zero runtime dependencies, no Flutter, no IO, no clock,
  32-bit-ARM friendly.
