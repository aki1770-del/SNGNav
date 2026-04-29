# navigation_lend_mode_experiment

**EXPLORE-PHASE — DO NOT PUBLISH. NOT FOR PRODUCTION USE.**

Aviation-style explicit handoff for navigation safety profile transfer between drivers
on the same device for a single trip. Receiving driver MUST actively acknowledge
responsibility transfer.

## Aspiration

When one driver lends a phone running snow-zone navigation to another driver for a
single trip, the receiving driver becomes the operator of safety-threshold-driven
alerts. A silent profile-switch toggle is insufficient: the receiving driver must
actively state "I am the driver for this trip; I understand the threshold defaults
change." Aviation crews resolve this with the verbal protocol "I have control / you
have control" and an explicit acknowledgement before authority transfers. This
package is a reference implementation of that discipline for the navigation
safety-threshold case.

## What this is

Interface and state-machine reference implementation for lend-mode handoff with an
accept-of-responsibility prompt. Aviation discipline: "I have control / you have
control." Pure Dart; no UI; no Flutter dependency; no dependency on any other
package in this monorepo (the caller passes profile tags as opaque strings).

## What this is NOT

A published package. A user-facing UI. A profile-switching toggle. A persistence
layer. A scheduler.

## Status

Explore-phase per the project's OPS-RULE-046 Aspiration Gate. API may change.
Never published to pub.dev. Imported only inside the monorepo, by callers that
have read this README and KNOWN_LIMITATIONS.md.
