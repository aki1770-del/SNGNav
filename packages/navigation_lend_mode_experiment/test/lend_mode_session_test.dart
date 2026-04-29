import 'package:navigation_lend_mode_experiment/navigation_lend_mode_experiment.dart';
import 'package:test/test.dart';

class _RecordingObserver implements LendModeSessionObserver {
  final List<LendModeState> states = [];
  final List<String> activeTags = [];
  final List<LendModeException> errors = [];

  @override
  void onStateChanged(LendModeState newState) => states.add(newState);

  @override
  void onActiveProfileChanged(String newActiveProfileTag) =>
      activeTags.add(newActiveProfileTag);

  @override
  void onError(LendModeException error) => errors.add(error);
}

LendModeSession _newSession({LendModeSessionObserver? observer}) =>
    LendModeSession(
      lenderProfileTag: 'lender',
      receiverProfileTag: 'receiver',
      observer: observer,
    );

void main() {
  group('construction', () {
    test('initial state is idle', () {
      expect(_newSession().state, LendModeState.idle);
    });

    test('active profile tag starts as lender', () {
      expect(_newSession().activeProfileTag, 'lender');
    });

    test('revert reason starts as null', () {
      expect(_newSession().revertReason, isNull);
    });

    test('isTerminal is false at construction', () {
      expect(_newSession().isTerminal, isFalse);
    });

    test('lender and receiver tags exposed', () {
      final s = _newSession();
      expect(s.lenderProfileTag, 'lender');
      expect(s.receiverProfileTag, 'receiver');
    });

    test('throws when lender tag is empty', () {
      expect(
        () => LendModeSession(
          lenderProfileTag: '',
          receiverProfileTag: 'receiver',
        ),
        throwsA(isA<LendModeException>()),
      );
    });

    test('throws when receiver tag is empty', () {
      expect(
        () => LendModeSession(
          lenderProfileTag: 'lender',
          receiverProfileTag: '',
        ),
        throwsA(isA<LendModeException>()),
      );
    });

    test('throws when lender == receiver', () {
      expect(
        () => LendModeSession(
          lenderProfileTag: 'same',
          receiverProfileTag: 'same',
        ),
        throwsA(isA<LendModeException>()),
      );
    });

    test('observer notified on construction error (lender == receiver)', () {
      final obs = _RecordingObserver();
      expect(
        () => LendModeSession(
          lenderProfileTag: 'same',
          receiverProfileTag: 'same',
          observer: obs,
        ),
        throwsA(isA<LendModeException>()),
      );
      expect(obs.errors, hasLength(1));
    });
  });

  group('happy-path transitions', () {
    test('idle -> initiated via initiate()', () {
      final s = _newSession();
      s.initiate();
      expect(s.state, LendModeState.initiated);
    });

    test('initiated -> awaitingAck via presentAcknowledgement()', () {
      final s = _newSession()..initiate();
      s.presentAcknowledgement();
      expect(s.state, LendModeState.awaitingAck);
    });

    test('awaitingAck -> active via acknowledge()', () {
      final s = _newSession()
        ..initiate()
        ..presentAcknowledgement();
      s.acknowledge('I have control');
      expect(s.state, LendModeState.active);
    });

    test('active profile tag becomes receiver on active', () {
      final s = _newSession()
        ..initiate()
        ..presentAcknowledgement()
        ..acknowledge('I have control');
      expect(s.activeProfileTag, 'receiver');
    });

    test('active -> reverted via revert()', () {
      final s = _newSession()
        ..initiate()
        ..presentAcknowledgement()
        ..acknowledge('I have control');
      s.revert(reason: RevertReason.tripEnded);
      expect(s.state, LendModeState.reverted);
    });

    test('revert restores lender as active profile', () {
      final s = _newSession()
        ..initiate()
        ..presentAcknowledgement()
        ..acknowledge('I have control')
        ..revert(reason: RevertReason.tripEnded);
      expect(s.activeProfileTag, 'lender');
    });

    test('revert records reason', () {
      final s = _newSession()
        ..initiate()
        ..presentAcknowledgement()
        ..acknowledge('I have control')
        ..revert(reason: RevertReason.explicitRevert);
      expect(s.revertReason, RevertReason.explicitRevert);
    });

    test('isTerminal is true after revert', () {
      final s = _newSession()
        ..initiate()
        ..presentAcknowledgement()
        ..acknowledge('I have control')
        ..revert(reason: RevertReason.tripEnded);
      expect(s.isTerminal, isTrue);
    });
  });

  group('cancellation paths (revert before active)', () {
    test('revert legal from initiated', () {
      final s = _newSession()..initiate();
      s.revert(reason: RevertReason.explicitRevert);
      expect(s.state, LendModeState.reverted);
      expect(s.activeProfileTag, 'lender');
      expect(s.revertReason, RevertReason.explicitRevert);
    });

    test('revert legal from awaitingAck', () {
      final s = _newSession()
        ..initiate()
        ..presentAcknowledgement();
      s.revert(reason: RevertReason.timeout);
      expect(s.state, LendModeState.reverted);
      expect(s.activeProfileTag, 'lender');
      expect(s.revertReason, RevertReason.timeout);
    });
  });

  group('illegal transitions', () {
    test('initiate throws from initiated', () {
      final s = _newSession()..initiate();
      expect(
        () => s.initiate(),
        throwsA(isA<LendModeException>()),
      );
    });

    test('presentAcknowledgement throws from idle', () {
      final s = _newSession();
      expect(
        () => s.presentAcknowledgement(),
        throwsA(isA<LendModeException>()),
      );
    });

    test('presentAcknowledgement throws from awaitingAck', () {
      final s = _newSession()
        ..initiate()
        ..presentAcknowledgement();
      expect(
        () => s.presentAcknowledgement(),
        throwsA(isA<LendModeException>()),
      );
    });

    test('acknowledge throws from idle', () {
      final s = _newSession();
      expect(
        () => s.acknowledge('x'),
        throwsA(isA<LendModeException>()),
      );
    });

    test('acknowledge throws from initiated', () {
      final s = _newSession()..initiate();
      expect(
        () => s.acknowledge('x'),
        throwsA(isA<LendModeException>()),
      );
    });

    test('acknowledge throws from active', () {
      final s = _newSession()
        ..initiate()
        ..presentAcknowledgement()
        ..acknowledge('x');
      expect(
        () => s.acknowledge('y'),
        throwsA(isA<LendModeException>()),
      );
    });

    test('acknowledge throws on empty text', () {
      final s = _newSession()
        ..initiate()
        ..presentAcknowledgement();
      expect(
        () => s.acknowledge(''),
        throwsA(isA<LendModeException>()),
      );
    });

    test('acknowledge throws on whitespace-only text', () {
      final s = _newSession()
        ..initiate()
        ..presentAcknowledgement();
      expect(
        () => s.acknowledge('   '),
        throwsA(isA<LendModeException>()),
      );
    });

    test('revert throws from idle', () {
      final s = _newSession();
      expect(
        () => s.revert(reason: RevertReason.explicitRevert),
        throwsA(isA<LendModeException>()),
      );
    });

    test('any method throws after reverted (terminal)', () {
      final s = _newSession()
        ..initiate()
        ..revert(reason: RevertReason.explicitRevert);
      expect(
        () => s.initiate(),
        throwsA(isA<LendModeException>()),
      );
      expect(
        () => s.presentAcknowledgement(),
        throwsA(isA<LendModeException>()),
      );
      expect(
        () => s.acknowledge('x'),
        throwsA(isA<LendModeException>()),
      );
      expect(
        () => s.revert(reason: RevertReason.tripEnded),
        throwsA(isA<LendModeException>()),
      );
    });
  });

  group('observer notifications', () {
    test('onStateChanged fires for each transition in happy path', () {
      final obs = _RecordingObserver();
      _newSession(observer: obs)
        ..initiate()
        ..presentAcknowledgement()
        ..acknowledge('x')
        ..revert(reason: RevertReason.tripEnded);
      expect(obs.states, [
        LendModeState.initiated,
        LendModeState.awaitingAck,
        LendModeState.active,
        LendModeState.reverted,
      ]);
    });

    test('onActiveProfileChanged fires exactly twice in happy path', () {
      final obs = _RecordingObserver();
      _newSession(observer: obs)
        ..initiate()
        ..presentAcknowledgement()
        ..acknowledge('x')
        ..revert(reason: RevertReason.tripEnded);
      expect(obs.activeTags, ['receiver', 'lender']);
    });

    test('onActiveProfileChanged does not fire on cancellation from initiated',
        () {
      final obs = _RecordingObserver();
      _newSession(observer: obs)
        ..initiate()
        ..revert(reason: RevertReason.explicitRevert);
      expect(obs.activeTags, isEmpty);
    });

    test('onError fires on illegal transition', () {
      final obs = _RecordingObserver();
      final s = _newSession(observer: obs);
      expect(() => s.acknowledge('x'), throwsA(isA<LendModeException>()));
      expect(obs.errors, hasLength(1));
      expect(obs.errors.single.attemptedFromState, LendModeState.idle);
    });

    test('onError fires on empty acknowledgement', () {
      final obs = _RecordingObserver();
      final s = _newSession(observer: obs)
        ..initiate()
        ..presentAcknowledgement();
      expect(() => s.acknowledge(''), throwsA(isA<LendModeException>()));
      expect(obs.errors, hasLength(1));
    });

    test('exception toString includes attempted state when present', () {
      final s = _newSession();
      try {
        s.acknowledge('x');
        fail('expected throw');
      } on LendModeException catch (e) {
        expect(e.toString(), contains('idle'));
      }
    });
  });

  group('D4 symmetry (KNOWN_LIMITATIONS dignity scope)', () {
    test('novice-lends-to-experienced is a first-class case', () {
      final s = LendModeSession(
        lenderProfileTag: 'noviceUrban',
        receiverProfileTag: 'experiencedRural',
      )
        ..initiate()
        ..presentAcknowledgement()
        ..acknowledge('I have control');
      expect(s.activeProfileTag, 'experiencedRural');
    });

    test('experienced-lends-to-novice is a first-class case', () {
      final s = LendModeSession(
        lenderProfileTag: 'experiencedRural',
        receiverProfileTag: 'noviceUrban',
      )
        ..initiate()
        ..presentAcknowledgement()
        ..acknowledge('I have control');
      expect(s.activeProfileTag, 'noviceUrban');
    });
  });
}
