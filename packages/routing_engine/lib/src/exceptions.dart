/// Exception thrown by any routing engine.
library;

class RoutingException implements Exception {
  final String message;
  const RoutingException(this.message);

  @override
  String toString() => 'RoutingException: $message';
}
