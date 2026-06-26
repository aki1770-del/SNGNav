import 'package:navigation_lend_mode_experiment/navigation_lend_mode_experiment.dart';

class _Log implements LendModeSessionObserver {
  @override
  void onStateChanged(LendModeState s) => print('state -> ${s.name}');
  @override
  void onActiveProfileChanged(String tag) => print('authority now -> $tag');
  @override
  void onError(LendModeException e) => print('error: ${e.message}');
}

void main() {
  final session = LendModeSession(
    lenderProfileTag: 'alice',
    receiverProfileTag: 'bob',
    observer: _Log(),
  );
  session.initiate();              // idle -> initiated
  session.presentAcknowledgement(); // show "I have control" prompt
  session.acknowledge('I am the driver for this trip');
  print('active profile: ${session.activeProfileTag}'); // bob bears authority
  session.revert(reason: RevertReason.tripEnded);        // authority back to alice
}
