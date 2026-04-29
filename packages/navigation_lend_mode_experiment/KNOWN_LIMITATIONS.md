# Known Limitations

**EXPLORE-PHASE — DO NOT PUBLISH. NOT FOR PRODUCTION USE.**

This package is in explore-phase per the project's OPS-RULE-046 Aspiration Gate.
The following limitations are intentional at this phase; each is recorded so that
callers know what is and is not provided.

## Out of scope at this phase

- **No UI shipped.** This package provides API and state machine only. The
  acknowledgement prompt is the caller's responsibility; this package only
  validates that a non-empty acknowledgement text was supplied.
- **No persistence.** Sessions exist in memory. Callers that need durability
  (across app restart, across device handoff to a different process) must
  serialize and restore session state themselves.
- **No built-in scheduler for timeout.** A `RevertReason.timeout` value exists
  for callers to record, but this package does not run timers. Callers
  decide when to invoke `revert(reason: RevertReason.timeout)`.
- **No profile validation.** Profile tags are opaque strings. This package does
  not check whether a tag corresponds to a known threshold profile in any
  other package; that check belongs to the caller.
- **No multi-device session.** A session is a single-device construct. Lending
  across two phones is out of scope.

## API stability

API may change without notice. Treat every minor-version bump as potentially
breaking. Pin exact versions if depended upon inside the monorepo.

## D4 — equal-dignity scope

The lender-receiver pair is symmetric in this API. The lender selector in any
caller-side UI must offer all profile tags equally; novice-lends-to-experienced
is a first-class case, not just experienced-lends-to-novice. This package does
not enforce that property, but documents it as a binding constraint on callers.
