/// Safety-calibrated fusion of in-vehicle signals into a driving-condition
/// hazard verdict, with an honest-degradation rail. Pure Dart — no Flutter, no
/// databroker SDK, no protobuf, no gRPC.
///
/// The input seam is [VehicleConditionSignals], a typed snapshot you produce
/// from ANY source (a KUKSA databroker adapter, your own CAN reader, or a
/// test). Drive [VehicleConditionFusion] with a `Stream<VehicleConditionSignals>`
/// and consume a `Stream<VehicleConditionUpdate>` — each update is either a
/// live, deterministically classified [DrivingConditionAssessment] or an
/// honest [VehicleConditionUpdate.unavailable] marker (never a fabricated
/// scene).
///
/// ```dart
/// import 'dart:async';
/// import 'package:vehicle_condition_fusion/vehicle_condition_fusion.dart';
///
/// final source = StreamController<VehicleConditionSignals>();
/// final fusion = VehicleConditionFusion(signals: source.stream);
/// fusion.conditions.listen((u) {
///   if (u.isAvailable) {
///     print(u.assessment!.surfaceState); // e.g. RoadSurfaceState.blackIce
///   } else {
///     print('no live vehicle signals: ${u.unavailableReason}');
///   }
/// });
///
/// // One-line mock — no SDK, no databroker, no protobuf:
/// source.add(const VehicleConditionSignals(roadFriction: 0.2, airTempC: -5));
/// ```
library;

export 'src/vehicle_condition_fusion.dart';
export 'src/vehicle_condition_signals.dart';
export 'src/vehicle_condition_update.dart';
export 'src/vehicle_signal_fusion.dart';
