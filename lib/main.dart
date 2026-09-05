/// SNGNav Getting Started — offline-first reference entrypoint.
///
/// The shortest path from `git clone` to a working app, and a reference for the
/// offline-first surfaces. It demonstrates:
/// - flutter_map rendering on Linux desktop with MBTiles offline tile loading
///   (no network required) and online OSM fallback when the MBTiles file is absent
/// - the pre-trip "Before you drive" safety briefing + the family-thread
///   destination-area card + in-app place entry (via the shared [PretripScreen],
///   the SAME widget the full `lib/snow_scene.dart` product demo hosts)
/// - the perspective forward-looking 3D snow scene (CPU-projected still frame)
/// - en/ja locale: the briefing follows the device locale so it reaches the driver
///   mother in Akita, who reads Japanese (English fallback for every other locale)
///
/// Usage:
///   1. Place `offline_tiles.mbtiles` in the `data/` directory
///   2. Run: flutter run -d linux
///   3. See the Chūbu region map (Nagoya / Toyota City area)
library;

import 'dart:async';
import 'dart:io';

import 'package:driving_weather/driving_weather.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:kalman_dr/kalman_dr.dart';
import 'package:kuksa_dart_sdk/kuksa_dart_sdk.dart';
import 'package:latlong2/latlong.dart';
import 'package:offline_tiles/offline_tiles.dart' as offline_tiles;
import 'package:snow_rendering/snow_rendering.dart';

import 'bloc/location_bloc.dart';
import 'bloc/location_event.dart';
import 'bloc/location_state.dart';
import 'config/provider_config.dart';
import 'fluorite/snow_scene_3d_view.dart';
import 'providers/kuksa_condition_provider.dart';
import 'providers/met_norway_hourly_forecast.dart';
import 'providers/serial_nmea_location_provider.dart';
import 'services/saved_place_store.dart';
import 'widgets/pretrip_screen.dart';

void main() {
  runApp(const SNGNavGettingStarted());
}

class SNGNavGettingStarted extends StatelessWidget {
  const SNGNavGettingStarted({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SNGNav Getting Started',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1A73E8),
        ),
        useMaterial3: true,
      ),
      // The pre-trip safety briefing must reach the driver's mother in Akita, who reads
      // Japanese — the briefing follows the device locale (ja → Japanese, any
      // other → the English fallback). The Material/Widgets delegates supply
      // the framework strings for the same locales.
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('en'), Locale('ja')],
      home: const OfflineMapPage(),
    );
  }
}

/// Which view fills the main body: the existing top-down 2D map, the
/// perspective forward-looking 3D snow scene, or the pre-trip briefing.
enum _ViewMode { map, forward, pretrip }

/// What can honestly be said about the offline map UNDER THE CURRENT VIEW.
///
/// Three states, because two were not enough and the missing one was the
/// dangerous one. Until 2026-08-29 this was a single bool set from
/// `File.existsSync()` — file presence reported as map presence — and on a real
/// IVI screen that produced a green "OFFLINE MAP" badge over a blank grey
/// rectangle, with a perfectly good archive open for another prefecture.
enum _MapCoverage {
  /// No archive opened at all.
  noArchive,

  /// An archive is open, and it holds no tile at all for this view.
  archiveButNotHere,

  /// An archive is open and it can paint SOME of this view but not all of it.
  ///
  /// ⚑ This state exists because of a measurement, not a hunch. Against the
  /// real 15.6 MB Akita archive at its own declared centre and its own declared
  /// floor zoom 8, only 6 of the 35 tiles an 800x480 viewport requests resolve
  /// locally. Asking about the centre POINT answers "covered"; asking about the
  /// VIEW answers "one sixth of it". Both are true, and only the second is what
  /// the driver is looking at.
  partiallyCovered,

  /// An archive is open and it can paint every tile of this view.
  covered,
}

class OfflineMapPage extends StatefulWidget {
  const OfflineMapPage({
    super.key,
    this.savedPlaceStore,
    this.destForecastProviderFactory,
    this.forecastSourceOverride,
    this.mbtilesPath,
  });

  /// Optional test seam: the offline archive to open. Production defaults to
  /// [_OfflineMapPageState._defaultMbtilesPath] when null.
  ///
  /// This exists so the coverage/camera coupling can be exercised against an
  /// archive OTHER than the one this checkout happens to ship. A guard that can
  /// only ever be pointed at the one archive that already agrees with the
  /// hardcoded camera cannot fail, and a guard that cannot fail is not a guard.
  final String? mbtilesPath;

  /// Optional test seam: the store for the driver-chosen destination area.
  /// Production defaults to [openDefaultSavedPlaceStore] when null.
  final SavedPlaceStore? savedPlaceStore;

  /// Optional test seam: a factory for the destination-area forecast provider,
  /// so a fake offline provider can be injected. Production defaults to a real
  /// [MetNorwayHourlyForecastProvider] when null.
  final MetNorwayHourlyForecastProvider Function()? destForecastProviderFactory;

  /// Optional test seam: overrides the compile-time `PRETRIP_FORECAST` define
  /// for the destination-area gate, so the full _setDestination contract (leak
  /// hygiene + re-render + anti-clobber) is exercised by a plain `flutter test`
  /// without a `--dart-define`. Null in production ⇒ the compile-time source is
  /// used. Consumed ONLY on the dest path in [_initDestAreaCondition].
  final String? forecastSourceOverride;

  @override
  State<OfflineMapPage> createState() => _OfflineMapPageState();
}

class _OfflineMapPageState extends State<OfflineMapPage> {
  offline_tiles.OfflineTileManager? _offlineTileManager;

  // THERE IS DELIBERATELY NO BOOLEAN "have we got a map" FLAG HERE ANY MORE.
  //
  // Two generations of one defect lived on this line, and both reached a
  // screen:
  //   gen 1 — the badge measured CONNECTIVITY and reported MAP. With no
  //           MBTiles it read "ONLINE" in a dead zone over a blank map.
  //           Fixed 2026-08-28.
  //   gen 2 — the replacement measured FILE PRESENCE (`File.existsSync()`)
  //           and reported MAP PRESENCE. Photographed on the ARM IVI target
  //           2026-08-29 at 09:09: a green "OFFLINE MAP" badge and
  //           "Offline — MBTiles loaded (15.6 MB)" over a blank grey
  //           rectangle. The archive was fine; it covered another prefecture.
  //
  // Absence of a measurement is not a measurement, and neither is a proxy for
  // one. The badge now reads [_coverage], which asks the open archive whether
  // it holds a tile for the view the driver is actually looking at.
  String _statusMessage = 'Initializing...';

  // Default view is the existing 2D map — the toggle is opt-in, the app's
  // default behaviour is unchanged.
  _ViewMode _viewMode = _ViewMode.map;

  // The driving-condition picture fed to the 3D forward-view.
  //
  // OFFLINE-FIRST (compound-failure worst case — non-negotiable): this field is initialised
  // to a SIMULATED default so the forward-view renders IMMEDIATELY with zero
  // network and zero GPS. The compound-failure case (Google Maps fails AND GPS
  // fails) must still show a meaningful Snow Scene — so the default is always a
  // valid assessment and is the permanent fallback.
  //
  // LIVE WIRING (additive, never load-bearing for offline): when the edge
  // developer selects the live Digitraffic provider
  // (`--dart-define=WEATHER_PROVIDER=digitraffic`, ONLINE only) we subscribe to
  // its `Stream<WeatherCondition>` and update `_assessment` via setState as real
  // winter-road severity arrives — reusing the exact provider/stream pattern the
  // full `snow_scene.dart` app uses (ProviderConfig.createWeatherProvider →
  // WeatherProvider.conditions). On ANY failure (no provider configured,
  // network error, parse error, disposed) the scene KEEPS the last-good /
  // default assessment and keeps rendering — no uncaught exception, no blank
  // scene, no hard network dependency. The non-digitraffic providers (simulated
  // default, open_meteo) are left untouched here: this minimal getting-started
  // entrypoint only opts in to the live winter-severity feed, and otherwise
  // stays purely offline-renderable.
  DrivingConditionAssessment _assessment =
      DrivingConditionAssessment.fromCondition(
    WeatherCondition(
      precipType: PrecipitationType.snow,
      intensity: PrecipitationIntensity.moderate,
      temperatureCelsius: -3.0,
      visibilityMeters: 600.0, // reduced — fog wall visible
      windSpeedKmh: 18.0,
      iceRisk: true,
      // This is an ASSERTED scenario (the getting-started default scene), not a
      // measurement. Saying so is the whole point of ObservationSource.
      source: ObservationSource.simulated,
      timestamp: DateTime(2026, 1, 1, 7, 15),
    ),
  );

  // The live weather provider (only constructed when WEATHER_PROVIDER=digitraffic).
  // Null on every offline/default path — the scene never depends on it existing.
  WeatherProvider? _weatherProvider;
  StreamSubscription<WeatherReading>? _weatherSub;

  // True once a live condition has actually arrived from the feed, so the
  // caption can tell the truth about whether the scene reflects live severity
  // or the simulated default.
  bool _liveConditionReceived = false;

  // LIVE IN-VEHICLE CONDITION SOURCE (compound-failure worst case — network AND GPS gone).
  //
  // The compound-failure path: when Google Maps fails AND GPS fails, the
  // vehicle's own ECUs are still publishing road-friction (ESC), TCS/ABS
  // engagement, wiper/rain intensity and ambient temperature onto the local
  // KUKSA databroker bus. We consume those VSS signals over gRPC via our
  // published `kuksa_dart_sdk` client and fuse them DETERMINISTICALLY into the
  // exact same DrivingConditionAssessment the Digitraffic path produces — no
  // network, no GPS, no cloud weather.
  //
  // SOURCE SELECTION (additive — never replaces the offline default or the
  // Digitraffic opt-in): this live source is wired ONLY when the edge developer
  // opts in with `--dart-define=KUKSA_HOST=<broker host>` (e.g. localhost on an
  // IVI headunit). On every other path it is a no-op and the scene keeps its
  // simulated/Digitraffic behaviour unchanged.
  //
  // HONEST FALLBACK (no fabrication): if the broker is unreachable, or the
  // stream errors/ends, we keep the last-good / default assessment and stop
  // claiming "live" — we never invent an in-vehicle condition. DISPLAY-ONLY:
  // signals are read, never written/commanded.
  static const String _kuksaHost = String.fromEnvironment('KUKSA_HOST');
  static const int _kuksaPort =
      int.fromEnvironment('KUKSA_PORT', defaultValue: 55555);

  KuksaClient? _kuksaClient;
  KuksaConditionProvider? _kuksaProvider;
  StreamSubscription<KuksaConditionUpdate>? _kuksaSub;

  // True once a live in-vehicle (KUKSA) condition has actually arrived, so the
  // caption tells the truth about the active source.
  bool _liveVehicleReceived = false;

  // HONEST GPS-LOSS DEGRADATION (compound-failure worst case — GPS fails).
  //
  // The 3D forward-view is driven by weather alone; on its own it would keep
  // painting a confident, crisp road even when GPS is lost and the real
  // position is drifting — the dishonest failure this project forbids. The fix is to feed
  // SnowScene3DView a LocationState so it degrades honestly (uncertainty fog +
  // "GPS lost" banner; "POSITION UNAVAILABLE" at the 500 m DR safety cap).
  //
  // REAL FEED: a serial GPS receiver speaks NMEA. We open the named port from
  // `--dart-define=GPS_PORT=/dev/ttyUSB0`, parse RMC/GGA into GeoPosition
  // (SerialNmeaLocationProvider), wrap it in a Kalman DeadReckoningProvider for
  // tunnel/GPS-loss fallback, and drive a LocationBloc whose state we subscribe
  // to here. The SnowScene3DView contract is identical to the simulated case —
  // the difference is the LocationState is now real.
  //
  // HONEST FALLBACK (no fake fix): if GPS_PORT is unset or the port can't be
  // opened (the usual desktop-host case — no GPS attached), we DO NOT start the
  // bloc and DO NOT invent a fix. `_location` stays null, which the scene reads
  // as the "position unavailable" honest floor — never a confident road.
  static const String _gpsPort = String.fromEnvironment('GPS_PORT');

  LocationBloc? _locationBloc;
  StreamSubscription<LocationState>? _locationSub;
  LocationState? _locationState;

  /// The live location state fed to the 3D scene — `null` until a real fix
  /// arrives (honest floor), never a simulated fix.
  LocationState? get _location => _locationState;

  /// Starts the real serial-NMEA → kalman_dr → LocationBloc feed when a
  /// GPS_PORT is configured. No-op (honest floor) otherwise.
  void _initLocation() {
    if (_gpsPort.isEmpty) return; // no port → honest floor, no fake fix
    try {
      final bloc = LocationBloc(
        provider: DeadReckoningProvider(
          inner: SerialNmeaLocationProvider(portName: _gpsPort),
          mode: DeadReckoningMode.kalman,
        ),
      )..add(const LocationStartRequested());
      _locationBloc = bloc;
      _locationSub = bloc.stream.listen((state) {
        if (!mounted) return;
        setState(() => _locationState = state);
      });
    } catch (_) {
      // Could not start the live feed → stay on the honest floor.
      _locationState = null;
    }
  }

  // Nagoya Station — the camera used ONLY when no archive is open, or when the
  // archive declines to say where it covers. It is not a claim about any
  // particular tileset; it is the documented demo's starting view.
  static const _nagoya = LatLng(35.1709, 136.8815);
  static const _fallbackZoom = 11.0;
  static const _fallbackMinZoom = 6.0;
  static const _fallbackMaxZoom = 16.0;

  /// The camera the OPEN ARCHIVE can actually serve.
  ///
  /// Derived from the archive's own `metadata` table (bounds / center / zoom
  /// range) and falling back per field to the constants above when there is no
  /// archive. Before 2026-08-29 the camera was a hardcoded constant and nothing
  /// compared it with the archive: on the ARM IVI target that put the view
  /// 580 km outside the Akita tileset's bounds, with a green "OFFLINE MAP"
  /// badge over a blank grey rectangle.
  offline_tiles.ArchiveCamera _camera = offline_tiles.ArchiveCamera.fallback(
    center: _nagoya,
    zoom: _fallbackZoom,
    minZoom: _fallbackMinZoom,
    maxZoom: _fallbackMaxZoom,
  );

  /// Where the map is looking RIGHT NOW — updated as the driver pans and pinches, so
  /// the coverage badge answers "is there a map HERE", not "was there a map
  /// where we started".
  LatLng? _viewCenter;
  double? _viewZoom;

  /// The rectangle the map is currently showing. Null until the map has been
  /// laid out once.
  LatLngBounds? _visibleBounds;

  /// The ring of off-screen tiles flutter_map prefetches. Declared once here
  /// and passed to BOTH the TileLayer and the coverage query, because a
  /// coverage answer computed over a different set of tiles than the renderer
  /// requests is a coverage answer about a different screen.
  static const int _panBuffer = 1;

  // MBTiles file path — relative to the project directory.
  // The edge developer places her .mbtiles file here.
  static const _defaultMbtilesPath = 'data/offline_tiles.mbtiles';

  /// The archive this page actually opens: the injected test seam when one is
  /// given, the documented default otherwise.
  String get _mbtilesPath => widget.mbtilesPath ?? _defaultMbtilesPath;

  @override
  void initState() {
    super.initState();
    _initTileProvider();
    _initLiveWeather();
    _initKuksaConditions();
    _initLocation();
  }

  /// Subscribes the held [_assessment] to the LIVE in-vehicle KUKSA condition
  /// feed, but ONLY when the edge developer has opted in via
  /// `--dart-define=KUKSA_HOST=<host>`. On every other path this is a no-op and
  /// the scene keeps its simulated/Digitraffic behaviour (offline-first
  /// preserved).
  ///
  /// All failures degrade honestly: if the broker can not be reached, the
  /// stream errors, or no live signals arrive, [_assessment] stays at its
  /// last-good value, [_liveVehicleReceived] stays/returns false, and no
  /// in-vehicle condition is ever fabricated.
  Future<void> _initKuksaConditions() async {
    if (_kuksaHost.isEmpty) return; // not selected → offline default, no broker
    try {
      final client = KuksaClient(host: _kuksaHost, port: _kuksaPort);
      _kuksaClient = client;
      final provider = await KuksaConditionProvider.connect(client);
      _kuksaProvider = provider;
      _kuksaSub = provider.conditions.listen(
        (update) {
          if (!mounted) return;
          if (!update.isAvailable) {
            // Honest "no live vehicle signals": keep last-good/default, never
            // fabricate — just stop claiming the scene is live.
            setState(() => _liveVehicleReceived = false);
            return;
          }
          setState(() {
            _assessment = update.assessment!;
            _liveVehicleReceived = true;
          });
        },
        onError: (Object _) {/* keep last-good assessment */},
        cancelOnError: false,
      );
    } catch (_) {
      // Broker unreachable (the usual no-vehicle host case) → honest floor:
      // keep the offline default assessment, never invent a vehicle condition.
    }
  }

  /// Subscribes the held [_assessment] to a LIVE winter-road severity feed,
  /// but ONLY when the edge developer has opted in via
  /// `--dart-define=WEATHER_PROVIDER=digitraffic`. On every other path
  /// (the default offline/simulated path) this is a no-op and the scene keeps
  /// rendering the simulated default — preserving the offline-first invariant.
  ///
  /// All failures are swallowed into the default-fallback: if the provider can
  /// not be built, can not start, or the feed errors, [_assessment] simply
  /// stays at its last-good value and the scene never blanks.
  Future<void> _initLiveWeather() async {
    try {
      final config = ProviderConfig.fromEnvironment();

      // Offline-first gate: only the explicit live Digitraffic selection wires
      // a network stream. simulated/open_meteo defaults stay purely local here.
      if (config.weatherType != WeatherProviderType.digitraffic) {
        return;
      }

      final provider = config.createWeatherProvider();
      _weatherProvider = provider;

      // driving_weather 0.5.0: the stream carries a SEALED WeatherReading.
      // An OBSERVED reading updates the scene. A STALE one still updates it (an
      // old reading is still information — the assessment itself now degrades
      // honestly on absent fields). An UNAVAILABLE one must NOT leave the last
      // good assessment standing as though it were current: the scene switches
      // to the honest unknown assessment, which renders the "not measured"
      // state rather than a stale-but-calm one.
      _weatherSub = provider.conditions.listen(
        (reading) {
          if (!mounted) return;
          final WeatherCondition condition = switch (reading) {
            WeatherObserved(:final condition) => condition,
            WeatherStale(:final lastKnown) => lastKnown,
            WeatherUnavailable() =>
              WeatherCondition.unknown(timestamp: DateTime.now()),
          };
          setState(() {
            _assessment =
                DrivingConditionAssessment.fromCondition(condition);
            _liveConditionReceived = true;
          });
        },
        // Stream errors fall back to the existing assessment — no rethrow.
        onError: (Object _) {/* keep last-good assessment */},
        cancelOnError: false,
      );

      await provider.startMonitoring();
    } catch (_) {
      // Any failure constructing/starting the live feed -> stay on the default
      // simulated assessment. The offline scene is never compromised.
    }
  }

  /// Opens the offline archive and derives the camera from it.
  ///
  /// SYNCHRONOUS ON PURPOSE, and this is load-bearing. [OfflineTileManager]'s
  /// constructor already opens the archive with a blocking `existsSync()` +
  /// `MbTiles(...)`, so the previous `await file.exists()` bought no
  /// concurrency whatsoever — all it guaranteed was that the FIRST FRAME was
  /// built before the camera was known. `MapOptions.initialCenter` is read
  /// exactly once, so a camera that arrives one microtask late is a camera that
  /// never reaches the screen at all.
  ///
  /// Assigns fields directly instead of calling setState: this runs from
  /// [initState], where markNeedsBuild would assert.
  void _initTileProvider() {
    final file = File(_mbtilesPath);
    try {
      if (file.existsSync()) {
        final manager = offline_tiles.OfflineTileManager(
          tileSource: offline_tiles.TileSourceType.mbtiles,
          mbtilesPath: _mbtilesPath,
          // OFFLINE-FIRST, AND HONEST ABOUT IT. The TileLayer below passes
          // `urlTemplate: null` whenever a manager exists, so a resolution of
          // RuntimeTileSource.online reaches NetworkTileProvider with no
          // template and `TileProvider.getTileUrl` throws an ArgumentError —
          // once per uncovered tile, swallowed by the image pipeline, no log,
          // no pixel, and identical whether or not a network exists. With the
          // fallback off the same tile resolves to a transparent placeholder
          // instead: same blank square, no thrown exception, and the badge
          // above now says WHY it is blank.
          allowOnlineFallback: false,
        );
        _offlineTileManager = manager;
        _camera = manager.archiveCamera(
          fallbackCenter: _nagoya,
          fallbackZoom: _fallbackZoom,
          fallbackMinZoom: _fallbackMinZoom,
          fallbackMaxZoom: _fallbackMaxZoom,
        );
        _viewCenter = _camera.center;
        _viewZoom = _camera.zoom;
        _statusMessage = _archiveStatusLine(file.lengthSync());
      } else {
        _resetTileState();
        _statusMessage = 'No MBTiles file at $_mbtilesPath — no offline map';
      }
    } catch (e) {
      // Reset BOTH, not just the message. Leaving the flag true here would
      // keep the badge reading "OFFLINE MAP" while the manager is null and
      // tiles come from the network. Latent while _initTileProvider has one
      // call site; live the moment a retry or reload is added.
      _resetTileState();
      _statusMessage = 'MBTiles error: $e — no offline map${_loaderHint(e)}';
    }
  }

  void _resetTileState() {
    _offlineTileManager = null;
    _camera = offline_tiles.ArchiveCamera.fallback(
      center: _nagoya,
      zoom: _fallbackZoom,
      minZoom: _fallbackMinZoom,
      maxZoom: _fallbackMaxZoom,
    );
    _viewCenter = null;
    _viewZoom = null;
  }

  /// Turns the one failure an edge developer cannot diagnose from the message
  /// alone into one she can.
  ///
  /// `package:sqlite3` opens the system library by the literal name
  /// `libsqlite3.so`. On Debian/Ubuntu that unversioned symlink ships in
  /// `libsqlite3-dev`, NOT in the runtime package — and on a production
  /// embedded rootfs it is absent for the same reason. Measured on the ARM IVI
  /// image 2026-08-29: `libsqlite3.so.0 -> libsqlite3.so.0.8.6` present, no
  /// unversioned `libsqlite3.so`. The raw FFI error names a file and says
  /// nothing about which package supplies it.
  String _loaderHint(Object error) {
    final text = error.toString();
    if (!text.contains('libsqlite3')) return '';
    return '\n(the versioned libsqlite3.so.N is usually present; the '
        'unversioned libsqlite3.so symlink the loader asks for is not — '
        'install sqlite3 development headers on a desktop, or add the symlink '
        'to the image on an embedded target)';
  }

  /// The status line, which must never claim more than coverage supports.
  String _archiveStatusLine(int bytes) {
    final size = _formatSize(bytes);
    switch (_coverage) {
      case _MapCoverage.covered:
        return 'Offline — MBTiles loaded ($size)';
      case _MapCoverage.partiallyCovered:
        return 'MBTiles loaded ($size) — only part of this view is in the '
            'archive; zoom in or move back inside its coverage';
      case _MapCoverage.archiveButNotHere:
        return 'MBTiles loaded ($size) but it holds no tiles for this view'
            '${_camera.bounds == null ? '' : ' — covers '
                '${_camera.bounds!.south.toStringAsFixed(2)},'
                '${_camera.bounds!.west.toStringAsFixed(2)} to '
                '${_camera.bounds!.north.toStringAsFixed(2)},'
                '${_camera.bounds!.east.toStringAsFixed(2)}'}';
      case _MapCoverage.noArchive:
        return 'No MBTiles file at $_mbtilesPath — no offline map';
    }
  }

  /// What we can actually say about the map under the current view.
  ///
  /// THIS IS A MEASUREMENT, not a file check. The flag this replaced answered
  /// "did a file open"; this answers "does that file hold tiles for where the
  /// driver is looking". Conflating the two is how a green OFFLINE MAP badge
  /// came to sit over a blank grey rectangle on a real IVI screen.
  _MapCoverage get _coverage {
    final manager = _offlineTileManager;
    if (manager == null || !manager.hasOfflineArchive) {
      return _MapCoverage.noArchive;
    }
    final zoom = (_viewZoom ?? _camera.zoom).round();

    // Prefer the WHOLE VISIBLE RECTANGLE over the centre point. The centre can
    // answer "covered" while most of the screen has nothing to draw — measured
    // 6/35 at z8 on the real Akita archive. `_visibleBounds` is null only
    // before the map has been laid out; then, and only then, fall back to the
    // point.
    final bounds = _visibleBounds;
    if (bounds != null) {
      final coverage = manager.coverageForBounds(
        bounds,
        zoom: zoom,
        // Must match TileLayer.panBuffer below: flutter_map REQUESTS the ring,
        // so a tile the driver cannot see still goes through the provider.
        panBuffer: _panBuffer,
      );
      if (coverage.isComplete) return _MapCoverage.covered;
      if (coverage.isEmpty) return _MapCoverage.archiveButNotHere;
      if (coverage.isPartial) return _MapCoverage.partiallyCovered;
    }

    final center = _viewCenter ?? _camera.center;
    return manager.hasLocalCoverageForPoint(center, zoom: zoom)
        ? _MapCoverage.covered
        : _MapCoverage.archiveButNotHere;
  }

  /// Recomputes the badge as the view moves. Cheap: a single indexed lookup in
  /// the already-open archive, and only when the answer actually changes.
  void _onViewChanged(MapCamera camera) {
    final before = _coverage;
    final beforeStatus = _statusMessage;
    _viewCenter = camera.center;
    _viewZoom = camera.zoom;
    _visibleBounds = camera.visibleBounds;
    final after = _coverage;
    if (after == before) return;
    if (!mounted) return;
    setState(() {
      if (_offlineTileManager != null) {
        try {
          _statusMessage = _archiveStatusLine(File(_mbtilesPath).lengthSync());
        } catch (_) {
          _statusMessage = beforeStatus;
        }
      }
    });
  }

  /// The badge, in the three states the driver must be able to tell apart.
  ///
  /// COLOUR CARRIES THE SAFETY FACT; TEXT AND ICON CARRY THE REASON.
  ///
  /// Green means one thing only: there is a real local map under this view.
  /// Both other states mean there is not — and for a driver at ten metres'
  /// visibility on a mountain pass they are the SAME actionable fact, so they
  /// share a colour rather than inventing a severity ladder that does not
  /// exist. What differs is the icon and the word, so she can see WHY without
  /// reading the status line, and so an edge developer can tell "you shipped no
  /// archive" from "you shipped the wrong one".
  Widget _buildCoverageBadge() {
    final (IconData icon, Color color, String label) = switch (_coverage) {
      _MapCoverage.covered => (Icons.map, Colors.green, 'OFFLINE MAP'),
      // Some of the view is real and some is not. Not green: she cannot trust
      // the whole picture. Not "NOT HERE" either: that would be false, and a
      // false alarm she learns to ignore is worse than no badge.
      _MapCoverage.partiallyCovered => (
          Icons.grid_off,
          Colors.orange,
          'MAP: PARTIAL',
        ),
      // An archive that does not reach here is not a map she can use here.
      _MapCoverage.archiveButNotHere => (
          Icons.wrong_location,
          Colors.orange,
          'MAP: NOT HERE',
        ),
      _MapCoverage.noArchive => (
          Icons.cloud_queue,
          Colors.orange,
          'NO OFFLINE MAP',
        ),
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Text(
          // What we measured: does the OPEN ARCHIVE hold tiles for THIS view?
          // Not whether a network exists — we never asked, and in the dead zone
          // the old 'ONLINE' label was actively false. And not whether a file
          // exists — that was the next generation of the same defect.
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  void dispose() {
    _weatherSub?.cancel();
    _weatherProvider?.dispose();
    _kuksaSub?.cancel();
    _kuksaProvider?.dispose();
    _kuksaClient?.dispose();
    _locationSub?.cancel();
    _locationBloc?.close();
    _offlineTileManager?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SNGNav — Offline Map Demo'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          // View-mode toggle: 2D map <-> 3D forward-view. The control lives in
          // the AppBar (idiomatic for a top-level mode switch) and drives the
          // _viewMode field via setState \u2014 matching this page's existing
          // setState-based state pattern (no app-shell BLoC here).
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Center(
              child: SegmentedButton<_ViewMode>(
                showSelectedIcon: false,
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  textStyle: WidgetStatePropertyAll(
                    Theme.of(context).textTheme.labelSmall,
                  ),
                ),
                segments: const [
                  ButtonSegment<_ViewMode>(
                    value: _ViewMode.map,
                    icon: Icon(Icons.map_outlined, size: 16),
                    label: Text('2D map'),
                  ),
                  ButtonSegment<_ViewMode>(
                    value: _ViewMode.forward,
                    icon: Icon(Icons.landscape_outlined, size: 16),
                    label: Text('Forward'),
                  ),
                  ButtonSegment<_ViewMode>(
                    value: _ViewMode.pretrip,
                    icon: Icon(Icons.checklist_outlined, size: 16),
                    label: Text('Pre-trip'),
                  ),
                ],
                selected: {_viewMode},
                onSelectionChanged: (selection) {
                  setState(() => _viewMode = selection.first);
                },
              ),
            ),
          ),
          // Read-only GPS status from the REAL location feed. With no GPS_PORT
          // configured (or no fix yet) `_location` is null → "no GPS" icon and
          // the scene shows the honest "position unavailable" floor. As the
          // serial GPS delivers fixes this reflects fix / estimated / lost.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Tooltip(
              message: switch (_location?.quality) {
                null => 'No GPS — set --dart-define=GPS_PORT=/dev/ttyUSB0',
                LocationQuality.fix => 'GPS fix',
                LocationQuality.error => 'GPS lost — position unavailable',
                final q => 'GPS ${q.name}',
              },
              child: Icon(switch (_location?.quality) {
                LocationQuality.fix =>
                  _location!.isDeadReckoning ? Icons.gps_not_fixed : Icons.gps_fixed,
                LocationQuality.error => Icons.gps_off,
                null => Icons.gps_off,
                _ => Icons.gps_not_fixed,
              }),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Center(child: _buildCoverageBadge()),
          ),
        ],
      ),
      body: switch (_viewMode) {
        _ViewMode.map => _buildMapView(),
        _ViewMode.forward => _buildForwardView(),
        // INTENDED RE-MOUNT (lift consequence, recorded by design): pre-lift the
        // ~17 pretrip fields lived on this State and persisted across view
        // switches, so the pretrip inits ran once per page lifetime. Post-lift
        // PretripScreen is its own StatefulWidget mounted directly as a switch
        // arm (no IndexedStack / keepalive), so switching AWAY and BACK destroys
        // + recreates its State: initState re-runs (re-fetch of the opted-in live
        // forecast/visibility/dest-area, re-load of the saved place) and the
        // trip-required toggle resets. This is accepted-as-intended for the
        // reusable shared screen — the briefing recomputes correctly and every
        // fetch degrades honestly (no stale/false data). If keepalive is ever
        // wanted, host the three views in an IndexedStack here (in main.dart
        // only); mixing AutomaticKeepAliveClientMixin into the screen alone would
        // be a silent no-op under this plain `switch` body.
        _ViewMode.pretrip => PretripScreen(
            savedPlaceStore: widget.savedPlaceStore,
            destForecastProviderFactory: widget.destForecastProviderFactory,
            forecastSourceOverride: widget.forecastSourceOverride,
            surfaceState: _assessment.surfaceState,
          ),
      },
    );
  }

  /// The existing top-down 2D offline map (unchanged behaviour; now extracted
  /// so the body can switch between view modes).
  Widget _buildMapView() {
    return Stack(
      children: [
        FlutterMap(
          options: MapOptions(
            // Every one of these four comes from the archive that is actually
            // open, falling back per field to the demo constants when there is
            // none. minZoom in particular is the archive's own floor: the tile
            // resolver only ever walks DOWN in zoom looking for a parent, so
            // one step below the floor the map is blank — and it used to be
            // reachable, with the badge still reading green.
            initialCenter: _camera.center,
            initialZoom: _camera.zoom,
            minZoom: _camera.minZoom,
            maxZoom: _camera.maxZoom,
            onPositionChanged: (camera, _) => _onViewChanged(camera),
          ),
          children: [
            TileLayer(
              tileProvider:
                  _offlineTileManager?.tileProvider ?? NetworkTileProvider(),
              urlTemplate: _offlineTileManager == null
                  ? 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'
                  : null,
              // Declared explicitly (it is flutter_map's default) because
              // _coverage above must ask about the SAME tile set the renderer
              // requests. Measured on the embedded target 2026-08-29: 0 visible tiles
              // took the online branch and 18 tiles in this ring did.
              panBuffer: _panBuffer,
              userAgentPackageName: 'com.sngnav.getting_started',
            ),
            const SimpleAttributionWidget(
              source: Text('\u00a9 OpenStreetMap contributors'),
            ),
          ],
        ),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            color: Colors.black87,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              _statusMessage,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// The perspective forward-looking 3D snow scene.
  ///
  /// Honest bounds (see [SnowScene3DView] doc-comment): this is a CPU-projected
  /// still-frame pixel \u2014 no GPU/PBR/lighting; the fog is a linear gradient and
  /// precipitation a deterministic glance-cue sample, not a physics sim. It is
  /// fed by [_assessment], which is a SIMULATED default (rendered immediately,
  /// offline) and updates to LIVE Digitraffic winter-road severity only when the
  /// edge developer opts in with `--dart-define=WEATHER_PROVIDER=digitraffic`
  /// AND the feed is reachable; on any failure it stays on the simulated
  /// default. The advisory chip's text legibility at small sizes is a known gap.
  Widget _buildForwardView() {
    final String caption;
    if (_liveVehicleReceived) {
      caption = 'Forward-view \u2014 CPU-projected still frame, '
          'LIVE in-vehicle VSS signals (KUKSA databroker, offline-capable)';
    } else if (_liveConditionReceived) {
      caption = 'Forward-view \u2014 CPU-projected still frame, '
          'live Digitraffic winter-road severity';
    } else {
      caption = 'Forward-view \u2014 CPU-projected still frame, simulated default '
          '(live Digitraffic when WEATHER_PROVIDER=digitraffic; '
          'live in-vehicle when KUKSA_HOST set)';
    }
    return Stack(
      children: [
        SnowScene3DView(assessment: _assessment, location: _location),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            color: Colors.black87,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              caption,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ),
      ],
    );
  }
}
