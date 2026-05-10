// Minimal example for nav2_safety_layer.
//
// Demonstrates the composition seam: nav2 Collision Monitor state
// events feed into Nav2SafetyLayer; the layer maps them through
// navigation_safety_core's AlertExplainer + AlertDensityThrottle and
// emits driver-facing advisory strings the integrator's HMI can
// surface.
//
// In production, the integrator wires their ROS-Dart bridge of
// choice (e.g. `rosbridge_dart_client`) to push typed records into
// the layer. Here we feed two synthetic events to show the loop.

import 'package:nav2_safety_layer/nav2_safety_layer.dart';
import 'package:navigation_safety_core/navigation_safety_core.dart';

Future<void> main() async {
  final layer = Nav2SafetyLayer(
    profile: DriverProfile.snowZoneExperienced,
    throttle: AlertDensityThrottle(alertsPerMinuteCap: 60),
  );
  layer.advisories.listen((advisory) {
    print('Advisory: $advisory');
  });

  layer.onMonitorState(
    const Nav2CollisionMonitorState(
      actionType: Nav2CollisionAction.stop,
      polygonName: 'forward_safety',
    ),
  );

  layer.onDetectorState(
    const Nav2CollisionDetectorState(
      polygons: ['front', 'rear'],
      detections: [true, false],
    ),
  );

  await Future<void>.delayed(const Duration(milliseconds: 50));
  await layer.dispose();
}
