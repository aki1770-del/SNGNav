/// Tests for rosbridge_dart_client.
///
/// Live WebSocket transport mocked via a controllable in-process
/// `WebSocketChannel` — tests run without a ROS bridge server.
library;

import 'dart:async';
import 'dart:convert';

import 'package:rosbridge_dart_client/rosbridge_dart_client.dart';
import 'package:test/test.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Synthetic in-process WebSocketChannel for tests. Wraps a
/// StreamChannelController to satisfy the full StreamChannel interface
/// without re-implementing transform / pipe / cast helpers.
class _FakeWebSocketChannel extends StreamChannelMixin<dynamic>
    implements WebSocketChannel {
  final StreamController<dynamic> _inbound =
      StreamController<dynamic>.broadcast();
  final List<dynamic> _outbound = <dynamic>[];
  late final WebSocketSink _sink = _FakeSink(_outbound, _inbound);

  @override
  Stream<dynamic> get stream => _inbound.stream;

  @override
  WebSocketSink get sink => _sink;

  @override
  Future<void> get ready async {}

  @override
  String? get protocol => null;

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;

  /// Inject an inbound frame as if the rosbridge server sent it.
  void injectInbound(dynamic frame) => _inbound.add(frame);

  /// All outbound frames the client has sent so far.
  List<dynamic> get outboundFrames => List.unmodifiable(_outbound);
}

class _FakeSink implements WebSocketSink {
  final List<dynamic> _outbound;
  final StreamController<dynamic> _inbound;

  _FakeSink(this._outbound, this._inbound);

  @override
  void add(dynamic data) => _outbound.add(data);

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<dynamic> stream) async {}

  @override
  Future<dynamic> close([int? closeCode, String? closeReason]) async {
    if (!_inbound.isClosed) await _inbound.close();
  }

  @override
  Future<void> get done async {}
}

void main() {
  group('RosbridgeClient subscribe', () {
    test('subscribe sends op=subscribe with topic and type', () {
      final ws = _FakeWebSocketChannel();
      final client = RosbridgeClient.withChannel(
        uri: Uri.parse('ws://test'),
        channel: ws,
      );

      client.subscribe(
        topic: '/collision_monitor/state',
        type: 'nav2_msgs/msg/CollisionMonitorState',
      );

      expect(ws.outboundFrames, hasLength(1));
      final decoded =
          jsonDecode(ws.outboundFrames.first as String) as Map<String, dynamic>;
      expect(decoded['op'], 'subscribe');
      expect(decoded['topic'], '/collision_monitor/state');
      expect(decoded['type'], 'nav2_msgs/msg/CollisionMonitorState');
    });

    test('inbound op=publish reaches the subscribe Stream', () async {
      final ws = _FakeWebSocketChannel();
      final client = RosbridgeClient.withChannel(
        uri: Uri.parse('ws://test'),
        channel: ws,
      );

      final sub = client.subscribe(
        topic: '/test/topic',
        type: 'std_msgs/msg/String',
      );
      final received = <Map<String, dynamic>>[];
      final s = sub.listen(received.add);

      ws.injectInbound(
        jsonEncode(<String, dynamic>{
          'op': 'publish',
          'topic': '/test/topic',
          'msg': <String, dynamic>{'data': 'hello'},
        }),
      );

      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(received, hasLength(1));
      expect(received.first['data'], 'hello');
      await s.cancel();
    });

    test('Stream cancel sends op=unsubscribe', () async {
      final ws = _FakeWebSocketChannel();
      final client = RosbridgeClient.withChannel(
        uri: Uri.parse('ws://test'),
        channel: ws,
      );

      final sub = client
          .subscribe(topic: '/t', type: 'std_msgs/msg/String')
          .listen((_) {});
      await sub.cancel();

      // First outbound is the subscribe; second should be the unsubscribe.
      final unsub =
          jsonDecode(ws.outboundFrames.last as String) as Map<String, dynamic>;
      expect(unsub['op'], 'unsubscribe');
      expect(unsub['topic'], '/t');
    });

    test(
      'inbound op=status level=error surfaces on the topic Stream',
      () async {
        final ws = _FakeWebSocketChannel();
        final client = RosbridgeClient.withChannel(
          uri: Uri.parse('ws://test'),
          channel: ws,
        );

        final sub = client.subscribe(
          topic: '/bad/topic',
          type: 'std_msgs/msg/String',
        );

        final completer = Completer<Object>();
        final s = sub.listen(
          (_) {},
          onError: (Object e) {
            if (!completer.isCompleted) completer.complete(e);
          },
        );

        ws.injectInbound(
          jsonEncode(<String, dynamic>{
            'op': 'status',
            'level': 'error',
            'msg': 'bad topic',
            'topic': '/bad/topic',
          }),
        );

        final result = await completer.future.timeout(
          const Duration(seconds: 1),
        );
        await s.cancel();
        expect(result, isA<RosbridgeProtocolException>());
      },
    );

    test('non-JSON inbound surfaces as RosbridgeTransportException', () async {
      final ws = _FakeWebSocketChannel();
      final client = RosbridgeClient.withChannel(
        uri: Uri.parse('ws://test'),
        channel: ws,
      );

      final sub = client.subscribe(topic: '/t', type: 'std_msgs/msg/String');
      final completer = Completer<Object>();
      final s = sub.listen(
        (_) {},
        onError: (Object e) {
          if (!completer.isCompleted) completer.complete(e);
        },
      );

      ws.injectInbound('<<not-json>>');

      final result = await completer.future.timeout(const Duration(seconds: 1));
      await s.cancel();
      expect(result, isA<RosbridgeTransportException>());
    });

    test('subscribe before connect throws transport exception', () {
      final client = RosbridgeClient(uri: Uri.parse('ws://test'));
      expect(
        () => client.subscribe(topic: '/t', type: 'std_msgs/msg/String'),
        throwsA(isA<RosbridgeTransportException>()),
      );
    });

    test('subscribe twice on same topic returns same broadcast Stream', () {
      final ws = _FakeWebSocketChannel();
      final client = RosbridgeClient.withChannel(
        uri: Uri.parse('ws://test'),
        channel: ws,
      );

      client.subscribe(topic: '/t', type: 'std_msgs/msg/String');
      client.subscribe(topic: '/t', type: 'std_msgs/msg/String');
      // Only one outbound subscribe op — second subscribe reuses
      // the existing controller without re-sending op=subscribe.
      expect(ws.outboundFrames, hasLength(1));
    });

    test('close is idempotent', () async {
      final ws = _FakeWebSocketChannel();
      final client = RosbridgeClient.withChannel(
        uri: Uri.parse('ws://test'),
        channel: ws,
      );
      await client.close();
      await client.close();
    });
  });
}
