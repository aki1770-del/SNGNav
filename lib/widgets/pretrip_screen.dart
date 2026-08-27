/// Shared pre-trip "Before you drive" briefing screen.
///
/// Lifted VERBATIM out of `lib/main.dart`'s `_OfflineMapPageState` so BOTH the
/// `lib/main.dart` reference entrypoint AND the `lib/snow_scene.dart` product
/// demo host the SAME pre-trip safety surface via one reusable widget (the
/// upstream JAF "pre-trip is the load-bearing safety surface" voice).
///
/// The lift is a MOVE, not a rewrite: the only behaviour changes vs the prior
/// inline `_buildPretripView` are (1) the winter-card surface state now comes
/// from [PretripScreen.surfaceState] (the host's assessment) instead of a
/// host-private `_assessment` field, and (2) the test seams
/// (savedPlaceStore / destForecastProviderFactory / forecastSourceOverride)
/// are read from `widget.*`. Everything else — the offline-first defaults, the
/// one-shot reads (no Timer/Stream/poll), the single local record, the honest
/// area-condition ceiling, the durable-clear tombstone — is carried verbatim.
library;

// `Advisory` (the source-neutral typed event) is the element type of the
// optional JMA-fetch test seam below; the JMA umbrella does not re-export it.
import 'package:condition_aggregator/condition_aggregator.dart';
import 'package:condition_aggregator_jma/condition_aggregator_jma.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:pretrip_decision_advisor/pretrip_decision_advisor.dart';
import 'package:snow_rendering/snow_rendering.dart';

import '../providers/digitraffic_visibility.dart';
import '../providers/jma_visibility.dart';
import '../providers/met_norway_hourly_forecast.dart';
import '../providers/pretrip_live_forecast.dart';
import '../providers/pretrip_route_bridges.dart';
import '../providers/winter_knowledge.dart';
import '../services/bridge_corridor_read.dart';
import '../services/saved_place_store.dart';
import '../services/snow_aware_pretrip_advisor.dart';
import 'briefing_strings.dart';
import 'family_area_card.dart';
import 'place_entry_dialog.dart';
import 'pretrip_briefing_card.dart';

/// The pre-trip "Before you drive" briefing — the upstream safety surface the
/// JAF driver voice argues matters most. Computed deterministically by
/// [SnowAwarePretripAdvisor] from the simulated demo forecast, or from a LIVE
/// MET Norway hourly forecast when the edge developer opted in via
/// `--dart-define=PRETRIP_FORECAST=met_norway` AND the fetch succeeded.
///
/// Reusable + host-agnostic: it holds its own pre-trip state and reads its
/// destination-area test seams + the winter-card surface state from the host
/// via constructor params, so it drops into both app entrypoints unchanged.
class PretripScreen extends StatefulWidget {
  const PretripScreen({
    super.key,
    this.savedPlaceStore,
    this.destForecastProviderFactory,
    this.forecastSourceOverride,
    this.jmaAdvisoryFetchOverride,
    this.metForecastFetchOverride,
    this.routeBridgesOverride,
    this.routeShapeFetchOverride,
    this.bridgeCsvLoadOverride,
    this.routeOsrmUrlOverride,
    this.bridgeGateNowOverride,
    this.pretripPointOverride,
    required this.surfaceState,
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

  /// Optional test seam: overrides the live JMA advisory fetch at a point, so a
  /// fake advisory list — INCLUDING an in-band incomplete-read notice — can be
  /// injected without a socket, and the partial-read reach is verified by a
  /// plain `flutter test`. Production constructs a real [JmaAdvisoryProvider]
  /// when null (the live behaviour is byte-for-byte unchanged). Used by BOTH
  /// the current-location briefing and the destination-area read.
  final Future<List<Advisory>> Function({
    required double latitude,
    required double longitude,
  })? jmaAdvisoryFetchOverride;

  /// Optional test seam: overrides the CURRENT-LOCATION live MET forecast
  /// fetch at a point, so the briefing's live path — and everything gated on
  /// it, e.g. the bridge caution's departure-window temperature gate — is
  /// exercisable by a plain `flutter test` without a socket or a
  /// `--dart-define`. Null in production ⇒ the compile-time `PRETRIP_FORECAST`
  /// gate + the real [MetNorwayHourlyForecastProvider] are used, byte-for-byte
  /// as before.
  final Future<WeatherForecast?> Function()? metForecastFetchOverride;

  /// Optional test seam: overrides the CURRENT-LOCATION forecast point (the
  /// compile-time `PRETRIP_LAT`/`PRETRIP_LON` defines), so the Japan
  /// snow-zone routing — and everything gated on it, e.g. the JMA warning
  /// lanes — is exercisable at an Akita point by a plain `flutter test`.
  /// Null in production ⇒ the compile-time defines are used, byte-for-byte
  /// as before.
  final ({double lat, double lon})? pretripPointOverride;

  /// Optional test seam: replaces the WHOLE opt-in route+asset bridge resolve
  /// (the `PRETRIP_ROUTE_OSRM_URL` gate + one-shot OSRM fetch + bundled-asset
  /// load) so the bridge caution is exercisable without network. Null in
  /// production ⇒ the real one-shot resolve. Returning null ⇒ the section is
  /// ABSENT (the honest floor, exactly as in production). For pinning the
  /// production arm ITSELF (gate + saved-place + coordinate threading), use
  /// the narrower seams below instead.
  final Future<BridgeCorridorResult?> Function()? routeBridgesOverride;

  /// Optional test seam (PRODUCTION-ARM): overrides ONLY the OSRM route-shape
  /// fetch inside the real one-shot wiring, so the `PRETRIP_ROUTE_OSRM_URL`
  /// gate, the memoized saved-place await, the no-destination return and the
  /// origin/destination threading all run REAL in tests. Receives the exact
  /// coordinates production threads into the fetch — a swapped pair would
  /// ship a plausible-but-wrong count, which is why this seam exists. Null in
  /// production ⇒ the real [fetchOsrmRouteShape].
  final Future<List<LatLng>> Function({
    required double originLat,
    required double originLon,
    required double destLat,
    required double destLon,
  })? routeShapeFetchOverride;

  /// Optional test seam (PRODUCTION-ARM): overrides the bundled bridge-CSV
  /// load inside the real wiring (pairs with [routeShapeFetchOverride]).
  /// Null in production ⇒ [loadBridgeCsvAsset].
  final Future<String> Function()? bridgeCsvLoadOverride;

  /// Optional test seam (PRODUCTION-ARM): stands in for the compile-time
  /// `PRETRIP_ROUTE_OSRM_URL` opt-in so a plain `flutter test` can exercise
  /// the gate in both directions. Null in production ⇒ the compile-time
  /// define (byte-for-byte unchanged).
  final String? routeOsrmUrlOverride;

  /// Optional test seam: the "now" the bridge caution's season band uses (its
  /// no-cold-evidence arm is month-gated, Oct–Apr). Null in production ⇒
  /// [DateTime.now] at build time.
  final DateTime? bridgeGateNowOverride;

  /// The road-surface state the host's driving-condition assessment expects;
  /// drives the offline winter-driving guidance card. The host owns the
  /// assessment (live/simulated); this screen only reads its surface state.
  ///
  /// **Nullable** (snow_rendering 0.3.0): `null` means the surface COULD NOT BE
  /// CLASSIFIED — the feed carried no ice risk, no temperature and no
  /// precipitation type. It does not mean `dry`. There is no winter card for a
  /// road nobody measured, and inventing the dry card (which is what the old
  /// non-nullable fall-through did, gripFactor 1.0 and all) is the defect.
  final RoadSurfaceState? surfaceState;

  @override
  State<PretripScreen> createState() => _PretripScreenState();
}

class _PretripScreenState extends State<PretripScreen> {
  // Offline winter-driving guidance cards (λ-RLM-baked, loaded once via a pure
  // asset read — no network/LLM). Null until loaded; the pre-trip briefing
  // omits the guidance block until then, or for a surface state with no card.
  WinterKnowledge? _winter;

  // PRE-TRIP BRIEFING (DRIVER_VOICES.md JAF voice: pre-trip — not in-trip —
  // is the load-bearing safety surface).
  //
  // OFFLINE-FIRST, like the assessment default: the briefing is computed from
  // a SIMULATED demo forecast (a morning where visibility collapses to
  // whiteout class around departure and clears two hours later) so the
  // surface renders immediately with zero network. The caption tells the
  // truth about the source.
  //
  // LIVE FORECAST (additive opt-in): `--dart-define=PRETRIP_FORECAST=met_norway`
  // fetches the MET Norway locationforecast hourly timeseries (a GLOBAL
  // product — it covers a Nagoya commute as well as a Nordic one) for
  // PRETRIP_LAT / PRETRIP_LON (defaulting to the app's Nagoya map center) and
  // replaces the demo forecast, with departure = the moment the briefing is
  // computed ("should I leave now?"). Data © MET Norway, CC BY 4.0 — the
  // caption carries the attribution.
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
  static final double _pretripLatDefault = double.tryParse(
          const String.fromEnvironment('PRETRIP_LAT')) ??
      35.1709;
  static final double _pretripLonDefault = double.tryParse(
          const String.fromEnvironment('PRETRIP_LON')) ??
      136.8815;

  // The effective point: the test seam wins when supplied; production is the
  // compile-time define, byte-for-byte as before.
  double get _pretripLat =>
      widget.pretripPointOverride?.lat ?? _pretripLatDefault;
  double get _pretripLon =>
      widget.pretripPointOverride?.lon ?? _pretripLonDefault;

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

  // PARTIAL-READ at HER current location: a border read where a containing
  // prefecture was unreachable. When true, the briefing shows an honest caution
  // (naming [_pretripJmaUnreachableArea]) — a partial read is never presented as
  // a complete warning check, even when a real warning DID merge.
  bool _pretripJmaBorderCheckIncomplete = false;
  String? _pretripJmaUnreachableArea;

  // In-force NON-snow JMA warnings (0.4.0 turmoil classes: 大雨 / 暴風・強風 /
  // 雷 / 濃霧) at HER current location — relayed verbatim as advisory cards,
  // highest severity first. Never merged into the road-condition band.
  List<Advisory> _pretripJmaTurmoilAdvisories = const <Advisory>[];
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

  // ROUTE BRIDGE CAUTION (additive opt-in):
  // `--dart-define=PRETRIP_ROUTE_OSRM_URL=<url>` fetches the REAL route
  // polyline ONCE PER DESTINATION EPOCH (origin = the briefing point,
  // destination = the driver-set destination) via the existing OSRM engine,
  // and counts the mapped bridge sites on it — bridge decks freeze before
  // the road surface does. One epoch = one destination: the resolve fires at
  // pre-trip initialization, and again exactly once when SHE sets a NEW
  // destination in-app; clearing the destination clears the count and
  // resolves NOTHING. ANY failure (no URL, no destination, network error,
  // empty shape, missing asset) ⇒ the feature is ABSENT: no section, no
  // error banner, no substitute claim. No Timer/Stream/poll and no re-fetch
  // on rebuild — the same HER-action-only discipline as the destination-area
  // read above.
  static const String _pretripRouteOsrmUrl =
      String.fromEnvironment('PRETRIP_ROUTE_OSRM_URL');

  /// The corridor-match result for the CURRENT destination epoch; null until
  /// (and unless) a real route AND the bridge dataset both delivered for that
  /// epoch. Null ⇒ no bridge section.
  BridgeCorridorResult? _routeBridges;

  /// Destination identity, bumped by the two HER-action mutations
  /// ([_setDestination] / [_clearDestination]). The route resolve (and the
  /// destination-area read) can be in flight for up to ~15 s; if SHE changes
  /// or clears the destination in that window, the late result describes the
  /// PRIOR destination — landing it would be exactly the false claim the
  /// clear-on-change contract forbids. [_initRouteBridges] and
  /// [_initDestAreaCondition] capture this before their awaits and drop the
  /// result on mismatch (honest absence); the fresh resolve the setter fires
  /// owns the new epoch.
  int _destEpoch = 0;

  // DESTINATION-AREA condition read (the FAMILY-THREAD section): the PUBLIC
  // weather + official advisory at a PLACE — "what conditions will SHE face in
  // her mother's area if she drives there", so she decides whether/when to go.
  //
  // The destination point comes ONLY from these static defines. It NEVER reads
  // a device location, a presence signal, or any person — and the fetch fires
  // one-shot from initState plus once per HER-action destination change (no
  // Timer, no Stream, no scheduled refresh): background polling of "her area"
  // would be 見守り-by-proxy, and is forbidden. Unparseable overrides ⇒ the
  // feature is OFF (null), never a guessed point.
  static final double? _pretripDestLat =
      double.tryParse(const String.fromEnvironment('PRETRIP_DEST_LAT'));
  static final double? _pretripDestLon =
      double.tryParse(const String.fromEnvironment('PRETRIP_DEST_LON'));
  static const String _pretripDestLabel =
      String.fromEnvironment('PRETRIP_DEST_LABEL');

  // LIVE (in-app) destination AREA: the dart-define values above are kept as the
  // initial SEED, but the driver (HER) can now set/change the area herself in
  // the app — the family-thread reach-fix. These instance fields are the live
  // source of truth (seeded from the defines); a saved place from
  // [SavedPlaceStore] overwrites them on load. The point is still a PLACE only;
  // it watches no person, and the fetch is still ONE-SHOT (initState + the
  // single HER-action setter), never a background poll.
  double? _destLat = _pretripDestLat;
  double? _destLon = _pretripDestLon;
  String _destLabel = _pretripDestLabel;
  SavedPlaceStore? _savedPlaceStore;
  Future<void>? _savedPlaceLoad;

  void Function()? _destVisibilityClose;
  MetNorwayHourlyForecastProvider? _destForecastProvider;

  /// The destination-area read; null until a real fetch delivers (honest floor
  /// — the section is simply omitted), never a fabricated value.
  AreaConditionRead? _destAreaRead;

  /// The raw DESTINATION-area forecast behind [_destAreaRead], kept so the
  /// bridge caution's cold gate can consult the far endpoint too (a warm
  /// coastal origin says nothing about inland decks; cold at either endpoint
  /// arms the caution — caution-add-only, zero extra network). Cleared with
  /// the read on every HER-action destination change.
  WeatherForecast? _destLiveForecast;

  /// The JMA prefecture code resolved for the current dest read (or null). Kept
  /// as a locale-INDEPENDENT input so the human-readable area label is resolved
  /// at RENDER time from the app's Localizations locale (see [build]) — never
  /// baked from the raw platform locale (which would split the card's locale)
  /// and never as an English literal leaking into the Japanese card.
  String? _destAreaPrefCode;

  /// PARTIAL-READ at the destination AREA (the FAMILY-THREAD section): the
  /// border read for her mother's area was incomplete — a containing prefecture
  /// could not be reached. When true, an honest caution naming
  /// [_destUnreachableArea] is shown next to the family card, so a partial read
  /// is never presented as a complete "no warnings" / "all checked".
  bool _destBorderCheckIncomplete = false;
  String? _destUnreachableArea;

  static final DateTime _pretripDeparture = DateTime(2026, 1, 1, 7, 15);

  // Route-local civil offset OVERRIDE for the offline daylight clock, in integer
  // minutes from UTC (e.g. `--dart-define=PRETRIP_UTC_OFFSET_MIN=540` for JST
  // +9 h). Null (unset) means "derive the offset from the departure instant's
  // device-local offset" — see [build] for the full rationale and the
  // cross-timezone limitation this override exists to cover.
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

  @override
  void initState() {
    super.initState();
    _initPretripForecast();
    _initPretripVisibility();
    _initDestAreaCondition();
    _initRouteBridges();
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
    // Test seam: an injected MET fetch exercises the live path in a plain
    // `flutter test`; production (null) keeps the compile-time gate + the real
    // provider, byte-for-byte as before.
    final metOverride = widget.metForecastFetchOverride;
    if (metOverride == null && _pretripForecastSource != 'met_norway') {
      return; // not selected
    }
    MetNorwayHourlyForecastProvider? met;
    if (metOverride == null) {
      met = MetNorwayHourlyForecastProvider();
      _pretripForecastProvider = met;
    }
    final result = await resolvePretripLiveForecast(
      latitude: _pretripLat,
      longitude: _pretripLon,
      now: DateTime.now(),
      window: _pretripWindow,
      fetchMetForecast: metOverride ??
          () =>
              met!.fetchForecast(latitude: _pretripLat, longitude: _pretripLon),
      fetchJmaAdvisories: () =>
          _fetchJmaAdvisories(latitude: _pretripLat, longitude: _pretripLon),
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
      // A border read where a sibling prefecture was unreachable: keep the
      // partial-read flag so the briefing discloses the gap (never a clean
      // "all warnings checked"), even when a real warning DID merge.
      _pretripJmaBorderCheckIncomplete = result.jmaBorderCheckIncomplete;
      _pretripJmaUnreachableArea = result.jmaUnreachableArea;
      // Turmoil-class warnings (e.g. 大雨危険警報) ride their own card lane —
      // a fetched in-force warning is never silently dropped.
      _pretripJmaTurmoilAdvisories = result.jmaTurmoilAdvisories;
    });
  }

  /// Fetches the JMA advisories at a point. Uses the
  /// [PretripScreen.jmaAdvisoryFetchOverride] test seam when supplied; otherwise
  /// constructs a real [JmaAdvisoryProvider] (init() is idempotent; close()
  /// releases the client after the fetch) — byte-for-byte the prior live path.
  Future<List<Advisory>> _fetchJmaAdvisories({
    required double latitude,
    required double longitude,
  }) async {
    final override = widget.jmaAdvisoryFetchOverride;
    if (override != null) {
      return override(latitude: latitude, longitude: longitude);
    }
    final jma = JmaAdvisoryProvider();
    await jma.init();
    try {
      return await jma.fetchActiveAdvisoriesAtPoint(
        latitude: latitude,
        longitude: longitude,
      );
    } finally {
      jma.close();
    }
  }

  /// Loads the driver-saved destination PLACE once (memoized future, so the
  /// HER-action setter's re-fetch never re-loads and clobbers the just-set
  /// fields — and so CONCURRENT initState callers, the dest-area read and the
  /// route-bridge fetch, AWAIT the same single load instead of racing past a
  /// boolean guard and reading not-yet-loaded fields). On a non-null saved
  /// place the live instance fields are overwritten; on any failure the
  /// dart-define seed is kept (honest floor). It loads a PLACE only — never a
  /// person.
  Future<void> _loadSavedPlace() => _savedPlaceLoad ??= _loadSavedPlaceOnce();

  Future<void> _loadSavedPlaceOnce() async {
    try {
      _savedPlaceStore =
          widget.savedPlaceStore ?? await openDefaultSavedPlaceStore();
      final result = await _savedPlaceStore!.load();
      if (result.place != null) {
        _destLat = result.place!.lat;
        _destLon = result.place!.lon;
        _destLabel = result.place!.label;
      } else if (result.cleared) {
        // The driver DELIBERATELY removed the place: suppress the build-time
        // PRETRIP_DEST_* seed so a cleared place does not resurrect on restart.
        _destLat = null;
        _destLon = null;
        _destLabel = '';
      }
      // else: never written (fresh) ⇒ keep the dart-define seed already in the
      // fields as the one-time bootstrap.
    } catch (_) {
      // Keep the dart-define defaults on any store failure (honest floor).
    }
  }

  /// HER-action setter: the driver chose a new destination AREA in the app.
  /// ONE-SHOT (no Timer/Stream) — closes prior providers (leak hygiene), hides
  /// the stale card, persists the single record, then re-fetches + re-renders.
  Future<void> _setDestination(SavedPlace place) async {
    // Leak hygiene: release the prior dest providers before a re-fetch.
    _destForecastProvider?.close();
    _destForecastProvider = null;
    _destVisibilityClose?.call();
    _destVisibilityClose = null;
    setState(() {
      _destLat = place.lat;
      _destLon = place.lon;
      _destLabel = place.label;
      _destAreaRead = null; // hide the stale area card until the re-fetch lands
      _destLiveForecast = null; // stale far-endpoint evidence goes with it
      // The bridge count described the route to the PRIOR destination; a stale
      // count for the new route would be a false claim. Cleared IMMEDIATELY;
      // exactly ONE fresh resolve then fires for the NEW epoch (below) —
      // one-shot per destination epoch, never a poll. The epoch bump also
      // drops an IN-FLIGHT resolve's late result (see [_destEpoch]) —
      // clearing the field alone cannot stop that landing.
      _routeBridges = null;
      _destEpoch++;
    });
    // Persist the ONE record (best-effort; a save failure must not block the read).
    try {
      _savedPlaceStore ??=
          widget.savedPlaceStore ?? await openDefaultSavedPlaceStore();
      await _savedPlaceStore!.save(place);
    } catch (_) {
      // Honest floor: the in-session place still drives the read even if the
      // write failed; nothing is fabricated.
    }
    // Re-fetch + re-render for the new place — the area read AND exactly one
    // fresh route-bridge resolve for the NEW epoch (same gates: URL opt-in,
    // honest absence on any failure). Fired together, like initState, so the
    // bridge caution never waits behind the area fetch. _loadSavedPlace is
    // guarded, so these re-entries will NOT re-load and clobber the just-set
    // fields.
    await Future.wait([
      _initDestAreaCondition(),
      _initRouteBridges(),
    ]);
  }

  /// HER-action: remove the saved destination AREA. Closes providers, clears the
  /// fields + card, and deletes the single record.
  Future<void> _clearDestination() async {
    _destForecastProvider?.close();
    _destForecastProvider = null;
    _destVisibilityClose?.call();
    _destVisibilityClose = null;
    setState(() {
      _destLat = null;
      _destLon = null;
      _destLabel = '';
      _destAreaRead = null;
      _destLiveForecast = null;
      // No destination ⇒ no route ⇒ the bridge count no longer describes
      // anything real. Cleared, and NO new resolve fires (nothing to route;
      // a clear ends the epoch, it does not start one). The epoch bump also
      // drops an IN-FLIGHT resolve's late result.
      _routeBridges = null;
      _destEpoch++;
    });
    try {
      _savedPlaceStore ??=
          widget.savedPlaceStore ?? await openDefaultSavedPlaceStore();
      await _savedPlaceStore!.clear();
    } catch (_) {
      // Honest floor: removal best-effort.
    }
  }

  /// Fetches the DESTINATION-AREA condition read (the FAMILY-THREAD section):
  /// the PUBLIC weather + official advisory at her mother's PLACE, so SHE
  /// decides whether/when to drive there. ON-DEMAND ONLY — called one-shot
  /// from [initState] plus once per HER-action destination change
  /// ([_setDestination]); there is NO Timer, NO Stream, NO scheduled refresh
  /// and NO notification: polling "her area" in the background would be
  /// 見守り-by-proxy, which is forbidden. It watches no person — the point
  /// comes ONLY from the static PRETRIP_DEST_* defines and the in-app
  /// place entry.
  ///
  /// Gated on the SAME live-forecast opt-in as the briefing, plus a configured
  /// destination point. Degrades honestly on every failure path: a null forecast
  /// (or no opt-in) leaves [_destAreaRead] null and the section is omitted —
  /// never a fabricated value. A read that lands AFTER the destination changed
  /// is DROPPED on the epoch guard ([_destEpoch]) — a stale area read must not
  /// resurrect into the family card or the bridge caution's cold gate.
  Future<void> _initDestAreaCondition() async {
    // Load any driver-saved place FIRST (guarded so re-entry from the HER-action
    // setter won't clobber the just-set fields). Seeds _destLat/_destLon/_destLabel.
    await _loadSavedPlace();
    final forecastSource =
        widget.forecastSourceOverride ?? _pretripForecastSource;
    if (forecastSource != 'met_norway' ||
        _destLat == null ||
        _destLon == null) {
      return; // feature off — no point or no live source
    }
    final destLat = _destLat!;
    final destLon = _destLon!;
    // Captured AFTER the coords are read (the [_initRouteBridges] idiom) and
    // BEFORE any await that can straddle a HER-action change: a read computed
    // for the coords as they stand HERE is correct for this epoch; any later
    // change/clear bumps the epoch and the landings below drop the stale read.
    final epoch = _destEpoch;

    final met = (widget.destForecastProviderFactory ??
        MetNorwayHourlyForecastProvider.new)();
    _destForecastProvider = met;
    final result = await resolvePretripLiveForecast(
      latitude: destLat,
      longitude: destLon,
      now: DateTime.now(),
      window: _pretripWindow,
      fetchMetForecast: () =>
          met.fetchForecast(latitude: destLat, longitude: destLon),
      fetchJmaAdvisories: () =>
          _fetchJmaAdvisories(latitude: destLat, longitude: destLon),
    );
    // Honest floor: no live forecast for the area ⇒ no section.
    if (!mounted || result.forecast == null) return;
    if (epoch != _destEpoch) {
      // The destination changed (or was cleared) while the area read was in
      // flight: this forecast describes the PRIOR area. Landing it would
      // resurrect stale data into the family card AND the bridge caution's
      // cold gate ([_destLiveForecast]) — dropped instead; the setter's own
      // re-fetch owns the new epoch.
      debugPrint('pretrip dest area: destination changed during the read — '
          'stale result dropped');
      return;
    }

    // Optional REAL measured visibility at the DEST point (real sensor or
    // nothing — never an estimate), gated on the same visibility opt-in.
    VisibilityObservation? destObs;
    try {
      switch (_pretripVisibilitySource) {
        case 'digitraffic':
          final p = DigitrafficVisibilityProvider();
          _destVisibilityClose = p.close;
          destObs = await p.fetchNearestVisibility(
              latitude: destLat, longitude: destLon);
        case 'jma':
          final p = JmaVisibilityProvider();
          _destVisibilityClose = p.close;
          destObs = await p.fetchNearestVisibility(
              latitude: destLat, longitude: destLon);
        default:
          destObs = null;
      }
    } catch (_) {
      destObs = null; // honest floor: no measured visibility, nothing estimated
    }
    // Epoch re-checked: the visibility fetch above is a second straddle window.
    if (!mounted || epoch != _destEpoch) return;

    // The human-readable PLACE label is resolved at RENDER time from the app's
    // Localizations locale (see [build]) so the area label and the rest of the
    // card never split locales, and no English literal leaks into the Japanese
    // card. Here we carry only the locale-INDEPENDENT inputs: the driver's
    // explicit label (raw, may be empty) and the prefecture code.
    final read = summarizeAreaConditions(
      forecast: result.forecast!,
      now: result.departure ?? DateTime.now(),
      areaLabel: _destLabel,
      warningEventVerbatim: result.jmaEventName,
      // Honest: the official-warning check was actually performed ONLY on the
      // arms where a warning source returned (JMA merged or JMA no-advisory).
      // The non-Japan (MET) arm consults NO official-warning source, and a JMA
      // failure is a gap — both render "check unavailable", never a fabricated
      // "no warning" negative for an area no source was queried about.
      warningCheckAvailable:
          result.status == PretripLiveStatus.japanJmaMerged ||
              result.status == PretripLiveStatus.japanJmaNoAdvisory,
      observed: destObs,
    );
    setState(() {
      _destAreaRead = read;
      // Kept for the bridge caution's cold gate (far-endpoint evidence).
      _destLiveForecast = result.forecast;
      _destAreaPrefCode = result.prefectureCode;
      // A border read where a sibling prefecture was unreachable: HER mother's
      // area read is PARTIAL. Carry the flag + the unreachable prefecture so the
      // family section shows an honest caution (over-warn), never a clean
      // "no warnings" / "all checked".
      _destBorderCheckIncomplete = result.jmaBorderCheckIncomplete;
      _destUnreachableArea = result.jmaUnreachableArea;
    });
  }

  /// Fetches the route polyline once PER DESTINATION EPOCH — from [initState]
  /// (a saved destination) and once per HER-action destination change
  /// ([_setDestination]); nothing self-scheduled in the background, no
  /// re-fetch on rebuild, and a clear ([_clearDestination]) resolves NOTHING
  /// — and counts the mapped bridge sites on it. Opt-in twice over: the
  /// `PRETRIP_ROUTE_OSRM_URL` dart-define must be set AND the driver must have
  /// a destination. Every failure path leaves [_routeBridges] null — the
  /// briefing simply has no bridge section, never an error banner and never a
  /// substitute claim. A result landing after the epoch moved on is dropped
  /// (see [_destEpoch]).
  Future<void> _initRouteBridges() async {
    final override = widget.routeBridgesOverride;
    BridgeCorridorResult? result;
    final int epoch;
    if (override != null) {
      epoch = _destEpoch;
      result = await override();
    } else {
      final osrmUrl = widget.routeOsrmUrlOverride ?? _pretripRouteOsrmUrl;
      if (osrmUrl.isEmpty) return; // not opted in
      // Same load as the dest-area read (memoized — no double read), so the
      // route destination is the driver-saved place, not just the seed.
      await _loadSavedPlace();
      final destLat = _destLat;
      final destLon = _destLon;
      if (destLat == null || destLon == null) return; // no destination set
      // Captured AFTER the coords are read: a result computed for the coords
      // as they stand HERE is correct for this epoch; any later HER-action
      // change bumps the epoch and the landing below drops the result.
      epoch = _destEpoch;
      final fetchOverride = widget.routeShapeFetchOverride;
      result = await resolvePretripRouteBridges(
        fetchRouteShape: () => fetchOverride != null
            ? fetchOverride(
                originLat: _pretripLat,
                originLon: _pretripLon,
                destLat: destLat,
                destLon: destLon,
              )
            : fetchOsrmRouteShape(
                baseUrl: osrmUrl,
                originLat: _pretripLat,
                originLon: _pretripLon,
                destLat: destLat,
                destLon: destLon,
              ),
        loadBridgeCsv: widget.bridgeCsvLoadOverride ?? loadBridgeCsvAsset,
      );
    }
    if (!mounted || result == null) return;
    if (epoch != _destEpoch) {
      // The destination changed (or was cleared) while this epoch's one-shot
      // resolve was in flight: the count describes the route to the PRIOR
      // destination. Landing it beside the NEW destination would be a false
      // claim — dropped instead. On a change, the setter's own fresh resolve
      // owns the new epoch; on a clear there is nothing to resolve.
      debugPrint('pretrip route bridges: destination changed during the '
          'one-shot resolve — stale result dropped');
      return;
    }
    setState(() => _routeBridges = result);
  }

  @override
  void dispose() {
    _pretripForecastProvider?.close();
    _pretripVisibilityClose?.call();
    _destForecastProvider?.close();
    _destVisibilityClose?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
    const profile = DriverProfileSpec(
      profileTag: 'demo',
      reactionTimeSeconds: 1.5,
    );

    // THE ALL-CLEAR MUST BE EARNED, AND THE TWO ABSENCES ARE NOT THE SAME.
    //
    // `pretrip_decision_advisor` 0.6.1 refuses the affirmative all-clear it did
    // not measure: `brief` throws [PretripAssessmentIncompleteException] when a
    // forecast DOES cover this window but the fields that decide the hazard
    // ladder were never measured. Published 0.6.0 printed
    // 「出発時間帯に冬季の危険を示す兆候はありません」 on exactly that morning —
    // a sentence produced BY the absence of evidence. On the MET Norway product
    // it was the DEFAULT: that source carries neither visibility nor road
    // surface on any slot, by its own honesty rule.
    //
    // The catch is the ONLY thing that can tell that morning apart from one
    // with no forecast at all. Both land as `PretripVerdict.noData`, and
    // `allClearEarned` answers `false` to both — `window.isEmpty` returns
    // `false` on the same line an unmeasured window does. Calling
    // `briefOrUnassessed` instead of catching loses the distinction too, and
    // the card would then tell HER 「出発時間帯の予報がありません」 — *there is
    // no forecast* — on a morning a forecast arrived. That is the same defect
    // 0.6.1 exists to close, moved into the headline, where it is larger and
    // is read first, and is announced first to assistive tech.
    PretripBriefing briefing;
    var assessmentIncomplete = false;
    try {
      briefing = advisor.brief(
        forecast: forecast,
        commute: commute,
        profile: profile,
      );
    } on PretripAssessmentIncompleteException {
      assessmentIncomplete = true;
      // The package already authored what this state SAYS — its
      // `assessmentIncomplete()` chip, in both languages. Take its briefing
      // rather than compose a second one here that could drift from it.
      briefing = advisor.briefOrUnassessed(
        forecast: forecast,
        commute: commute,
        profile: profile,
      );
    }
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              PretripBriefingCard(
                // The briefing reads in the driver's own language — Japanese for
                // HER mother in Akita — resolved once from the active locale above.
                strings: strings,
                briefing: briefing,
                assessmentIncomplete: assessmentIncomplete,
                commute: commute,
                forecastIssuedAt: forecast.issuedAt,
                tripRequired: _pretripTripRequired,
                onTripRequiredChanged: (v) =>
                    setState(() => _pretripTripRequired = v),
                sourceCaption: caption,
                // Grounded offline guidance for the surface state the host's
                // assessment expects; null (omitted) until the asset loads or for
                // a benign surface with no baked card. Resolved in the driver's
                // language — Japanese for HER mother when a verified card exists,
                // else the grounded English (honest fallback, never blank).
                winterCard: widget.surfaceState == null
                    ? null
                    : _winter?.cardFor(
                        widget.surfaceState!,
                        lang: locale.languageCode,
                      ),
              ),
              // IN-FORCE JMA TURMOIL WARNINGS (0.4.0 widening): downpour /
              // typhoon-wind / thunder / fog warnings at HER current location,
              // relayed VERBATIM as cards (Article 17 β) — a fetched in-force
              // 大雨危険警報 must reach HER, never be silently dropped. These
              // never touch the road-condition band (that inference would be
              // fabrication); they inform, the driver always drives.
              if (live != null && _pretripJmaTurmoilAdvisories.isNotEmpty)
                _jmaTurmoilWarningsCard(
                    context, strings, _pretripJmaTurmoilAdvisories),
              // PARTIAL-READ caution for HER CURRENT location: a border read
              // where a sibling prefecture was unreachable. HER must SEE that
              // the official-warning check was incomplete — over-warn, never a
              // clean "all checked". Naming the unreachable prefecture (秋田県).
              if (live != null &&
                  _pretripJmaBorderCheckIncomplete &&
                  _pretripJmaUnreachableArea != null)
                _borderIncompleteCaution(
                    context, strings, _pretripJmaUnreachableArea!),
              // ROUTE BRIDGE caution: the real fetched route crosses about N
              // mapped bridge sites, and bridge decks freeze before the road
              // surface does. Shown only when a real route delivered, the
              // count is ≥ 1, AND a frozen deck is plausible: window min ≤
              // +3.0 °C at EITHER endpoint (origin live read, or the
              // destination-area read the family section already fetched), or
              // the season band otherwise — warm POINT evidence never
              // suppresses the band (the decks are elsewhere on the route).
              // Zero/no-data ⇒ NO section — never an all-clear.
              if (_routeBridges != null &&
                  shouldShowBridgeCaution(
                    clusterCount: _routeBridges!.clusterCount,
                    liveForecast: live,
                    destForecast: _destLiveForecast,
                    departure: departure,
                    window: _pretripWindow,
                    now: widget.bridgeGateNowOverride ?? DateTime.now(),
                  ))
                _bridgeCorridorCaution(
                    context, strings, _routeBridges!.clusterCount),
              // In-app TYPED-PLACE ENTRY: the driver (HER) sets/changes the
              // destination AREA herself. ALWAYS visible — she must be able to
              // set the place the FIRST time, when _destAreaRead is still null.
              // It is a PLACE entry; it watches no person.
              DestinationEntryTile(
                strings: strings,
                hasPlace: _destLat != null && _destLon != null,
                placeLabel: _destLabel,
                forecastEnabled: _pretripForecastSource == 'met_norway',
                onEdit: () async {
                  final r = await showPlaceEntryDialog(
                    context,
                    strings: strings,
                    initial: (_destLat != null && _destLon != null)
                        ? SavedPlace(
                            lat: _destLat!,
                            lon: _destLon!,
                            label: _destLabel,
                          )
                        : null,
                  );
                  if (r != null) await _setDestination(r);
                },
                onClear: _clearDestination,
              ),
              // The FAMILY-THREAD destination-area section (companion to the
              // daylight clock) — shown only when a real area read delivered.
              if (_destAreaRead != null)
                FamilyAreaCard(
                  read: _destAreaRead!,
                  messages: PretripMessages.forLanguage(locale.languageCode),
                  strings: strings,
                  // Resolve the area label from the SINGLE Localizations-locale
                  // `strings` (above) so it never splits locale with the rest of
                  // the card and never leaks an English literal into the Japanese
                  // card: the driver's explicit label, else the LOCALIZED
                  // prefecture name (秋田県 for ja, Akita for en) when the code is
                  // in the catalog, else a localized generic phrase — never a
                  // bare office code.
                  areaLabelOverride: _destLabel.isNotEmpty
                      ? _destLabel
                      : (_destAreaPrefCode != null &&
                              jmaPrefectureName(_destAreaPrefCode!) != null
                          ? strings.prefectureName(_destAreaPrefCode!)
                          : strings.genericDestinationArea),
                ),
              // PARTIAL-READ caution for the FAMILY-THREAD area (her mother's
              // area): a border read where a sibling prefecture was unreachable.
              // The family card still shows any real warning that DID arrive;
              // this caution adds the honest gap so a partial read is never
              // presented as a complete "no warnings" — over-warn, never deter.
              if (_destBorderCheckIncomplete && _destUnreachableArea != null)
                _borderIncompleteCaution(
                    context, strings, _destUnreachableArea!),
            ],
          ),
        ),
      ),
    );
  }

  /// The one-line ROUTE BRIDGE caution: about [approxCount] mapped bridge
  /// sites lie on the fetched route, and bridge decks freeze before the road
  /// surface does. Same visual weight as [_borderIncompleteCaution] — a
  /// caution, not an alarm. The count is approximate by construction and the
  /// string says so (約/"About"); it never tells HER not to drive.
  Widget _bridgeCorridorCaution(
    BuildContext context,
    BriefingStrings strings,
    int approxCount,
  ) {
    final theme = Theme.of(context);
    return Card(
      key: const Key('pretrip-bridge-corridor-caution'),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      color: theme.colorScheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(
                Icons.warning_amber_rounded,
                size: 18,
                color: theme.colorScheme.onTertiaryContainer,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    strings.bridgeCorridorCaution(approxCount),
                    style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onTertiaryContainer),
                  ),
                  const SizedBox(height: 4),
                  // ODbL produced-work notice: this surface never shows the
                  // map's tile credit, so the card carries its own (the
                  // winterFooter / visibility-caption source-credit idiom).
                  Text(
                    strings.bridgeDataAttribution,
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onTertiaryContainer),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// In-force JMA NON-snow warnings (0.4.0 turmoil classes), relayed verbatim
  /// — one row per warning, highest severity first, prefecture-labeled. The
  /// card is visual-only (no spoken/audio path from this surface) per the
  /// adapter's severity-gated modality guidance; it informs, it never tells
  /// HER not to drive. Card color escalates only when a 警報-class
  /// (severe/extreme) warning is present; 注意報-only stays caution-toned.
  Widget _jmaTurmoilWarningsCard(
    BuildContext context,
    BriefingStrings strings,
    List<Advisory> advisories,
  ) {
    final theme = Theme.of(context);
    final highImpact = advisories.any((a) => a.isHighImpact);
    final bg = highImpact
        ? theme.colorScheme.errorContainer
        : theme.colorScheme.tertiaryContainer;
    final fg = highImpact
        ? theme.colorScheme.onErrorContainer
        : theme.colorScheme.onTertiaryContainer;
    return Card(
      key: const Key('pretrip-jma-turmoil-warnings'),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      color: bg,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.campaign_outlined, size: 18, color: fg),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    strings.jmaWarningsInForceHeader,
                    style: theme.textTheme.titleSmall?.copyWith(color: fg),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            for (final a in advisories)
              Padding(
                padding: const EdgeInsets.only(left: 26, bottom: 2),
                child: Text(
                  strings.jmaWarningWithArea(a.eventClass, a.areaDescription),
                  style: theme.textTheme.bodyMedium?.copyWith(color: fg),
                ),
              ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 26),
              child: Text(
                strings.jmaWarningsVerbatimNote,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: fg.withValues(alpha: 0.8)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// An honest, conservative caution that the official-warning check was only
  /// PARTIAL: a border prefecture ([unreachableArea]) could not be reached, so a
  /// warning (up to a 大雪特別警報) may be in force there that is not shown. It
  /// DISCLOSES the gap; it never tells HER not to drive. Localized for HER
  /// (Japanese for her mother in Akita).
  Widget _borderIncompleteCaution(
    BuildContext context,
    BriefingStrings strings,
    String unreachableArea,
  ) {
    final theme = Theme.of(context);
    return Card(
      key: const Key('pretrip-border-incomplete-caution'),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      color: theme.colorScheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(
                Icons.warning_amber_rounded,
                size: 18,
                color: theme.colorScheme.onTertiaryContainer,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                strings.borderWarningCheckIncomplete(unreachableArea),
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onTertiaryContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
