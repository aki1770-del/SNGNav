library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:routing_bloc/routing_bloc.dart';

void main() {
  test('maps depart to flag', () {
    expect(ManeuverIcons.forType('depart'), equals(Icons.flag));
  });

  test('maps left family to turn_left', () {
    expect(ManeuverIcons.forType('left'), equals(Icons.turn_left));
    expect(ManeuverIcons.forType('slight_left'), equals(Icons.turn_left));
    expect(ManeuverIcons.forType('sharp_left'), equals(Icons.turn_left));
  });

  test('maps right family to turn_right', () {
    expect(ManeuverIcons.forType('right'), equals(Icons.turn_right));
    expect(ManeuverIcons.forType('slight_right'), equals(Icons.turn_right));
    expect(ManeuverIcons.forType('sharp_right'), equals(Icons.turn_right));
  });

  test('maps fallback to navigation', () {
    expect(ManeuverIcons.forType('unknown'), equals(Icons.navigation));
  });
}