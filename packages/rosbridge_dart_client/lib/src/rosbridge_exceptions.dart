/// Exception types for the rosbridge client. Two classes for caller-side
/// discrimination: protocol errors (server-reported) vs transport errors
/// (network / WebSocket layer).
library;

/// Thrown when the rosbridge_server reports an `op:status` message with
/// `level:error`. The message field carries the server's verbatim
/// description.
class RosbridgeProtocolException implements Exception {
  /// Server-reported error message (verbatim).
  final String message;

  /// Optional topic the error pertains to, when surfaced as part of a
  /// per-subscription Stream.
  final String? topic;

  const RosbridgeProtocolException(this.message, {this.topic});

  @override
  String toString() {
    final t = topic == null ? '' : ' topic=$topic';
    return 'RosbridgeProtocolException($message)$t';
  }
}

/// Thrown when the WebSocket transport fails — connect failure, abrupt
/// close, or unexpected non-text frame.
class RosbridgeTransportException implements Exception {
  /// Human-readable description of the transport failure.
  final String message;

  const RosbridgeTransportException(this.message);

  @override
  String toString() => 'RosbridgeTransportException($message)';
}
