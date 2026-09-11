/// The live in-vehicle road-condition path — the compound-failure worst case.
///
/// These are the looms that were absent when the defect below reached `main`.
/// Measured 2026-09-11 against a real `kuksa-databroker:0.7.1` whose VSS tree
/// lacked tyre pressure (a trim without TPMS): `connect()` returned OK, the
/// `subscribe` stream then died `NOT_FOUND`, **none** of the ten requested
/// leaves was delivered — and the scene kept rendering a SIMULATED
/// `RoadSurfaceState.blackIce` advisory with a caption that still read
/// "live in-vehicle when KUKSA_HOST set". Zero measurements, one confident
/// hazard on HER screen.
///
/// The app's 1303-test suite was green throughout, because nothing set
/// `KUKSA_HOST` and nothing asserted on the shape of the request.
///
/// NOT covered here, deliberately: signal LIVENESS (a subscription that is
/// alive while every leaf stays silent). That is FSE's lane and FSE's watchdog
/// in `vehicle_condition_fusion`; duplicating it here would be a second loom
/// for one thread.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kuksa_dart_sdk/kuksa_dart_sdk.dart';
// ignore: implementation_imports
import 'package:kuksa_dart_sdk/src/generated/kuksa/val/v2/types.pb.dart' as pb;
import 'package:driving_weather/driving_weather.dart';
import 'package:snow_rendering/snow_rendering.dart';
import 'package:sngnav_snow_scene/providers/kuksa_condition_provider.dart';
import 'package:vehicle_condition_fusion/vehicle_condition_fusion.dart';

Datapoint _f(String p, double v) =>
    Datapoint(raw: pb.Datapoint(value: pb.Value(float: v)), path: p);
Datapoint _b(String p, bool v) =>
    Datapoint(raw: pb.Datapoint(value: pb.Value(bool_12: v)), path: p);

void main() {
  group('the request we actually send', () {
    test('every subscribed leaf is one we can decode, and vice versa', () {
      // `kuksa.val.v2` Subscribe is ALL-OR-NOTHING: one leaf the vehicle lacks
      // and NOTHING is delivered. So every path in the request is a liability.
      // Asking for a leaf we never decode risks all the others for nothing;
      // decoding a leaf we never ask for means a fusion input that can never
      // arrive. The two sets must be the same set.
      final subscribed = kSngnavVehicleConditionSignals.toSet();
      final decodable = VehicleConditionSignals.recognizedVssPaths.toSet();

      expect(
        subscribed.difference(decodable),
        isEmpty,
        reason: 'subscribed but never decoded — dead weight that can kill the '
            'whole all-or-nothing request',
      );
      expect(
        decodable.difference(subscribed),
        isEmpty,
        reason: 'decoded but never subscribed — a fusion input the app can '
            'never receive',
      );
    });

    test('the two frost/slip witnesses are in the request', () {
      // Humidity is the radiative-frost path (frost forming ABOVE freezing),
      // and it LEADS: it fires before the wheels have slipped. ESC-engaged is a
      // third slip witness and it LAGS: it confirms a slip already under way.
      // Both were decodable-but-never-subscribed until 2026-09-11.
      expect(kSngnavVehicleConditionSignals,
          contains(VehicleConditionSignals.vssHumidity));
      expect(kSngnavVehicleConditionSignals,
          contains(VehicleConditionSignals.vssEscEngaged));
    });

    test('the three leaves we never decode are not in the request', () {
      // These are what killed the whole subscription on a trim without TPMS.
      expect(kSngnavVehicleConditionSignals, isNot(contains(kRoadFrictionLowerBound)));
      expect(kSngnavVehicleConditionSignals, isNot(contains(kTirePressureFrontLeft)));
      expect(kSngnavVehicleConditionSignals, isNot(contains(kTirePressureFrontRight)));
    });
  });

  group('no asserted hazard survives a live-data failure', () {
    test('the unmeasured assessment is not a claim about the road', () {
      final a = unmeasuredVehicleAssessment(now: DateTime(2026, 1, 1));
      expect(a.isAssessed, isFalse,
          reason: 'an unmeasured road must not present as an assessed one');
      expect(a.surfaceState, isNull);
      expect(a.recommendedResponse, RecommendedResponse.conditionsUnknown);
    });

    test('the simulated default IS an asserted hazard — the thing we replace',
        () {
      // Guard on the premise. If this ever stops being an asserted hazard the
      // test above is measuring nothing.
      final simulated = DrivingConditionAssessment.fromCondition(
        WeatherCondition(
          precipType: PrecipitationType.snow,
          intensity: PrecipitationIntensity.moderate,
          temperatureCelsius: -3.0,
          visibilityMeters: 600.0,
          windSpeedKmh: 18.0,
          iceRisk: true,
          source: ObservationSource.simulated,
          timestamp: DateTime(2026, 1, 1, 7, 15),
        ),
      );
      expect(simulated.isAssessed, isTrue);
      expect(simulated.surfaceState, RoadSurfaceState.blackIce);
    });
  });

  group('the caption tells the truth about the source', () {
    test('no live source selected: says simulated, keeps the TRUE pointer', () {
      // Two different states reach the old `else`, and only one of them was
      // broken. Here no live source was ever selected, the simulated scenario
      // really IS on the glass, and "live in-vehicle when KUKSA_HOST set" is
      // true and useful advice. Deleting it to fix the OTHER state would have
      // removed correct guidance from the common path.
      final c = vehicleConditionCaption(
        liveVehicleReceived: false,
        liveWeatherReceived: false,
        absentSignals: const <String>[],
        vehicleSourceSelected: false,
      );
      expect(c, contains('simulated default'));
      expect(c, contains('NOT a measurement'));
      expect(c, contains('live in-vehicle when KUKSA_HOST set'),
          reason: 'true advice on this path — do not delete it');
      expect(c, isNot(contains('LIVE in-vehicle VSS signals')),
          reason: 'the CLAIM form must never appear without live signals');
    });

    test('source selected but the vehicle has not spoken: claims nothing', () {
      final c = vehicleConditionCaption(
        liveVehicleReceived: false,
        liveWeatherReceived: false,
        absentSignals: const <String>[],
        vehicleSourceSelected: true,
      );
      expect(c, isNot(contains('LIVE in-vehicle VSS signals')));
      expect(c, isNot(contains('simulated default')),
          reason: 'the simulated scenario was retired the moment a live '
              'vehicle source was selected — the caption must not name it');
    });

    test('names what THIS VEHICLE does not have, without calling it silence',
        () {
      final c = vehicleConditionCaption(
        liveVehicleReceived: true,
        liveWeatherReceived: false,
        absentSignals: const <String>[
          VehicleConditionSignals.vssHumidity,
          VehicleConditionSignals.vssEscEngaged,
        ],
        unavailableReason: null,
      );
      expect(c, contains('2'));
      expect(c, contains('not available on this vehicle'));
      expect(c, contains('Humidity'));
    });

    test('carries the failure reason instead of discarding it', () {
      const reason = 'the databroker does not know 2 of the 9 requested signals';
      final c = vehicleConditionCaption(
        liveVehicleReceived: false,
        liveWeatherReceived: false,
        absentSignals: const <String>[],
        unavailableReason: reason,
      );
      expect(c, contains('does not know'));
      expect(c, contains('UNAVAILABLE'));
      expect(c, contains('not an all-clear'),
          reason: 'an unavailable read is not a clear road');
    });
  });

  group('the diagnostic reaches the caller', () {
    test('stream end after an error does not clobber the specific reason',
        () async {
      // MEASURED 2026-09-11: `_onSourceError` emitted the reason naming the two
      // missing leaves, then `_onSourceDone` emitted "vehicle signal stream
      // ended" one event later and overwrote it. A caller that DID read the
      // reason would have shown the useless one.
      final source = StreamController<Map<String, Datapoint>>();
      final provider = KuksaConditionProvider(updates: source.stream);
      final results = <KuksaConditionUpdate>[];
      final sub = provider.conditions.listen(results.add);

      source.addError(
          'UnknownSignalPathsException: does not know Vehicle.Exterior.Humidity');
      await pumpEventQueue();
      await source.close();
      await pumpEventQueue();

      expect(results.last.unavailableReason, contains('Humidity'),
          reason: 'the last thing the caller sees must still name the cause');

      await sub.cancel();
      await provider.dispose();
    });

    test('absentSignals is what the broker lacks METADATA for, never silence',
        () {
      final p = KuksaConditionProvider(
        updates: const Stream<Map<String, Datapoint>>.empty(),
        absentSignals: const <String>[VehicleConditionSignals.vssHumidity],
      );
      expect(p.absentSignals, hasLength(1));
      expect(() => p.absentSignals.add('x'), throwsUnsupportedError,
          reason: 'the caller must not be able to edit the vehicle inventory');
    });
  });

  group("the Chair's criterion — warn her from the signals that DID arrive",
      () {
    test('a partial frame still produces an actionable warning', () async {
      // The squall case: the vehicle gives us friction, temperature and TCS.
      // Humidity and tyre pressure never arrive. She must still be warned.
      // The governing doctrine is already written at
      // snow_rendering/lib/src/models/road_surface_state.dart:58-63 — positive
      // evidence classifies on partial data; only a BENIGN claim needs
      // complete data. Suppressing here would be the SOTIF failure, not the
      // mitigation.
      final source = StreamController<Map<String, Datapoint>>();
      final provider = KuksaConditionProvider(
        updates: source.stream,
        surfaceFilter: HysteresisFilter<RoadSurfaceState?>(threshold: 1),
      );
      final results = <KuksaConditionUpdate>[];
      final sub = provider.conditions.listen(results.add);

      source.add({
        // 18 % friction — VSS ships this as PERCENT, not a 0..1 fraction.
        VehicleConditionSignals.vssRoadFriction:
            _f(VehicleConditionSignals.vssRoadFriction, 18.0),
        VehicleConditionSignals.vssAirTemperature:
            _f(VehicleConditionSignals.vssAirTemperature, -4.0),
        VehicleConditionSignals.vssTcsEngaged:
            _b(VehicleConditionSignals.vssTcsEngaged, true),
      });
      await pumpEventQueue();

      expect(results, isNotEmpty);
      final update = results.last;
      expect(update.isAvailable, isTrue);
      expect(update.assessment, isNotNull);
      expect(update.assessment!.isAssessed, isTrue,
          reason: 'silence in a squall is also a failure — three witnesses is '
              'enough to speak');
      expect(update.assessment!.recommendedResponse,
          isNot(RecommendedResponse.conditionsUnknown));

      await sub.cancel();
      await provider.dispose();
      await source.close();
    });
  });

  group('the debounce filter cannot be poisoned by a covariant type argument',
      () {
    test('a non-nullable RoadSurfaceState filter is refused at construction',
        () {
      // MEASURED 2026-09-11: `HysteresisFilter<RoadSurfaceState>` is ACCEPTED at
      // compile time (Dart class generics are covariant) and then throws
      //   type 'Null' is not a subtype of type 'RoadSurfaceState' of 'reading'
      // inside `HysteresisFilter.add` the FIRST time the road cannot be
      // classified — the compound-failure frame this whole path exists to
      // survive. Worse, the throw escapes as an uncaught async error: it never
      // becomes an honest `unavailable` update and the listener's `onError`
      // never sees it. The analyzer cannot catch this. This assert can.
      //
      // The same defect was found and fixed in
      // `vehicle_condition_fusion/example/kuksa_databroker.dart:80-88`. The
      // example was fixed; the app provider was not, until now.
      expect(
        () => KuksaConditionProvider(
          updates: const Stream<Map<String, Datapoint>>.empty(),
          surfaceFilter: HysteresisFilter<RoadSurfaceState>(
            windowSize: 1,
            threshold: 1,
          ),
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('an unclassifiable frame does not throw with the correct type arg',
        () async {
      final source = StreamController<Map<String, Datapoint>>();
      final provider = KuksaConditionProvider(
        updates: source.stream,
        surfaceFilter: HysteresisFilter<RoadSurfaceState?>(
          windowSize: 1,
          threshold: 1,
        ),
      );
      final results = <KuksaConditionUpdate>[];
      final sub = provider.conditions.listen(results.add);

      // Real signals that classify to NO surface state.
      source.add({
        VehicleConditionSignals.vssRoadFriction:
            _f(VehicleConditionSignals.vssRoadFriction, 95.0),
        VehicleConditionSignals.vssAirTemperature:
            _f(VehicleConditionSignals.vssAirTemperature, 12.0),
      });
      await pumpEventQueue();

      expect(results, isNotEmpty);
      expect(results.last.assessment?.surfaceState, isNull);
      expect(results.last.assessment?.isAssessed, isFalse,
          reason: 'an unclassifiable road is reported unknown, not clear');

      await sub.cancel();
      await provider.dispose();
      await source.close();
    });
  });
}
