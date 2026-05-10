// ignore_for_file: avoid_print
//
// Minimal example for rosbridge_dart_client.
//
// Demonstrates connect → subscribe → close lifecycle. In production,
// the integrator subscribes to nav2_msgs (or other) topics and maps
// the JSON payload to typed records (e.g. via
// Nav2CollisionMonitorState.fromJson from the nav2_safety_layer
// package).
//
// To run against a real rosbridge_server:
//   ros2 launch rosbridge_server rosbridge_websocket_launch.xml
// then `dart run example/main.dart` — or substitute your own URI.

import 'package:rosbridge_dart_client/rosbridge_dart_client.dart';

Future<void> main() async {
  final client = RosbridgeClient(uri: Uri.parse('ws://localhost:9090'));

  try {
    await client.connect();
  } on RosbridgeTransportException catch (e) {
    print('Connect failed (no rosbridge_server reachable): $e');
    print('Start a rosbridge_server with:');
    print('  ros2 launch rosbridge_server rosbridge_websocket_launch.xml');
    return;
  }

  final sub = client
      .subscribe(
        topic: '/collision_monitor/state',
        type: 'nav2_msgs/msg/CollisionMonitorState',
      )
      .listen(
        (json) => print('Got: $json'),
        onError: (Object e) => print('Stream error: $e'),
      );

  await Future<void>.delayed(const Duration(seconds: 5));
  await sub.cancel();
  await client.close();
}
