// A RELEASE-MODE probe for the PositionIntegrityMonitor constructor guards.
//
// WHY THIS FILE EXISTS
// --------------------
// Dart strips `assert` from AOT builds (`dart compile exe`,
// `flutter build --release`) and from plain `dart run`. It keeps them only
// under `dart test` / `flutter test` / Flutter debug. Measured 2026-09-13:
//
//     dart test                        asserts ON
//     dart run file.dart               asserts OFF
//     dart compile exe                 asserts OFF
//     dart compile exe --enable-asserts asserts ON
//
// Every test result this package had ever produced was taken in the one mode
// where assert-based guards are present. The mode a driver's device actually
// runs — AOT, asserts stripped — had no test at all. This file is that missing
// matrix cell: it is COMPILED to a native executable and run, so the guards are
// exercised in the mode that ships.
//
// It is driven by `test/release_mode_guard_test.dart`; it is also runnable by
// hand:
//
//     dart compile exe tool/release_guard_probe.dart -o /tmp/probe && /tmp/probe
//
// Exit codes:  0 = every guard fired and a valid configuration still built
//              1 = a guard did NOT fire in release mode (the defect)
//              2 = the probe cannot prove anything (it was built with asserts
//                  enabled, so a firing guard might only be the assert)

import 'dart:io';

import 'package:position_integrity/position_integrity.dart';

int _checked = 0;
int _failures = 0;

/// Every case below must reject its configuration by THROWING, in a build where
/// `assert` does nothing.
void mustReject(String label, void Function() build) {
  _checked++;
  try {
    build();
    _failures++;
    stdout.writeln('  NOT-REJECTED  $label  <-- guard absent in release mode');
  } on ArgumentError catch (e) {
    // RangeError extends ArgumentError, so both guard styles land here and a
    // consumer has one type to catch.
    stdout.writeln('  rejected      $label  (${e.runtimeType})');
  } on AssertionError {
    _failures++;
    stdout.writeln(
        '  ASSERTION     $label  <-- an assert fired; this build is not '
        'release-representative');
  }
}

/// The negative control. Without it a constructor that threw on EVERYTHING
/// would pass this probe, and the probe would be measuring nothing.
void mustAccept(String label, void Function() build) {
  _checked++;
  try {
    build();
    stdout.writeln('  accepted      $label');
  } catch (e) {
    _failures++;
    stdout
        .writeln('  REJECTED      $label  <-- valid configuration refused: $e');
  }
}

void main() {
  // The instrument checks itself before it reports. If this binary was built
  // with asserts enabled, a guard firing proves nothing about release mode, so
  // the probe refuses to return a verdict rather than returning a green one.
  var assertsEnabled = false;
  assert(() {
    assertsEnabled = true;
    return true;
  }());
  stdout.writeln('asserts_enabled=$assertsEnabled');
  if (assertsEnabled) {
    stdout
        .writeln('PROBE-INVALID: built with asserts ON. This probe only proves '
            'something when asserts are stripped.');
    exit(2);
  }

  stdout.writeln('-- guards that must fire with asserts stripped --');

  // Silently disables the stationary-jitter gate: below 3 the window net
  // displacement equals its single step, so the gate can never fire.
  mustReject(
      'jitterWindow: 1', () => PositionIntegrityMonitor(jitterWindow: 1));
  mustReject(
      'jitterWindow: 2', () => PositionIntegrityMonitor(jitterWindow: 2));

  // Defeats the soft-fault debounce: one acceleration glitch fails outright.
  mustReject('failAfterConsecutiveSoft: 0',
      () => PositionIntegrityMonitor(failAfterConsecutiveSoft: 0));

  // Non-positive thresholds make their gate fire on every fix (permanent
  // false alarm).
  mustReject('maxPlausibleSpeed: 0',
      () => PositionIntegrityMonitor(maxPlausibleSpeed: 0));
  mustReject('maxPlausibleSpeed: -1',
      () => PositionIntegrityMonitor(maxPlausibleSpeed: -1));
  mustReject('maxPlausibleAccel: 0',
      () => PositionIntegrityMonitor(maxPlausibleAccel: 0));
  mustReject('teleportMaxDistanceMetres: 0',
      () => PositionIntegrityMonitor(teleportMaxDistanceMetres: 0));

  // NaN and infinity make their gate fire on NO fix (permanent silence, verdict
  // stays `trusted`). `double.infinity > 0` is true, so the assert this
  // replaced let infinity straight through even in debug.
  mustReject('maxPlausibleSpeed: NaN',
      () => PositionIntegrityMonitor(maxPlausibleSpeed: double.nan));
  mustReject('maxPlausibleSpeed: infinity',
      () => PositionIntegrityMonitor(maxPlausibleSpeed: double.infinity));
  mustReject('maxPlausibleAccel: infinity',
      () => PositionIntegrityMonitor(maxPlausibleAccel: double.infinity));

  // Guards that did not exist before 2026-09-13, in any mode.
  mustReject('stationaryRadiusMetres: 0',
      () => PositionIntegrityMonitor(stationaryRadiusMetres: 0));
  mustReject('jitterAccuracyMultiplier: -1',
      () => PositionIntegrityMonitor(jitterAccuracyMultiplier: -1));
  mustReject('minSpeedDelta: Duration.zero',
      () => PositionIntegrityMonitor(minSpeedDelta: Duration.zero));
  mustReject(
      'deadReckoningMaxAge: -1s',
      () => PositionIntegrityMonitor(
          deadReckoningMaxAge: const Duration(seconds: -1)));

  stdout
      .writeln('-- negative control: valid configuration must still build --');
  mustAccept('defaults', () => PositionIntegrityMonitor());
  mustAccept(
      'explicit valid configuration',
      () => PositionIntegrityMonitor(
            maxPlausibleSpeed: 60,
            maxPlausibleAccel: 9,
            teleportMaxDistanceMetres: 25,
            minSpeedDelta: const Duration(milliseconds: 200),
            deadReckoningMaxAge: const Duration(seconds: 30),
            failAfterConsecutiveSoft: 1,
            jitterWindow: 3,
            stationaryRadiusMetres: 4,
            jitterAccuracyMultiplier: 0,
          ));

  stdout.writeln('checked=$_checked failures=$_failures');
  if (_failures != 0) {
    stdout.writeln('RELEASE-GUARD-PROBE: FAIL');
    exit(1);
  }
  stdout.writeln('RELEASE-GUARD-PROBE: OK');
  exit(0);
}
