// EXPLORE-PHASE — DO NOT PUBLISH. NOT FOR PRODUCTION USE.

/// Discrete states of an aviation-style lend-mode handoff.
///
/// Transitions form a strict directed graph:
///
///   idle ─initiate()──▶ initiated ─(internal)─▶ awaitingAck
///        ─acknowledge()─▶ active ─revert()─▶ reverted
///
/// Any other transition raises [StateError]. The aviation discipline:
/// the controls do not change hands without an explicit, recorded act.
enum LendModeState {
  /// No handoff in progress. The lender's profile is bound to the trip.
  idle,

  /// Handoff requested by the lender; not yet broadcast for ack.
  initiated,

  /// Receiver has been prompted; system is waiting for an explicit ack.
  awaitingAck,

  /// Receiver acknowledged. Receiver's profile is bound to the trip.
  active,

  /// Handoff has ended. Lender's profile is restored.
  reverted,
}

/// Why an active lend-mode session was reverted.
enum RevertReason {
  /// Trip ended naturally (e.g. arrival at destination).
  tripEnded,

  /// Either party explicitly ended the lend.
  explicitRevert,

  /// Caller-driven timeout fired (this package does not schedule).
  timeout,
}

/// A single aviation-style lend-mode handoff session.
///
/// Construct one per trip. The session is single-use: once it has been
/// reverted it cannot be reused; create a new [LendModeSession] for the
/// next trip.
///
/// Severity-not-profile (D4): the lender selector that produces the
/// [lenderProfileTag] and [receiverProfileTag] passed in here MUST offer
/// all six driver-class profiles equally. A novice lending to an
/// experienced driver is a first-class case.
class LendModeSession {
  LendModeSession({
    required this.lenderProfileTag,
    required this.receiverProfileTag,
    required this.initiatedAt,
  });

  /// Profile tag of the phone owner / lender.
  final String lenderProfileTag;

  /// Profile tag of the receiving driver.
  final String receiverProfileTag;

  /// Timestamp the [LendModeSession] was constructed (lender intent).
  final DateTime initiatedAt;

  DateTime? _acknowledgedAt;
  DateTime? _revertedAt;
  LendModeState _state = LendModeState.idle;
  RevertReason? _revertReason;

  /// Timestamp of the receiver's explicit ack, if any.
  DateTime? get acknowledgedAt => _acknowledgedAt;

  /// Timestamp of revert, if any.
  DateTime? get revertedAt => _revertedAt;

  /// Reason the session was reverted, if any.
  RevertReason? get revertReason => _revertReason;

  /// Current state.
  LendModeState get state => _state;

  /// The profile tag currently bound to the trip.
  ///
  /// Only when the session is [LendModeState.active] is the receiver's
  /// profile bound; in every other state the lender's profile is bound.
  String get activeProfileTag => _state == LendModeState.active
      ? receiverProfileTag
      : lenderProfileTag;

  /// Begin the handoff. idle ─▶ initiated ─▶ awaitingAck.
  ///
  /// Throws [StateError] if not currently [LendModeState.idle].
  void initiate() {
    if (_state != LendModeState.idle) {
      throw StateError(
        'initiate() called from $_state; only valid from idle.',
      );
    }
    _state = LendModeState.initiated;
    _state = LendModeState.awaitingAck;
  }

  /// Receiver explicitly acknowledges responsibility transfer.
  ///
  /// [explicitAckText] must be non-empty and non-whitespace per aviation
  /// discipline: there is no implicit ack. An empty string is not a
  /// readback.
  ///
  /// Throws [ArgumentError] if [explicitAckText] is empty/whitespace.
  /// Throws [StateError] if not currently [LendModeState.awaitingAck].
  void acknowledge({required String explicitAckText}) {
    if (explicitAckText.trim().isEmpty) {
      throw ArgumentError.value(
        explicitAckText,
        'explicitAckText',
        'Aviation-discipline ack must be non-empty and non-whitespace.',
      );
    }
    if (_state != LendModeState.awaitingAck) {
      throw StateError(
        'acknowledge() called from $_state; only valid from awaitingAck.',
      );
    }
    _acknowledgedAt = DateTime.now();
    _state = LendModeState.active;
  }

  /// End the active lend. active ─▶ reverted.
  ///
  /// Throws [StateError] if not currently [LendModeState.active].
  void revert({required RevertReason reason}) {
    if (_state != LendModeState.active) {
      throw StateError(
        'revert() called from $_state; only valid from active.',
      );
    }
    _revertedAt = DateTime.now();
    _revertReason = reason;
    _state = LendModeState.reverted;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LendModeSession &&
          runtimeType == other.runtimeType &&
          lenderProfileTag == other.lenderProfileTag &&
          receiverProfileTag == other.receiverProfileTag &&
          initiatedAt == other.initiatedAt &&
          _state == other._state &&
          _acknowledgedAt == other._acknowledgedAt &&
          _revertedAt == other._revertedAt &&
          _revertReason == other._revertReason;

  @override
  int get hashCode => Object.hash(
        lenderProfileTag,
        receiverProfileTag,
        initiatedAt,
        _state,
        _acknowledgedAt,
        _revertedAt,
        _revertReason,
      );

  @override
  String toString() =>
      'LendModeSession(lender: $lenderProfileTag, receiver: $receiverProfileTag, '
      'state: $_state, initiatedAt: $initiatedAt, '
      'acknowledgedAt: $_acknowledgedAt, revertedAt: $_revertedAt, '
      'revertReason: $_revertReason)';
}
