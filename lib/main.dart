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
/// - en/ja locale: the briefing follows the device locale so it reaches HER
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
import 'package:flutter/services.dart' show rootBundle;
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
      // The pre-trip safety briefing must reach HER mother in Akita, who reads
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

/// Test seams for the offline-basemap resolver (OPS-068 2026-07-19): under
/// `flutter test` the repo-relative mbtiles candidate always exists, so the
/// extraction and honest-absence branches are unreachable without these.
/// Production leaves all three null.
@visibleForTesting
List<String>? debugMbtilesCandidatesOverride;
@visibleForTesting
Map<String, String>? debugMbtilesEnvOverride;
@visibleForTesting
Directory? debugMbtilesExtractBaseOverride;

class OfflineMapPage extends StatefulWidget {
  const OfflineMapPage({
    super.key,
    this.savedPlaceStore,
    this.destForecastProviderFactory,
    this.forecastSourceOverride,
  });

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
  bool _isOffline = false;
  String _statusMessage = 'Initializing...';

  // Default view is the existing 2D map — the toggle is opt-in, the app's
  // default behaviour is unchanged.
  // Boot default = the glanceable forward scene (purpose: on the IVI the
  // compositor owns layout and the app cannot self-foreground — the default
  // view IS the glance; the map/pretrip stay one tap away).
  _ViewMode _viewMode = _ViewMode.forward;

  // The driving-condition picture fed to the 3D forward-view.
  //
  // OFFLINE-FIRST (D3 worst-case — non-negotiable): this field is initialised
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

  // LIVE IN-VEHICLE CONDITION SOURCE — an EMBEDDED / IVI-TARGET signal source.
  //
  // WHAT IT IS: on a build running on a vehicle head-unit (or an embedded target
  // already attached to the vehicle's own network), the car's ECUs publish
  // road-friction (ESC), TCS/ABS/ESC engagement, wiper/rain intensity, ambient
  // temperature and humidity onto a local KUKSA databroker. We subscribe to
  // those VSS leaves over gRPC via the `kuksa_dart_sdk` client and fuse them
  // DETERMINISTICALLY (in `package:vehicle_condition_fusion`) into the exact
  // same DrivingConditionAssessment the Digitraffic path produces. On a real
  // vehicle bus this is a genuine sensor the cloud cannot replace.
  //
  // WHAT IT IS NOT — and this comment previously claimed otherwise:
  // it is NOT the D3 compound-failure lifeline and NOT the offline safety path.
  //  * A databroker is ANOTHER NETWORK HOP (a gRPC dial). "No cloud" != "no
  //    network". Unreachable host → this source produces nothing at all.
  //  * A PHONE CANNOT TOUCH THAT BUS. This stack ships ZERO BYTES onto the
  //    driver's handset; on the phone build KUKSA_HOST is unset and every line
  //    below is a no-op. The offline safety path is the bundled on-device one.
  // Claiming this as the "network AND GPS gone" path was a fabrication about our
  // own reach. It is a real capability — on a different target.
  //
  // SOURCE SELECTION (additive — never replaces the offline default or the
  // Digitraffic opt-in): wired ONLY when the edge developer opts in with
  // `--dart-define=KUKSA_HOST=<broker host>` (e.g. localhost on an IVI
  // headunit). On every other path it is a no-op and the scene keeps its
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

  // VSS leaves the fusion reads that THIS vehicle's broker does not publish, so
  // the subscription omitted them (KuksaConditionProvider.connect's per-signal
  // degradation). Empty is the only state meaning "the fusion sees everything".
  //
  // WHY THIS IS ON SCREEN AND NOT JUST IN A LOG: the fusion refuses to fabricate
  // from a missing signal, so a signal it never receives makes it fail toward NO
  // ice warning while the ice is real. Losing humidity does not dim a feature —
  // it removes the ability to warn BEFORE the wheels slip. A partial feed
  // captioned as a plain live feed would be exactly that silent false-clear.
  Set<String> _kuksaUnsubscribed = const {};

  // Black-ice detection CAPABILITY, derived per-update from the signals that
  // ACTUALLY ARRIVED — never from the subscription set.
  //
  // Reading capability from data closes three doors one path-set cannot see: the
  // leaf that was never subscribed, the leaf that is exposed but never valued,
  // and the value `fromVss` rejected as out-of-spec. `fromVss` has already
  // nulled each of them.
  //
  // The predicates mirror `_iceRisk` (`vehicle_signal_fusion.dart:108-126`):
  //  * ice can be attributed AT ALL when there is a friction reading, OR an
  //    ambient temperature together with at least one traction-loss signal;
  //  * it can be seen BEFORE a slip only with humidity AND temperature — the
  //    radiative-frost pair.
  // `true` until a live update says otherwise, so we never caption a capability
  // claim before any signal has arrived.
  bool _kuksaIceAttributable = true;
  bool _kuksaPreSlipCapable = true;

  // HONEST GPS-LOSS DEGRADATION (D3 worst-case — GPS fails).
  //
  // The 3D forward-view is driven by weather alone; on its own it would keep
  // painting a confident, crisp road even when GPS is lost and the real
  // position is drifting — the dishonest failure D4 forbids. The fix is to feed
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

  // Akita City — the bundled basemap's own center (archive metadata:
  // center 140.10,39.72; bounds cover Akita prefecture). The pre-position
  // view must open on REAL tiles, not a blank region outside the archive.
  static const _akitaCenter = LatLng(39.72, 140.10);

  // Offline basemap resolution — offline is constitutive (purpose clause 4).
  // Candidates are tried in order; if none is a real file, the bundled asset
  // is extracted once to a writable dir (embedder-safe: no path_provider —
  // ivi-homescreen registers none; same fallback family as saved_place_store).
  static const _mbtilesEnvVar = 'SNGNAV_MBTILES';
  static const _mbtilesCandidates = <String>[
    // IVI image / integrator-installed absolute path:
    '/usr/share/sngnav/akita_offline.mbtiles',
    // Repo/dev working-dir paths (edge-developer workflow, unchanged):
    'assets/tiles/akita_offline.mbtiles',
    'data/offline_tiles.mbtiles',
  ];
  static const _mbtilesAsset = 'assets/tiles/akita_offline.mbtiles';

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
      // Per-signal degradation is only honest if it is DISCLOSED. Capture which
      // leaves this broker could not supply, so the caption can NAME them.
      // Detection capability is NOT derived from this set — see the listener.
      if (provider.unsubscribedPaths.isNotEmpty && mounted) {
        setState(() => _kuksaUnsubscribed = provider.unsubscribedPaths);
      }
      _kuksaSub = provider.conditions.listen(
        (update) {
          if (!mounted) return;
          if (!update.isAvailable) {
            // Honest "no live vehicle signals": keep last-good/default, never
            // fabricate — just stop claiming the scene is live.
            setState(() => _liveVehicleReceived = false);
            return;
          }
          // Capability from the ARRIVED signals (carried-forward merged snapshot
          // on the partial-frame rail), mirroring `_iceRisk`. A path set cannot
          // see a leaf that is exposed-but-never-valued, nor a value `fromVss`
          // rejected as out-of-spec; a null field can.
          final iceAttributable =
              KuksaConditionProvider.iceAttributableFrom(update.signals);
          final preSlipCapable =
              KuksaConditionProvider.preSlipCapableFrom(update.signals);
          setState(() {
            _assessment = update.assessment!;
            _liveVehicleReceived = true;
            _kuksaIceAttributable = iceAttributable;
            _kuksaPreSlipCapable = preSlipCapable;
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

  /// Resolve the offline basemap to a real file path: env override → file
  /// candidates → one-time extraction of the bundled asset to a writable dir.
  /// Returns null only when every route fails — the map then degrades
  /// HONESTLY (no silent online fetch; purpose clause 4).
  ///
  /// Test seams ([debugMbtilesCandidatesOverride] etc.) exist because under
  /// `flutter test` the repo-relative candidate always exists, which would
  /// leave the extraction + honest-absence branches untestable (OPS-068
  /// review finding, 2026-07-19).
  Future<String?> _resolveMbtilesPath() async {
    final env = debugMbtilesEnvOverride ?? Platform.environment;
    final candidates = debugMbtilesCandidatesOverride ?? _mbtilesCandidates;
    final override = env[_mbtilesEnvVar];
    for (final p in [if (override != null && override.isNotEmpty) override,
        ...candidates]) {
      if (File(p).existsSync()) return p;
    }
    // Extract the bundled asset (sqlite needs a real file). Writable-dir
    // fallback chain mirrors saved_place_store (embedder has no path_provider).
    try {
      final home = env['HOME'];
      // The test seam REPLACES the base list (not prepends): otherwise the
      // always-writable systemTemp candidate would make the honest-absence
      // branch unreachable in tests — the exact blind spot the seam closes.
      final bases = debugMbtilesExtractBaseOverride != null
          ? <Directory>[debugMbtilesExtractBaseOverride!]
          : <Directory>[
              if (home != null && home.isNotEmpty)
                Directory('$home/.local/share/sngnav'),
              Directory('${Directory.systemTemp.path}/sngnav'),
            ];
      Directory? base;
      for (final b in bases) {
        // Real write probe, not `createSync` — an existing-but-unwritable dir
        // (locked IVI rootfs) passes `createSync` silently and would be
        // accepted here, making the systemTemp candidate below unreachable and
        // deferring the failure to the 16 MB extraction write. See
        // [isDirectoryWritable] in services/saved_place_store.dart.
        if (isDirectoryWritable(b)) {
          base = b;
          break;
        }
      }
      if (base == null) return null;
      final out = File('${base.path}/akita_offline.mbtiles');
      final data = await rootBundle.load(_mbtilesAsset);
      if (!out.existsSync() || out.lengthSync() != data.lengthInBytes) {
        await out.writeAsBytes(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          flush: true,
        );
      }
      return out.path;
    } catch (e) {
      debugPrint('offline basemap asset extraction failed: $e');
      return null;
    }
  }

  Future<void> _initTileProvider() async {
    try {
      final path = await _resolveMbtilesPath();
      if (path != null) {
        final manager = offline_tiles.OfflineTileManager(
          tileSource: offline_tiles.TileSourceType.mbtiles,
          mbtilesPath: path,
          // Honest degradation must be QUIET, not a crash: with online
          // fallback on (the package default), an out-of-archive tile would
          // resolve to the network route and the urlTemplate-less TileLayer
          // throws an unguarded ArgumentError inside flutter_map. False ⇒
          // out-of-coverage tiles render the transparent placeholder
          // (OPS-068 review MUST, 2026-07-19).
          allowOnlineFallback: false,
        );
        setState(() {
          _offlineTileManager = manager;
          _isOffline = true;
          _statusMessage =
              'Offline — MBTiles loaded (${_formatSize(File(path).lengthSync())})';
        });
      } else {
        // Honest degradation: NO silent online basemap. The ground stays
        // visibly absent and the status line says why; position/route layers
        // still orient. (Offline is constitutive — an online fallback would
        // fabricate capability the snow will take away.)
        setState(() {
          _offlineTileManager = null;
          _isOffline = false;
          _statusMessage =
              'オフライン地図が利用できません — offline basemap unavailable '
              '(no file, asset extraction failed)';
        });
      }
    } catch (e) {
      setState(() {
        _offlineTileManager = null;
        _isOffline = false;
        _statusMessage = 'MBTiles error: $e — offline map unavailable';
      });
    }
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
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _isOffline ? Icons.wifi_off : Icons.wifi,
                    size: 16,
                    color: _isOffline ? Colors.green : Colors.orange,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _isOffline ? 'OFFLINE' : 'ONLINE',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: _isOffline ? Colors.green : Colors.orange,
                    ),
                  ),
                ],
              ),
            ),
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
            initialCenter: _akitaCenter,
            initialZoom: 11,
            minZoom: 6,
            maxZoom: 16,
          ),
          children: [
            if (_offlineTileManager != null)
              TileLayer(
                tileProvider: _offlineTileManager!.tileProvider,
                userAgentPackageName: 'com.sngnav.getting_started',
              )
            else
              // Honest offline-degraded ground (purpose clause 4): no silent
              // online OSM — a network basemap fabricates capability the snow
              // will take away. Position/route layers below still orient.
              IgnorePointer(
                child: Container(
                  color: const Color(0xFFE8E4DA),
                  alignment: Alignment.center,
                  child: const Text(
                    'オフライン地図が利用できません\noffline basemap unavailable',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFF8A8578), fontSize: 16),
                  ),
                ),
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
              key: const Key('status-message'),
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
      // NOT "offline-capable": a KUKSA databroker is a network hop to a vehicle
      // bus. It is a live IVI/embedded source, not the offline path.
      const base = 'Forward-view \u2014 CPU-projected still frame, '
          'LIVE in-vehicle VSS signals (KUKSA databroker on the vehicle bus)';
      // Three states, and the SAFETY sentence is driven by measured capability \u2014
      // never by the subscription set. An earlier cut derived it from a static
      // path list and so promised detection "AFTER traction is lost" on vehicles
      // that could not attribute ice at all: an explicit on-screen false
      // assurance, worse than the silence this change was written to fix.
      final missing = _kuksaUnsubscribed.isEmpty
          ? ''
          : ' (absent: ${(_kuksaUnsubscribed.toList()..sort()).join(', ')})';
      if (!_kuksaIceAttributable) {
        caption = '$base \u2014 PARTIAL$missing: this vehicle cannot determine '
            'black ice from its own sensors. Treat the road as unknown.';
      } else if (!_kuksaPreSlipCapable) {
        caption = '$base \u2014 PARTIAL$missing: early black-ice detection '
            'unavailable on this vehicle.';
      } else if (_kuksaUnsubscribed.isNotEmpty) {
        caption = '$base \u2014 PARTIAL$missing.';
      } else {
        caption = base;
      }
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
