// LIVE demonstration: a real kuksa-databroker 0.7.1, real published VSS values,
// the real app provider, and main.dart's own listener + caption logic verbatim.
// Prints what is on HER screen. Requires a broker on 127.0.0.1:PORT.
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuksa_dart_sdk/kuksa_dart_sdk.dart';
import 'package:driving_weather/driving_weather.dart';
import 'package:snow_rendering/snow_rendering.dart';
import 'package:sngnav_snow_scene/providers/kuksa_condition_provider.dart';
import 'package:vehicle_condition_fusion/vehicle_condition_fusion.dart';

const int kPort = int.fromEnvironment('BROKER_PORT', defaultValue: 55557);
const String kLabel = String.fromEnvironment('VEHICLE', defaultValue: 'vehicle');

void main() {
  test('LIVE: $kLabel on port $kPort', () async {
    // ---- main.dart:188-201, the asserted getting-started default ----
    DrivingConditionAssessment assessment =
        DrivingConditionAssessment.fromCondition(WeatherCondition(
      precipType: PrecipitationType.snow,
      intensity: PrecipitationIntensity.moderate,
      temperatureCelsius: -3.0, visibilityMeters: 600.0, windSpeedKmh: 18.0,
      iceRisk: true, source: ObservationSource.simulated,
      timestamp: DateTime(2026, 1, 1, 7, 15)));
    bool liveVehicleReceived = false, liveWeatherReceived = false;
    String? unavailableReason;
    List<String> absent = const <String>[];

    void dropToFloor() {
      if (liveWeatherReceived && assessment.isAssessed) return;
      assessment = unmeasuredVehicleAssessment();
    }
    String screen() => vehicleConditionCaption(
          liveVehicleReceived: liveVehicleReceived,
          liveWeatherReceived: liveWeatherReceived,
          absentSignals: absent,
          vehicleSourceSelected: true,
          unavailableReason: unavailableReason,
        );

    print('\n== BEFORE (asserted default) ==');
    print('  SCENE   : ${assessment.surfaceState} / "${assessment.advisoryMessage}"');
    print('  isAssessed=${assessment.isAssessed}');

    // ---- main.dart:_initKuksaConditions, verbatim shape ----
    dropToFloor();
    print('\n== OPTED INTO A LIVE VEHICLE SOURCE (before any byte arrives) ==');
    print('  SCENE   : ${assessment.surfaceState} / "${assessment.advisoryMessage}"');
    print('  CAPTION : ${screen()}');

    final client = KuksaClient(host: '127.0.0.1', port: kPort);
    final pub = KuksaClient(host: '127.0.0.1', port: kPort);
    KuksaConditionProvider? provider;
    try {
      provider = await KuksaConditionProvider.connect(client);
      absent = provider.absentSignals;
      provider.conditions.listen((u) {
        if (!u.isAvailable) {
          liveVehicleReceived = false;
          unavailableReason = u.unavailableReason;
          dropToFloor();
          return;
        }
        assessment = u.assessment!;
        liveVehicleReceived = true;
        unavailableReason = null;
      }, onError: (Object e) {
        liveVehicleReceived = false; unavailableReason = e.toString(); dropToFloor();
      }, cancelOnError: false);
    } catch (e) {
      unavailableReason = e.toString(); dropToFloor();
      print('\n== connect() THREW ==\n  $e');
      print('  SCENE   : ${assessment.surfaceState} / "${assessment.advisoryMessage}"');
      print('  CAPTION : ${screen()}');
      await client.dispose();
      return;
    }
    print('\n== SUBSCRIBED ==');
    print('  requested ${kSngnavVehicleConditionSignals.length}, '
        'absent on this vehicle: ${absent.isEmpty ? "(none)" : absent}');

    // ---- the vehicle bus speaks: an unexpected squall, sub-zero, slipping ----
    await pub.connect();
    Future<void> one(String path, Object v) async {
      try {
        await pub.publishValue(path, v);
        print('  published  ${path.split('.').last} = \$v');
      } catch (e) {
        print('  PUBLISH FAILED ${path.split('.').last} = \$v  ->  '
            '${e.toString().split(',').take(2).join(',')}');
      }
    }
    Future<void> publishSquall() async {
      await one(VehicleConditionSignals.vssRoadFriction, 18.0); // percent
      await one(VehicleConditionSignals.vssAirTemperature, -6.0);
      await one(VehicleConditionSignals.vssTcsEngaged, true);
      await one(VehicleConditionSignals.vssAbsEngaged, false);
      await one(VehicleConditionSignals.vssEscEngaged, true);
      await one(VehicleConditionSignals.vssWiperIntensity, 5);
      await one(VehicleConditionSignals.vssRainIntensity, 80);
      for (var i = 0; i < 4; i++) {
        await one(VehicleConditionSignals.vssSpeed, 40.0 + i);
        await Future<void>.delayed(const Duration(milliseconds: 180));
      }
    }
    await publishSquall();
    await Future<void>.delayed(const Duration(seconds: 2));

    print('\n== WHAT IS ON HER SCREEN, from the vehicle\'s own signals ==');
    print('  SCENE   : ${assessment.surfaceState}');
    print('  ADVISORY: "${assessment.advisoryMessage}"');
    print('  RESPONSE: ${assessment.recommendedResponse}');
    print('  isAssessed=${assessment.isAssessed}  liveVehicleReceived=$liveVehicleReceived');
    print('  CAPTION : ${screen()}');

    await provider.dispose();
    await client.dispose();
    await pub.dispose();
  }, timeout: const Timeout(Duration(seconds: 90)));
}
