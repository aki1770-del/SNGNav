// THE SEAM. Two lists, two packages, and until now nothing in the tree that
// looked at both.
//
//   SUBSCRIBED : kSnowSafetySignals            (kuksa_dart_sdk)
//   DECODED    : recognizedVssPaths            (vehicle_condition_fusion)
//
// `KuksaConditionProvider.connect` subscribes the first and the decode loop
// iterates the second, so a path in one and not the other is either risk with
// no information behind it, or a decodable hazard limb we never ask for. Each
// half has thorough tests of its own; neither could ever see this.
//
// Measured 2026-09-11 — the divergence this test exists to close:
//   subscribed, never decoded : ESC.RoadFriction.LowerBound
//                               Row1.Wheel.Left.Tire.Pressure
//                               Row1.Wheel.Right.Tire.Pressure
//   decodable, never subscribed: ESC.IsEngaged
//                               Exterior.Humidity
//
// The two tyre-pressure leaves are trim-dependent, and `subscribe` is
// all-or-nothing by default: an ordinary vehicle without per-wheel TPMS loses
// the ENTIRE road-friction subscription over two values the next statement
// would have discarded. Exterior.Humidity is the radiative-frost limb, which
// fires BEFORE any wheel slips.
import 'package:flutter_test/flutter_test.dart';
import 'package:kuksa_dart_sdk/kuksa_dart_sdk.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sngnav_snow_scene/providers/kuksa_condition_provider.dart';
import 'package:vehicle_condition_fusion/vehicle_condition_fusion.dart';

/// Captures the path list the provider actually hands to the databroker.
/// Deliberately tests BEHAVIOUR, not a constant: it goes green whichever way
/// the subscribed set is expressed, so it does not dictate the shape of the fix.
class _CapturingClient extends Fake implements KuksaClient {
  List<String>? subscribed;

  @override
  Future<void> connect() async {}

  @override
  Stream<Map<String, Datapoint>> subscribe(
    List<String> paths, {
    int bufferSize = 0,
    bool skipUnknownPaths = false,
    void Function(List<String> unknownPaths)? onUnknownPaths,
  }) {
    subscribed = paths;
    return const Stream.empty();
  }
}

void main() {
  late _CapturingClient client;
  late List<String> subscribed;

  setUp(() async {
    client = _CapturingClient();
    await KuksaConditionProvider.connect(client);
    subscribed = client.subscribed!;
  });

  group('what the provider ASKS FOR must be what it can READ', () {
    test('every subscribed path is one we can actually decode', () {
      final undecodable = subscribed
          .where((p) => !VehicleConditionSignals.recognizedVssPaths.contains(p))
          .toList();
      expect(undecodable, isEmpty,
          reason: 'these carry 100% of the all-or-nothing subscribe risk and '
              '0% of the information — the decode loop drops them on arrival');
    });

    test('every decodable path is one we actually ask for', () {
      final unsubscribed = VehicleConditionSignals.recognizedVssPaths
          .where((p) => !subscribed.contains(p))
          .toList();
      expect(unsubscribed, isEmpty,
          reason: 'built, tested, and dark at runtime because nothing '
              'subscribes to them');
    });
  });
}
