/// Render-and-see capture for the map screen's demo-fleet disclosure.
///
/// "Verified" means someone went and LOOKED at the output. A green assertion
/// that the caption is somewhere in the widget tree does not prove a human can
/// read it, in either language, without it burying the map it sits on.
///
/// Writes two PNGs of the WHOLE live-drive map screen — the same screen a
/// developer running the README quickstart lands on after "Start drive" — one
/// per locale, so the caption can be looked at in place, next to the markers
/// and rings it describes.
///
/// Run:
///   flutter test --update-goldens test/widgets/simulated_fleet_caption_capture_test.dart
/// Then OPEN and LOOK at:
///   test/widgets/goldens/map_simulated_fleet_caption_en.png
///   test/widgets/goldens/map_simulated_fleet_caption_ja.png
library;

import 'dart:io';

import 'package:bloc_test/bloc_test.dart';
import 'package:driving_consent/driving_consent.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:sngnav_snow_scene/widgets/snow_scene_scaffold.dart';

/// Whether the golden COMPARISON should run on this host.
///
/// Text rasterisation is host-dependent. Measured on CI at commit `5f16dbe`:
/// the EN capture differed from goldens authored on a dev host by
/// **5.62%, 39328px** — the same widget tree, the same locale, a different
/// font renderer. Comparing pixels across hosts asserts the renderer, not the
/// disclosure.
///
/// Per this file's own header it exists to WRITE images a human then opens and
/// looks at. So the comparison runs only where it means something: while
/// updating (`--update-goldens`, which writes rather than compares), or when a
/// caller deliberately asks for it.
///
/// The DISCLOSURE CONTRACT is not gated by this and is not skipped anywhere:
/// `simulated_fleet_caption_test.dart` asserts in 19 expectations that the
/// caption is present, in the right language, and absent when consent is
/// denied, when the bloc is not listening, and when the caller declares a real
/// fleet feed. That file is the guard. This one is the camera.
final bool _compareGoldens =
    autoUpdateGoldenFiles ||
    Platform.environment['SNGNAV_GOLDEN_COMPARE'] == '1';

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

/// Three vehicles reporting, two of them hazards — the state in which the red
/// rings are on the map and the disclosure is owed.
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
    'V-002': FleetReport(
      vehicleId: 'V-002',
      position: const LatLng(35.1000, 137.1000),
      timestamp: _now,
      condition: RoadCondition.snowy,
      confidence: 0.8,
    ),
    'V-003': FleetReport(
      vehicleId: 'V-003',
      position: const LatLng(35.1600, 136.9500),
      timestamp: _now,
      condition: RoadCondition.wet,
      confidence: 0.7,
    ),
  },
);

void main() {
  var fontLoaded = false;

  setUpAll(() async {
    registerFallbackValue(const MapInitialized(center: LatLng(0, 0), zoom: 1));
    registerFallbackValue(const CenterChanged(LatLng(0, 0)));
    registerFallbackValue(const ManeuverAdvanced());

    // flutter_map asks path_provider for a tile-cache directory; there is no
    // platform implementation in a widget test, so answer it here rather than
    // let the capture die on an unrelated plugin.
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async =>
              Directory.systemTemp.createTempSync('sngnav_cap').path,
        );

    // Without a real CJK font the Japanese caption renders as tofu boxes and a
    // passing golden would prove nothing about whether a Japanese-reading
    // driver can read it.
    for (final path in const [
      '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',
      '/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc',
    ]) {
      final file = File(path);
      if (file.existsSync()) {
        final loader = FontLoader('NotoSansCJK')
          ..addFont(Future.value(file.readAsBytesSync().buffer.asByteData()));
        await loader.load();
        fontLoaded = true;
      }
    }
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

  Widget buildMapScreen(Locale locale) {
    return MaterialApp(
      locale: locale,
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('en'), Locale('ja')],
      theme: ThemeData(fontFamily: 'NotoSansCJK', useMaterial3: true),
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
        child: const SnowSceneScaffold(),
      ),
    );
  }

  testWidgets('map screen shows the demo-fleet disclosure — English', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildMapScreen(const Locale('en')));
    await tester.pump();

    await expectLater(
      find.byType(SnowSceneScaffold),
      matchesGoldenFile('goldens/map_simulated_fleet_caption_en.png'),
    );
  }, skip: !_compareGoldens);

  testWidgets('map screen shows the demo-fleet disclosure — Japanese', (
    tester,
  ) async {
    if (!fontLoaded) {
      markTestSkipped('No Noto CJK font on this host — skipping JA capture.');
      return;
    }
    tester.view.physicalSize = const Size(1000, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildMapScreen(const Locale('ja')));
    await tester.pump();

    await expectLater(
      find.byType(SnowSceneScaffold),
      matchesGoldenFile('goldens/map_simulated_fleet_caption_ja.png'),
    );
  }, skip: !_compareGoldens);
}
