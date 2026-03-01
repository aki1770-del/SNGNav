/// GeoClue2 D-Bus probe — Sprint 9 Day 5 investigation.
///
/// This test attempts to connect to GeoClue2 on the system bus
/// and report what's available. It is NOT a pass/fail test —
/// it's a diagnostic probe for the go/no-go gate.
///
/// Run: flutter test test/providers/geoclue_probe_test.dart
@TestOn('linux')
library;

import 'package:dbus/dbus.dart';
import 'package:flutter_test/flutter_test.dart';

const _busName = 'org.freedesktop.GeoClue2';
const _managerPath = '/org/freedesktop/GeoClue2/Manager';
const _managerIface = 'org.freedesktop.GeoClue2.Manager';
const _clientIface = 'org.freedesktop.GeoClue2.Client';
const _locationIface = 'org.freedesktop.GeoClue2.Location';

void main() {
  test('GeoClue2 D-Bus probe — connection and accuracy', () async {
    DBusClient? bus;
    try {
      bus = DBusClient.system();

      final manager = DBusRemoteObject(
        bus,
        name: _busName,
        path: DBusObjectPath(_managerPath),
      );

      // Check available accuracy level.
      final level = (await manager.getProperty(
        _managerIface,
        'AvailableAccuracyLevel',
      ))
          .asUint32();

      // Accuracy levels: 0=none, 1=country, 4=city, 5=neighborhood,
      // 6=street, 7=exact(wifi), 8=exact(gps)
      // ignore: avoid_print
      print('GeoClue2 AvailableAccuracyLevel: $level');
      // Level 0 = disabled, >0 = some capability.
      // Machine D reports 0 (location services disabled for UID 1000).
      // This is expected on dev machines without GPS hardware.
      expect(level, isA<int>());
    } finally {
      await bus?.close();
    }
  });

  test('GeoClue2 D-Bus probe — client creation', () async {
    DBusClient? bus;
    try {
      bus = DBusClient.system();

      final manager = DBusRemoteObject(
        bus,
        name: _busName,
        path: DBusObjectPath(_managerPath),
      );

      final result = await manager.callMethod(
        _managerIface,
        'GetClient',
        [],
        replySignature: DBusSignature('o'),
      );
      final clientPath = result.returnValues[0].asObjectPath();
      // ignore: avoid_print
      print('GeoClue2 client path: $clientPath');
      expect(clientPath.value, startsWith('/org/freedesktop/GeoClue2/Client/'));
    } finally {
      await bus?.close();
    }
  });

  test('GeoClue2 D-Bus probe — client lifecycle', () async {
    DBusClient? bus;
    try {
      bus = DBusClient.system();

      final manager = DBusRemoteObject(
        bus,
        name: _busName,
        path: DBusObjectPath(_managerPath),
      );

      // Get client.
      final result = await manager.callMethod(
        _managerIface,
        'GetClient',
        [],
        replySignature: DBusSignature('o'),
      );
      final clientPath = result.returnValues[0].asObjectPath();
      final client = DBusRemoteObject(
        bus,
        name: _busName,
        path: clientPath,
      );

      // Set DesktopId — required before Start.
      await client.setProperty(
        _clientIface,
        'DesktopId',
        DBusString('sngnav-snow-scene'),
      );
      // ignore: avoid_print
      print('DesktopId set');

      // Set accuracy.
      await client.setProperty(
        _clientIface,
        'RequestedAccuracyLevel',
        DBusUint32(8),
      );
      // ignore: avoid_print
      print('RequestedAccuracyLevel set');

      // Listen for signals.
      final signalStream = DBusSignalStream(
        bus,
        sender: _busName,
        interface: _clientIface,
        name: 'LocationUpdated',
        path: clientPath,
      );

      String? locationResult;
      final sub = signalStream.listen((signal) async {
        try {
          final locationPath = signal.values[1].asObjectPath();
          final location = DBusRemoteObject(
            bus!,
            name: _busName,
            path: locationPath,
          );

          final lat = (await location.getProperty(
            _locationIface,
            'Latitude',
          ))
              .asDouble();
          final lon = (await location.getProperty(
            _locationIface,
            'Longitude',
          ))
              .asDouble();
          final acc = (await location.getProperty(
            _locationIface,
            'Accuracy',
          ))
              .asDouble();

          locationResult = 'lat=$lat, lon=$lon, acc=${acc}m';
        } catch (e) {
          locationResult = 'signal error: $e';
        }
      });

      // Start.
      try {
        await client.callMethod(_clientIface, 'Start', []);
        // ignore: avoid_print
        print('Client started — waiting 5s for location...');

        // Wait up to 5 seconds.
        for (var i = 0; i < 50 && locationResult == null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }

        if (locationResult != null) {
          // ignore: avoid_print
          print('LOCATION RECEIVED: $locationResult');
        } else {
          // ignore: avoid_print
          print('No location received within 5 seconds');
        }
      } catch (e) {
        // ignore: avoid_print
        print('Start failed: $e');
      }

      // Clean up.
      await sub.cancel();
      try {
        await client.callMethod(_clientIface, 'Stop', []);
      } catch (_) {}
    } finally {
      await bus?.close();
    }
  }, timeout: const Timeout(Duration(seconds: 15)));
}
