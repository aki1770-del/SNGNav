/// SimulatedFleetCaption — the guard for the map screen's demo-data disclosure.
///
/// The defect this catches: the live-drive map drew fleet vehicle markers and
/// red hazard rings from a fixed-seed `Random(42)` and said nothing about it,
/// while the pre-trip screen had disclosed its simulated forecast all along.
/// A red ring that reads as a real road report, and is not one, is what these
/// tests exist to stop from returning.
///
/// The enumerated scenario set (each asserted below):
///   1. renders in EN when the fleet layers are drawing
///   2. renders in JA under a `ja` locale
///   3. absent when fleet consent is denied  (nothing drawn → nothing to label)
///   4. absent when the fleet bloc is not listening (same reason)
///   5. absent when the caller declares the fleet is NOT simulated
///   6. lives in the bottom strip of the map screen, clear of the markers
///   7. does not displace the fleet consent chip from the right edge
library;

import 'package:bloc_test/bloc_test.dart';
import 'package:driving_consent/driving_consent.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:map_viewport_bloc/map_viewport_bloc.dart';
import 'package:mocktail/mocktail.dart';
import 'package:navigation_safety/navigation_safety.dart';
import 'package:routing_bloc/routing_bloc.dart';

import 'package:fleet_hazard/fleet_hazard.dart';
import 'package:sngnav_snow_scene/bloc/consent_bloc.dart';
import 'package:sngnav_snow_scene/bloc/consent_event.dart';
import 'package:sngnav_snow_scene/bloc/consent_state.dart';
import 'package:sngnav_snow_scene/bloc/fleet_bloc.dart';
import 'package:sngnav_snow_scene/bloc/fleet_event.dart';
import 'package:sngnav_snow_scene/bloc/fleet_state.dart';
import 'package:sngnav_snow_scene/bloc/location_bloc.dart';
import 'package:sngnav_snow_scene/bloc/location_event.dart';
import 'package:sngnav_snow_scene/bloc/location_state.dart';
import 'package:sngnav_snow_scene/bloc/weather_bloc.dart';
import 'package:sngnav_snow_scene/bloc/weather_event.dart';
import 'package:sngnav_snow_scene/bloc/weather_state.dart';
import 'package:sngnav_snow_scene/widgets/briefing_strings.dart';
import 'package:sngnav_snow_scene/widgets/map_layer.dart';
import 'package:sngnav_snow_scene/widgets/simulated_fleet_caption.dart';
import 'package:sngnav_snow_scene/widgets/snow_scene_scaffold.dart';

class MockLocationBloc extends MockBloc<LocationEvent, LocationState>
    implements LocationBloc {}

class MockRoutingBloc extends MockBloc<RoutingEvent, RoutingState>
    implements RoutingBloc {}

class MockNavigationBloc extends MockBloc<NavigationEvent, NavigationState>
    implements NavigationBloc {}

class MockMapBloc extends MockBloc<MapEvent, MapState> implements MapBloc {}

class MockWeatherBloc extends MockBloc<WeatherEvent, WeatherState>
    implements WeatherBloc {}

class MockConsentBloc extends MockBloc<ConsentEvent, ConsentState>
    implements ConsentBloc {}

class MockFleetBloc extends MockBloc<FleetEvent, FleetState>
    implements FleetBloc {}

final _now = DateTime.utc(2026, 1, 15, 8);

final _consentGranted = ConsentState(
  status: ConsentBlocStatus.ready,
  consents: {
    ConsentPurpose.fleetLocation: ConsentRecord(
      purpose: ConsentPurpose.fleetLocation,
      status: ConsentStatus.granted,
      jurisdiction: Jurisdiction.appi,
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
      jurisdiction: Jurisdiction.appi,
      updatedAt: _now,
    ),
  },
);

/// A listening fleet with an icy report — the exact state in which the red
/// hazard ring is on the map and the disclosure is owed.
final _fleetListening = FleetState(
  status: FleetStatus.listening,
  activeReports: {
    'V-001': FleetReport(
      vehicleId: 'V-001',
      position: const LatLng(35.0600, 137.2500),
      timestamp: _now,
      condition: RoadCondition.icy,
      confidence: 0.9,
    ),
  },
);

void main() {
  setUpAll(() {
    registerFallbackValue(const MapInitialized(center: LatLng(0, 0), zoom: 1));
    registerFallbackValue(const CenterChanged(LatLng(0, 0)));
    registerFallbackValue(const ManeuverAdvanced());
  });

  late MockLocationBloc locationBloc;
  late MockRoutingBloc routingBloc;
  late MockNavigationBloc navigationBloc;
  late MockMapBloc mapBloc;
  late MockWeatherBloc weatherBloc;
  late MockConsentBloc consentBloc;
  late MockFleetBloc fleetBloc;

  setUp(() {
    locationBloc = MockLocationBloc();
    routingBloc = MockRoutingBloc();
    navigationBloc = MockNavigationBloc();
    mapBloc = MockMapBloc();
    weatherBloc = MockWeatherBloc();
    consentBloc = MockConsentBloc();
    fleetBloc = MockFleetBloc();

    when(
      () => locationBloc.state,
    ).thenReturn(const LocationState.uninitialized());
    when(() => routingBloc.state).thenReturn(const RoutingState.idle());
    when(() => navigationBloc.state).thenReturn(const NavigationState.idle());
    when(() => mapBloc.state).thenReturn(MapState.loading());
    when(() => weatherBloc.state).thenReturn(const WeatherState.unavailable());
    when(() => consentBloc.state).thenReturn(_consentGranted);
    when(() => fleetBloc.state).thenReturn(_fleetListening);
  });

  Widget buildMapScreen({
    Locale locale = const Locale('en'),
    bool fleetIsSimulated = true,
  }) {
    return MaterialApp(
      locale: locale,
      // Same delegates the real app installs (lib/snow_scene.dart) — without
      // them a `ja` locale throws before the caption is ever built.
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('en'), Locale('ja')],
      home: MultiBlocProvider(
        providers: [
          BlocProvider<LocationBloc>.value(value: locationBloc),
          BlocProvider<RoutingBloc>.value(value: routingBloc),
          BlocProvider<NavigationBloc>.value(value: navigationBloc),
          BlocProvider<MapBloc>.value(value: mapBloc),
          BlocProvider<WeatherBloc>.value(value: weatherBloc),
          BlocProvider<ConsentBloc>.value(value: consentBloc),
          BlocProvider<FleetBloc>.value(value: fleetBloc),
        ],
        child: SnowSceneScaffold(fleetIsSimulated: fleetIsSimulated),
      ),
    );
  }

  group('SimulatedFleetCaption on the live-drive map', () {
    testWidgets('1. discloses the demo fleet in English while it is drawing', (
      tester,
    ) async {
      await tester.pumpWidget(buildMapScreen());
      await tester.pump();

      expect(find.byType(SimulatedFleetCaption), findsOneWidget);
      expect(
        find.text(BriefingStrings.en.simulatedFleetCaption),
        findsOneWidget,
        reason: 'the map draws seeded fleet data; the screen must say so',
      );
    });

    testWidgets('2. discloses it in Japanese for a ja driver', (tester) async {
      await tester.pumpWidget(buildMapScreen(locale: const Locale('ja')));
      await tester.pump();

      expect(
        find.text(BriefingStrings.ja.simulatedFleetCaption),
        findsOneWidget,
        reason: 'her mother reads the map in Japanese or not at all',
      );
      expect(find.text(BriefingStrings.en.simulatedFleetCaption), findsNothing);
    });

    testWidgets('3. says nothing when fleet consent is denied', (tester) async {
      when(() => consentBloc.state).thenReturn(_consentDenied);

      await tester.pumpWidget(buildMapScreen());
      await tester.pump();

      expect(
        find.text(BriefingStrings.en.simulatedFleetCaption),
        findsNothing,
        reason: 'no fleet layer is drawn, so there is nothing to label',
      );
    });

    testWidgets('4. says nothing when the fleet bloc is not listening', (
      tester,
    ) async {
      when(() => fleetBloc.state).thenReturn(const FleetState.idle());

      await tester.pumpWidget(buildMapScreen());
      await tester.pump();

      expect(find.text(BriefingStrings.en.simulatedFleetCaption), findsNothing);
    });

    testWidgets('5. says nothing when the caller declares a real fleet feed', (
      tester,
    ) async {
      await tester.pumpWidget(buildMapScreen(fleetIsSimulated: false));
      await tester.pump();

      expect(
        find.text(BriefingStrings.en.simulatedFleetCaption),
        findsNothing,
        reason: 'a real telemetry feed must not be labelled simulated',
      );
    });

    testWidgets('6. sits in the bottom strip, clear of the map markers', (
      tester,
    ) async {
      await tester.pumpWidget(buildMapScreen());
      await tester.pump();

      final caption = tester.getRect(
        find.text(BriefingStrings.en.simulatedFleetCaption),
      );
      final map = tester.getRect(find.byType(MapLayer));

      // The fleet markers and hazard rings are drawn across the map viewport,
      // densest around its centre. The caption is chrome: it must stay in the
      // bottom strip so it can never sit on top of what it describes.
      expect(
        caption.top,
        greaterThan(map.center.dy),
        reason: 'caption must not intrude into the upper/central map area',
      );
      expect(caption.bottom, lessThanOrEqualTo(map.bottom + 1));
      expect(
        caption.height,
        lessThan(map.height * 0.1),
        reason: 'a disclosure that eats the map is a different defect',
      );
    });

    testWidgets('7. does not shove the fleet consent chip off the right edge', (
      tester,
    ) async {
      // Caught by looking at the running app, not by a green suite: wrapping
      // the caption + chip column in a Flexible made it split the row's spare
      // space with the Spacer, and the consent chip — untouched by this change
      // — slid from the right edge into the middle of the screen. Adding a
      // disclosure must not move a control the driver already knows.
      await tester.pumpWidget(buildMapScreen());
      await tester.pump();

      final chip = tester.getRect(find.text('Fleet: ON'));
      final screen = tester.getRect(find.byType(SnowSceneScaffold));

      expect(
        chip.right,
        greaterThan(screen.right - 40),
        reason: 'the consent chip belongs against the right edge',
      );
    });
  });

  group('BriefingStrings fleet caption', () {
    test('carries both locales and never silently falls back to English', () {
      expect(BriefingStrings.en.simulatedFleetCaption, isNotEmpty);
      expect(BriefingStrings.ja.simulatedFleetCaption, isNotEmpty);
      expect(
        BriefingStrings.ja.simulatedFleetCaption,
        isNot(equals(BriefingStrings.en.simulatedFleetCaption)),
      );
      expect(
        BriefingStrings.of(const Locale('ja')).simulatedFleetCaption,
        equals(BriefingStrings.ja.simulatedFleetCaption),
      );
    });

    test('names the demo and the determinism, like its pre-trip sibling', () {
      // Same register as simulatedForecastCaption — the pattern this app
      // already had, applied to the screen that never got it.
      expect(BriefingStrings.en.simulatedFleetCaption, contains('demo'));
      expect(
        BriefingStrings.en.simulatedFleetCaption,
        contains('deterministic'),
      );
      expect(BriefingStrings.ja.simulatedFleetCaption, contains('デモ'));
      expect(BriefingStrings.ja.simulatedFleetCaption, contains('確定的'));
    });
  });
}
