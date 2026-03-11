library;

import 'package:driving_conditions/driving_conditions.dart';
import 'package:driving_weather/driving_weather.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalman_dr/kalman_dr.dart';
import 'package:map_viewport_bloc/map_viewport_bloc.dart';
import 'package:navigation_safety/navigation_safety.dart';
import 'package:offline_tiles/offline_tiles.dart';
import 'package:routing_bloc/routing_bloc.dart';
import 'package:routing_engine/routing_engine.dart';

import 's52_test_fixtures.dart';

void main() {
  test('Sprint 52 target packages resolve together in one integration context', () {
    final exportedTypes = <Type>[
      WeatherCondition,
      DrivingConditionAssessment,
      SafetyScoreSimulator,
      SafetyScore,
      RoutingEngine,
      RoutingBloc,
      DeadReckoningProvider,
      OfflineTileManager,
      MapBloc,
    ];

    expect(exportedTypes, hasLength(9));
    expect(S52TestFixtures.safetySeed, equals(42));
    expect(S52TestFixtures.nagoyaToOkazakiRequest.origin,
        equals(S52TestFixtures.nagoya));
    expect(S52TestFixtures.nagoyaToOkazakiRoute.hasGeometry, isTrue);
    expect(S52TestFixtures.nagoyaToOkazakiRoute.engineInfo.name,
        equals('mock-s52'));
  });
}