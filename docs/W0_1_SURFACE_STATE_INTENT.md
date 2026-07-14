# W0.1 — Is the surface-state warning library being DEMO-ONLY a design choice or a wiring GAP?

**Investigator:** SDE (sngnav-debug-engineer + SNGNav feature-exploration lead)
**Date:** 2026-07-12
**Type:** Investigation (read code + docs + git). No code changed. Every claim is cited to file:line / doc / git so the Chair can re-verify (OPS-062 / OPS-065).

**Mission anchor (OPS-060B):** HER mother, 70+, rural Akita, mountain pass, GPS+Maps+network dead. If the richest surface-hazard warnings are meant to be autonomous but are not, HER never hears them while driving — online or offline. This asks whether that is the case.

---

## VERDICT: MIXED

Two claims, both evidenced:

1. **The `RoadSurfaceCondition` → `AlertExplainer` library (the library W0.1 names) being manual/demo is DEMO-BY-DESIGN** — not a forgotten wire. It was scaffolded as a mock, is labelled "Mocked road condition", was deliberately split from the autonomous lane in a Chair-ratified commit, and **structurally cannot be autonomously driven on HER phone** (its only derivation is a vehicle-bus VSS sensor she does not have).

2. **BUT autonomous winter *surface* coverage is NOT fully adequate.** A *parallel*, weather-derivable surface taxonomy (`RoadSurfaceState`, snow_rendering) carries real spoken snow / slush / compacted-snow / standing-water lines and already has an app-side classifier — yet only its **black-ice subset** is autonomously voiced. Snow / slush / compacted-snow / standing-water are in an autonomous blind spot. That is a genuine coverage gap, on a *different* code path than the demo library.

So: the named library is demo-by-design; the autonomous coverage it would seem to promise is real but incomplete on a sibling path. Hence **MIXED**, not a clean "by-design" (which would falsely imply coverage is adequate) and not a clean "GAP" (which would falsely imply the demo library just needs a wire).

### Single most load-bearing piece of evidence

Git commit **`6bce1a4`** — `feat(reach): WS5 audio+haptic actuators + WS6 auto-announce drive HUD + WS7 JA consent (BOD-17)` (Chair-ratified 2026-07-01). Its body states the design intent verbatim:

> "wire the already-built safety catalog to HER's platform so a real compound-failure hazard reaches her eyes-off-the-road — **not a manual button.**"
> "WS6 — reach-wiring (**auto, not the manual button**): DriveHudController wired into the live tree ... **auto-announces (spoken + felt) on rung rise** ..."

The **same commit** created `_announceCurrentAlert` (WS5, the manual button off the mocked dropdown) *and* the autonomous WS6 lane — and WS6 deliberately auto-announces the **DriveHudController compound-failure caution**, **not** the `AlertExplainer` surface library. The manual status of the surface-state library is therefore a design decision recorded in the commit that built the autonomous lane, not an oversight.

---

## Evidence by question

### Q1 — INTENT: is the manual dropdown deliberate showcase, or meant to be autonomous?

Deliberate showcase. Four independent signals:

- **`lib/main.dart:283-284`** — the state field is commented **"Mocked road-surface condition for Slice 0."** and defaults to `RoadSurfaceCondition.ice`.
- **`lib/main.dart:1527-1528`** — the UI section is titled **"Mocked road condition"**; the dropdown is `DropdownButton<RoadSurfaceCondition>` (`:1529`) whose `onChanged` is the only writer of `_condition` (`:1533` `if (v != null) setState(() => _condition = v)`).
- **`lib/main.dart:1636-1646`** — the button comment reads **"WS5 — the button that ends the silence"**; `onPressed: _announceCurrentAlert` (`:1643`). `grep` confirms `_announceCurrentAlert` has exactly two occurrences: its definition (`:1413`) and this single caller (`:1643`). It is a demo button.
- **`lib/main.dart:1662`** — the *adjacent* section is titled **"Live drive — compound-failure caution (WS6, auto)"**. The app itself labels one lane WS5-manual and the next WS6-auto.

Git history:
- **`8503010`** ("feat: initial sngnav-app scaffold — try-first Slice 0 (Akita station)") introduced `_condition = RoadSurfaceCondition.ice` — it has been a **mock from the first scaffold commit**.
- **`6bce1a4`** (BOD-17, above) is the decisive intent record: WS5-manual and WS6-auto built together, WS6 explicitly "not the manual button".

**Intent conclusion:** the manual dropdown is a deliberate edge-developer/showcase surface for the `AlertExplainer` library, not a lane that was intended to run autonomously and forgotten. This is well-evidenced, not projected.

### Q2 — DERIVATION EXISTS? Is there a `RoadSurfaceCondition`-from-live-weather derivation that could feed `_condition` but is simply unwired?

**No weather derivation of `RoadSurfaceCondition` exists anywhere** (app or catalog). The only constructor is:

- **`packages/navigation_safety_core/lib/src/road_surface_condition.dart:98`** — `static RoadSurfaceCondition fromVss(String value)` — parses a **VSS (Vehicle Signal Specification) allowed-value string** (`'ICE'`, `'SNOW'`, ...). That is a **vehicle-bus sensor signal HER's phone does not have**. There is no `RoadSurfaceCondition.fromWeather/fromObservation`.

There **is** a live-weather surface derivation — but it targets a **different enum**:

- **`RoadSurfaceState`** (snow_rendering) has `RoadSurfaceState.fromCondition(WeatherCondition)` (used at `lib/services/road_surface_classifier.dart:45` and `lib/services/invisible_ice_watch.dart:67`).
- The app even wraps it: **`lib/services/road_surface_classifier.dart`** — `RoadSurfaceClassifier.classify(WeatherCondition) → RoadSurfaceState` (hysteresis-debounced). **But this classifier is itself unwired to the live loop** — `grep` shows it is used only in `lib/scenarios/nagoya_unexpected_snow_scenario.dart` and its own test, never in the live drive tree.

**No bridge `RoadSurfaceState → RoadSurfaceCondition` exists** in the app or catalog (`grep` for the two names co-occurring returns nothing). So `_condition` cannot be fed from live weather even indirectly without new code.

**Q2 conclusion:** the demo library's enum has **no** unwired weather derivation waiting to be connected — feeding it autonomously would require either a VSS sensor (absent on a phone) or a **new** State→Condition mapping. The weather-derivable surface path exists on the *sibling* `RoadSurfaceState` enum, and its app-side classifier is present but unwired.

### Q3 — OVERLAP: do the autonomous watches subsume the surface library, or is it materially richer?

The autonomous voice lanes (fire without a button) are:

| Lane | Source | What it voices | Cite |
|---|---|---|---|
| Invisible-ice watch | live JMA obs | **black-ice window only** (precip10m == 0 **and** temp > 0 → `RoadSurfaceState.blackIce`) | `lib/services/invisible_ice_watch.dart:51-78`; announced in `_announceWatchTransitions` `lib/main.dart:1160-1167`, stale/absence `:1218,1240` |
| Turmoil watch | live JMA obs | **downpour (rain) + strong wind** — atmospheric, not surface | `lib/services/turmoil_watch.dart:87-113`; announced `lib/main.dart:1169-1178` |
| Drive HUD (WS6) | GPS + visibility + advisory | **compound-failure caution** (position-trust degradation → "heightened caution / consider stopping") — not surface-specific | `lib/main.dart:725-799`, `_feedDriveHud` auto-announce on rung rise; commit `6bce1a4` |

The `AlertExplainer` / `RoadSurfaceCondition` library covers **8 surface conditions** — unknown / dry / wet / snow / ice / slush / wetIce / looseGravel — each with a per-profile, JAF/MLIT/NEXCO-verbatim **action** string (`road_surface_condition.dart:32` enum; `alert_explainer.dart`; rendered verbatim at `lib/main.dart:1414-1424, 1619-1629`).

They **do not subsume** each other: the autonomous lanes overlap the surface library only on the **black-ice** case (invisible-ice ≈ ice/wetIce window). **Snow, slush, compacted-snow, loose-gravel, standing-water, and general ice actions are not autonomously voiced.** Note the gate at `invisible_ice_watch.dart:60`: `if (precip10m > 0) return clear` — so **during actual snowfall the invisible-ice lane goes silent**, and no surface-state line replaces it. On the surface axis the library is materially richer than what runs autonomously.

### Q4 — Is HER's autonomous winter coverage adequate?

Partially. She autonomously hears: black-ice window, downpour/strong-wind turmoil, compound-failure "consider stopping", and honest stale/absence lines. She does **not** autonomously hear a surface-state warning for **snow / slush / compacted-snow / standing-water**, even though the weather-derivable path can produce them and has finished spoken text for each:

- **`packages/snow_rendering/lib/src/models/road_surface_announcement.dart`** — `RoadSurfaceStateAnnouncement.announcement` returns real ja+en spoken lines for **slush** (`:20` 「シャーベット状の路面です。下が凍結している可能性があります…」), **compactedSnow** (`:32` 「圧雪路面です。急のつく操作を避け…」), **standingWater** (`:64` 「…ハイドロプレーニングに注意し…」), wet, and blackIce.

So the answer to "is autonomous coverage adequate?" is **no, not on the snow/slush/compacted-snow surface axis** — but the vehicle to close that gap is the **`RoadSurfaceState`** path (weather-derivable, classifier already present), **not** the `RoadSurfaceCondition`/`AlertExplainer` demo library.

---

## If GAP — the concrete missing wiring

To give HER autonomous surface-state coverage beyond black-ice, wire the **already-present** `RoadSurfaceState` path — do **not** attempt to autonomously drive the demo `RoadSurfaceCondition` enum (it has no phone-derivable source):

1. Feed live JMA/weather into the existing **`RoadSurfaceClassifier`** (`lib/services/road_surface_classifier.dart`) on the same JMA ticker that drives `_announceWatchTransitions` (`lib/main.dart:626`, `:1114`).
2. On a rung-rise (same de-dupe + cry-wolf discipline as `_announceWatchTransitions`), autonomously announce `RoadSurfaceState.announcement` (snow_rendering `RoadSurfaceStateAnnouncement`) for **slush / compactedSnow / standingWater** (black-ice already covered — avoid double-firing with the invisible-ice watch).
3. Close the snowfall blind spot: the invisible-ice lane goes `clear` when `precip10m > 0` (`invisible_ice_watch.dart:60`); a snow/slush surface line is exactly what should fire in that precip>0 window.

This is a **build** proposal for a later pass, surfaced for the Chair — this session changed no code.

---

## Secondary finding (flagged, tangential)

`_condition` defaults to `RoadSurfaceCondition.ice` (`main.dart:284`) and is only ever changed by the manual dropdown. The GPS-bound maneuver narration reads it: `_maneuverCoincidesWithHazard()` → `isSlipperySurface(_condition)` (`main.dart:1385-1391`, `services/maneuver_narration.dart:268-272`). In real autonomous driving HER never touches the dropdown, so `_condition` stays `ice` and the "icy-turn" advisory couples on **every** maneuver by default. This is the one place the manual mock leaks into an autonomous-ish (GPS) lane. Noted for the Chair; out of W0.1's core scope.

---

## Honesty bounds

- Top-level docs (`BETA_PLAN.md`, `KNOWN_LIMITATIONS.md`, `SNGNAV_WAY.md`) do **not** explicitly discuss the surface-state demo surface or the snow/slush autonomous gap (`grep` returned nothing on point). The intent conclusion rests on **code comments + the BOD-17 commit body + git origin**, which are strong and consistent — not on a top-level design doc. Stated so the Chair knows exactly where the intent evidence lives.
- I did not run the app; this is a static read. Claims are code/git-cited and re-verifiable.
