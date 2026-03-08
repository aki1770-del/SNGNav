/// MapLayer dual-renderer widget tests.
///
/// Tests:
///   1. Renders FlutterMap when fluoriteAvailable = false (default)
///   2. Renders FluoriteView when fluoriteAvailable = true
///   3. FluoriteView falls back to FlutterMap when unavailable (Phase A)
///   4. Shows route polyline when route layer visible and route exists
///   5. Hides route polyline when route layer not visible
///   6. Shows weather zone when weather layer visible and snowing
///   7. Shows safety markers when safety layer visible and hazardous
///   8. Shows position marker when location available
///   9. Hides position marker when no location
///  10. Shows FleetLayer when consent granted + fleet listening (Gap 2)
///  11. Hides FleetLayer when consent denied despite fleet listening (Gap 2)
///  12. Hides FleetLayer when consent granted but fleet not listening (Gap 2)
///  13. Shows HazardZoneLayer when consent + fleet + hazards present (Gap 2)
///  14. Hides HazardZoneLayer when fleet has no hazards (Gap 2)
///  15. Hides fleet layers when fleet layer toggled off in MapState (Gap 2)
///  16. HazardAggregator pipeline: fleet reports → zones in MapLayer (Gap 3)
///
/// Sprint 7 Day 10 — FluoriteView scaffold.
/// Sprint 8 Day 11 — Consent-gated fleet + hazard pipeline tests.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart' hide MapEvent;
import 'package:flutter_test/flutter_test.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:mocktail/mocktail.dart';

import 'package:sngnav_snow_scene/bloc/consent_bloc.dart';
import 'package:sngnav_snow_scene/bloc/consent_event.dart';
import 'package:sngnav_snow_scene/bloc/consent_state.dart';
import 'package:sngnav_snow_scene/bloc/fleet_bloc.dart';
import 'package:sngnav_snow_scene/bloc/fleet_event.dart';
import 'package:sngnav_snow_scene/bloc/fleet_state.dart';
import 'package:sngnav_snow_scene/bloc/location_bloc.dart';
import 'package:sngnav_snow_scene/bloc/location_event.dart';
import 'package:sngnav_snow_scene/bloc/location_state.dart';
import 'package:sngnav_snow_scene/bloc/map_bloc.dart';
import 'package:sngnav_snow_scene/bloc/map_event.dart';
import 'package:sngnav_snow_scene/bloc/map_state.dart';
import 'package:sngnav_snow_scene/bloc/routing_bloc.dart';
import 'package:sngnav_snow_scene/bloc/routing_event.dart';
import 'package:sngnav_snow_scene/bloc/routing_state.dart';
import 'package:sngnav_snow_scene/bloc/weather_bloc.dart';
import 'package:sngnav_snow_scene/bloc/weather_event.dart';
import 'package:sngnav_snow_scene/bloc/weather_state.dart';
import 'package:sngnav_snow_scene/fluorite/fluorite_view.dart';
import 'package:sngnav_snow_scene/models/consent_record.dart';
import 'package:sngnav_snow_scene/models/fleet_report.dart';
import 'package:kalman_dr/kalman_dr.dart';
import 'package:routing_engine/routing_engine.dart';
import 'package:sngnav_snow_scene/models/weather_condition.dart';
import 'package:sngnav_snow_scene/widgets/fleet_layer.dart';
import 'package:sngnav_snow_scene/widgets/hazard_zone_layer.dart';
import 'package:sngnav_snow_scene/widgets/map_layer.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockMapBloc extends MockBloc<MapEvent, MapState> implements MapBloc {}

class MockRoutingBloc extends MockBloc<RoutingEvent, RoutingState>
    implements RoutingBloc {}

class MockLocationBloc extends MockBloc<LocationEvent, LocationState>
    implements LocationBloc {}

class MockWeatherBloc extends MockBloc<WeatherEvent, WeatherState>
    implements WeatherBloc {}

class MockFleetBloc extends MockBloc<FleetEvent, FleetState>
    implements FleetBloc {}

class MockConsentBloc extends MockBloc<ConsentEvent, ConsentState>
    implements ConsentBloc {}

// ---------------------------------------------------------------------------
// Test data
// ---------------------------------------------------------------------------

const _defaultMapState = MapState(
  status: MapStatus.ready,
  center: LatLng(35.1709, 136.8815),
  zoom: 12.0,
  visibleLayers: {MapLayerType.route, MapLayerType.weather, MapLayerType.safety},
);

final _routeActive = RoutingState(
  status: RoutingStatus.routeActive,
  route: RouteResult(
    shape: const [
      LatLng(35.1709, 136.8815),
      LatLng(35.0500, 137.3200),
    ],
    totalDistanceKm: 45.0,
    totalTimeSeconds: 3600,
    maneuvers: const [],
    summary: 'Nagoya → Mt. Sanage',
    engineInfo: const EngineInfo(
      name: 'mock',
      version: '1.0',
      queryLatency: Duration.zero,
    ),
  ),
  destinationLabel: 'Mt. Sanage',
);

final _snowCondition = WeatherCondition(
  precipType: PrecipitationType.snow,
  intensity: PrecipitationIntensity.light,
  temperatureCelsius: -2.0,
  visibilityMeters: 3000,
  windSpeedKmh: 15,
  timestamp: DateTime(2026),
);

final _hazardCondition = WeatherCondition(
  precipType: PrecipitationType.snow,
  intensity: PrecipitationIntensity.heavy,
  temperatureCelsius: -8.0,
  visibilityMeters: 150,
  windSpeedKmh: 40,
  timestamp: DateTime(2026),
);

final _fixPosition = GeoPosition(
  latitude: 35.1709,
  longitude: 136.8815,
  accuracy: 5.0,
  speed: 0.0,
  heading: 0.0,
  timestamp: DateTime(2026),
);

// Fleet + consent test data (Gap 2/3)

final _now = DateTime.now();

final _fleetMapState = const MapState(
  status: MapStatus.ready,
  center: LatLng(35.1709, 136.8815),
  zoom: 12.0,
  visibleLayers: {
    MapLayerType.route,
    MapLayerType.weather,
    MapLayerType.safety,
    MapLayerType.fleet,
  },
);

final _consentGranted = ConsentState(
  status: ConsentBlocStatus.ready,
  consents: {
    ConsentPurpose.fleetLocation: ConsentRecord(
      purpose: ConsentPurpose.fleetLocation,
      status: ConsentStatus.granted,
      jurisdiction: Jurisdiction.gdpr,
      updatedAt: _now,
    ),
  },
);

final _consentDenied = ConsentState(
  status: ConsentBlocStatus.ready,
  consents: {
    ConsentPurpose.fleetLocation: ConsentRecord(
      purpose: ConsentPurpose.fleetLocation,
      status: ConsentStatus.denied,
      jurisdiction: Jurisdiction.gdpr,
      updatedAt: _now,
    ),
  },
);

final _icyReport = FleetReport(
  vehicleId: 'V-001',
  position: const LatLng(35.0600, 137.2500),
  timestamp: _now,
  condition: RoadCondition.icy,
  confidence: 0.9,
);

final _snowyReport = FleetReport(
  vehicleId: 'V-002',
  position: const LatLng(35.0500, 137.3200),
  timestamp: _now,
  condition: RoadCondition.snowy,
  confidence: 0.85,
);

final _dryReport = FleetReport(
  vehicleId: 'V-003',
  position: const LatLng(35.1000, 137.0000),
  timestamp: _now,
  condition: RoadCondition.dry,
  confidence: 0.95,
);

final _fleetListeningWithHazards = FleetState(
  status: FleetStatus.listening,
  activeReports: {
    'V-001': _icyReport,
    'V-002': _snowyReport,
    'V-003': _dryReport,
  },
);

final _fleetListeningDryOnly = FleetState(
  status: FleetStatus.listening,
  activeReports: {'V-003': _dryReport},
);

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Widget _buildMapLayer({
  required MockMapBloc mapBloc,
  required MockRoutingBloc routingBloc,
  required MockLocationBloc locationBloc,
  required MockWeatherBloc weatherBloc,
  required MockFleetBloc fleetBloc,
  required MockConsentBloc consentBloc,
  bool fluoriteAvailable = false,
}) {
  return MaterialApp(
    home: Scaffold(
      body: MultiBlocProvider(
        providers: [
          BlocProvider<MapBloc>.value(value: mapBloc),
          BlocProvider<RoutingBloc>.value(value: routingBloc),
          BlocProvider<LocationBloc>.value(value: locationBloc),
          BlocProvider<WeatherBloc>.value(value: weatherBloc),
          BlocProvider<FleetBloc>.value(value: fleetBloc),
          BlocProvider<ConsentBloc>.value(value: consentBloc),
        ],
        child: MapLayer(
          mapController: MapController(),
          fluoriteAvailable: fluoriteAvailable,
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('MapLayer', () {
    late MockMapBloc mapBloc;
    late MockRoutingBloc routingBloc;
    late MockLocationBloc locationBloc;
    late MockWeatherBloc weatherBloc;
    late MockFleetBloc fleetBloc;
    late MockConsentBloc consentBloc;

    setUp(() {
      mapBloc = MockMapBloc();
      routingBloc = MockRoutingBloc();
      locationBloc = MockLocationBloc();
      weatherBloc = MockWeatherBloc();
      fleetBloc = MockFleetBloc();
      consentBloc = MockConsentBloc();

      // Defaults: ready map, no route, no location, no weather, no fleet
      when(() => mapBloc.state).thenReturn(_defaultMapState);
      when(() => routingBloc.state)
          .thenReturn(const RoutingState.idle());
      when(() => locationBloc.state)
          .thenReturn(const LocationState.uninitialized());
      when(() => weatherBloc.state)
          .thenReturn(const WeatherState.unavailable());
      when(() => fleetBloc.state)
          .thenReturn(const FleetState.idle());
      when(() => consentBloc.state)
          .thenReturn(const ConsentState(status: ConsentBlocStatus.loading));
    });

    testWidgets('renders FlutterMap when fluoriteAvailable = false (default)',
        (tester) async {
      await tester.pumpWidget(_buildMapLayer(
        mapBloc: mapBloc,
        routingBloc: routingBloc,
        locationBloc: locationBloc,
        weatherBloc: weatherBloc,
        fleetBloc: fleetBloc,
        consentBloc: consentBloc,
      ));

      expect(find.byType(FlutterMap), findsOneWidget);
      expect(find.byType(FluoriteView), findsNothing);
    });

    testWidgets('renders FluoriteView when fluoriteAvailable = true',
        (tester) async {
      await tester.pumpWidget(_buildMapLayer(
        mapBloc: mapBloc,
        routingBloc: routingBloc,
        locationBloc: locationBloc,
        weatherBloc: weatherBloc,
        fleetBloc: fleetBloc,
        consentBloc: consentBloc,
        fluoriteAvailable: true,
      ));
      await tester.pumpAndSettle();

      // FluoriteView is in the tree (falls back to FlutterMap as placeholder)
      expect(find.byType(FluoriteView), findsOneWidget);
    });

    testWidgets('FluoriteView falls back to FlutterMap when unavailable',
        (tester) async {
      await tester.pumpWidget(_buildMapLayer(
        mapBloc: mapBloc,
        routingBloc: routingBloc,
        locationBloc: locationBloc,
        weatherBloc: weatherBloc,
        fleetBloc: fleetBloc,
        consentBloc: consentBloc,
        fluoriteAvailable: true,
      ));
      await tester.pumpAndSettle();

      // Phase A: NotImplementedHostApi → unavailable → shows FlutterMap fallback
      expect(find.byType(FlutterMap), findsOneWidget);
    });

    testWidgets('shows route polyline when route layer visible and route exists',
        (tester) async {
      when(() => routingBloc.state).thenReturn(_routeActive);

      await tester.pumpWidget(_buildMapLayer(
        mapBloc: mapBloc,
        routingBloc: routingBloc,
        locationBloc: locationBloc,
        weatherBloc: weatherBloc,
        fleetBloc: fleetBloc,
        consentBloc: consentBloc,
      ));

      expect(find.byType(PolylineLayer), findsOneWidget);
    });

    testWidgets('hides route polyline when route layer not visible',
        (tester) async {
      when(() => routingBloc.state).thenReturn(_routeActive);
      when(() => mapBloc.state).thenReturn(const MapState(
        status: MapStatus.ready,
        center: LatLng(35.1709, 136.8815),
        zoom: 12.0,
        visibleLayers: {}, // No visible layers
      ));

      await tester.pumpWidget(_buildMapLayer(
        mapBloc: mapBloc,
        routingBloc: routingBloc,
        locationBloc: locationBloc,
        weatherBloc: weatherBloc,
        fleetBloc: fleetBloc,
        consentBloc: consentBloc,
      ));

      expect(find.byType(PolylineLayer), findsNothing);
    });

    testWidgets('shows weather zone when weather layer visible and snowing',
        (tester) async {
      when(() => weatherBloc.state).thenReturn(WeatherState(
        status: WeatherStatus.monitoring,
        condition: _snowCondition,
      ));

      await tester.pumpWidget(_buildMapLayer(
        mapBloc: mapBloc,
        routingBloc: routingBloc,
        locationBloc: locationBloc,
        weatherBloc: weatherBloc,
        fleetBloc: fleetBloc,
        consentBloc: consentBloc,
      ));

      expect(find.byType(PolygonLayer), findsOneWidget);
    });

    testWidgets('shows safety markers when safety layer visible and hazardous',
        (tester) async {
      when(() => weatherBloc.state).thenReturn(WeatherState(
        status: WeatherStatus.monitoring,
        condition: _hazardCondition,
      ));

      await tester.pumpWidget(_buildMapLayer(
        mapBloc: mapBloc,
        routingBloc: routingBloc,
        locationBloc: locationBloc,
        weatherBloc: weatherBloc,
        fleetBloc: fleetBloc,
        consentBloc: consentBloc,
      ));

      // MarkerLayer is rendered for hazard markers
      // (Icon may not render if marker is outside test viewport)
      expect(find.byType(MarkerLayer), findsOneWidget);
    });

    testWidgets('shows position marker when location available',
        (tester) async {
      when(() => locationBloc.state).thenReturn(LocationState(
        quality: LocationQuality.fix,
        position: _fixPosition,
      ));

      await tester.pumpWidget(_buildMapLayer(
        mapBloc: mapBloc,
        routingBloc: routingBloc,
        locationBloc: locationBloc,
        weatherBloc: weatherBloc,
        fleetBloc: fleetBloc,
        consentBloc: consentBloc,
      ));

      // At least 1 MarkerLayer for position
      expect(find.byType(MarkerLayer), findsOneWidget);
    });

    testWidgets('hides position marker when no location', (tester) async {
      // Default: uninitialized location — no position marker
      await tester.pumpWidget(_buildMapLayer(
        mapBloc: mapBloc,
        routingBloc: routingBloc,
        locationBloc: locationBloc,
        weatherBloc: weatherBloc,
        fleetBloc: fleetBloc,
        consentBloc: consentBloc,
      ));

      // No MarkerLayer at all (no route markers, no position marker)
      expect(find.byType(MarkerLayer), findsNothing);
    });
  });

  // -------------------------------------------------------------------------
  // Gap 2: Consent-gated fleet + hazard rendering
  // -------------------------------------------------------------------------

  group('MapLayer consent-gated fleet layers (Gap 2)', () {
    late MockMapBloc mapBloc;
    late MockRoutingBloc routingBloc;
    late MockLocationBloc locationBloc;
    late MockWeatherBloc weatherBloc;
    late MockFleetBloc fleetBloc;
    late MockConsentBloc consentBloc;

    setUp(() {
      mapBloc = MockMapBloc();
      routingBloc = MockRoutingBloc();
      locationBloc = MockLocationBloc();
      weatherBloc = MockWeatherBloc();
      fleetBloc = MockFleetBloc();
      consentBloc = MockConsentBloc();

      // Defaults: fleet layer visible in map, no route/location/weather
      when(() => mapBloc.state).thenReturn(_fleetMapState);
      when(() => routingBloc.state)
          .thenReturn(const RoutingState.idle());
      when(() => locationBloc.state)
          .thenReturn(const LocationState.uninitialized());
      when(() => weatherBloc.state)
          .thenReturn(const WeatherState.unavailable());
    });

    testWidgets('shows FleetLayer when consent granted + fleet listening',
        (tester) async {
      when(() => consentBloc.state).thenReturn(_consentGranted);
      when(() => fleetBloc.state).thenReturn(_fleetListeningWithHazards);

      await tester.pumpWidget(_buildMapLayer(
        mapBloc: mapBloc,
        routingBloc: routingBloc,
        locationBloc: locationBloc,
        weatherBloc: weatherBloc,
        fleetBloc: fleetBloc,
        consentBloc: consentBloc,
      ));

      expect(find.byType(FleetLayer), findsOneWidget);
    });

    testWidgets('hides FleetLayer when consent denied despite fleet listening',
        (tester) async {
      when(() => consentBloc.state).thenReturn(_consentDenied);
      when(() => fleetBloc.state).thenReturn(_fleetListeningWithHazards);

      await tester.pumpWidget(_buildMapLayer(
        mapBloc: mapBloc,
        routingBloc: routingBloc,
        locationBloc: locationBloc,
        weatherBloc: weatherBloc,
        fleetBloc: fleetBloc,
        consentBloc: consentBloc,
      ));

      expect(find.byType(FleetLayer), findsNothing);
      expect(find.byType(HazardZoneLayer), findsNothing);
    });

    testWidgets('hides FleetLayer when consent granted but fleet not listening',
        (tester) async {
      when(() => consentBloc.state).thenReturn(_consentGranted);
      when(() => fleetBloc.state).thenReturn(const FleetState.idle());

      await tester.pumpWidget(_buildMapLayer(
        mapBloc: mapBloc,
        routingBloc: routingBloc,
        locationBloc: locationBloc,
        weatherBloc: weatherBloc,
        fleetBloc: fleetBloc,
        consentBloc: consentBloc,
      ));

      expect(find.byType(FleetLayer), findsNothing);
    });

    testWidgets(
        'shows HazardZoneLayer when consent + fleet + hazards present',
        (tester) async {
      when(() => consentBloc.state).thenReturn(_consentGranted);
      when(() => fleetBloc.state).thenReturn(_fleetListeningWithHazards);

      await tester.pumpWidget(_buildMapLayer(
        mapBloc: mapBloc,
        routingBloc: routingBloc,
        locationBloc: locationBloc,
        weatherBloc: weatherBloc,
        fleetBloc: fleetBloc,
        consentBloc: consentBloc,
      ));

      expect(find.byType(HazardZoneLayer), findsOneWidget);
    });

    testWidgets('hides HazardZoneLayer when fleet has no hazards',
        (tester) async {
      when(() => consentBloc.state).thenReturn(_consentGranted);
      when(() => fleetBloc.state).thenReturn(_fleetListeningDryOnly);

      await tester.pumpWidget(_buildMapLayer(
        mapBloc: mapBloc,
        routingBloc: routingBloc,
        locationBloc: locationBloc,
        weatherBloc: weatherBloc,
        fleetBloc: fleetBloc,
        consentBloc: consentBloc,
      ));

      // FleetLayer renders (dry reports still visible), but no HazardZoneLayer
      expect(find.byType(FleetLayer), findsOneWidget);
      expect(find.byType(HazardZoneLayer), findsNothing);
    });

    testWidgets('hides fleet layers when fleet layer toggled off in MapState',
        (tester) async {
      // Map state without fleet layer visible
      when(() => mapBloc.state).thenReturn(_defaultMapState);
      when(() => consentBloc.state).thenReturn(_consentGranted);
      when(() => fleetBloc.state).thenReturn(_fleetListeningWithHazards);

      await tester.pumpWidget(_buildMapLayer(
        mapBloc: mapBloc,
        routingBloc: routingBloc,
        locationBloc: locationBloc,
        weatherBloc: weatherBloc,
        fleetBloc: fleetBloc,
        consentBloc: consentBloc,
      ));

      // _defaultMapState has {route, weather, safety} — no fleet
      expect(find.byType(FleetLayer), findsNothing);
      expect(find.byType(HazardZoneLayer), findsNothing);
    });
  });

  // -------------------------------------------------------------------------
  // Gap 3: HazardAggregator pipeline through MapLayer
  // -------------------------------------------------------------------------

  group('MapLayer hazard aggregation pipeline (Gap 3)', () {
    late MockMapBloc mapBloc;
    late MockRoutingBloc routingBloc;
    late MockLocationBloc locationBloc;
    late MockWeatherBloc weatherBloc;
    late MockFleetBloc fleetBloc;
    late MockConsentBloc consentBloc;

    setUp(() {
      mapBloc = MockMapBloc();
      routingBloc = MockRoutingBloc();
      locationBloc = MockLocationBloc();
      weatherBloc = MockWeatherBloc();
      fleetBloc = MockFleetBloc();
      consentBloc = MockConsentBloc();

      when(() => mapBloc.state).thenReturn(_fleetMapState);
      when(() => routingBloc.state)
          .thenReturn(const RoutingState.idle());
      when(() => locationBloc.state)
          .thenReturn(const LocationState.uninitialized());
      when(() => weatherBloc.state)
          .thenReturn(const WeatherState.unavailable());
      when(() => consentBloc.state).thenReturn(_consentGranted);
    });

    testWidgets(
        'fleet reports flow through HazardAggregator to HazardZoneLayer',
        (tester) async {
      // Two hazard reports close together (< 2km clustering threshold)
      // should produce a HazardZone via HazardAggregator.aggregate()
      when(() => fleetBloc.state).thenReturn(_fleetListeningWithHazards);

      await tester.pumpWidget(_buildMapLayer(
        mapBloc: mapBloc,
        routingBloc: routingBloc,
        locationBloc: locationBloc,
        weatherBloc: weatherBloc,
        fleetBloc: fleetBloc,
        consentBloc: consentBloc,
      ));

      // HazardZoneLayer is present — confirms the pipeline:
      // fleetState.reports → HazardAggregator.aggregate() → HazardZoneLayer
      expect(find.byType(HazardZoneLayer), findsOneWidget);

      // CircleLayer inside HazardZoneLayer confirms zones were generated
      expect(find.byType(CircleLayer), findsOneWidget);
    });
  });
}
