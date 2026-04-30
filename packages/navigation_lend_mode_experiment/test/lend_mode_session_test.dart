// EXPLORE-PHASE — DO NOT PUBLISH. NOT FOR PRODUCTION USE.

import 'package:navigation_lend_mode_experiment/navigation_lend_mode_experiment.dart';
import 'package:test/test.dart';

LendModeSession _fresh({
  String lender = 'novice',
  String receiver = 'experienced',
}) =>
    LendModeSession(
      lenderProfileTag: lender,
      receiverProfileTag: receiver,
      initiatedAt: DateTime(2026, 4, 30, 8, 0),
    );

void main() {
  group('initial state', () {
    test('starts in idle', () {
      expect(_fresh().state, LendModeState.idle);
    });

    test('activeProfileTag in idle returns lender', () {
      final s = _fresh();
      expect(s.activeProfileTag, 'novice');
    });

    test('acknowledgedAt and revertedAt start null', () {
      final s = _fresh();
      expect(s.acknowledgedAt, isNull);
      expect(s.revertedAt, isNull);
      expect(s.revertReason, isNull);
    });
  });

  group('initiate()', () {
    test('idle -> awaitingAck', () {
      final s = _fresh();
      s.initiate();
      expect(s.state, LendModeState.awaitingAck);
    });

    test('initiate() twice throws StateError', () {
      final s = _fresh()..initiate();
      expect(s.initiate, throwsStateError);
    });

    test('initiate() after active throws StateError', () {
      final s = _fresh()
        ..initiate()
        ..acknowledge(explicitAckText: 'I have the controls.');
      expect(s.initiate, throwsStateError);
    });

    test('initiate() after reverted throws StateError', () {
      final s = _fresh()
        ..initiate()
        ..acknowledge(explicitAckText: 'I have the controls.')
        ..revert(reason: RevertReason.tripEnded);
      expect(s.initiate, throwsStateError);
    });
  });

  group('acknowledge()', () {
    test('awaitingAck + valid text -> active', () {
      final s = _fresh()..initiate();
      s.acknowledge(explicitAckText: 'I have the controls.');
      expect(s.state, LendModeState.active);
      expect(s.acknowledgedAt, isNotNull);
    });

    test('activeProfileTag flips to receiver after ack', () {
      final s = _fresh()..initiate();
      s.acknowledge(explicitAckText: 'Roger, I have it.');
      expect(s.activeProfileTag, 'experienced');
    });

    test('empty ack text -> ArgumentError', () {
      final s = _fresh()..initiate();
      expect(
        () => s.acknowledge(explicitAckText: ''),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('whitespace-only ack text -> ArgumentError', () {
      final s = _fresh()..initiate();
      expect(
        () => s.acknowledge(explicitAckText: '   \t\n  '),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('acknowledge() in idle -> StateError', () {
      final s = _fresh();
      expect(
        () => s.acknowledge(explicitAckText: 'Roger.'),
        throwsStateError,
      );
    });

    test('acknowledge() twice -> StateError', () {
      final s = _fresh()
        ..initiate()
        ..acknowledge(explicitAckText: 'Roger.');
      expect(
        () => s.acknowledge(explicitAckText: 'Roger again.'),
        throwsStateError,
      );
    });

    test('acknowledge() after revert -> StateError', () {
      final s = _fresh()
        ..initiate()
        ..acknowledge(explicitAckText: 'Roger.')
        ..revert(reason: RevertReason.explicitRevert);
      expect(
        () => s.acknowledge(explicitAckText: 'Roger.'),
        throwsStateError,
      );
    });
  });

  group('revert()', () {
    test('active -> reverted (tripEnded)', () {
      final s = _fresh()
        ..initiate()
        ..acknowledge(explicitAckText: 'Roger.');
      s.revert(reason: RevertReason.tripEnded);
      expect(s.state, LendModeState.reverted);
      expect(s.revertReason, RevertReason.tripEnded);
      expect(s.revertedAt, isNotNull);
    });

    test('active -> reverted (explicitRevert)', () {
      final s = _fresh()
        ..initiate()
        ..acknowledge(explicitAckText: 'Roger.');
      s.revert(reason: RevertReason.explicitRevert);
      expect(s.revertReason, RevertReason.explicitRevert);
    });

    test('active -> reverted (timeout)', () {
      final s = _fresh()
        ..initiate()
        ..acknowledge(explicitAckText: 'Roger.');
      s.revert(reason: RevertReason.timeout);
      expect(s.revertReason, RevertReason.timeout);
    });

    test('revert() in idle -> StateError', () {
      expect(
        () => _fresh().revert(reason: RevertReason.tripEnded),
        throwsStateError,
      );
    });

    test('revert() in awaitingAck -> StateError', () {
      final s = _fresh()..initiate();
      expect(
        () => s.revert(reason: RevertReason.tripEnded),
        throwsStateError,
      );
    });

    test('revert() twice -> StateError', () {
      final s = _fresh()
        ..initiate()
        ..acknowledge(explicitAckText: 'Roger.')
        ..revert(reason: RevertReason.tripEnded);
      expect(
        () => s.revert(reason: RevertReason.explicitRevert),
        throwsStateError,
      );
    });

    test('reverted activeProfileTag returns lender (not receiver)', () {
      final s = _fresh()
        ..initiate()
        ..acknowledge(explicitAckText: 'Roger.')
        ..revert(reason: RevertReason.tripEnded);
      expect(s.activeProfileTag, 'novice');
    });
  });

  group('severity-not-profile (D4) — direction-agnostic', () {
    test('experienced lends to novice — first-class', () {
      final s = _fresh(lender: 'experienced', receiver: 'novice')
        ..initiate()
        ..acknowledge(explicitAckText: 'I have it.');
      expect(s.activeProfileTag, 'novice');
    });

    test('novice lends to experienced — first-class', () {
      final s = _fresh(lender: 'novice', receiver: 'experienced')
        ..initiate()
        ..acknowledge(explicitAckText: 'I have it.');
      expect(s.activeProfileTag, 'experienced');
    });
  });

  group('equality / hashCode / toString', () {
    test('two freshly-constructed identical sessions are equal', () {
      final a = _fresh();
      final b = _fresh();
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('different state -> not equal', () {
      final a = _fresh();
      final b = _fresh()..initiate();
      expect(a, isNot(equals(b)));
    });

    test('toString contains state and profiles', () {
      final s = _fresh();
      final str = s.toString();
      expect(str, contains('novice'));
      expect(str, contains('experienced'));
      expect(str, contains('idle'));
    });
  });
}
