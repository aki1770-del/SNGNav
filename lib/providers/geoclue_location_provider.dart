/// GeoClue2 D-Bus location provider — concrete implementation.
///
/// Implements the abstract [LocationProvider] interface for BLoC consumption.
/// Part of the configurable location pipeline.
library;

import 'dart:async';
import 'package:dbus/dbus.dart';

import '../models/geo_position.dart';
import 'location_provider.dart';

const _busName = 'org.freedesktop.GeoClue2';
const _managerPath = '/org/freedesktop/GeoClue2/Manager';
const _managerIface = 'org.freedesktop.GeoClue2.Manager';
const _clientIface = 'org.freedesktop.GeoClue2.Client';
const _locationIface = 'org.freedesktop.GeoClue2.Location';
const _accuracyLevelExact = 8;
const _desktopId = 'sngnav-snow-scene';

class GeoClueLocationProvider implements LocationProvider {
  DBusClient? _bus;
  DBusRemoteObject? _client;
  StreamSubscription<DBusSignal>? _signalSub;
  final _controller = StreamController<GeoPosition>.broadcast();

  @override
  Stream<GeoPosition> get positions => _controller.stream;

  int? get availableAccuracyLevel => _availableLevel;
  int? _availableLevel;

  bool get isRunning => _running;
  bool _running = false;

  @override
  Future<void> start() async {
    if (_running) return;

    _bus = DBusClient.system();

    final manager = DBusRemoteObject(
      _bus!,
      name: _busName,
      path: DBusObjectPath(_managerPath),
    );

    try {
      _availableLevel = (await manager.getProperty(
        _managerIface,
        'AvailableAccuracyLevel',
      ))
          .asUint32();
    } catch (_) {
      _availableLevel = null;
    }

    final result = await manager.callMethod(
      _managerIface,
      'GetClient',
      [],
      replySignature: DBusSignature('o'),
    );
    final clientPath = result.returnValues[0].asObjectPath();

    _client = DBusRemoteObject(
      _bus!,
      name: _busName,
      path: clientPath,
    );

    await _client!.setProperty(
      _clientIface,
      'DesktopId',
      DBusString(_desktopId),
    );
    await _client!.setProperty(
      _clientIface,
      'RequestedAccuracyLevel',
      DBusUint32(_accuracyLevelExact),
    );

    final signalStream = DBusSignalStream(
      _bus!,
      sender: _busName,
      interface: _clientIface,
      name: 'LocationUpdated',
      path: clientPath,
    );

    _signalSub = signalStream.listen(_onLocationUpdated);

    await _client!.callMethod(_clientIface, 'Start', []);
    _running = true;
  }

  Future<void> _onLocationUpdated(DBusSignal signal) async {
    final locationPath = signal.values[1].asObjectPath();
    final location = DBusRemoteObject(
      _bus!,
      name: _busName,
      path: locationPath,
    );

    final lat =
        (await location.getProperty(_locationIface, 'Latitude')).asDouble();
    final lon =
        (await location.getProperty(_locationIface, 'Longitude')).asDouble();
    final acc =
        (await location.getProperty(_locationIface, 'Accuracy')).asDouble();

    double alt = double.nan, spd = double.nan, hdg = double.nan;
    try {
      alt =
          (await location.getProperty(_locationIface, 'Altitude')).asDouble();
    } catch (_) {}
    try {
      spd = (await location.getProperty(_locationIface, 'Speed')).asDouble();
    } catch (_) {}
    try {
      hdg =
          (await location.getProperty(_locationIface, 'Heading')).asDouble();
    } catch (_) {}

    final pos = GeoPosition(
      latitude: lat,
      longitude: lon,
      accuracy: acc,
      altitude: alt,
      speed: spd,
      heading: hdg,
      timestamp: DateTime.now(),
    );

    _controller.add(pos);
  }

  @override
  Future<void> stop() async {
    _running = false;
    await _signalSub?.cancel();
    _signalSub = null;

    if (_client != null) {
      try {
        await _client!.callMethod(_clientIface, 'Stop', []);
      } catch (_) {}
    }
    _client = null;

    await _bus?.close();
    _bus = null;
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _controller.close();
  }
}
