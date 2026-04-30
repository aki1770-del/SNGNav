# Known Limitations

> **EXPLORE-PHASE — DO NOT PUBLISH. NOT FOR PRODUCTION USE.**
>
> This document is an honest declaration of what this package does NOT
> do, so that no caller is misled by what it does. A1.1-clean: no
> over-claiming, no production-readiness implication.

## Out of scope (deliberate)

- **No UI shipped.** This package is API only: state machine plus
  observer protocol. The lender-selector UI, the receiver-ack screen,
  the readback affordance, and any visual / haptic feedback are entirely
  the caller's responsibility.

- **No persistence.** [`LendModeSession`] is in-memory. It does not
  survive app restart or process kill. If the trip needs to span a
  restart, the caller must persist `lenderProfileTag`,
  `receiverProfileTag`, `initiatedAt`, current `state`, and
  (if applicable) `acknowledgedAt` / `revertedAt` / `revertReason`, then
  rehydrate by replaying the state-machine transitions.

- **No timeout scheduler.** `RevertReason.timeout` exists as a vocabulary
  for the caller, not as a built-in timer. The caller decides what
  "no ack within N seconds" means and invokes `revert(reason: timeout)`
  itself. The aviation analogue: the cockpit clock is not in this box.

- **No driver-class enum.** `lenderProfileTag` and `receiverProfileTag`
  are strings. The package deliberately does not depend on
  `navigation_safety_core::DriverProfile` so it can be exercised in
  isolation. Callers that want type-safety should wrap.

- **No telemetry hooks beyond observer.** If you need analytics, log
  through the observer; this package does not phone home.

## API stability

The API may change at any time without deprecation. Pin to a specific
git SHA if you need stability for a spike.

## What this package deliberately DOES NOT claim

- It does NOT claim to make navigation safer.
- It does NOT claim to satisfy any regulatory requirement.
- It does NOT claim aviation-grade reliability.
- It does NOT claim to have been validated against driver behaviour.

It claims only: the state machine matches the aviation-handoff
discipline expressed in the scoping-doc aspiration, and the API surface
makes implicit profile toggles structurally impossible at the call site.
