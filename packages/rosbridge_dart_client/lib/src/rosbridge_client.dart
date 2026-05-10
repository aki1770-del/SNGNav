/// Subscribe-only WebSocket client for the rosbridge_suite JSON
/// protocol.
///
/// Connects to a `rosbridge_server` ROS 2 node over WebSocket and
/// surfaces topic-subscribe streams as `Stream<Map<String, dynamic>>`.
/// Out of scope for 0.1.0: publish (op:publish), service calls
/// (op:call_service), advertise / unadvertise, action goals, PNG-
/// compressed messages, and authentication. The integrator wraps
/// authentication into the WebSocket connect URI if needed.
///
/// Per the rosbridge_suite PROTOCOL.md (canonical at
/// `RobotWebTools/rosbridge_suite`), the four ops we use:
///
/// - `op:subscribe` (client → server) — request topic subscription
/// - `op:unsubscribe` (client → server) — cancel subscription on
///   Stream cancel
/// - `op:publish` (server → client) — message payload arriving on a
///   subscribed topic
/// - `op:status` (server → client) — protocol-level status / error
///   notifications
library;

import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'rosbridge_exceptions.dart';

/// Subscribe-only rosbridge_suite WebSocket client.
class RosbridgeClient {
  /// rosbridge_server WebSocket endpoint (e.g.
  /// `Uri.parse('ws://localhost:9090')`).
  final Uri uri;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _channelSub;

  /// Per-topic broadcast controllers; one per subscribed topic.
  final Map<String, StreamController<Map<String, dynamic>>> _topicControllers =
      <String, StreamController<Map<String, dynamic>>>{};

  bool _closed = false;

  RosbridgeClient({required this.uri});

  /// Test-only constructor: inject a pre-built WebSocketChannel
  /// (typically backed by a mock transport).
  RosbridgeClient.withChannel({
    required this.uri,
    required WebSocketChannel channel,
  }) : _channel = channel {
    _wireChannel();
  }

  /// Connect to the rosbridge_server WebSocket endpoint. Must be called
  /// exactly once before any [subscribe] call. Idempotent: calling
  /// connect on an already-connected client is a no-op.
  Future<void> connect() async {
    if (_channel != null) return;
    try {
      _channel = WebSocketChannel.connect(uri);
      await _channel!.ready;
    } on Exception catch (e) {
      throw RosbridgeTransportException('connect failed: $e');
    }
    _wireChannel();
  }

  void _wireChannel() {
    _channelSub = _channel!.stream.listen(
      _handleInbound,
      onError: _handleTransportError,
      onDone: _handleTransportClose,
    );
  }

  /// Subscribe to a ROS 2 topic. Returns a Stream of decoded JSON
  /// message maps (the publisher's `msg` field). Caller maps the maps
  /// to typed records (e.g. via `Nav2CollisionMonitorState.fromJson`
  /// in the `nav2_safety_layer` package).
  ///
  /// Cancelling the returned Stream subscription emits an
  /// `op:unsubscribe` to the server.
  Stream<Map<String, dynamic>> subscribe({
    required String topic,
    required String type,
  }) {
    if (_closed) {
      throw const RosbridgeTransportException(
        'subscribe called on closed client',
      );
    }
    if (_channel == null) {
      throw const RosbridgeTransportException(
        'subscribe called before connect',
      );
    }

    final existing = _topicControllers[topic];
    if (existing != null) return existing.stream;

    final controller = StreamController<Map<String, dynamic>>.broadcast(
      onCancel: () => _onTopicCancelled(topic),
    );
    _topicControllers[topic] = controller;

    _send(<String, dynamic>{'op': 'subscribe', 'topic': topic, 'type': type});

    return controller.stream;
  }

  void _send(Map<String, dynamic> op) {
    if (_channel == null) return;
    _channel!.sink.add(jsonEncode(op));
  }

  void _onTopicCancelled(String topic) {
    final controller = _topicControllers.remove(topic);
    if (controller == null) return;
    if (!_closed && _channel != null) {
      _send(<String, dynamic>{'op': 'unsubscribe', 'topic': topic});
    }
    controller.close();
  }

  void _handleInbound(dynamic frame) {
    if (frame is! String) {
      _broadcastTransportError(
        const RosbridgeTransportException('expected text WebSocket frame'),
      );
      return;
    }
    Map<String, dynamic> decoded;
    try {
      final dynamic raw = jsonDecode(frame);
      if (raw is! Map<String, dynamic>) {
        _broadcastTransportError(
          const RosbridgeTransportException('expected JSON object frame'),
        );
        return;
      }
      decoded = raw;
    } on FormatException catch (e) {
      _broadcastTransportError(
        RosbridgeTransportException('non-JSON frame: ${e.message}'),
      );
      return;
    }

    final op = decoded['op'];
    if (op == 'publish') {
      final topic = decoded['topic'] as String?;
      final msg = decoded['msg'];
      if (topic == null || msg is! Map<String, dynamic>) return;
      final controller = _topicControllers[topic];
      if (controller != null) controller.add(msg);
    } else if (op == 'status') {
      final level = decoded['level'] as String?;
      final message = decoded['msg'] as String? ?? '(no message)';
      final topic = decoded['topic'] as String?;
      if (level == 'error') {
        final exc = RosbridgeProtocolException(message, topic: topic);
        if (topic != null && _topicControllers.containsKey(topic)) {
          _topicControllers[topic]!.addError(exc);
        } else {
          _broadcastProtocolError(exc);
        }
      }
    }
  }

  void _broadcastTransportError(RosbridgeTransportException exc) {
    for (final controller in _topicControllers.values) {
      controller.addError(exc);
    }
  }

  void _broadcastProtocolError(RosbridgeProtocolException exc) {
    for (final controller in _topicControllers.values) {
      controller.addError(exc);
    }
  }

  void _handleTransportError(Object error) {
    _broadcastTransportError(
      RosbridgeTransportException('transport error: $error'),
    );
  }

  void _handleTransportClose() {
    _broadcastTransportError(
      const RosbridgeTransportException('transport closed by server'),
    );
  }

  /// Close the WebSocket connection + all subscribe Streams.
  /// Idempotent. Safe to call from a parent app's lifecycle teardown.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final controllers = _topicControllers.values.toList(growable: false);
    _topicControllers.clear();
    for (final c in controllers) {
      await c.close();
    }
    await _channelSub?.cancel();
    await _channel?.sink.close();
  }
}
