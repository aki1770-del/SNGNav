/// Emit-only telemetry stream for fired / dropped / critical-bypass /
/// cold-start alert outcomes, paired with the per-profile context the
/// outcome occurred under.
///
/// Why this exists (literature anchors):
///
/// The throttle's job is to prevent advisory-tier desensitization
/// (PMC12181921 medical alarm-fatigue + AAA-FTS ADAS-exposure /
/// driver-workload + arxiv 2410.06388 silent over-warning failure).
/// The cap defaults are literature-anchored DEFAULTS, not population-
/// validated invariants. To know whether a per-profile cap actually
/// fits the driver-class it's nominally tuned for, the consuming
/// application needs to observe the firing decisions in operation:
/// how often does the throttle drop an advisory? do critical-bypass
/// firings cluster? do cold-start firings dominate the early-session
/// window? — these are calibration-class questions only the integrator
/// has the data to answer.
///
/// `LoomFitTelemetry` is the package-boundary surface for emitting
/// those observations. It is **emit-only**: the package observes its
/// own firing decisions and surfaces them on a broadcast stream; it
/// does NOT classify "fit" vs "misfit" itself, does NOT enact any
/// policy change in response, and does NOT harvest driver-identity
/// data. Detection logic — if any consuming app wants it — lives in
/// the consuming app's analytics layer, where the integrator owns
/// the privacy-class boundary, the consent surface, and the threshold
/// for "the loom does not fit this driver-class."
///
/// **Schema** (per the Bian et al. PubMed 38669900 "alert-magnitude ×
/// duration as one product" frame, expanded for per-profile context):
///
/// - `profileClass` — the active `DriverProfile`. Necessary for any
///   per-profile fit analysis; without it, drop-rate is an aggregate
///   that cannot be calibrated against the per-class baseline.
/// - `ambientThreshold` — caller-supplied identifier of the active
///   threshold context (e.g. `"icy_road_30km"`). Nullable; when no
///   specific threshold is associated with the alert (e.g. fleet-class
///   advisories), pass null.
/// - `alertSequence` — rolling-window timestamps of recent fired
///   alerts at the moment of this record. Captures the in-window
///   density without the analytics consumer having to reconstruct it.
/// - `responseLatency` — optional driver-response latency. Nullable
///   because the package boundary cannot observe driver action; the
///   integrator may supply it from instrumentation downstream of the
///   alert (e.g. brake-application latency from vehicle CAN, or
///   modal-dismissal latency from HMI). When null, the consuming
///   analytics layer treats the record as "outcome-only without
///   latency."
/// - `outcome` — one of `fired`, `droppedByThrottle`, `criticalBypass`,
///   `coldStart`. Disjoint and exhaustive over `shouldFire` decisions.
///
/// **PHIL-001 boundary discipline** (load-bearing):
///
/// - **No driver-grading.** The schema names the OUTCOME of the loom
///   ("did the alert fire?"), not the DRIVER ("did the driver
///   respond?"). When `responseLatency` is supplied, it is information
///   about the loom's fit, not about the driver's competence. The
///   surface this telemetry feeds is the calibration loop that asks
///   *"did the loom fit the operator?"*, not *"did the operator
///   fail?"*.
/// - **No data harvest.** This class instantiates a broadcast
///   `StreamController` and exposes a `Stream` for subscribers. It
///   ships no records anywhere by itself; the integrator who chooses
///   to subscribe owns the storage / aggregation / consent surface.
///   An integrator who never subscribes incurs zero data-flow cost.
/// - **Pure Dart.** No Flutter dependency, no I/O, no platform
///   channels. The integrator's analytics adapter performs any
///   network or persistent-storage work outside the package boundary.
///
/// **Composition pattern**:
///
/// ```dart
/// final throttle = AlertDensityThrottle.forProfile(profile);
/// final telemetry = LoomFitTelemetry();
/// telemetry.records.listen(_consumingAppAnalytics.record);
///
/// // At alert-firing seam:
/// final fired = throttle.shouldFire(now, severity);
/// telemetry.record(LoomFitTelemetryRecord(
///   profileClass: profile,
///   ambientThreshold: thresholdId,
///   alertSequence: throttle.recentFireTimestamps(now),
///   responseLatency: null,
///   outcome: fired
///       ? (severity == AlertSeverity.critical
///             ? LoomFitOutcome.criticalBypass
///             : LoomFitOutcome.fired)
///       : LoomFitOutcome.droppedByThrottle,
/// ));
/// ```
///
/// This is a Pure Dart, advisory-only surface. It does not actuate the
/// vehicle. The class observes the loom; the consuming application
/// owns delivery to any analytics surface and retains full
/// responsibility for the calibration loop the records feed.
library;

import 'dart:async';

import 'driver_profile.dart';

/// Outcome class for a single `shouldFire` decision.
///
/// Disjoint and exhaustive: every `shouldFire` call resolves to exactly
/// one of these four. The integrator's analytics layer aggregates by
/// this enum to compute fit-class metrics (drop-rate, critical-share,
/// cold-start-share).
enum LoomFitOutcome {
  /// Alert fired under the per-profile cap (non-critical, non-coldStart).
  fired,

  /// Alert was dropped by the density throttle (cap exceeded; non-critical).
  droppedByThrottle,

  /// Alert fired via the documented critical-bypass invariant. Tracked
  /// separately from `fired` so the integrator can audit critical-share
  /// (sudden critical-share growth is a calibration-class signal).
  criticalBypass,

  /// First alert in the session bypassed the window check (no
  /// historical context). Tracked separately so cold-start-share can
  /// be excluded from steady-state fit analysis.
  coldStart,
}

/// Single telemetry record for one alert-firing decision.
///
/// Immutable value-object; the consuming analytics layer treats it as
/// a closed observation. No setters; pass a fresh instance per record.
class LoomFitTelemetryRecord {
  /// Active driver profile when the alert-firing decision was made.
  final DriverProfile profileClass;

  /// Caller-supplied identifier of the active threshold context (e.g.
  /// `"icy_road_30km"`, `"black_ice_temp_2c"`, `"visibility_floor_320m"`).
  ///
  /// Nullable; pass null when the alert does not associate with a
  /// specific named threshold (fleet-class advisories, generic
  /// scenario alerts).
  final String? ambientThreshold;

  /// Rolling-window timestamps of recent fired alerts at the moment of
  /// this record. Empty list permitted (early-session, post-purge).
  /// Always a fresh list — caller may safely retain it.
  final List<DateTime> alertSequence;

  /// Optional driver-response latency. The package boundary cannot
  /// observe driver action; the integrator may supply this from
  /// downstream instrumentation. Null when not observed at the
  /// integrator level.
  final Duration? responseLatency;

  /// Outcome class for the firing decision this record describes.
  final LoomFitOutcome outcome;

  /// Construct an immutable telemetry record.
  ///
  /// `alertSequence` is copied defensively so the caller may mutate
  /// the source list without affecting recorded observations.
  LoomFitTelemetryRecord({
    required this.profileClass,
    required this.ambientThreshold,
    required List<DateTime> alertSequence,
    required this.responseLatency,
    required this.outcome,
  }) : alertSequence = List<DateTime>.unmodifiable(alertSequence);
}

/// Emit-only telemetry stream for alert-firing observations.
///
/// Loom Protocol vision attribution (3 slots — see `LOOMS.md` for the
/// cross-reference table and the SPA AI loom-authoring guide for the
/// canonical convention):
///
/// - `sakichi_vision_id: 14` — silent-failure / anti-Jidoka. The
///   failure this loom prevents is *the loom that does not fit the
///   driver-class but cannot be observed to mis-fit*. The throttle
///   defaults are literature-anchored DEFAULTS; without observation,
///   a population mismatch (per-profile cap too sensitive or too
///   permissive for an actual driver-class) stays silent. The
///   telemetry stream is the observation surface that lets the
///   calibration loop ask "did the loom fit?" — and act on the
///   answer.
/// - `method_vision_ids: [77, 99]` — genchi-genbutsu (the records are
///   the gemba of the loom's operation; the schema is structured to
///   make the gemba legible to an analytics layer the integrator
///   owns); write-decision-down (each record IS the recorded
///   observation; the disjoint outcome enum forbids
///   record-without-outcome ambiguity).
/// - `stance_vision_ids: [22, 96, 100]` — loom-serves-weaver (the
///   telemetry is for the calibration loop that protects the driver,
///   not for grading the driver); maintainers-as-edge-developers (the
///   integrator is a weaver too; the emit-only surface respects their
///   ownership of privacy-class / storage-class boundaries);
///   equal-dignity per-profile (records carry the profile so per-class
///   fit can be analyzed; no class is silently aggregated away).
///
/// Subscribers receive every record passed to [record]. Multiple
/// subscribers permitted (broadcast stream). [dispose] closes the
/// stream and releases the controller; subsequent calls to [record]
/// after [dispose] silently no-op.
class LoomFitTelemetry {
  final StreamController<LoomFitTelemetryRecord> _controller =
      StreamController<LoomFitTelemetryRecord>.broadcast();

  /// Broadcast stream of telemetry records. Subscribe to consume.
  ///
  /// Multiple listeners supported. Late subscribers do not see records
  /// emitted before subscription (broadcast semantics). When the
  /// integrator needs replay, the integrator owns that surface in the
  /// analytics layer.
  Stream<LoomFitTelemetryRecord> get records => _controller.stream;

  /// Emit a single telemetry record onto the broadcast stream.
  ///
  /// No-op after [dispose] is called.
  void record(LoomFitTelemetryRecord r) {
    if (_controller.isClosed) return;
    _controller.add(r);
  }

  /// Close the stream controller. Idempotent — subsequent calls
  /// no-op.
  Future<void> dispose() async {
    if (_controller.isClosed) return;
    await _controller.close();
  }
}
