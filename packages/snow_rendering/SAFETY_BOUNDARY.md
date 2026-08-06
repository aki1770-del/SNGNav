# snow_rendering — Safety-Class Boundary Record

**Package**: `snow_rendering`
**Version**: 0.3.0 (DEPLOY)
**Boundary record version**: 2.0
**Authoring skill**: AAA (automotive-adas-analyst)
**Date**: 2026-05-06; **corrected 2026-07-12**
**Anchor**: D-VGC189-1 (driver-facing-loom-as-default architectural discipline)
**Related**: `navigation_safety_core` SAFETY_BOUNDARY.md (severity-not-profile + driver-always-drives invariants inherited verbatim through transitive `navigation_safety_core: ^0.10.0` dependency); `navigation_safety` SAFETY_BOUNDARY.md §8.1 (GlanceBudgetTracker structural precedent); `navigation_safety_core` SAFETY_BOUNDARY.md §7.3 (cap-override-with-confirmation pattern precedent).

---

## 0 — Correction notice (2026-07-12, record v2.0)

**This package held the FATAL PATH of the fabrication defect, and boundary
record v1.0 was silent on it.** The record is corrected here in the same commit
as the code, not after it: a document certifying a property the code lacks is
the certificate of a defect, and is worse than no certificate.

**The chain, in versions up to and including 0.2.7:**

```
WeatherCondition.clear()          (driving_weather ≤ 0.4.4: +5.0 °C, 10 km,
                                   0 km/h, iceRisk = false — all FABRICATED,
                                   returned for an EMPTY advisory feed)
  → RoadSurfaceState.fromCondition(...)  → RoadSurfaceState.dry
  → gripFactor 1.0                        (MAXIMUM GRIP on an unmeasured road)
  → RecommendedResponse.proceed
  → advisoryMessage "Conditions normal"   ← shown to a driver in Akita
```

`fromCondition` had **no way to say "I cannot classify this road"** — an absent
ice risk, temperature and precipitation type fell through to `dry`. `dry` is a
POSITIVE claim, it carries `gripFactor: 1.0`, and it produced the green light.
Absence became maximum grip.

**0.3.0 breaks the chain at every link:** `fromCondition` returns
`RoadSurfaceState?` (`null` = cannot classify); `gripFactor`, `visibility` and
`precipitation` are nullable; `RecommendedResponse.conditionsUnknown` exists and
is routed BEFORE the `proceed` fall-through; and the advisory for that tier says
so, in Japanese first — 「路面状況を取得できていません。見える範囲で運転してください。」
The defect is disclosed in `CHANGELOG.md` 0.3.0, because pub.dev versions are
immutable and a silent fix would be a silent recall.

## 1 — SAE J3016 driver-task regime

**Level**: L0 / L1 supportive use only.
**Driver-task assignment**: the driver performs the dynamic driving task at all times. The package's surfaces — `RoadSurfaceState` + `PrecipitationConfig` + `VisibilityDegradation` + `DrivingConditionAssessment` + (new in 0.2.0) `DataBudget` — supply weather-to-rendering computation and per-cycle data-budget telemetry consumed by the integrator HMI. The package neither actuates the vehicle nor closes a control loop. Pure Dart; no Flutter dependency.
**No L2+ claim.** Any handover-class or supervision-class deployment requires the integrator to add their own driver-attention monitoring, take-over-request signalling, and minimum-risk-manoeuvre fallback per L2+ standards.

## 2 — ISO 26262 ASIL classification

**Package boundary**: **QM** (Quality Management; not functional-safety-scope).
**Reasoning**: package outputs are advisory-class assessment value-objects (road-surface state, precipitation parameters, visibility degradation) plus advisory-class data-budget telemetry. No control authority. No ASIL-A through ASIL-D claim asserted at the package boundary. The 0.2.0 `DataBudget` integration emits broadcast events the integrator HMI may consume to drop snow-overlay fidelity; it does not actuate any vehicle surface.
**Integrator responsibility**: the integrator performs the hazard analysis and decides the final ASIL classification for their integration.

## 3 — SOTIF (ISO 21448) posture

**Stance**: **advisory not control.** SOTIF addresses Safety Of The Intended Functionality at automated-driving-feature scope. This package does not deliver an automated driving feature; it delivers weather-rendering computation plus advisory data-budget telemetry consumed by integrator HMI surfaces. SOTIF triage is performed by the integrator at their HMI scope.
**Severity-not-profile invariant** (load-bearing, inherited verbatim from `navigation_safety_core` SAFETY_BOUNDARY.md §6): the per-cycle `DataBudget` modulates RENDER-FIDELITY per profile (bandwidth-margin direction); it does NOT modify alert severity, score floors, or critical thresholds. Critical alerts in `navigation_safety` retain their critical-bypass invariant regardless of data-budget state.

**Known performance insufficiency — ABSENT INPUT (SOTIF, the 0.3.0 correction)**: up to 0.2.7 an absent ice-risk / temperature / precipitation-type triple was classified as `RoadSurfaceState.dry` with `gripFactor: 1.0` and advised `proceed` / "Conditions normal". An absent input was thereby resolved to the **most benign** output the model can produce — the specification-insufficiency class SOTIF exists to name. **Mitigated in 0.3.0**: the classifier ABSTAINS (`null`) rather than defaulting, the response tier carries `conditionsUnknown`, and the driver-facing advisory names the absence. The asymmetry is deliberate and is the safety argument: POSITIVE evidence of a hazard fires on partial data (an ice flag alone still warns), but the NEGATIVE verdict ("proceed / conditions normal") now requires complete data. Absence is reported AS absence — not as a hazard (which would cry wolf on every offline moment until the driver stopped believing the alert, the failure mode that matters on the night it is real).

**Residual insufficiency recorded against 0.3.0 — ABSENT HUMIDITY (CLOSED, unreleased)**: as published in 0.3.0, an absent **humidity** reading still resolved to `dry` on the radiative-frost path (`road_surface_state.dart`: with `precip == none`, `temp > -3` and humidity absent, `isRadiativeFrostBlackIce` abstains and the classifier reached `return dry`), so on a humidity-blind feed an unjudged frost morning read as confident safety. **Mitigated (unreleased, see CHANGELOG)**: where the frost check ABSTAINS because `humidityRH` is null or non-finite and the temperature is at or below the check's ambient ceiling (+3 °C), the classifier now abstains too (`null` → `conditionsUnknown`) rather than reporting a declining check as an affirmative all-clear. This applies the §3 asymmetry one field further in: the NEGATIVE verdict requires the data the determination actually rests on. It remains an abstention, not an alert — `null` cannot cry wolf — and the bound is deliberate: above the ceiling the check declines on the MEASURED temperature, so those roads stay `dry`.

**Residual insufficiency STILL open — CORRUPT input (recorded, not left unstated)**: the frost check also abstains on a **non-finite temperature** (`NaN` / `±inf`, which additionally defeats the `temp <= -3` deep-cold rule and the ceiling comparison) and on a **humidity outside `[5, 105] %`** (rejected as implausible or as a mis-wired fraction). Both paths still reach `return dry`. These are the same absence-resolved-to-most-benign class as above, on inputs that are corrupt rather than missing; they require a feed emitting bad values rather than an incomplete one, and they are not fixed. Documented in `KNOWN_LIMITATIONS.md` §4.

## 4 — WP.29 cybersecurity touchpoint

**Touchpoint location**: **none at package boundary.** The package consumes typed value-objects (`DriverProfile` from `navigation_safety_core`, `WeatherCondition` from `driving_weather`, `DataFetchEvent` value objects). No external network surface at this layer; no over-the-air update surface; no key-management surface. Data-fetch byte-counts are integrator-supplied via `DataMeterProvider` adapter.
**Integrator responsibility**: any integrator who wires external sources (sensor / cloud / fleet) into the `DataMeterProvider` adapter is the consumer-side WP.29 touchpoint owner.

## 5 — JIS / JASO conformance

**Conformance status**: **not mapped at this scope.** Japanese-domestic certification is integrator-class concern. Per the inherited `navigation_safety_core` boundary record §5: *"Consult a qualified Japanese-domestic functional-safety partner before any IVI-vendor or OEM-pilot integration that targets the Japanese-domestic certification surface."*

## 6 — Severity-not-profile invariant

**Status**: **applies in scope by design.**
**Concrete locus**:
- `lib/src/data_budget.dart` library-level docstring — explicit declaration that the tracker is bandwidth-class only and does not modify severity tiers.
- `lib/src/data_budget.dart` `DataBudgetConfig.forProfile` — per-cohort `budgetBytes` adjusts BANDWIDTH ALLOWANCE only; the factory does not return severity-mutating values; the runtime debug assertion verifies `budgetBytes <= baselineBudgetBytes`.

**Operational consequence**: per-profile differentiation lives in `DataBudgetConfig.forProfile`'s data-budget allowance only — never in alert severity, never in score-floor tiers.

## 7 — Driver-always-drives invariant

**Status**: **applies in scope by design** per D-VGC188-1.
**Concrete locus**:
- `lib/src/data_budget.dart` library-level docstring — *"the tracker is presentation-class only. The integrator may render lower-fidelity snow overlay when `BudgetWarning` fires, but the package itself does not modify any driver-facing surface or vehicle state."*
- `DataBudget.record(DataFetchEvent)` — observation-only; no actuator surface.
- `DataBudget.tighten(int)` — auto-tightening allowed within an active cycle (caution-add direction); rejected if attempting to LOOSEN.
- `DataBudget.relax(int, BudgetRelaxConfirmation)` — **cap-override-with-confirmation pattern** (mirrors `navigation_safety_core` 0.10.0 #30): auto-relax FORBIDDEN; loosening requires integrator-supplied affirmative confirmation token (`isConfirmed: true` + non-empty `reason`). Default-constructed or non-affirmed token rejected at runtime via debug-mode assertion. The driver retains full control authority over relax decisions; the system never auto-loosens the data budget.

## 8 — DataBudget driver-facing-loom (new in 0.2.0)

**Operational discipline**: *the budget reports cumulative per-cycle data-fetch consumption against a per-cohort allowance so an integrator HMI can drop snow-overlay fidelity before the budget is exhausted; the package supplies the substrate, the integrator owns the surface.*

**Concrete locus**: `lib/src/data_budget.dart` `DataBudget.record(DataFetchEvent)` consumes integrator-supplied data-fetch byte-count events; emits `BudgetWarning` (default 75% consumed), `BudgetExhausted` (100% consumed), and `RenderFidelityDrop` (in lock-step with Exhausted) records on a broadcast `budgetEvents` stream. Reset via `reset(BudgetResetReason)` is integrator-explicit only.

**Caution-add-only invariant** (load-bearing): the per-cohort data budget produced by `DataBudgetConfig.forProfile` is `<=` the 4MB baseline. Larger-than-baseline values would relax the bandwidth-margin direction and are rejected at runtime via debug-mode assertion in `forProfile`. Within an active cycle, `tighten(int)` may only DECREASE the budget (debug-mode assertion enforces). Auto-relax (loosening) is FORBIDDEN; only `relax(int, BudgetRelaxConfirmation)` with affirmative confirmation may loosen the budget. The cap-override-with-confirmation pattern is the ONLY exception to the auto-tighten-only rule; it explicitly preserves the driver-always-drives invariant.

**Severity-not-profile invariant preserved** (load-bearing per §6 above): the tracker is bandwidth-class only. It supplies a substrate the integrator may use to drop snow-overlay fidelity; it does not adjust score floors or severity tiers. Critical alerts retain their critical-bypass invariant.

**Driver-always-drives invariant preserved** (load-bearing per §7 above): the tracker is reporting-only at the read path; the relax path requires integrator-affirmed confirmation. The package itself never auto-loosens; the driver retains full control authority over relax decisions through the integrator's surface.

**UNVERIFIED-magnitude flags** (per `KNOWN_LIMITATIONS.md`): per-cohort data-budget magnitudes are **design-default hypotheses** pending field-measurement validation. Per-population calibration deferred pending fleet-class field measurement; bandwidth-class assumptions (assumed-slower-data for `ageingRural` rural-bandwidth-margin; assumed-roaming-cost for `foreignTouristSnowZone`) are not yet anchored in a published study mapping driver-class to optimal-data-budget specifically.

**ASIL-QM advisory** per §2 (no functional-safety claim asserted at the package boundary). **WP.29 touchpoint** at integrator's `DataMeterProvider` implementation, not at this package (per §4; the interface is consumer-implemented; the package consumes only typed `DataFetchEvent` values at this layer).

## 9 — Cross-references

- `lib/src/data_budget.dart` — 0.2.0 `DataBudget` substrate
- `lib/snow_rendering.dart` — re-exports `data_budget.dart`
- `KNOWN_LIMITATIONS.md` — per-cohort budget UNVERIFIED-magnitude flag; bandwidth-class assumption
- `CHANGELOG.md` 0.2.0 entry — verbatim caution-add-only declaration + UNVERIFIED-magnitude flag
- `navigation_safety_core` SAFETY_BOUNDARY.md (re-exported core boundary applies; severity-not-profile invariant inherited verbatim; §7.3 cap-override-with-confirmation pattern precedent)
- `navigation_safety` SAFETY_BOUNDARY.md §8.1 — `GlanceBudgetTracker` structural precedent
- LICENSE: BSD-3-Clause

---

**Boundary record authored** by AAA (automotive-adas-analyst) under VAA-as-SEO operational pen authorization (spawn -86). Subject = We / AAA. Verbatim citation discipline observed. PHIL-001 8-test PASS preserved at boundary scope. D4 dignity audit clear.

**Record v2.0 correction (2026-07-12)**: v1.0's closing certification stood while the code shipped `dry` / grip 1.0 / "Conditions normal" for a road nobody had measured. The certification is re-asserted at v2.0 **only** for the corrected 0.3.0 code, with the absent-input insufficiency named in §3 and the humidity residual disclosed rather than certified away.
