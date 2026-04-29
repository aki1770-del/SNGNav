/// Observer interface for lend-mode session events.
///
/// Callers attach an observer to receive state-machine and active-profile
/// transitions, plus error notifications. The observer is the integration
/// point for UI, logging, and persistence layers; this package itself does
/// not perform any of those.
library;

/// State of a [LendModeSession].
///
/// See `lend_mode_session.dart` for transition rules.
enum LendModeState {
  /// Initial state. No handoff has been requested.
  idle,

  /// Lender has requested a handoff. The acknowledgement prompt has not
  /// yet been shown.
  initiated,

  /// Acknowledgement prompt is shown. Awaiting explicit acknowledge text
  /// from the receiver.
  awaitingAck,

  /// Receiver has acknowledged. Active threshold profile is the receiver's.
  active,

  /// Session ended; active threshold profile reverted to the lender's.
  /// Terminal state for this session instance.
  reverted,
}

/// Reason a session was reverted.
enum RevertReason {
  /// Trip ended through normal means (route completed, navigation closed).
  tripEnded,

  /// Caller explicitly invoked revert (e.g. user pressed "end lend mode").
  explicitRevert,

  /// Session reached a caller-decided maximum duration. This package does
  /// not run timers; the caller chooses when this applies.
  timeout,
}

/// Exception raised by the lend-mode state machine on illegal transitions
/// or invalid input.
class LendModeException implements Exception {
  /// Human-readable cause.
  final String message;

  /// State the caller attempted to transition from, when known.
  final LendModeState? attemptedFromState;

  /// Construct an exception. [attemptedFromState] is optional context.
  LendModeException(this.message, {this.attemptedFromState});

  @override
  String toString() {
    if (attemptedFromState != null) {
      return 'LendModeException: $message (from state: $attemptedFromState)';
    }
    return 'LendModeException: $message';
  }
}

/// Observer notified of session state changes.
///
/// All methods are called synchronously from the state-machine method that
/// caused the change. Implementations must not block.
abstract class LendModeSessionObserver {
  /// Called when [LendModeState] transitions to [newState].
  void onStateChanged(LendModeState newState);

  /// Called when the active threshold-profile tag changes (i.e. when the
  /// session enters [LendModeState.active] or returns to a lender-active
  /// state via [LendModeState.reverted]).
  void onActiveProfileChanged(String newActiveProfileTag);

  /// Called when a state-machine method raises [LendModeException].
  /// The exception is also rethrown to the caller; this hook is for
  /// logging and UI feedback only.
  void onError(LendModeException error);
}
