import 'dart:async';

import 'package:driving_conditions/driving_conditions.dart';

import 'vehicle_condition_signals.dart';
import 'vehicle_condition_update.dart';
import 'vehicle_signal_fusion.dart';

/// Fuses a stream of in-vehicle signal snapshots into a deterministically
/// classified, debounced, honestly-degrading [VehicleConditionUpdate] stream.
///
/// ## Two source rails — pick by your transport's framing semantics
///
/// The input is `Stream<VehicleConditionSignals>` — typed snapshots, NOT raw
/// `Map<String, Datapoint>` frames — so this package stays completely free of
/// any databroker / protobuf / gRPC dependency. There are two constructors,
/// differing ONLY in how a `null` field on a later frame is interpreted:
///
///  * [VehicleConditionFusion] (default) — every snapshot is a COMPLETE
///    picture; a `null` field means "this signal is genuinely unknown right
///    now". Use this for a CAN reader, a sensor-fusion source, or a test —
///    any source where nulling a field is a real statement that the signal is
///    no longer valid. It does NO carry-forward, so it never stale-over-warns.
///
///  * [VehicleConditionFusion.fromPartialFrames] — for a PARTIAL-frame
///    transport that re-sends only the signals that changed (the
///    documented-primary KUKSA `subscribe` path). It maintains a running merged
///    snapshot, carrying forward the last-known value of any field a frame did
///    not re-send (see [VehicleConditionSignals.carriedForwardOnto]), then runs
///    the identical fusion pipeline on the merged snapshot. Use this for a
///    KUKSA adapter.
///
/// ## SAFETY: why the rail is load-bearing
///
/// On the KUKSA `subscribe` path, a later frame re-sends ONLY the signals that
/// changed. If such partial frames are fed to the *default* constructor, the
/// ice-risk signals (`roadFriction`, `tcsEngaged` / `absEngaged`) drop to
/// `null` the moment they rotate out of a frame — and because this processor
/// honestly refuses to fabricate from a missing signal, it would then **fail
/// toward NO ice warning while a real ice hazard persists** (intermittently as
/// signals flicker, or sustainedly if an ice signal stops re-firing). That is
/// the driver-dangerous direction: the snapshot looks safe precisely when the
/// road is not. [VehicleConditionFusion.fromPartialFrames] closes that gap by
/// carrying the last-known value forward, so a once-seen ice signal persists
/// across later partial frames.
///
/// Conversely, feeding complete snapshots — where a `null` means "now
/// unknown" — to `fromPartialFrames` would carry a stale ice signal forward and
/// **over-warn** on data the source has explicitly retracted: the opposite
/// divergence. The two rails exist so the carry-forward decision is made where
/// the transport's framing semantics are actually known.
///
/// ## Determinism
///
/// The fusion is a pure, total function of the snapshot (see
/// [vehicleSignalsToWeatherCondition]) handed to the existing
/// [DrivingConditionAssessment.fromCondition] classifier — no LLM, no prose, no
/// ad-hoc heuristic. Surface-state flicker is debounced with the existing
/// [HysteresisFilter]. Both rails share this identical pipeline.
///
/// ## Honest degradation (no fabrication)
///
/// A snapshot with no real signal ([VehicleConditionSignals.hasAnySignal] ==
/// false) is NEVER fused into a fabricated condition — it is simply not
/// emitted. If the source stream errors or ends, the processor emits a
/// [VehicleConditionUpdate.unavailable] marker (so the caller can keep its
/// last-good / offline-first default and stop claiming "live") and never
/// throws. This holds identically on BOTH rails. Reads only; this processor
/// never writes to or commands the vehicle.
class VehicleConditionFusion {
  /// Primary, injectable constructor for **complete** snapshots. Each
  /// [signals] event is treated as a full picture: a `null` field means the
  /// signal is genuinely unknown right now, never "unchanged" — so NO
  /// carry-forward is performed and a retracted signal cannot stale-over-warn.
  /// Use this for a CAN reader, a sensor-fusion source, or tests.
  VehicleConditionFusion({
    required Stream<VehicleConditionSignals> signals,
    HysteresisFilter<RoadSurfaceState>? surfaceFilter,
    DateTime Function()? clock,
  }) : this._(
         frames: signals,
         mergePartialFrames: false,
         surfaceFilter: surfaceFilter,
         clock: clock,
       );

  /// Constructor for a **partial-frame** transport (e.g. KUKSA `subscribe`,
  /// which re-sends only the signals that changed after the first cycle).
  ///
  /// Maintains a running merged snapshot — starting empty and folding each
  /// incoming [partialFrames] event via
  /// [VehicleConditionSignals.carriedForwardOnto] — then runs the identical
  /// fusion pipeline on the merged snapshot. This restores the
  /// last-known-value (auto carry-forward) behaviour the KUKSA path requires,
  /// so a once-seen ice signal is held across later partial frames and the
  /// processor does NOT under-warn while a real ice hazard persists.
  VehicleConditionFusion.fromPartialFrames({
    required Stream<VehicleConditionSignals> partialFrames,
    HysteresisFilter<RoadSurfaceState>? surfaceFilter,
    DateTime Function()? clock,
  }) : this._(
         frames: partialFrames,
         mergePartialFrames: true,
         surfaceFilter: surfaceFilter,
         clock: clock,
       );

  VehicleConditionFusion._({
    required Stream<VehicleConditionSignals> frames,
    required bool mergePartialFrames,
    HysteresisFilter<RoadSurfaceState>? surfaceFilter,
    DateTime Function()? clock,
  }) : _mergePartialFrames = mergePartialFrames,
       _surfaceFilter = surfaceFilter ?? HysteresisFilter<RoadSurfaceState>(),
       _clock = clock ?? DateTime.now {
    _sub = frames.listen(
      _onFrame,
      onError: _onSourceError,
      onDone: _onSourceDone,
      cancelOnError: false,
    );
  }

  /// When true, each incoming frame is a partial frame folded into [_running]
  /// (carry-forward); when false, each frame is a complete snapshot used as-is.
  final bool _mergePartialFrames;
  final HysteresisFilter<RoadSurfaceState> _surfaceFilter;
  final DateTime Function() _clock;
  final StreamController<VehicleConditionUpdate> _controller =
      StreamController<VehicleConditionUpdate>.broadcast();

  /// Running merged snapshot for the partial-frame rail. Empty until the first
  /// frame; unused (and never mutated) on the complete-snapshot rail.
  VehicleConditionSignals _running = const VehicleConditionSignals();

  StreamSubscription<VehicleConditionSignals>? _sub;
  DrivingConditionAssessment? _lastAssessment;
  bool _available = true;

  /// The fused condition stream.
  Stream<VehicleConditionUpdate> get conditions => _controller.stream;

  /// Whether the most recent activity indicates live signals are flowing.
  bool get available => _available;

  /// Resolves the incoming frame to a complete snapshot per the active rail,
  /// then hands it to the shared [_process] pipeline.
  void _onFrame(VehicleConditionSignals frame) {
    if (_mergePartialFrames) {
      // Partial-frame rail: carry forward last-known values into a running
      // complete picture so a once-seen ice signal is not dropped.
      _running = frame.carriedForwardOnto(_running);
      _process(_running);
    } else {
      // Complete-snapshot rail: take the frame as a full picture, as-is.
      _process(frame);
    }
  }

  /// The shared fusion pipeline — identical for both rails. [signals] is the
  /// complete snapshot to classify (already merged on the partial-frame rail).
  void _process(VehicleConditionSignals signals) {
    // Nothing real yet — do NOT fabricate a condition.
    if (!signals.hasAnySignal) return;

    _available = true;
    final weather = vehicleSignalsToWeatherConditionOrNull(
      signals,
      timestamp: _clock(),
    );

    // The signals are real and flowing, but they cannot support a verdict: no
    // hazard is asserted and the ambient temperature — which every remaining
    // branch of the classifier reads — was never measured. Emit the honest
    // abstention rather than "Conditions normal" at full grip. It carries the
    // signals (so the caller can still show what the vehicle DID publish) and
    // the reason, and it is deliberately NOT an alarm: it cannot cry wolf.
    if (weather == null) {
      if (!_controller.isClosed) {
        _controller.add(
          VehicleConditionUpdate(
            assessment: null,
            signals: signals,
            live: false,
            unavailableReason: kUnmeasuredTemperatureReason,
          ),
        );
      }
      return;
    }

    final candidate = DrivingConditionAssessment.fromCondition(weather);

    // Debounce the road-surface picture with the existing HysteresisFilter:
    // hold the last-good assessment until a new surface state persists
    // (threshold readings), so the scene does not flicker at boundaries.
    final stable = _surfaceFilter.add(candidate.surfaceState);
    if (_lastAssessment == null || stable == candidate.surfaceState) {
      _lastAssessment = candidate;
    }

    if (!_controller.isClosed) {
      _controller.add(
        VehicleConditionUpdate(
          assessment: _lastAssessment,
          signals: signals,
          live: true,
        ),
      );
    }
  }

  void _onSourceError(Object error, StackTrace stackTrace) {
    // Honest degradation: a source drop / stream error NEVER fabricates a
    // condition — surface unavailability so the caller keeps its offline
    // default. Holds on both rails.
    _available = false;
    if (!_controller.isClosed) {
      _controller.add(
        VehicleConditionUpdate.unavailable(reason: error.toString()),
      );
    }
  }

  void _onSourceDone() {
    _available = false;
    if (!_controller.isClosed) {
      _controller.add(
        const VehicleConditionUpdate.unavailable(
          reason: 'vehicle signal stream ended',
        ),
      );
    }
  }

  /// Releases the source subscription and closes the output stream.
  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
    if (!_controller.isClosed) await _controller.close();
  }
}
