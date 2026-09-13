# release_guard_inventory.md

**Every `assert` under a published package's `lib/` is declared here, or CI is red.**
Checked by `scripts/release_guard_inventory.py`, which runs in `.github/workflows/ci.yml`
on every push. Prove it can fail: `python3 scripts/release_guard_inventory.py --self-test`.

## Why this file exists

Dart strips `assert` from AOT builds AND from plain `dart run`. Measured with a
compiled probe on Dart 3.11.1, 2026-09-13 -- not recalled:

| invocation | asserts |
|---|---|
| `dart test` / `flutter test` | **ON** |
| `dart run file.dart` | **OFF** |
| `dart compile exe` | **OFF** |
| `dart compile exe --enable-asserts` | ON |

So our test suite is the one place these guards exist. An edge developer who ships
our package, and one who merely scripts against it with `dart run`, both get a build
with none of them. On 2026-09-13 that was not theoretical: `DataBudget.relax` handed
an UNCONFIRMED caller the relaxation its own message called forbidden, and
`VehicleThresholdOverrides.applyOverrideForToken` accepted a vehicle-class override
that moved a score floor or made her warning fire LATER. Those invariants were not
merely unenforced in what shipped -- they were inverted. Neither was caught by a
test; the suites were green, because the suites run in the one mode where the
guards exist.

## What the classes mean

| class | meaning |
|---|---|
| `REFUSAL` | forbids a CALLER's request, before the act. Stripped, it PERMITS the forbidden thing. **Must be a real throw** -- so a row in this class is a FAILURE, by design. |
| `POST-CONDITION` | checks OUR OWN computed state, mid-drive. Throwing takes her navigation away at the moment it is already degraded. Stays an `assert`; the remedy is degrade-to-safe-verdict and report. |
| `CONST-CTOR` | an initializer-list `assert` in a `const` constructor. **Cannot** become a throw without dropping `const`, a breaking change for every consumer using it as a default value. Named as an unclosed gap, **not** as an exemption earned. |
| `DEBUG-BLOCK` | documented debug-only diagnostic, including the `assert(() {...}())` form. |
| `UNREVIEWED` | nobody has read its release semantics. **A true statement of debt, not a clearance.** Printed loudly on every run. |

The exemptions are therefore in a file a person reads, not inside a regex nobody
audits. A new `assert` in any shipped `lib/` fails until someone writes down why.

## Honest bounds of this instrument

- It does **not** judge which asserts are load-bearing. That judgement failed once
  already, the same day: a remedy prescribed as `if (v <= 0) throw` would have
  REGRESSED the code it replaced, because `double.nan <= 0` is false and the assert
  it replaced had rejected NaN. A pattern that decides for you decides wrong quietly.
- It sees `packages/*/lib/` only. `sngnav-app/lib/` lives in another repository and
  is **not covered**.
- `CONST-CTOR` rows are unclosed defects with no cheap fix, not cleared ground.

## Inventory

| key | class | digest | reason |
|---|---|---|---|
| `packages/compound_failure_advisor/lib/src/in_drive_advisor.dart` | UNREVIEWED | a723ff951bc4 | not read for release semantics |
| `packages/driving_conditions/lib/src/simulation/constant_fleet_confidence_provider.dart` | CONST-CTOR | 52e499d5d7ff | `const ConstantFleetConfidenceProvider` -- measured const; a throw would drop const |
| `packages/localization_fallback/lib/src/localization_config.dart` | CONST-CTOR | 1931d6c424f5 | `const LocalizationConfig` -- measured const |
| `packages/localization_fallback/lib/src/localization_config.dart#1` | CONST-CTOR | b58a32de7de8 | `const LocalizationConfig` -- measured const |
| `packages/localization_fallback/lib/src/localization_config.dart#2` | CONST-CTOR | 14b523deae4b | `const LocalizationConfig` -- measured const |
| `packages/navigation_safety/lib/src/bloc/navigation_bloc.dart` | DEBUG-BLOCK | 4e0eaec05e0f | diagnostic only -- the refusal is the `if (state.status != ...) return` DIRECTLY ABOVE it, which runs in every build mode. Read 2026-09-13. |
| `packages/navigation_safety/lib/src/bloc/navigation_bloc.dart#1` | DEBUG-BLOCK | 29482ff15c4f | `assert(() {...}())` -- a latency print, debug-only by construction |
| `packages/navigation_safety/lib/src/glance_budget_tracker.dart` | CONST-CTOR | e19f36bf49e3 | `const NHTSAGlanceBudgetConfig` -- measured const |
| `packages/navigation_safety/lib/src/glance_budget_tracker.dart#1` | UNREVIEWED | e5b82ddb6d12 | refusal-SHAPED (caller-supplied GlanceEvent.duration) but the method body is not read; may sit on a mid-drive path, where a throw is the wrong remedy |
| `packages/navigation_safety/lib/src/glance_budget_tracker.dart#2` | POST-CONDITION | 7775ece4608b | compares two of OUR OWN private fields after our own arithmetic; a throw mid-drive would take her navigation away |
| `packages/navigation_safety_core/lib/src/navigation_safety_config.dart` | POST-CONDITION | d59125beb407 | `m >= 1.0` on OUR OWN CircadianPhase multiplier table, not on caller input |
| `packages/navigation_safety_core/lib/src/navigation_safety_config.dart#1` | UNREVIEWED | f362a5518d3d | not read for release semantics |
| `packages/navigation_safety_core/lib/src/navigation_safety_config.dart#2` | UNREVIEWED | 511ab2b00d4b | not read for release semantics |
| `packages/navigation_safety_core/lib/src/ux_differentiation.dart` | DEBUG-BLOCK | 6ac32ddc250f | `assert(() {...}())`; the library doc states the release no-op explicitly |
| `packages/noaa_nws_adapter/lib/src/noaa_nws_client.dart` | CONST-CTOR | 2f71594ef671 | `const NoaaNwsRetryPolicy` -- measured const |
| `packages/noaa_nws_adapter/lib/src/noaa_nws_client.dart#1` | UNREVIEWED | 8248ed030f39 | not read for release semantics |
| `packages/offline_tiles/lib/src/performance_budget.dart` | CONST-CTOR | e19f36bf49e3 | `const PerformanceBudgetConfig` -- measured const |
| `packages/offline_tiles/lib/src/performance_budget.dart#1` | CONST-CTOR | fcf8af87e669 | `const PerformanceBudgetConfig` -- measured const |
| `packages/offline_tiles/lib/src/performance_budget.dart#2` | UNREVIEWED | dca54fd0548e | caution-add-only shape, mirrors DataBudget.tighten which WAS a live inversion; a strong candidate, not yet read |
| `packages/offline_tiles/lib/src/performance_budget.dart#3` | UNREVIEWED | 1c393cb96581 | not read for release semantics |
| `packages/route_condition_forecast/lib/src/services/route_segmenter.dart` | UNREVIEWED | 38c659ebfd79 | not read for release semantics |
| `packages/snow_rendering/lib/src/data_budget.dart` | CONST-CTOR | a8ef29088657 | `const DataBudgetConfig` -- measured const, and used as a DEFAULT PARAMETER VALUE (`const DataBudgetConfig()`), so const cannot be dropped without a breaking change. warningRatio is a `double`, so this one can take NaN: an UNCLOSED gap, named. |
| `packages/snow_rendering/lib/src/data_budget.dart#1` | CONST-CTOR | e19f36bf49e3 | same const constructor; see the row above -- unclosed, not exempt |
| `packages/snow_rendering/lib/src/data_budget.dart#2` | POST-CONDITION | 4e42efff9a49 | checks the output of OUR OWN exhaustive switch over OUR OWN enum and literals; nothing a caller supplies reaches it |
| `packages/snow_rendering/lib/src/data_budget.dart#3` | POST-CONDITION | 7052f6f97c1a | refusal-SHAPED on caller data, but record() is the MID-DRIVE path: a throw would take her navigation away. OWED remedy is clamp-and-report on the event stream, not a throw. Read in full 2026-09-13. |
| `packages/snow_rendering/lib/src/data_budget.dart#4` | POST-CONDITION | b07b50b31a41 | compares OUR OWN field before/after OUR OWN arithmetic |
| `packages/voice_guidance/lib/src/budget_aware_pace_profile.dart` | CONST-CTOR | 55309c4ab5c6 | `const BudgetAwarePaceProfile` -- measured const |
| `packages/voice_guidance/lib/src/budget_aware_pace_profile.dart#1` | CONST-CTOR | fef6e7d2e621 | `const BudgetAwarePaceProfile` -- measured const |
| `packages/voice_guidance/lib/src/budget_aware_pace_profile.dart#2` | CONST-CTOR | a726e48b0251 | `const BudgetAwarePaceProfile` -- measured const |
| `packages/voice_guidance/lib/src/voice_guidance_config.dart` | CONST-CTOR | e678d248d91e | `const VoiceGuidanceConfig` -- measured const |
| `packages/voice_guidance/lib/src/voice_guidance_config.dart#1` | CONST-CTOR | 00848910320c | `const VoiceGuidanceConfig` -- measured const |
| `packages/voice_guidance/lib/src/voice_guidance_config.dart#2` | CONST-CTOR | 0b3afb1fad61 | `const VoiceGuidanceConfig` -- measured const |
| `packages/voice_guidance/lib/src/voice_guidance_config.dart#3` | CONST-CTOR | 821e7a400e37 | `const VoiceGuidanceConfig` -- measured const |
