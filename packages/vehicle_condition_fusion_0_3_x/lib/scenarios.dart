/// SYNTHETIC, opt-in winter-drive traces + a replay helper for
/// `vehicle_condition_fusion`.
///
/// ## Why this library exists (the blank-page problem)
///
/// An edge developer can `pub add vehicle_condition_fusion` today, but to SEE or
/// test the fusion they still need vehicle signals — a databroker, a CAN bus, or
/// a real car in a real snowstorm. This library lowers that floor: it ships
/// hand-authored, physically-plausible signal traces and a one-line replay
/// helper, so a developer with **just a laptop** can drive the fusion through a
/// full Akita whiteout end-to-end — no databroker, no vehicle, no SDK.
///
/// ## ⚠️ These traces are ILLUSTRATIVE / SYNTHETIC — NOT recorded sensor data
///
/// Every scenario below is **hand-authored** from plausible physical values. It
/// is **not** a recording of any real vehicle's bus, not telemetry from any
/// drive, and not calibrated against any logged dataset. The numbers were chosen
/// to exercise the published fusion's hazard rules (ice-risk friction threshold,
/// cold-slip TCS rule, precipitation→visibility proxy) so a developer can watch
/// the assessment escalate and clear. Treat them as a **teaching fixture**, the
/// same way you would treat example data in a tutorial — never as evidence about
/// real roads.
///
/// ## This library does NOT change the fusion
///
/// `scenarios.dart` is a SEPARATE, opt-in import. It is intentionally **not**
/// part of the main `package:vehicle_condition_fusion/vehicle_condition_fusion.dart`
/// barrel, so the core stays lean and the safety-calibrated fusion is untouched —
/// these traces only *feed* it.
///
/// ## Partial-frame style
///
/// The scenarios are authored as **partial frames** to pair with
/// [VehicleConditionFusion.fromPartialFrames]: after the first frame, each later
/// frame re-sends **only the signals that changed** (a `null` field means
/// "unchanged — not re-sent this cycle"). This mirrors the documented-primary
/// KUKSA `subscribe` transport and exercises the carry-forward safety rail — note
/// how a speed-only frame in the whiteout STILL reports black ice, because the
/// once-seen low-friction / TCS signals are held forward.
///
/// ```dart
/// import 'package:vehicle_condition_fusion/vehicle_condition_fusion.dart';
/// import 'package:vehicle_condition_fusion/scenarios.dart';
///
/// final fusion = VehicleConditionFusion.fromPartialFrames(
///   partialFrames: replayWinterDrive(akitaWhiteoutDrive),
/// );
/// fusion.conditions.listen((u) {
///   if (u.isAvailable) print(u.assessment!.surfaceState);
/// });
/// ```
library;

import 'vehicle_condition_fusion.dart';

/// Replays a list of [VehicleConditionSignals] [frames] as a stream, spaced by
/// [step].
///
/// Pair this with [VehicleConditionFusion.fromPartialFrames] (the scenarios are
/// authored partial-frame style — see the library doc). Each frame is emitted in
/// order; with `step == Duration.zero` (the default) the whole trace is emitted
/// as fast as the event loop allows, which is what you want in a test. Pass a
/// non-zero [step] (e.g. `Duration(milliseconds: 200)`) to pace the replay so a
/// human watching a demo SEES the hazard evolve frame by frame.
///
/// The stream is single-subscription. It completes after the last frame, which
/// makes [VehicleConditionFusion] surface its honest end-of-stream
/// `unavailable` marker — a convenient "drive finished" signal.
Stream<VehicleConditionSignals> replayWinterDrive(
  List<VehicleConditionSignals> frames, {
  Duration step = Duration.zero,
}) async* {
  for (final frame in frames) {
    if (step > Duration.zero) {
      await Future<void>.delayed(step);
    }
    yield frame;
  }
}

/// SYNTHETIC — an Akita-style winter drive that escalates from a dry road into a
/// whiteout black-ice event and then clears. ILLUSTRATIVE hand-authored values,
/// **not** recorded sensor data.
///
/// Authored as **partial frames** (each later frame re-sends only what changed),
/// so it must be driven through [VehicleConditionFusion.fromPartialFrames]. The
/// trace is sized so the fusion's [HysteresisFilter] debounce (window 3,
/// threshold 2) actually flips the surface state at each phase, producing the
/// visible progression: **dry → compacted snow → black ice → slush → wet**.
///
/// The severe phase mirrors a real-databroker (KUKSA) end-to-end test in the
/// SNGNav source repository (`tool/kuksa_e2e/kuksa_e2e.dart`, repo-relative —
/// NOT shipped with this package): friction ≈ 0.18, TCS engaged, air ≈ −6 °C,
/// wiper 5, rain 80 → black ice + a ~300 m low-visibility (heavy-snow) cue.
///
/// Per-phase physical rationale (one line each):
const akitaWhiteoutDrive = <VehicleConditionSignals>[
  // ── Phase 1 · DRY / CLEAR ────────────────────────────────────────────────
  // Cold, dry pavement leaving home: full grip, no precipitation, sub-zero but
  // not cold enough for residual ice (a dry road just below 0 °C is still dry).
  VehicleConditionSignals(
    roadFriction: 0.95,
    tcsEngaged: false,
    absEngaged: false,
    wiperIntensity: 0,
    rainIntensity: 0,
    airTempC: -1.0,
    speedKmh: 50,
  ),
  // partial: only speed changes — conditions unchanged, still dry.
  VehicleConditionSignals(speedKmh: 55),

  // ── Phase 2 · SNOW ONSET ─────────────────────────────────────────────────
  // Snow begins: wipers on, the rain sensor sees moderate precipitation, the
  // road cools to −3 °C and friction drops toward (but not below) the icy
  // threshold → snow accumulating on a cold road reads as compacted snow.
  VehicleConditionSignals(
    roadFriction: 0.45,
    wiperIntensity: 3,
    rainIntensity: 40,
    airTempC: -3.0,
    speedKmh: 40,
  ),
  // partial: snowfall intensifies a little (wiper/rain up); friction/temp held.
  VehicleConditionSignals(wiperIntensity: 4, rainIntensity: 50, speedKmh: 35),

  // ── Phase 3 · WHITEOUT (severe black ice) ────────────────────────────────
  // The worst-case picture: ESC friction collapses to 0.18, TCS engages on a
  // −6 °C surface, wiper maxes and the rain sensor pegs near 80% → black ice
  // with a ~300 m low-visibility (heavy-snow) cue. (Mirrors the KUKSA e2e severe phase.)
  VehicleConditionSignals(
    roadFriction: 0.18,
    tcsEngaged: true,
    wiperIntensity: 5,
    rainIntensity: 80,
    airTempC: -6.0,
    speedKmh: 25,
  ),
  // partial: ONLY speed changes — the ice/whiteout signals are NOT re-sent.
  // Carry-forward HOLDS them, so the assessment STILL reports black ice. This
  // is the load-bearing safety property of the partial-frame rail, made visible.
  VehicleConditionSignals(speedKmh: 20),
  // partial: still crawling through the whiteout; hazard persists.
  VehicleConditionSignals(speedKmh: 18),

  // ── Phase 4 · CLEARING ───────────────────────────────────────────────────
  // The squall eases: ESC friction recovers above the icy threshold, TCS
  // disengages, snowfall drops to light and the air warms toward freezing →
  // ice cleared, but a slushy cold road remains.
  VehicleConditionSignals(
    roadFriction: 0.55,
    tcsEngaged: false,
    wiperIntensity: 2,
    rainIntensity: 20,
    airTempC: -2.0,
    speedKmh: 35,
  ),
  // partial: snowfall keeps easing and the air keeps warming; grip held.
  VehicleConditionSignals(
    wiperIntensity: 1,
    rainIntensity: 10,
    airTempC: -1.0,
    speedKmh: 40,
  ),

  // ── Phase 5 · WET ────────────────────────────────────────────────────────
  // Past the front: air rises above freezing so the precipitation is now rain,
  // grip is good, the road is merely wet from the melt.
  VehicleConditionSignals(
    roadFriction: 0.85,
    wiperIntensity: 2,
    rainIntensity: 25,
    airTempC: 3.0,
    speedKmh: 50,
  ),
  // partial: warming further, conditions steady → still wet.
  VehicleConditionSignals(airTempC: 4.0, speedKmh: 55),
  // partial: cruising on a clear wet road; nothing hazardous left.
  VehicleConditionSignals(speedKmh: 60),
];

/// SYNTHETIC — a short drive that hits a localized black-ice patch via the
/// **cold-slip TCS rule** (traction lost on a cold road even though the ESC
/// friction estimate still reads normal), then recovers. ILLUSTRATIVE
/// hand-authored values, **not** recorded sensor data.
///
/// Complements [akitaWhiteoutDrive]: that one triggers ice via low friction;
/// this one triggers it via `(tcsEngaged && airTempC <= kColdSlipCelsius)`, the
/// other published ice-risk path. Progression: **dry → black ice → dry**.
/// Drive through [VehicleConditionFusion.fromPartialFrames].
const blackIcePatch = <VehicleConditionSignals>[
  // Dry, fast, good grip — a clear cold road.
  VehicleConditionSignals(
    roadFriction: 0.90,
    tcsEngaged: false,
    absEngaged: false,
    wiperIntensity: 0,
    rainIntensity: 0,
    airTempC: -1.0,
    speedKmh: 60,
  ),
  VehicleConditionSignals(speedKmh: 58),
  // A glazed patch: TCS fires on a −4 °C surface even though the friction
  // estimate has not yet fallen → cold-slip ice risk.
  VehicleConditionSignals(tcsEngaged: true, airTempC: -4.0, speedKmh: 40),
  // partial: speed only — TCS/cold held, hazard persists.
  VehicleConditionSignals(speedKmh: 35),
  // Past the patch: traction restored, TCS releases, road is dry again.
  VehicleConditionSignals(tcsEngaged: false, airTempC: -2.0, speedKmh: 45),
  VehicleConditionSignals(speedKmh: 50),
];

/// SYNTHETIC — a benign, low-hazard drive (a mild rain shower on a warm road,
/// then dry). ILLUSTRATIVE hand-authored values, **not** recorded sensor data.
///
/// A sanity / contrast trace: no ice is ever asserted. Progression:
/// **dry → wet → dry**. Drive through [VehicleConditionFusion.fromPartialFrames].
const clearRoad = <VehicleConditionSignals>[
  // Warm, dry, good grip.
  VehicleConditionSignals(
    roadFriction: 0.98,
    tcsEngaged: false,
    absEngaged: false,
    wiperIntensity: 0,
    rainIntensity: 0,
    airTempC: 8.0,
    speedKmh: 60,
  ),
  // A light, warm rain shower — wet, no ice.
  VehicleConditionSignals(wiperIntensity: 2, rainIntensity: 20, speedKmh: 55),
  VehicleConditionSignals(speedKmh: 50),
  // Shower passes — dry again.
  VehicleConditionSignals(wiperIntensity: 0, rainIntensity: 0, speedKmh: 60),
  VehicleConditionSignals(speedKmh: 62),
];
