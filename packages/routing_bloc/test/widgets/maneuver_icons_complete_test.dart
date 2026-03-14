/// Tests for ManeuverIcons complete mapping and RouteProgressStatus enum.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:routing_bloc/routing_bloc.dart';

void main() {
  group('RouteProgressStatus enum', () {
    test('has four values', () {
      expect(RouteProgressStatus.values, hasLength(4));
    });

    test('values are in expected order', () {
      expect(RouteProgressStatus.values, [
        RouteProgressStatus.idle,
        RouteProgressStatus.active,
        RouteProgressStatus.deviated,
        RouteProgressStatus.arrived,
      ]);
    });

    test('name property matches', () {
      expect(RouteProgressStatus.idle.name, 'idle');
      expect(RouteProgressStatus.active.name, 'active');
      expect(RouteProgressStatus.deviated.name, 'deviated');
      expect(RouteProgressStatus.arrived.name, 'arrived');
    });
  });

  group('ManeuverIcons.forType — complete mapping', () {
    test('arrive maps to sports_score', () {
      expect(ManeuverIcons.forType('arrive'), equals(Icons.sports_score));
    });

    test('straight and continue map to straight', () {
      expect(ManeuverIcons.forType('straight'), equals(Icons.straight));
      expect(ManeuverIcons.forType('continue'), equals(Icons.straight));
    });

    test('u_turn variants map to u_turn_left', () {
      expect(ManeuverIcons.forType('u_turn_left'), equals(Icons.u_turn_left));
      expect(ManeuverIcons.forType('u_turn_right'), equals(Icons.u_turn_left));
    });

    test('roundabout variants map to roundabout_left', () {
      expect(
          ManeuverIcons.forType('roundabout_enter'), Icons.roundabout_left);
      expect(
          ManeuverIcons.forType('roundabout_exit'), Icons.roundabout_left);
    });

    test('merge variants map to merge', () {
      expect(ManeuverIcons.forType('merge'), equals(Icons.merge));
      expect(ManeuverIcons.forType('merge_left'), equals(Icons.merge));
      expect(ManeuverIcons.forType('merge_right'), equals(Icons.merge));
    });

    test('ramp variants map to ramp_right', () {
      expect(ManeuverIcons.forType('ramp_right'), equals(Icons.ramp_right));
      expect(ManeuverIcons.forType('ramp_left'), equals(Icons.ramp_right));
      expect(ManeuverIcons.forType('ramp_straight'), equals(Icons.ramp_right));
    });

    test('all known types return non-fallback icon', () {
      const knownTypes = [
        'depart',
        'arrive',
        'left',
        'slight_left',
        'sharp_left',
        'right',
        'slight_right',
        'sharp_right',
        'straight',
        'continue',
        'u_turn_left',
        'u_turn_right',
        'roundabout_enter',
        'roundabout_exit',
        'merge',
        'merge_left',
        'merge_right',
        'ramp_right',
        'ramp_left',
        'ramp_straight',
      ];

      for (final type in knownTypes) {
        expect(
          ManeuverIcons.forType(type),
          isNot(equals(Icons.navigation)),
          reason: '$type should not fall through to default',
        );
      }
    });

    test('unknown types fall back to navigation', () {
      expect(ManeuverIcons.forType('ferry'), equals(Icons.navigation));
      expect(ManeuverIcons.forType('elevator'), equals(Icons.navigation));
      expect(ManeuverIcons.forType(''), equals(Icons.navigation));
    });
  });
}
