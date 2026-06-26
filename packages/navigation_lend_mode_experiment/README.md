# navigation_lend_mode_experiment

A pure-Dart state machine for an aviation-style explicit navigation handoff — transfer
of safety-threshold authority from one driver to another on the same device for one trip
("I have control / you have control"), requiring an active acknowledgement before
authority moves.

## Install

This package is explore-phase and is **not published to pub.dev** (`publish_to: none`),
so `dart pub add` will not resolve it. Use a path (or git) dependency:

```yaml
# pubspec.yaml
dependencies:
  navigation_lend_mode_experiment:
    path: ../packages/navigation_lend_mode_experiment   # or a git: ref
```

```sh
dart pub get
```

No peer deps (pure Dart, no Flutter).

## Quick start

```dart
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
```

Run it with `dart run example/lend_mode_example.dart`. Real output:

```
state -> initiated
state -> awaitingAck
state -> active
authority now -> bob
active profile: bob
state -> reverted
authority now -> alice
```

**What you get back:** a `LendModeSession` that walks the full handoff lifecycle
(lender → acknowledged receiver → revert back to lender) with observer callbacks on every
state change, and `LendModeException` on any illegal transition or empty acknowledgement.

---

## Background & provenance

**EXPLORE-PHASE — DO NOT PUBLISH. NOT FOR PRODUCTION USE.**

Aviation-style explicit handoff for navigation safety profile transfer between drivers
on the same device for a single trip. Receiving driver MUST actively acknowledge
responsibility transfer.

### Aspiration

When one driver lends a phone running snow-zone navigation to another driver for a
single trip, the receiving driver becomes the operator of safety-threshold-driven
alerts. A silent profile-switch toggle is insufficient: the receiving driver must
actively state "I am the driver for this trip; I understand the threshold defaults
change." Aviation crews resolve this with the verbal protocol "I have control / you
have control" and an explicit acknowledgement before authority transfers. This
package is a reference implementation of that discipline for the navigation
safety-threshold case.

### What this is

Interface and state-machine reference implementation for lend-mode handoff with an
accept-of-responsibility prompt. Aviation discipline: "I have control / you have
control." Pure Dart; no UI; no Flutter dependency; no dependency on any other
package in this monorepo (the caller passes profile tags as opaque strings).

### What this is NOT

A published package. A user-facing UI. A profile-switching toggle. A persistence
layer. A scheduler.

### Status

Explore-phase per the project's Aspiration Gate. API may change.
Never published to pub.dev. Imported only inside the monorepo, by callers that
have read this README and KNOWN_LIMITATIONS.md.
