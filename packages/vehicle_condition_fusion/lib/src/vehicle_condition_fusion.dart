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
    HysteresisFilter<RoadSurfaceState?>? surfaceFilter,
    DateTime Function()? clock,
    Duration maxFrameSilence = kMaxFrameSilence,
    Duration maxOptimisticFieldAge = kMaxOptimisticSignalAge,
    Duration maxPessimisticFieldAge = kMaxPessimisticSignalAge,
    Duration? watchdogInterval,
  }) : this._(
          maxFrameSilence: maxFrameSilence,
          maxOptimisticFieldAge: maxOptimisticFieldAge,
          maxPessimisticFieldAge: maxPessimisticFieldAge,
          watchdogInterval: watchdogInterval,
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
    HysteresisFilter<RoadSurfaceState?>? surfaceFilter,
    DateTime Function()? clock,
    Duration maxFrameSilence = kMaxFrameSilence,
    Duration maxOptimisticFieldAge = kMaxOptimisticSignalAge,
    Duration maxPessimisticFieldAge = kMaxPessimisticSignalAge,
    Duration? watchdogInterval,
  }) : this._(
          maxFrameSilence: maxFrameSilence,
          maxOptimisticFieldAge: maxOptimisticFieldAge,
          maxPessimisticFieldAge: maxPessimisticFieldAge,
          watchdogInterval: watchdogInterval,
          frames: partialFrames,
          mergePartialFrames: true,
          surfaceFilter: surfaceFilter,
          clock: clock,
        );

  VehicleConditionFusion._({
    required Stream<VehicleConditionSignals> frames,
    required bool mergePartialFrames,
    required Duration maxFrameSilence,
    required Duration maxOptimisticFieldAge,
    required Duration maxPessimisticFieldAge,
    Duration? watchdogInterval,
    HysteresisFilter<RoadSurfaceState?>? surfaceFilter,
    DateTime Function()? clock,
  })  : _mergePartialFrames = mergePartialFrames,
        _maxFrameSilence = maxFrameSilence,
        _maxOptimisticFieldAge = maxOptimisticFieldAge,
        _maxPessimisticFieldAge = maxPessimisticFieldAge,
        _surfaceFilter = surfaceFilter ?? HysteresisFilter<RoadSurfaceState?>(),
        _clock = clock ?? DateTime.now {
    _lastFrameAt = _clock();
    final tick = watchdogInterval ?? maxFrameSilence;
    if (tick > Duration.zero) {
      _watchdog = Timer.periodic(tick, (_) => checkLiveness());
    }
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
  final HysteresisFilter<RoadSurfaceState?> _surfaceFilter;
  final DateTime Function() _clock;
  final StreamController<VehicleConditionUpdate> _controller =
      StreamController<VehicleConditionUpdate>.broadcast();

  /// Running merged snapshot for the partial-frame rail. Empty until the first
  /// frame; unused (and never mutated) on the complete-snapshot rail.
  VehicleConditionSignals _running = const VehicleConditionSignals();

  StreamSubscription<VehicleConditionSignals>? _sub;
  DrivingConditionAssessment? _lastAssessment;
  final Duration _maxFrameSilence;
  final Duration _maxOptimisticFieldAge;
  final Duration _maxPessimisticFieldAge;
  Timer? _watchdog;

  /// When each signal was last actually SENT by the vehicle (partial rail).
  final Map<String, DateTime> _observedAt = {};

  /// When the newest frame of any kind arrived; seeded at construction so a
  /// transport that connects and then says nothing still trips the watchdog.
  late DateTime _lastFrameAt;

  /// Whether a real, classification-relevant picture has ever been emitted.
  /// Distinguishes "nothing yet" (stay silent) from "it aged out" (say so).
  bool _hadSignal = false;

  /// Whether the current quiet spell has already been announced.
  bool _quietAnnounced = false;

  /// Starts FALSE. A processor that has never received a signal is not live,
  /// and saying otherwise is a liveness claim with no evidence behind it.
  bool _available = false;

  /// The fused condition stream.
  Stream<VehicleConditionUpdate> get conditions => _controller.stream;

  /// Whether the most recent activity indicates live signals are flowing.
  bool get available => _available;

  /// Resolves the incoming frame to a complete snapshot per the active rail,
  /// then hands it to the shared [_process] pipeline.
  void _onFrame(VehicleConditionSignals frame) {
    final now = _clock();
    _lastFrameAt = now;
    _quietAnnounced = false;
    if (_mergePartialFrames) {
      // Partial-frame rail: carry forward last-known values into a running
      // complete picture so a once-seen ice signal is not dropped.
      _stampObserved(frame, now);
      _running = frame.carriedForwardOnto(_running);
      // ...but a carried-forward value is not timeless. Expire each field at
      // the bound its own direction earns, BEFORE it reaches the classifier.
      _process(expireStaleSignals(
        _running,
        observedAt: _observedAt,
        now: now,
        maxOptimisticAge: _maxOptimisticFieldAge,
        maxPessimisticAge: _maxPessimisticFieldAge,
      ));
    } else {
      // Complete-snapshot rail: take the frame as a full picture, as-is.
      _process(frame);
    }
  }

  /// The shared fusion pipeline — identical for both rails. [signals] is the
  /// complete snapshot to classify (already merged on the partial-frame rail).
  void _process(VehicleConditionSignals signals) {
    if (!signals.hasAnySignal) {
      // Nothing real YET — do NOT fabricate a condition, and do not announce
      // an absence nobody was relying on.
      if (!_hadSignal) return;
      // But this is different: we HAD a picture and every classification-
      // relevant signal in it has now expired. Falling silent here would leave
      // the caller holding the stale assessment forever — the expiry would be
      // real internally and invisible to her. Knowledge lost is news.
      _hadSignal = false;
      if (!_available) return;
      _available = false;
      if (!_controller.isClosed) {
        _controller.add(const VehicleConditionUpdate.unavailable(
          reason: 'vehicle signals aged out',
        ));
      }
      return;
    }

    _available = true;
    _hadSignal = true;
    final weather =
        vehicleSignalsToWeatherCondition(signals, timestamp: _clock());
    final candidate = DrivingConditionAssessment.fromCondition(weather);

    // Debounce the road-surface picture with the existing HysteresisFilter:
    // hold the last-good assessment until a new surface state persists
    // (threshold readings), so the scene does not flicker at boundaries.
    final stable = _surfaceFilter.add(candidate.surfaceState);
    // LOSS OF KNOWLEDGE IS NOT FLICKER. The debounce (window 3, threshold 2)
    // exists to stop the scene oscillating between two CLASSIFICATIONS. An
    // expired or absent signal is not a classification — it is the honest
    // floor, and holding the previous confident surface for two more frames
    // while we no longer know is precisely the stale all-clear this rail
    // exists to stop. Unknown is taken immediately, downgrade-first.
    if (_lastAssessment == null ||
        candidate.surfaceState == null ||
        stable == candidate.surfaceState) {
      _lastAssessment = candidate;
    }

    if (!_controller.isClosed) {
      _controller.add(VehicleConditionUpdate(
        assessment: _lastAssessment,
        signals: signals,
        live: true,
        observedAt: _lastFrameAt,
        fieldObservedAt: Map.unmodifiable(_observedAt),
      ));
    }
  }

  /// Records the arrival time of every field this frame actually carried.
  void _stampObserved(VehicleConditionSignals f, DateTime now) {
    void mark(Object? v, String field) {
      if (v != null) _observedAt[field] = now;
    }

    mark(f.roadFriction, VehicleSignalField.roadFriction);
    mark(f.tcsEngaged, VehicleSignalField.tcsEngaged);
    mark(f.absEngaged, VehicleSignalField.absEngaged);
    mark(f.escEngaged, VehicleSignalField.escEngaged);
    mark(f.airTempC, VehicleSignalField.airTempC);
    mark(f.humidityRH, VehicleSignalField.humidityRH);
    mark(f.speedKmh, VehicleSignalField.speedKmh);
    mark(f.wiperIntensity, VehicleSignalField.wiperIntensity);
    mark(f.rainIntensity, VehicleSignalField.rainIntensity);
  }

  /// Fails the liveness claim when the transport has gone quiet.
  ///
  /// The degradation this closes produces NO error and NO stream end: the gRPC
  /// stream stays open and simply stops delivering. Nothing else in this class
  /// can observe that, because nothing arrives to observe. Driven by an
  /// internal watchdog in production; call it directly to test deterministically
  /// against an injected clock.
  void checkLiveness() {
    if (_clock().difference(_lastFrameAt) <= _maxFrameSilence) return;
    // Announce once per quiet spell. This fires even if no frame EVER arrived:
    // "connected, and the bus is saying nothing" is a different fact from
    // "no source configured", and the caller can only act on the difference if
    // we say it out loud.
    if (_quietAnnounced) return;
    _quietAnnounced = true;
    _available = false;
    if (!_controller.isClosed) {
      _controller.add(const VehicleConditionUpdate.unavailable(
        reason: 'vehicle signal stream went quiet',
      ));
    }
  }

  void _onSourceError(Object error, StackTrace stackTrace) {
    // Honest degradation: a source drop / stream error NEVER fabricates a
    // condition — surface unavailability so the caller keeps its offline
    // default. Holds on both rails.
    _available = false;
    if (!_controller.isClosed) {
      _controller
          .add(VehicleConditionUpdate.unavailable(reason: error.toString()));
    }
  }

  void _onSourceDone() {
    _available = false;
    if (!_controller.isClosed) {
      _controller.add(const VehicleConditionUpdate.unavailable(
        reason: 'vehicle signal stream ended',
      ));
    }
  }

  /// Releases the source subscription and closes the output stream.
  Future<void> dispose() async {
    _watchdog?.cancel();
    _watchdog = null;
    await _sub?.cancel();
    _sub = null;
    if (!_controller.isClosed) await _controller.close();
  }
}
