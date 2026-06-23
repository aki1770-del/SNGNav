/// SNGNav Getting Started — Minimal offline map demo.
///
/// This is the shortest path from `git clone` to a working offline map.
/// It demonstrates:
/// - flutter_map rendering on Linux desktop
/// - MBTiles offline tile loading (no network required)
/// - Fallback to online OSM tiles when MBTiles file is absent
///
///
/// Usage:
///   1. Place `offline_tiles.mbtiles` in the `data/` directory
///   2. Run: flutter run -d linux
///   3. See the Chūbu region map (Nagoya / Toyota City area)
library;

import 'dart:async';
import 'dart:io';

import 'package:condition_aggregator_jma/condition_aggregator_jma.dart';
import 'package:driving_weather/driving_weather.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:kalman_dr/kalman_dr.dart';
import 'package:kuksa_dart_sdk/kuksa_dart_sdk.dart';
import 'package:latlong2/latlong.dart';
import 'package:offline_tiles/offline_tiles.dart' as offline_tiles;
import 'package:pretrip_decision_advisor/pretrip_decision_advisor.dart';
import 'package:snow_rendering/snow_rendering.dart';

import 'bloc/location_bloc.dart';
import 'bloc/location_event.dart';
import 'bloc/location_state.dart';
import 'config/provider_config.dart';
import 'fluorite/snow_scene_3d_view.dart';
import 'providers/digitraffic_visibility.dart';
import 'providers/jma_visibility.dart';
import 'providers/kuksa_condition_provider.dart';
import 'providers/met_norway_hourly_forecast.dart';
import 'providers/pretrip_live_forecast.dart';
import 'providers/serial_nmea_location_provider.dart';
import 'providers/winter_knowledge.dart';
import 'services/snow_aware_pretrip_advisor.dart';
import 'widgets/briefing_strings.dart';
import 'widgets/pretrip_briefing_card.dart';

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

class OfflineMapPage extends StatefulWidget {
  const OfflineMapPage({super.key});

  @override
  State<OfflineMapPage> createState() => _OfflineMapPageState();
}

class _OfflineMapPageState extends State<OfflineMapPage> {
  offline_tiles.OfflineTileManager? _offlineTileManager;
  bool _isOffline = false;
  String _statusMessage = 'Initializing...';

  // Default view is the existing 2D map — the toggle is opt-in, the app's
  // default behaviour is unchanged.
  _ViewMode _viewMode = _ViewMode.map;

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
      timestamp: DateTime(2026, 1, 1, 7, 15),
    ),
  );

  // The live weather provider (only constructed when WEATHER_PROVIDER=digitraffic).
  // Null on every offline/default path — the scene never depends on it existing.
  WeatherProvider? _weatherProvider;
  StreamSubscription<WeatherCondition>? _weatherSub;

  // True once a live condition has actually arrived from the feed, so the
  // caption can tell the truth about whether the scene reflects live severity
  // or the simulated default.
  bool _liveConditionReceived = false;

  // Offline winter-driving guidance cards (λ-RLM-baked, loaded once via a pure
  // asset read — no network/LLM). Null until loaded; the pre-trip briefing
  // omits the guidance block until then, or for a surface state with no card.
  WinterKnowledge? _winter;

  // LIVE IN-VEHICLE CONDITION SOURCE (D3 worst-case — network AND GPS gone).
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

  // PRE-TRIP BRIEFING (DRIVER_VOICES.md JAF voice: pre-trip — not in-trip —
  // is the load-bearing safety surface; everything above this line fires only
  // once she is already driving).
  //
  // OFFLINE-FIRST, like the assessment default: the briefing is computed from
  // a SIMULATED demo forecast (a morning where visibility collapses to
  // whiteout class around departure and clears two hours later) so the
  // surface renders immediately with zero network. The caption tells the
  // truth about the source.
  //
  // LIVE FORECAST (additive opt-in, same pattern as the Digitraffic / KUKSA
  // opt-ins above): `--dart-define=PRETRIP_FORECAST=met_norway` fetches the
  // MET Norway locationforecast hourly timeseries (a GLOBAL product — it
  // covers a Nagoya commute as well as a Nordic one) for PRETRIP_LAT /
  // PRETRIP_LON (defaulting to the app's Nagoya map center) and replaces the
  // demo forecast, with departure = the moment the briefing is computed
  // ("should I leave now?"). Data © MET Norway, CC BY 4.0 — the caption
  // carries the attribution.
  //
  // HONEST FALLBACK (no fabrication): on any fetch/parse failure the demo
  // forecast stays, the caption keeps saying "demo", and nothing live is
  // claimed. The compact product carries no visibility/surface fields, so
  // the live briefing's hazard signal comes from temperature + precipitation
  // alone (the advisor's icing rule) — fields the publisher did not forecast
  // are null, never estimated.
  //
  // The "trip required" switch is the contract's honesty rule made visible:
  // when on, the advisor never urges a delay — it names the hazard, helps her
  // prepare, and leaves the decision with her.
  bool _pretripTripRequired = false;

  static const String _pretripForecastSource =
      String.fromEnvironment('PRETRIP_FORECAST');
  // Forecast point — defaults to the app's Nagoya map center. Unparseable
  // overrides fall back to the default rather than guessing a location.
  static final double _pretripLat = double.tryParse(
          const String.fromEnvironment('PRETRIP_LAT')) ??
      35.1709;
  static final double _pretripLon = double.tryParse(
          const String.fromEnvironment('PRETRIP_LON')) ??
      136.8815;

  MetNorwayHourlyForecastProvider? _pretripForecastProvider;

  /// Live forecast + the departure it was fetched for; null until a real
  /// fetch succeeds (the demo forecast below stays the offline default).
  WeatherForecast? _pretripLiveForecast;
  DateTime? _pretripLiveDeparture;

  // Per-location live-source resolution (MET Norway global vs JMA Japan
  // snow-zone) and the HONEST status the caption switches on. JMA only ever
  // ADDS a road-condition band to the MET base; on ANY JMA failure the base
  // is kept and the caption says the warning check was UNAVAILABLE.
  PretripLiveStatus? _pretripLiveStatus;
  String? _pretripJmaEventName;
  String? _pretripJmaPrefecture;
  static const Duration _pretripWindow = Duration(minutes: 30);

  // MEASURED VISIBILITY (additive opt-in on top of the live forecast):
  // `--dart-define=PRETRIP_VISIBILITY=digitraffic` fetches the nearest fresh
  // visibility sensor on Finland's Digitraffic road-weather network (measured
  // 2026-06-12: 453/526 stations report visibility) and merges it into the
  // departure-hour slot ONLY. This is the one channel that can light the
  // severe band on live data — the 2026-06-12 quant run confirmed forecast
  // data alone can never reach it (0/620 slots; the compact product carries
  // no visibility, and we refuse to estimate it). Real sensor or nothing.
  // Applied only when the LIVE forecast is also present: merging a real
  // observation into the fixed demo timeline would be fabrication.
  // Data © Fintraffic / digitraffic.fi, CC BY 4.0 — caption carries it.
  //
  // `--dart-define=PRETRIP_VISIBILITY=jma` is the Japan equivalent: the nearest
  // fresh visibility sensor on JMA's AMeDAS network (probed 2026-06-14:
  // 151/1286 stations report visibility, incl. 秋田/Akita) — same merge, same
  // departure-hour-only rule, same real-sensor-or-nothing honesty. Data: 気象庁
  // / Japan Meteorological Agency (open data) — caption carries it.
  static const String _pretripVisibilitySource =
      String.fromEnvironment('PRETRIP_VISIBILITY');

  void Function()? _pretripVisibilityClose;
  VisibilityObservation? _pretripVisibility;

  static final DateTime _pretripDeparture = DateTime(2026, 1, 1, 7, 15);

  // Route-local civil offset OVERRIDE for the offline daylight clock, in integer
  // minutes from UTC (e.g. `--dart-define=PRETRIP_UTC_OFFSET_MIN=540` for JST
  // +9 h). Null (unset) means "derive the offset from the departure instant's
  // device-local offset" — see [_buildPretripView] for the full rationale and
  // the cross-timezone limitation this override exists to cover.
  static final int? _pretripUtcOffsetMin =
      int.tryParse(const String.fromEnvironment('PRETRIP_UTC_OFFSET_MIN'));

  static final WeatherForecast _pretripForecast = WeatherForecast(
    issuedAt: DateTime(2026, 1, 1, 6, 0),
    hourly: [
      HourlyForecast(
        hour: DateTime(2026, 1, 1, 7),
        tempCelsius: -4,
        precipitationMmPerHour: 2.5,
        visibilityMeters: 80, // whiteout class — below the 100 m band
        estimatedRoadCondition: RoadConditionEstimate.packedSnow,
      ),
      HourlyForecast(
        hour: DateTime(2026, 1, 1, 8),
        tempCelsius: -3,
        precipitationMmPerHour: 1.0,
        visibilityMeters: 250,
        estimatedRoadCondition: RoadConditionEstimate.packedSnow,
      ),
      HourlyForecast(
        hour: DateTime(2026, 1, 1, 9),
        tempCelsius: -1,
        precipitationMmPerHour: 0.0,
        visibilityMeters: 2000,
        estimatedRoadCondition: RoadConditionEstimate.dry,
      ),
      HourlyForecast(
        hour: DateTime(2026, 1, 1, 10),
        tempCelsius: 0,
        precipitationMmPerHour: 0.0,
        visibilityMeters: 5000,
        estimatedRoadCondition: RoadConditionEstimate.dry,
      ),
      HourlyForecast(
        hour: DateTime(2026, 1, 1, 11),
        tempCelsius: 1,
        precipitationMmPerHour: 0.0,
        visibilityMeters: 8000,
        estimatedRoadCondition: RoadConditionEstimate.dry,
      ),
    ],
  );

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

  // Nagoya Station — default center for Chūbu region tiles
  static const _nagoya = LatLng(35.1709, 136.8815);

  // MBTiles file path — relative to the project directory.
  // The edge developer places her .mbtiles file here.
  static const _mbtilesPath = 'data/offline_tiles.mbtiles';

  @override
  void initState() {
    super.initState();
    _initTileProvider();
    _initLiveWeather();
    _initKuksaConditions();
    _initLocation();
    _initPretripForecast();
    _initPretripVisibility();
    _initWinterKnowledge();
  }

  /// Loads the offline winter-driving guidance cards once (pure asset read,
  /// no network/LLM). On any failure the lookup is empty, so the briefing
  /// simply omits the guidance block — honest degradation, never a crash.
  Future<void> _initWinterKnowledge() async {
    final wk = await WinterKnowledge.fromAsset();
    if (mounted) setState(() => _winter = wk);
  }

  /// Fetches the nearest MEASURED visibility for the pre-trip briefing, but
  /// ONLY when the edge developer has opted in via
  /// `--dart-define=PRETRIP_VISIBILITY=digitraffic` (Finland) or `=jma`
  /// (Japan / AMeDAS). Honest floor on every failure path: no station in range,
  /// stale sensor, or fetch error → [_pretripVisibility] stays null and the
  /// briefing simply has no measured visibility — never an estimated one.
  Future<void> _initPretripVisibility() async {
    VisibilityObservation? obs;
    try {
      switch (_pretripVisibilitySource) {
        case 'digitraffic':
          final p = DigitrafficVisibilityProvider();
          _pretripVisibilityClose = p.close;
          obs = await p.fetchNearestVisibility(
              latitude: _pretripLat, longitude: _pretripLon);
        case 'jma':
          final p = JmaVisibilityProvider();
          _pretripVisibilityClose = p.close;
          obs = await p.fetchNearestVisibility(
              latitude: _pretripLat, longitude: _pretripLon);
        default:
          return; // not selected
      }
    } catch (_) {
      // Network unreachable / API failure → honest floor: no measured
      // visibility, nothing estimated in its place.
      return;
    }
    if (!mounted || obs == null) return;
    setState(() => _pretripVisibility = obs);
  }

  /// Fetches a LIVE hourly forecast for the pre-trip briefing, but ONLY when
  /// the edge developer has opted in via
  /// `--dart-define=PRETRIP_FORECAST=met_norway`. On every other path this is
  /// a no-op and the briefing keeps its simulated demo forecast
  /// (offline-first preserved).
  ///
  /// All failures degrade honestly: on fetch/parse error or an empty hourly
  /// timeseries, [_pretripLiveForecast] stays null, the briefing stays on the
  /// demo forecast, and the caption keeps saying "demo" — a live source is
  /// never claimed that did not actually deliver.
  Future<void> _initPretripForecast() async {
    if (_pretripForecastSource != 'met_norway') return; // not selected
    final met = MetNorwayHourlyForecastProvider();
    _pretripForecastProvider = met;
    final jma = JmaAdvisoryProvider();
    final result = await resolvePretripLiveForecast(
      latitude: _pretripLat,
      longitude: _pretripLon,
      now: DateTime.now(),
      window: _pretripWindow,
      fetchMetForecast: () =>
          met.fetchForecast(latitude: _pretripLat, longitude: _pretripLon),
      fetchJmaAdvisories: () async {
        // init() is idempotent; close() releases the client after the fetch.
        await jma.init();
        try {
          return await jma.fetchActiveAdvisoriesAtPoint(
            latitude: _pretripLat,
            longitude: _pretripLon,
          );
        } finally {
          jma.close();
        }
      },
    );
    // Honest floor: the orchestrator never throws, and a null forecast means
    // no live source delivered → the offline demo forecast stays, nothing live
    // is claimed.
    if (!mounted || result.forecast == null) return;
    setState(() {
      _pretripLiveForecast = result.forecast; // already JMA-merged when applicable
      _pretripLiveDeparture = result.departure;
      _pretripLiveStatus = result.status;
      _pretripJmaEventName = result.jmaEventName;
      _pretripJmaPrefecture = result.prefectureCode;
    });
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

      _weatherSub = provider.conditions.listen(
        (condition) {
          // Reuse the proven mapping the rest of the app uses:
          // WeatherCondition -> DrivingConditionAssessment.
          if (!mounted) return;
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

  Future<void> _initTileProvider() async {
    final file = File(_mbtilesPath);
    try {
      if (await file.exists()) {
        final manager = offline_tiles.OfflineTileManager(
          tileSource: offline_tiles.TileSourceType.mbtiles,
          mbtilesPath: _mbtilesPath,
        );
        setState(() {
          _offlineTileManager = manager;
          _isOffline = true;
          _statusMessage =
              'Offline — MBTiles loaded (${_formatSize(file.lengthSync())})';
        });
      } else {
        setState(() {
          _offlineTileManager = null;
          _isOffline = false;
          _statusMessage =
              'No MBTiles file at $_mbtilesPath — using online fallback';
        });
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'MBTiles error: $e — using online fallback';
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
    _pretripForecastProvider?.close();
    _pretripVisibilityClose?.call();
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
        _ViewMode.pretrip => _buildPretripView(),
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
            initialCenter: _nagoya,
            initialZoom: 11,
            minZoom: 6,
            maxZoom: 16,
          ),
          children: [
            TileLayer(
              tileProvider:
                  _offlineTileManager?.tileProvider ?? NetworkTileProvider(),
              urlTemplate: _offlineTileManager == null
                  ? 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'
                  : null,
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

  /// The pre-trip "Before you drive" briefing — the upstream safety surface
  /// the JAF driver voice argues matters most. Computed deterministically by
  /// [SnowAwarePretripAdvisor] from the simulated demo forecast, or from a
  /// LIVE MET Norway hourly forecast when the edge developer opted in via
  /// `--dart-define=PRETRIP_FORECAST=met_norway` AND the fetch succeeded;
  /// the "trip required" switch demonstrates the contract's honesty rule.
  Widget _buildPretripView() {
    // The whole pre-trip surface reads in the driver's own language — Japanese
    // for HER mother in Akita — resolved ONCE from the app's active locale so
    // the chips, the card's structural strings, and the winter card never
    // diverge on which locale they used.
    final locale = Localizations.localeOf(context);
    final strings = BriefingStrings.of(locale);
    final advisor = SnowAwarePretripAdvisor(
      messages: PretripMessages.forLanguage(locale.languageCode),
    );
    final live = _pretripLiveForecast;
    var forecast = live ?? _pretripForecast;
    // Normalize the departure instant ONCE at its single source so the offset
    // AND the instant handed to [CommuteShape] share the same converted value.
    // `.toLocal()` is a no-op for the local DateTimes we have today (the demo
    // literal 07:15 and the live DateTime.now() are both local), but if a
    // future path stamps the departure UTC, converting here keeps the daylight
    // clock's raw wall-clock fields and the route offset consistent.
    final departure =
        (live != null ? _pretripLiveDeparture! : _pretripDeparture).toLocal();

    // Real measured visibility merges into the departure hour ONLY, and only
    // on top of a live forecast (never the fixed demo timeline).
    final obs = live != null ? _pretripVisibility : null;
    if (obs != null) {
      forecast = mergeObservedVisibility(forecast, obs, departure);
    }

    final visAttribution = _pretripVisibilitySource == 'jma'
        ? 'Japan Meteorological Agency / AMeDAS (気象庁)'
        : 'Fintraffic / digitraffic.fi (CC BY 4.0)';
    final visCaption = obs != null
        ? ' Departure-hour visibility MEASURED: ${obs.meters.round()} m at '
            '${obs.stationName} (${obs.distanceKm.toStringAsFixed(0)} km '
            'away) — data: $visAttribution.'
        : '';
    final caption = live != null
        ? pretripLiveSourceCaption(
            status: _pretripLiveStatus ?? PretripLiveStatus.metNorway,
            latitude: _pretripLat,
            longitude: _pretripLon,
            prefectureCode: _pretripJmaPrefecture,
            eventGloss: _pretripJmaEventName == null
                ? null
                : jmaEventEnglishGloss(_pretripJmaEventName!),
            visCaption: visCaption,
          )
        : strings.simulatedForecastCaption +
            (_pretripForecastSource == 'met_norway'
                ? strings.liveFetchUnavailableSuffix
                : '');
    // OFFLINE DAYLIGHT CLOCK — route-local civil offset for the daylight chip.
    //
    // The [CommuteShape] departure above is a NAIVE wall-clock time in the
    // ROUTE's civil timezone (the demo literal 07:15 and the live
    // DateTime.now() the resolver stamps are both LOCAL DateTimes; `departure`
    // is `.toLocal()`-normalized at its source). The daylight astronomy needs
    // that route offset to know when the trip crosses sunset into the refreeze
    // + 薄暮 (twilight) hours.
    //
    // SOURCE OF TRUTH (offline, zero-dep): the local UTC offset of the
    // already-converted departure instant — `departure.timeZoneOffset`. Because
    // `departure` was `.toLocal()`-converted at its single source, this offset
    // and the wall-clock fields the package reads come from the SAME instant, so
    // a future UTC-stamped departure cannot leave the offset and the clock out
    // of step. This is EXACTLY correct whenever the device timezone == the route
    // timezone — HER dominant case (a Japanese device driving in/to Japan,
    // JST +9, no DST).
    //
    // LIMITATION: when the route and the device are in DIFFERENT timezones (a
    // cross-zone edge developer), the device offset is wrong for the route, so
    // pass `--dart-define=PRETRIP_UTC_OFFSET_MIN=<minutes>` to override. We
    // deliberately do NOT guess from longitude/15: a solar guess can mis-place
    // HER wall clock by up to an hour, and a wrong sunrise time is worse than no
    // chip at all.
    final utcOffset = _pretripUtcOffsetMin != null
        ? Duration(minutes: _pretripUtcOffsetMin!)
        : departure.timeZoneOffset;
    final geo = TripGeo(
      latitude: _pretripLat,
      longitude: _pretripLon,
      utcOffset: utcOffset,
    );
    final commute = CommuteShape(
      plannedDeparture: departure,
      plannedDuration: _pretripWindow,
      routeIdentifiers: const ['demo-commute'],
      flexibility: _pretripTripRequired
          ? CommuteFlexibility.required
          : CommuteFlexibility.discretionary,
      geo: geo,
    );
    final briefing = advisor.brief(
      forecast: forecast,
      commute: commute,
      profile: const DriverProfileSpec(
        profileTag: 'demo',
        reactionTimeSeconds: 1.5,
      ),
    );
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: PretripBriefingCard(
          // The briefing reads in the driver's own language — Japanese for HER
          // mother in Akita — resolved once from the app's active locale above.
          strings: strings,
          briefing: briefing,
          commute: commute,
          forecastIssuedAt: forecast.issuedAt,
          tripRequired: _pretripTripRequired,
          onTripRequiredChanged: (v) =>
              setState(() => _pretripTripRequired = v),
          sourceCaption: caption,
          // Grounded offline guidance for the surface state the assessment
          // expects; null (omitted) until the asset loads or for a benign
          // surface with no baked card. Resolved in the driver's language —
          // Japanese for HER mother when a verified card exists, else the
          // grounded English (honest fallback, never blank).
          winterCard: _winter?.cardFor(
            _assessment.surfaceState,
            lang: locale.languageCode,
          ),
        ),
      ),
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
