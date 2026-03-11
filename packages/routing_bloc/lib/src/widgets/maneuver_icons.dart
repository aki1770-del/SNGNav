/// Maneuver icon mapping for turn-by-turn display.
library;

import 'package:flutter/material.dart';

abstract final class ManeuverIcons {
  static IconData forType(String type) {
    return switch (type) {
      'depart' => Icons.flag,
      'arrive' => Icons.sports_score,
      'left' || 'slight_left' || 'sharp_left' => Icons.turn_left,
      'right' || 'slight_right' || 'sharp_right' => Icons.turn_right,
      'straight' || 'continue' => Icons.straight,
      'u_turn_left' || 'u_turn_right' => Icons.u_turn_left,
      'roundabout_enter' || 'roundabout_exit' => Icons.roundabout_left,
      'merge' || 'merge_left' || 'merge_right' => Icons.merge,
      'ramp_right' || 'ramp_left' || 'ramp_straight' => Icons.ramp_right,
      _ => Icons.navigation,
    };
  }
}