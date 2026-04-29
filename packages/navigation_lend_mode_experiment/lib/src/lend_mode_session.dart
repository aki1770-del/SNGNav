/// Aviation-style explicit-handoff state machine for navigation safety
/// profile lending between drivers on the same device for a single trip.
///
/// EXPLORE-PHASE. NOT PUBLISHED. See README.md and KNOWN_LIMITATIONS.md.
///
/// ## Transitions
///
/// ```
/// idle ── initiate() ───────────► initiated
/// initiated ── presentAcknowledgement() ─► awaitingAck
/// awaitingAck ── acknowledge(text) ──────► active
/// {initiated, awaitingAck, active} ── revert(reason) ─► reverted
/// ```
///
/// `reverted` is terminal: any further state-changing call raises
/// [LendModeException].
///
/// The active threshold-profile tag is the lender's tag in every state
/// except [LendModeState.active], where it is the receiver's tag. The
/// observer's `onActiveProfileChanged` is invoked exactly when the active
/// tag changes.
library;

import 'lend_mode_session_observer.dart';

/// Aviation-handoff lend-mode session.
///
/// Pure-Dart, single-trip, single-device. Constructor takes the two
/// profile tags as opaque strings; this package does not interpret them.
class LendModeSession {
  /// Construct a session.
  ///
  /// [lenderProfileTag] is the profile that owns the device at start and
  /// returns to ownership on revert. [receiverProfileTag] becomes active
  /// after the receiver acknowledges. Both must be non-empty and must
  /// differ; otherwise the constructor throws [LendModeException].
  ///
  /// [observer] is optional. If supplied, it is notified synchronously
  /// from each state-changing call.
  LendModeSession({
    required String lenderProfileTag,
    required String receiverProfileTag,
    LendModeSessionObserver? observer,
  })  : _lenderProfileTag = _requireNonEmpty(
          lenderProfileTag,
          'lenderProfileTag',
        ),
        _receiverProfileTag = _requireNonEmpty(
          receiverProfileTag,
          'receiverProfileTag',
        ),
        _observer = observer,
        _state = LendModeState.idle,
        _activeProfileTag = lenderProfileTag,
        _revertReason = null {
    if (lenderProfileTag == receiverProfileTag) {
      final err = LendModeException(
        'lenderProfileTag and receiverProfileTag must differ',
      );
      observer?.onError(err);
      throw err;
    }
  }

  final String _lenderProfileTag;
  final String _receiverProfileTag;
  final LendModeSessionObserver? _observer;

  LendModeState _state;
  String _activeProfileTag;
  RevertReason? _revertReason;

  /// Lender profile tag (constant for the session lifetime).
  String get lenderProfileTag => _lenderProfileTag;

  /// Receiver profile tag (constant for the session lifetime).
  String get receiverProfileTag => _receiverProfileTag;

  /// Current state.
  LendModeState get state => _state;

  /// Profile tag currently bearing safety-threshold authority.
  ///
  /// Equals [lenderProfileTag] in every state except
  /// [LendModeState.active], where it equals [receiverProfileTag].
  String get activeProfileTag => _activeProfileTag;

  /// Reason the session was reverted, or null if not reverted.
  RevertReason? get revertReason => _revertReason;

  /// True iff the session is in its terminal state ([LendModeState.reverted]).
  bool get isTerminal => _state == LendModeState.reverted;

  /// Lender requests a handoff. Only legal from [LendModeState.idle].
  void initiate() {
    _requireFrom({LendModeState.idle}, 'initiate');
    _setState(LendModeState.initiated);
  }

  /// Show the acknowledgement prompt to the receiver.
  /// Only legal from [LendModeState.initiated].
  void presentAcknowledgement() {
    _requireFrom({LendModeState.initiated}, 'presentAcknowledgement');
    _setState(LendModeState.awaitingAck);
  }

  /// Receiver acknowledges responsibility transfer.
  ///
  /// Only legal from [LendModeState.awaitingAck]. [acknowledgementText]
  /// must be non-empty after trimming; this package does not interpret
  /// the text further.
  void acknowledge(String acknowledgementText) {
    _requireFrom({LendModeState.awaitingAck}, 'acknowledge');
    if (acknowledgementText.trim().isEmpty) {
      _raise(
        'acknowledgementText must be non-empty',
        attemptedFromState: _state,
      );
    }
    _setState(LendModeState.active);
    _setActiveProfileTag(_receiverProfileTag);
  }

  /// End the session. Legal from [LendModeState.initiated],
  /// [LendModeState.awaitingAck], or [LendModeState.active]. Restores
  /// the lender as the active profile (if it was not already) and
  /// records [reason]. Terminal.
  void revert({required RevertReason reason}) {
    _requireFrom(
      {
        LendModeState.initiated,
        LendModeState.awaitingAck,
        LendModeState.active,
      },
      'revert',
    );
    _revertReason = reason;
    _setState(LendModeState.reverted);
    if (_activeProfileTag != _lenderProfileTag) {
      _setActiveProfileTag(_lenderProfileTag);
    }
  }

  void _requireFrom(Set<LendModeState> allowed, String method) {
    if (!allowed.contains(_state)) {
      _raise(
        '$method is not legal from state $_state '
        '(allowed: ${allowed.toList()})',
        attemptedFromState: _state,
      );
    }
  }

  void _setState(LendModeState newState) {
    if (_state == newState) return;
    _state = newState;
    _observer?.onStateChanged(newState);
  }

  void _setActiveProfileTag(String tag) {
    if (_activeProfileTag == tag) return;
    _activeProfileTag = tag;
    _observer?.onActiveProfileChanged(tag);
  }

  Never _raise(String message, {LendModeState? attemptedFromState}) {
    final err = LendModeException(
      message,
      attemptedFromState: attemptedFromState,
    );
    _observer?.onError(err);
    throw err;
  }

  static String _requireNonEmpty(String value, String name) {
    if (value.isEmpty) {
      throw LendModeException('$name must be non-empty');
    }
    return value;
  }
}
