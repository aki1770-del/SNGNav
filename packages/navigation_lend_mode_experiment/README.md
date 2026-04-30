# navigation_lend_mode_experiment

> **EXPLORE-PHASE — DO NOT PUBLISH. NOT FOR PRODUCTION USE.**
>
> This package is an explore-phase experiment. It is not on pub.dev, will
> not be published, and its API may change or disappear without notice.
> Do not depend on it from any shipping product.

## Aspiration (verbatim from scoping-doc)

> *"When a phone running an SNGNav-class app is lent from one driver to
> another for a single trip, the navigation safety profile must not change
> without an explicit, aviation-style acknowledgement from the receiving
> driver, so that the safer threshold defaults of the receiver's actual
> driver-class are bound to the trip by an act of conscious
> responsibility-transfer rather than an implicit profile toggle."*

## Why aviation-style?

Aviation handoff between pilot-flying and pilot-monitoring is verbal,
explicit, and acknowledged. "You have the controls." "I have the
controls." Both crew agree, on the record, who is responsible. This
package models that contract for navigation-app lend events, where the
"controls" being transferred are the safety-threshold profile that
governs alert density, hazard severity, and intervention timing.

## Severity-not-profile (D4 invariant)

The lender's selector offers ALL six driver-class profiles equally.
A novice lending the phone to an experienced driver is a first-class
case, not an edge case. The receiver's profile is bound by the
receiver's actual driver-class, not by who happens to own the phone.

## Status

- A1.1-clean (no production claims; no driver-safety claims; no
  efficacy claims; explore-phase banner present).
- API surface: state machine + observer protocol only. No UI.
- See `KNOWN_LIMITATIONS.md` for what is deliberately out of scope.

## License

Same as parent SNGNav workspace.
