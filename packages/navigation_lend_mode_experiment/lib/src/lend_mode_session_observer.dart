// EXPLORE-PHASE — DO NOT PUBLISH. NOT FOR PRODUCTION USE.

import 'lend_mode_session.dart';

/// Exception raised when an illegal lend-mode operation is attempted.
///
/// Wraps the underlying error with the state the operation was attempted
/// from, so observers can surface a precise diagnostic to UI / telemetry.
class LendModeException implements Exception {
  LendModeException({
    required this.message,
    required this.attemptedFromState,
    this.cause,
  });

  final String message;
  final LendModeState attemptedFromState;
  final Object? cause;

  @override
  String toString() =>
      'LendModeException(message: $message, attemptedFromState: '
      '$attemptedFromState${cause == null ? '' : ', cause: $cause'})';
}

/// Observer protocol for [LendModeSession] transitions.
///
/// Implementations are caller-managed: this package does not retain
/// observer references on its own.
abstract class LendModeSessionObserver {
  /// Called whenever the session's state changes.
  void onStateChanged(
    LendModeSession session,
    LendModeState from,
    LendModeState to,
  );

  /// Called whenever the bound profile changes (lender ↔ receiver).
  ///
  /// Only fires when [LendModeSession.activeProfileTag] genuinely flips.
  void onActiveProfileChanged(
    LendModeSession session,
    String fromProfileTag,
    String toProfileTag,
  );

  /// Called when an illegal transition or invalid argument was caught.
  void onError(LendModeSession session, LendModeException error);
}
