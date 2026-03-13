/// GeoClue2 D-Bus location provider — concrete implementation.
///
/// Implements the abstract [LocationProvider] interface for BLoC consumption.
/// Part of the configurable location pipeline.
library;

import 'dart:async';

import 'package:dbus/dbus.dart';
import 'package:kalman_dr/kalman_dr.dart';

const _busName = 'org.freedesktop.GeoClue2';
const _managerPath = '/org/freedesktop/GeoClue2/Manager';
const _managerIface = 'org.freedesktop.GeoClue2.Manager';
const _clientIface = 'org.freedesktop.GeoClue2.Client';
const _locationIface = 'org.freedesktop.GeoClue2.Location';
const _accuracyLevelExact = 8;
const _desktopId = 'sngnav-snow-scene';

typedef GeoClueSessionFactory = GeoClueSession Function();

class GeoClueException implements Exception {
  const GeoClueException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() {
    if (cause == null) {
      return 'GeoClueException: $message';
    }
    return 'GeoClueException: $message ($cause)';
  }
}

class GeoClueLocationProvider implements LocationProvider {
  GeoClueLocationProvider({
    GeoClueSessionFactory? sessionFactory,
    DateTime Function()? now,
  })  : _sessionFactory = sessionFactory ?? GeoClueDbusSession.new,
        _now = now ?? DateTime.now;

  final GeoClueSessionFactory _sessionFactory;
  final DateTime Function() _now;
  final _controller = StreamController<GeoPosition>.broadcast();

  GeoClueSession? _session;
  StreamSubscription<String>? _signalSub;
  int? _availableLevel;
  int? _requestedLevel;
  bool _running = false;
  bool _disposed = false;

  @override
  Stream<GeoPosition> get positions => _controller.stream;

  int? get availableAccuracyLevel => _availableLevel;

  int? get requestedAccuracyLevel => _requestedLevel;

  bool get isRunning => _running;

  @override
  Future<void> start() async {
    if (_disposed) {
      throw StateError('GeoClueLocationProvider has already been disposed');
    }
    if (_running) return;

    final session = _sessionFactory();
    _session = session;

    try {
      _availableLevel = await session.getAvailableAccuracyLevel();
      if (_availableLevel == 0) {
        throw const GeoClueException(
          'GeoClue is available but location services are disabled or denied for this session',
        );
      }

      _requestedLevel = _effectiveAccuracyLevel(_availableLevel);
      await session.initializeClient(
        desktopId: _desktopId,
        requestedAccuracyLevel: _requestedLevel!,
      );

      _signalSub = session.locationUpdates.listen(
        _onLocationUpdated,
        onError: (Object error, StackTrace stackTrace) {
          if (!_controller.isClosed) {
            _controller.addError(error, stackTrace);
          }
        },
      );

      await session.start();
      _running = true;
    } catch (error) {
      await _cleanupAfterFailedStart();
      if (error is GeoClueException || error is StateError) {
        rethrow;
      }
      throw GeoClueException(
        'Failed to start GeoClue location provider',
        cause: error,
      );
    }
  }

  int _effectiveAccuracyLevel(int? availableLevel) {
    if (availableLevel == null || availableLevel <= 0) {
      return _accuracyLevelExact;
    }
    return availableLevel < _accuracyLevelExact
        ? availableLevel
        : _accuracyLevelExact;
  }

  Future<void> _onLocationUpdated(String locationPath) async {
    final session = _session;
    if (session == null) {
      return;
    }

    try {
      final position = await session.readPosition(locationPath, now: _now);
      if (!_controller.isClosed) {
        _controller.add(position);
      }
    } catch (error, stackTrace) {
      if (!_controller.isClosed) {
        _controller.addError(
          GeoClueException(
            'Failed to read GeoClue location update',
            cause: error,
          ),
          stackTrace,
        );
      }
    }
  }

  @override
  Future<void> stop() async {
    _running = false;
    await _signalSub?.cancel();
    _signalSub = null;

    if (_session != null) {
      try {
        await _session!.stop();
      } catch (_) {}
    }

    await _session?.close();
    _session = null;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await stop();
    await _controller.close();
  }

  Future<void> _cleanupAfterFailedStart() async {
    _running = false;
    await _signalSub?.cancel();
    _signalSub = null;
    await _session?.close();
    _session = null;
  }
}

abstract class GeoClueSession {
  Future<int?> getAvailableAccuracyLevel();

  Future<void> initializeClient({
    required String desktopId,
    required int requestedAccuracyLevel,
  });

  Stream<String> get locationUpdates;

  Future<GeoPosition> readPosition(
    String locationPath, {
    required DateTime Function() now,
  });

  Future<void> start();

  Future<void> stop();

  Future<void> close();
}

class GeoClueDbusSession implements GeoClueSession {
  GeoClueDbusSession({DBusClient Function()? busFactory})
      : _busFactory = busFactory ?? DBusClient.system;

  final DBusClient Function() _busFactory;

  DBusClient? _bus;
  DBusRemoteObject? _client;
  DBusObjectPath? _clientPath;

  DBusClient get _activeBus => _bus ??= _busFactory();

  DBusRemoteObject get _manager => DBusRemoteObject(
        _activeBus,
        name: _busName,
        path: DBusObjectPath(_managerPath),
      );

  @override
  Future<int?> getAvailableAccuracyLevel() async {
    try {
      return (await _manager.getProperty(
        _managerIface,
        'AvailableAccuracyLevel',
      ))
          .asUint32();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> initializeClient({
    required String desktopId,
    required int requestedAccuracyLevel,
  }) async {
    final result = await _manager.callMethod(
      _managerIface,
      'GetClient',
      [],
      replySignature: DBusSignature('o'),
    );

    _clientPath = result.returnValues[0].asObjectPath();
    _client = DBusRemoteObject(
      _activeBus,
      name: _busName,
      path: _clientPath!,
    );

    await _client!.setProperty(
      _clientIface,
      'DesktopId',
      DBusString(desktopId),
    );
    await _client!.setProperty(
      _clientIface,
      'RequestedAccuracyLevel',
      DBusUint32(requestedAccuracyLevel),
    );
  }

  @override
  Stream<String> get locationUpdates {
    final clientPath = _clientPath;
    if (clientPath == null) {
      throw StateError('GeoClue client has not been initialized');
    }

    return DBusSignalStream(
      _activeBus,
      sender: _busName,
      interface: _clientIface,
      name: 'LocationUpdated',
      path: clientPath,
    ).map((signal) => signal.values[1].asObjectPath().value);
  }

  @override
  Future<GeoPosition> readPosition(
    String locationPath, {
    required DateTime Function() now,
  }) async {
    final location = DBusRemoteObject(
      _activeBus,
      name: _busName,
      path: DBusObjectPath(locationPath),
    );

    final latitude =
        (await location.getProperty(_locationIface, 'Latitude')).asDouble();
    final longitude =
        (await location.getProperty(_locationIface, 'Longitude')).asDouble();
    final accuracy =
        (await location.getProperty(_locationIface, 'Accuracy')).asDouble();

    return GeoPosition(
      latitude: latitude,
      longitude: longitude,
      accuracy: accuracy,
      altitude: await _readOptionalDouble(location, 'Altitude'),
      speed: await _readOptionalDouble(location, 'Speed'),
      heading: await _readOptionalDouble(location, 'Heading'),
      timestamp: now(),
    );
  }

  Future<double> _readOptionalDouble(
    DBusRemoteObject location,
    String propertyName,
  ) async {
    try {
      return (await location.getProperty(_locationIface, propertyName))
          .asDouble();
    } catch (_) {
      return double.nan;
    }
  }

  @override
  Future<void> start() async {
    await _client!.callMethod(_clientIface, 'Start', []);
  }

  @override
  Future<void> stop() async {
    final client = _client;
    if (client == null) {
      return;
    }

    try {
      await client.callMethod(_clientIface, 'Stop', []);
    } catch (_) {}
  }

  @override
  Future<void> close() async {
    _client = null;
    _clientPath = null;
    await _bus?.close();
    _bus = null;
  }
}
