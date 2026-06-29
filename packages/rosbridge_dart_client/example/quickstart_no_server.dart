// Self-contained: runs with NO ROS server. A tiny in-process WebSocket
// stands in for rosbridge_server so you see real decoded output now.
import 'dart:convert';
import 'dart:io';
import 'package:rosbridge_dart_client/rosbridge_dart_client.dart';

Future<void> main() async {
  // 1. Fake rosbridge_server: replies to any subscribe with one publish frame.
  final server = await HttpServer.bind('localhost', 9090);
  server.listen((req) async {
    final ws = await WebSocketTransformer.upgrade(req);
    ws.listen((_) => ws.add(jsonEncode({
          'op': 'publish',
          'topic': '/collision_monitor/state',
          'msg': {'state': 'CAUTION', 'stamp': 12.3},
        })));
  });

  // 2. The REAL package API:
  final client = RosbridgeClient(uri: Uri.parse('ws://localhost:9090'));
  await client.connect();
  final json = await client
      .subscribe(topic: '/collision_monitor/state', type: 'nav2_msgs/msg/CollisionMonitorState')
      .first;
  print('Decoded nav2 state: $json'); // -> {state: CAUTION, stamp: 12.3}

  await client.close();
  await server.close();
}
