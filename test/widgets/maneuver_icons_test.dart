/// ManeuverIcons unit tests — exhaustive type → icon mapping.
///
/// ManeuverIcons.forType() is a pure function mapping engine-agnostic
/// maneuver type strings to Material icons. Tests cover all 20 known
/// types plus the default fallback.
///
/// Sprint 9 Day 11 — Test hardening.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sngnav_snow_scene/widgets/maneuver_icons.dart';

void main() {
  group('ManeuverIcons.forType', () {
    test('depart → flag', () {
      expect(ManeuverIcons.forType('depart'), Icons.flag);
    });

    test('arrive → sports_score', () {
      expect(ManeuverIcons.forType('arrive'), Icons.sports_score);
    });

    test('left → turn_left', () {
      expect(ManeuverIcons.forType('left'), Icons.turn_left);
    });

    test('slight_left → turn_left', () {
      expect(ManeuverIcons.forType('slight_left'), Icons.turn_left);
    });

    test('sharp_left → turn_left', () {
      expect(ManeuverIcons.forType('sharp_left'), Icons.turn_left);
    });

    test('right → turn_right', () {
      expect(ManeuverIcons.forType('right'), Icons.turn_right);
    });

    test('slight_right → turn_right', () {
      expect(ManeuverIcons.forType('slight_right'), Icons.turn_right);
    });

    test('sharp_right → turn_right', () {
      expect(ManeuverIcons.forType('sharp_right'), Icons.turn_right);
    });

    test('straight → straight', () {
      expect(ManeuverIcons.forType('straight'), Icons.straight);
    });

    test('continue → straight', () {
      expect(ManeuverIcons.forType('continue'), Icons.straight);
    });

    test('u_turn_left → u_turn_left', () {
      expect(ManeuverIcons.forType('u_turn_left'), Icons.u_turn_left);
    });

    test('u_turn_right → u_turn_left', () {
      expect(ManeuverIcons.forType('u_turn_right'), Icons.u_turn_left);
    });

    test('roundabout_enter → roundabout_left', () {
      expect(ManeuverIcons.forType('roundabout_enter'), Icons.roundabout_left);
    });

    test('roundabout_exit → roundabout_left', () {
      expect(ManeuverIcons.forType('roundabout_exit'), Icons.roundabout_left);
    });

    test('merge → merge', () {
      expect(ManeuverIcons.forType('merge'), Icons.merge);
    });

    test('merge_left → merge', () {
      expect(ManeuverIcons.forType('merge_left'), Icons.merge);
    });

    test('merge_right → merge', () {
      expect(ManeuverIcons.forType('merge_right'), Icons.merge);
    });

    test('ramp_right → ramp_right', () {
      expect(ManeuverIcons.forType('ramp_right'), Icons.ramp_right);
    });

    test('ramp_left → ramp_right', () {
      expect(ManeuverIcons.forType('ramp_left'), Icons.ramp_right);
    });

    test('ramp_straight → ramp_right', () {
      expect(ManeuverIcons.forType('ramp_straight'), Icons.ramp_right);
    });

    test('unknown type → navigation (default)', () {
      expect(ManeuverIcons.forType('ferry_enter'), Icons.navigation);
    });

    test('empty string → navigation (default)', () {
      expect(ManeuverIcons.forType(''), Icons.navigation);
    });

    test('nonsense string → navigation (default)', () {
      expect(ManeuverIcons.forType('xyzzy'), Icons.navigation);
    });
  });
}
