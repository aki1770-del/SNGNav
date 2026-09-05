/// KUKSA end-to-end proof against a REAL local databroker.
///
/// This is the "real-databroker e2e" rung: it does NOT inject a mock stream.
/// It connects [KuksaConditionProvider.connect] to a live `kuksa-databroker`
/// over real gRPC (kuksa.val.v2), publishes real snow-safety VSS signals from a
/// SEPARATE publisher client, and asserts that the deterministic fusion drives
/// the SAME `DrivingConditionAssessment` the 3D Snow Scene consumes — then kills
/// the broker and asserts the honest-degradation `unavailable` marker fires on a
/// real broker drop (never a fabricated condition).
///
/// Usage:
///   `dart run tool/kuksa_e2e/kuksa_e2e.dart <host> <port> <brokerHandle>`
///
/// `brokerHandle` selects how PHASE 3 drops the real broker:
///   * `pid:N`    — send SIGTERM to native databroker process N
///   * any other  — `docker stop brokerHandle` (containerised broker)
///
/// Exit 0 = all phases passed; exit 1 = a phase failed (with the actual decoded
/// values printed so the failure is measured at the source, not narrated).
library;

import 'dart:async';
import 'dart:io';

import 'package:driving_conditions/driving_conditions.dart';
import 'package:kuksa_dart_sdk/kuksa_dart_sdk.dart';
import 'package:sngnav_snow_scene/providers/kuksa_condition_provider.dart';

int _failures = 0;

void _check(bool ok, String label, {Object? got}) {
  final tag = ok ? 'PASS' : 'FAIL';
  stdout.writeln('  [$tag] $label${got != null ? '  (got: $got)' : ''}');
  if (!ok) _failures++;
}

Future<void> main(List<String> args) async {
  final host = args.isNotEmpty ? args[0] : '127.0.0.1';
  final port = args.length > 1 ? int.parse(args[1]) : 55555;
  final container = args.length > 2 ? args[2] : 'kuksa-e2e';

  stdout.writeln('KUKSA e2e — host=$host port=$port container=$container');

  // --- Provider under test: wired to the REAL broker via connect() ---------
  final providerClient = KuksaClient(host: host, port: port);
  final provider = await KuksaConditionProvider.connect(providerClient);

  // Collect every emission so assertions read actual live state.
  KuksaConditionUpdate? last;
  final emissions = <KuksaConditionUpdate>[];
  final sub = provider.conditions.listen((u) {
    last = u;
    emissions.add(u);
  });

  // --- Separate publisher client (the "vehicle bus" side) -------------------
  final pub = KuksaClient(host: host, port: port);
  await pub.connect();

  // Wait until an emission satisfies [pred], or time out.
  Future<bool> waitFor(bool Function(KuksaConditionUpdate u) pred,
      {Duration timeout = const Duration(seconds: 12)}) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (last != null && pred(last!)) return true;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return false;
  }

  // Pump a few distinct speed values so the HysteresisFilter (threshold 2)
  // accumulates the new surface state and the assessment converges.
  Future<void> pump(double base) async {
    for (var i = 0; i < 3; i++) {
      await pub.publishValue(kVehicleSpeed, base + i);
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
  }

  // ========================================================================
  // PHASE 1 — severe: low friction + TCS + sub-zero + heavy wiper → black ice
  // ========================================================================
  stdout.writeln('\nPHASE 1 — severe winter (worst-case bus picture)');
  await pub.publishValue(kRoadFrictionMostProbable, 18.0); // percent, not 0.18
  await pub.publishValue(kTcsIsEngaged, true);
  await pub.publishValue(kAbsIsEngaged, false);
  await pub.publishValue(kWiperFrontIntensity, 5);
  await pub.publishValue(kRaindetectionIntensity, 80);
  await pub.publishValue(kAirTemperature, -6.0);
  await pump(40.0);

  final sawSevere = await waitFor((u) =>
      u.live &&
      u.assessment?.surfaceState == RoadSurfaceState.blackIce &&
      u.signals?.roadFriction != null &&
      u.signals!.roadFriction! < 0.3);
  _check(sawSevere, 'live black-ice assessment from real broker signals',
      got: last == null
          ? 'no emission'
          : 'live=${last!.live} surface=${last!.assessment?.surfaceState} '
              'friction=${last!.signals?.roadFriction} '
              'tcs=${last!.signals?.tcsEngaged} temp=${last!.signals?.airTempC}');
  _check(last?.assessment?.advisoryMessage.toLowerCase().contains('ice') ?? false,
      'advisory mentions ice', got: last?.assessment?.advisoryMessage);

  // ========================================================================
  // PHASE 2 — clear: high friction, no precip, warm → dry (assessment flips)
  // ========================================================================
  stdout.writeln('\nPHASE 2 — clear (assessment must flip off black ice)');
  await pub.publishValue(kRoadFrictionMostProbable, 92.0); // percent, not 0.92
  await pub.publishValue(kTcsIsEngaged, false);
  await pub.publishValue(kAbsIsEngaged, false);
  await pub.publishValue(kWiperFrontIntensity, 0);
  await pub.publishValue(kRaindetectionIntensity, 0);
  await pub.publishValue(kAirTemperature, 12.0);
  await pump(50.0);

  final sawClear = await waitFor((u) =>
      u.live && u.assessment?.surfaceState == RoadSurfaceState.dry);
  _check(sawClear, 'assessment flipped to dry on clear signals',
      got: last == null
          ? 'no emission'
          : 'surface=${last!.assessment?.surfaceState} '
              'friction=${last!.signals?.roadFriction} temp=${last!.signals?.airTempC}');

  // ========================================================================
  // PHASE 3 — honest degradation: kill the REAL broker → unavailable marker
  // ========================================================================
  stdout.writeln('\nPHASE 3 — kill broker → honest unavailable (no fabrication)');
  final emissionsBefore = emissions.length;
  final ProcessResult stopRes;
  if (container.startsWith('pid:')) {
    final pid = container.substring(4);
    stopRes = await Process.run('kill', ['-TERM', pid]);
    stdout.writeln('  kill -TERM $pid exit=${stopRes.exitCode} '
        '${stopRes.stderr.toString().trim()}');
  } else {
    stopRes = await Process.run('docker', ['stop', container]);
    stdout.writeln('  docker stop exit=${stopRes.exitCode} '
        '${stopRes.stdout.toString().trim()}${stopRes.stderr.toString().trim()}');
  }

  final sawUnavailable = await waitFor(
      (u) => !u.live && u.assessment == null,
      timeout: const Duration(seconds: 15));
  _check(sawUnavailable, 'unavailable marker emitted on real broker drop',
      got: last == null
          ? 'no emission'
          : 'live=${last!.live} assessment=${last!.assessment} '
              'reason=${last!.unavailableReason}');
  _check(emissions.length > emissionsBefore,
      'a new (degradation) emission actually arrived',
      got: 'before=$emissionsBefore after=${emissions.length}');

  // --- cleanup --------------------------------------------------------------
  await sub.cancel();
  await provider.dispose();

  stdout.writeln(
      '\n==== ${_failures == 0 ? 'ALL PHASES PASSED' : '$_failures CHECK(S) FAILED'} ====');
  exit(_failures == 0 ? 0 : 1);
}
