// EXPLORE-PHASE — DO NOT PUBLISH. NOT FOR PRODUCTION USE.

import 'package:navigation_lend_mode_experiment/navigation_lend_mode_experiment.dart';
import 'package:test/test.dart';

class _RecordingObserver implements LendModeSessionObserver {
  final List<({LendModeState from, LendModeState to})> stateChanges = [];
  final List<({String from, String to})> profileChanges = [];
  final List<LendModeException> errors = [];

  @override
  void onStateChanged(
    LendModeSession session,
    LendModeState from,
    LendModeState to,
  ) {
    stateChanges.add((from: from, to: to));
  }

  @override
  void onActiveProfileChanged(
    LendModeSession session,
    String fromProfileTag,
    String toProfileTag,
  ) {
    profileChanges.add((from: fromProfileTag, to: toProfileTag));
  }

  @override
  void onError(LendModeSession session, LendModeException error) {
    errors.add(error);
  }
}

/// Helper that drives a session through transitions and dispatches to a
/// list of observers. The package does not retain observer refs by design;
/// this helper exercises the protocol contract.
class _ObservedSession {
  _ObservedSession({
    required String lender,
    required String receiver,
  }) : _session = LendModeSession(
          lenderProfileTag: lender,
          receiverProfileTag: receiver,
          initiatedAt: DateTime(2026, 4, 30, 8, 0),
        );

  final LendModeSession _session;
  final List<LendModeSessionObserver> _observers = [];

  LendModeSession get session => _session;

  void attach(LendModeSessionObserver o) => _observers.add(o);
  bool detach(LendModeSessionObserver o) => _observers.remove(o);

  void initiate() {
    final fromState = _session.state;
    final fromProfile = _session.activeProfileTag;
    try {
      _session.initiate();
    } on StateError catch (e) {
      _emitError(LendModeException(
        message: 'initiate() rejected',
        attemptedFromState: fromState,
        cause: e,
      ));
      return;
    }
    _emitState(fromState, _session.state);
    _maybeEmitProfile(fromProfile);
  }

  void acknowledge(String text) {
    final fromState = _session.state;
    final fromProfile = _session.activeProfileTag;
    try {
      _session.acknowledge(explicitAckText: text);
    } on StateError catch (e) {
      _emitError(LendModeException(
        message: 'acknowledge() rejected',
        attemptedFromState: fromState,
        cause: e,
      ));
      return;
    } on ArgumentError catch (e) {
      _emitError(LendModeException(
        message: 'acknowledge() ack-text invalid',
        attemptedFromState: fromState,
        cause: e,
      ));
      return;
    }
    _emitState(fromState, _session.state);
    _maybeEmitProfile(fromProfile);
  }

  void revert(RevertReason r) {
    final fromState = _session.state;
    final fromProfile = _session.activeProfileTag;
    try {
      _session.revert(reason: r);
    } on StateError catch (e) {
      _emitError(LendModeException(
        message: 'revert() rejected',
        attemptedFromState: fromState,
        cause: e,
      ));
      return;
    }
    _emitState(fromState, _session.state);
    _maybeEmitProfile(fromProfile);
  }

  void _emitState(LendModeState from, LendModeState to) {
    if (from == to) return;
    for (final o in _observers) {
      o.onStateChanged(_session, from, to);
    }
  }

  void _maybeEmitProfile(String fromProfile) {
    final to = _session.activeProfileTag;
    if (fromProfile == to) return;
    for (final o in _observers) {
      o.onActiveProfileChanged(_session, fromProfile, to);
    }
  }

  void _emitError(LendModeException e) {
    for (final o in _observers) {
      o.onError(_session, e);
    }
  }
}

void main() {
  group('LendModeSessionObserver', () {
    test('onStateChanged fires per transition', () {
      final obs = _RecordingObserver();
      final s = _ObservedSession(lender: 'novice', receiver: 'experienced')
        ..attach(obs)
        ..initiate()
        ..acknowledge('Roger.')
        ..revert(RevertReason.tripEnded);
      expect(obs.stateChanges.length, 3);
      expect(obs.stateChanges[0].to, LendModeState.awaitingAck);
      expect(obs.stateChanges[1].to, LendModeState.active);
      expect(obs.stateChanges[2].to, LendModeState.reverted);
      expect(s.session.state, LendModeState.reverted);
    });

    test('onActiveProfileChanged fires only on profile flip', () {
      final obs = _RecordingObserver();
      _ObservedSession(lender: 'novice', receiver: 'experienced')
        ..attach(obs)
        ..initiate()
        ..acknowledge('Roger.')
        ..revert(RevertReason.tripEnded);
      // Two flips: lender->receiver on ack; receiver->lender on revert.
      expect(obs.profileChanges.length, 2);
      expect(obs.profileChanges[0].from, 'novice');
      expect(obs.profileChanges[0].to, 'experienced');
      expect(obs.profileChanges[1].from, 'experienced');
      expect(obs.profileChanges[1].to, 'novice');
    });

    test('onActiveProfileChanged does not fire on idle->awaitingAck', () {
      final obs = _RecordingObserver();
      _ObservedSession(lender: 'novice', receiver: 'experienced')
        ..attach(obs)
        ..initiate();
      expect(obs.profileChanges, isEmpty);
    });

    test('onError fires on illegal initiate (already active)', () {
      final obs = _RecordingObserver();
      _ObservedSession(lender: 'novice', receiver: 'experienced')
        ..attach(obs)
        ..initiate()
        ..acknowledge('Roger.')
        ..initiate();
      expect(obs.errors, hasLength(1));
      expect(obs.errors.first.attemptedFromState, LendModeState.active);
    });

    test('onError fires on empty ack text', () {
      final obs = _RecordingObserver();
      _ObservedSession(lender: 'novice', receiver: 'experienced')
        ..attach(obs)
        ..initiate()
        ..acknowledge('');
      expect(obs.errors, hasLength(1));
      expect(obs.errors.first.message, contains('ack-text invalid'));
    });

    test('onError fires on revert from idle', () {
      final obs = _RecordingObserver();
      _ObservedSession(lender: 'novice', receiver: 'experienced')
        ..attach(obs)
        ..revert(RevertReason.tripEnded);
      expect(obs.errors, hasLength(1));
      expect(obs.errors.first.attemptedFromState, LendModeState.idle);
    });

    test('multiple observers all receive events', () {
      final a = _RecordingObserver();
      final b = _RecordingObserver();
      _ObservedSession(lender: 'novice', receiver: 'experienced')
        ..attach(a)
        ..attach(b)
        ..initiate()
        ..acknowledge('Roger.');
      expect(a.stateChanges.length, 2);
      expect(b.stateChanges.length, 2);
    });

    test('detach() stops further notifications', () {
      final obs = _RecordingObserver();
      final s = _ObservedSession(lender: 'novice', receiver: 'experienced')
        ..attach(obs)
        ..initiate();
      expect(obs.stateChanges, hasLength(1));
      expect(s.detach(obs), isTrue);
      s.acknowledge('Roger.');
      expect(obs.stateChanges, hasLength(1));
    });

    test('detach() of non-attached observer returns false', () {
      final obs = _RecordingObserver();
      final s = _ObservedSession(lender: 'novice', receiver: 'experienced');
      expect(s.detach(obs), isFalse);
    });

    test('LendModeException toString carries state', () {
      final e = LendModeException(
        message: 'test',
        attemptedFromState: LendModeState.idle,
      );
      expect(e.toString(), contains('idle'));
      expect(e.toString(), contains('test'));
    });

    test('LendModeException carries cause when provided', () {
      final cause = StateError('inner');
      final e = LendModeException(
        message: 'test',
        attemptedFromState: LendModeState.active,
        cause: cause,
      );
      expect(e.cause, same(cause));
      expect(e.toString(), contains('cause'));
    });

    test('observer stays consistent across full happy-path lifecycle', () {
      final obs = _RecordingObserver();
      _ObservedSession(lender: 'experienced', receiver: 'novice')
        ..attach(obs)
        ..initiate()
        ..acknowledge('I have it.')
        ..revert(RevertReason.explicitRevert);
      expect(obs.errors, isEmpty);
      expect(obs.stateChanges, hasLength(3));
      expect(obs.profileChanges, hasLength(2));
    });
  });
}
