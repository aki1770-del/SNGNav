# Changelog

## 0.2.0 — 2026-08-23 — unreadable input stops reading as "no hazard"

**BREAKING.** Two API changes, both deliberate, both on the safety path.

### What 0.1.4 and earlier did, in plain words

When the nav2 Collision Monitor sent this package a message it could not read, the package
told the driver **nothing** — the same thing it does when the monitor is quiet and healthy.
Four distinct unreadable-message conditions produced silence at the HMI, and an integrator
could not tell them apart from an all-clear.

| was | now |
|---|---|
| absent `action_type` → `DO_NOTHING` | → `Nav2CollisionAction.unreadable`, severity **critical** |
| unknown action code (nav2 adds a 6th) → `DO_NOTHING` | → `unreadable`, **critical** |
| absent `detections` → `anyDetection == false` | → `anyDetection == null` (**NOT KNOWN**) |
| `polygons`/`detections` length mismatch → silently truncated to `min(len)` | → unreadable state holding **no pairs** |

`unreadable` **fails toward the severe reading** — the bound this package already stated for
`APPROACH`: *a faithful relay cannot tier what it could not read.* An unreadable
`action_type` may be a `STOP` we failed to parse, so it must not land in the tier
`doNothing` occupies.

### Breaking changes

* **`Nav2CollisionAction` gains `unreadable`.** Exhaustive `switch` statements over this
  enum will no longer compile until they handle it — **if your switch is exhaustive.**
  ⚑ **A `switch` with a `default:` clause still compiles, and will route `unreadable` into
  whatever branch `default:` leads to.** If that branch is your benign one, this release
  changes nothing for you and the defect survives in your code with a green build. Our own
  pre-0.2.0 documentation taught exactly that pattern (*"caution-add-only invariant"*), so
  this warning is owed. **Check every `switch` over `Nav2CollisionAction` for a `default:`.**
* **`Nav2CollisionDetectorState.anyDetection` is now `bool?`** — `null` when the message was
  unreadable. `null` means NOT KNOWN; it never means "nothing detected". Unlike the enum
  there is no escape hatch: every read site must be visited. **Migrate with
  `anyDetection == true`, NOT `anyDetection ?? false`** — `?? false` re-creates the exact
  defect this release closes, in your code, in one keystroke.
* New field `Nav2CollisionDetectorState.isReadable`.

### Why this was shipped broken, recorded rather than hidden

The four defects were **documented, tested and deliberately red** since the package shipped:
`test/defect_proof_absent_state_test.dart` asserted the fix and failed, `SAFETY_BOUNDARY.md`
tabulated them as PI-01..PI-04, and `dart_test.yaml` explained that a `pinned-live` failure
*is* the record that a defect exists. The honesty machinery worked; the repair had not been
done.

⚑ **Fixing the code required rewriting seven passing tests that pinned the defect** — among
them one named *"fromInt degrades unknown to doNothing (caution-add-only)"* and one
asserting *"the whole channel is silent on all four — nothing reaches the HMI"*. **The
specification was the hazard, and the tests were the specification.** That is the shape of a
SOTIF insufficiency, and it is why a green suite proved nothing here.

### Not discharged by this release

**AoU-1 still holds.** Silence on `advisories` is still not an all-clear: the **detector
path emits no advisory at all** by construction (see BI-8 — the divergence is path-specific).
PI-03's repair is observable on `anyDetection == null`, not on the advisory stream. What
changed is that the **monitor** path no longer contributes to that silence.

**PI-05, PI-06, PI-06-R and PI-07 remain open**, unchanged and still tabulated.

## 0.1.4 — 2026-08-21 — an obstacle is no longer announced as road ice

**What 0.1.3 did, in plain words.** When the nav2 Collision Monitor reported that an
**object** was inside a configured polygon, this package told the driver the **road was
frozen**. Measured output on a well-formed `STOP`:

> 「凍結路面です。気温0°C以下で薄氷ができています。時速30km以下に減速し、急ブレーキは避けてください」
> *(Frozen road surface. Ice is forming below 0°C. Reduce to under 30 km/h and avoid braking hard.)*

The message carried **no temperature**, and the text fabricated one. Worse, it told the
driver to **avoid braking hard** while the monitor was commanding a **stop**. It was false
about a road she was on, and it inverted the instruction.

**⚑ 0.1.3's changelog told you this was correct.** It said the mapping *"remains the closest
available semantic."* **That sentence is withdrawn.** It was not the closest available
semantic: `RoadSurfaceCondition.unknown` already existed in the enum this package imports
(`road_surface_condition.dart:34` — *"Sensor cannot determine current road-surface state"*)
and was nearer in every respect. An assurance is worse than silence, because silence can be
discovered and an assurance is believed.

**What changed.** All four non-`DO_NOTHING` actions now map to `RoadSurfaceCondition.unknown`,
yielding 「路面状況不明。慎重に運転してください」 — which claims nothing about the surface,
because the message says nothing about the surface. Guarded by `BI-7`.

**Non-breaking.** No API changed. Anyone on `^0.1.3` receives this without editing a line.

**Also repaired in this line:** a nav2 `STOP` arriving after an advisory burst had consumed
the throttle cap was previously **dropped**. `severityOf` now maps `stop`/`approach` to
`AlertSeverity.critical`, which takes the throttle's non-negotiable critical-bypass. Guarded
by `BI-9`. `SAFETY_BOUNDARY.md` AoU-5 and AoU-6 both asserted the pre-repair behaviour and
are amended, with their previous text preserved in place.

### ⚑ What this release does NOT fix — read this before you rely on it

Four defects remain **live and proven**, each with a test that fails on purpose in the
`pinned-live` suite (run `dart test -t pinned-live`; they are reported in CI, never skipped):

| | still true of 0.1.4 |
|---|---|
| **PI-01** | a message **missing `action_type`** is read as `DO_NOTHING` — absence renders as "no action" |
| **PI-02** | an **unknown action code** is read as `DO_NOTHING` |
| **PI-03** | a message **missing `detections`** reports `anyDetection == false` |
| **PI-04** | `polygons` and `detections` of **different length** are absorbed as a shorter loop |
| **PI-05** | `STOP` and `LIMIT` remain **byte-identical in the advisory text**; read `state.actionType` yourself |
| **D-08** | the source comment claims `polygon_name` is relayed on the monitor path; **it is not** |

**Residual on the fix itself, stated not hidden:** `.unknown` is honest and still wrong in
**domain**. nav2 reported an *obstacle*; `RoadSurfaceCondition` has no obstacle member, so no
value in that enum can say what actually happened. The vocabulary gap is recorded, not closed.

**This package is QM. No ASIL is claimed and none can be inherited from here.** It has no
timeout, no staleness clock and no heartbeat (AoU-3), so it should not be the sole path for a
reflexive-stop architecture — the reason is liveness and QM scope, **not** a dropped STOP.

## 0.1.3 — 2026-07-11 — navigation_safety_core 0.11 compatibility (constraint widen)

- **Constraint widen (no source change):** `navigation_safety_core:
  ">=0.10.0 <0.12.0"` (was `^0.10.0`). The published `^0.10.0` constraint
  made this package a version-conflict blocker for any consumer taking the
  core 0.11 line (graded ja announcements, finite-position safety); the
  full test suite passes unchanged at BOTH bounds of the range — 12/12
  against 0.11.1 and 12/12 against the 0.10.0 floor (each resolved and run,
  not argued from source reading); the `AlertExplainer` / `DriverProfile` /
  `RoadSurfaceCondition` surface this package consumes is source-compatible
  across 0.10 → 0.11.
- **Mapping unchanged:** obstacle-class monitor events still map to the
  conservative `RoadSurfaceCondition.ice` advisory shape (caution-add-only).
  Core 0.11 introduces no obstacle-class vocabulary (`RoadSurfaceCondition`
  is VSS road-surface state by design), so the documented shim remains the
  closest available semantic; a dedicated obstacle-class advisory vocabulary
  in core remains the tracked future work that would retire the shim.

## 0.1.2

- Republish from the embedded-target Dart 3.10.1 SDK (Flutter 3.38.3) to correct a stale
  `^3.11.0` SDK floor in the previously-published artifact. No source or behavior change; the
  source already declared `sdk: ^3.10.0`. Restores `pub get` for embedded/automotive Dart
  consumers on Dart 3.10.x.

## 0.1.1 — 2026-05-10 — Pana score recovery (Theme α P3)

- Trim pubspec `description` to within the pana 60–180 character target.
- Add minimal `example/main.dart` for pana documentation scoring.
- Apply `dart format` to clear any formatter findings.
- No SDK source changes; metadata + format pass only.


## 0.1.0 — 2026-05-10 — Initial nav2 safety-layer composition

- `Nav2CollisionMonitorState` / `Nav2CollisionDetectorState` — Dart
  records mirroring `nav2_msgs/msg/CollisionMonitorState` and
  `nav2_msgs/msg/CollisionDetectorState` ROS 2 messages verbatim.
- `Nav2CollisionAction` — enum mirroring the upstream `uint8`
  action-type constants (DO_NOTHING / STOP / SLOWDOWN / APPROACH /
  LIMIT) with caution-add-only fallback for unknown values.
- `Nav2SafetyMapper` — static mapper from collision-monitor state
  events to `navigation_safety_core` `AlertExplainer` advisories.
- `Nav2SafetyLayer` — composition class with internal
  `AlertDensityThrottle` rate-limiting and a broadcast advisory
  stream the integrator's HMI can subscribe to.
- No transport lock-in: package depends only on
  `navigation_safety_core` + `equatable`. Integrators wire any
  ROS-Dart bridge (`roslibdart`, rosbridge over WebSocket, MQTT
  bridge, custom) to feed typed records into the layer.
- Tests construct typed records directly; no live bridge required.
