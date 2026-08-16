# condition_aggregator — SEooC assumptions of use

**Package**: `condition_aggregator`
**Applies from**: 0.0.10
**Form**: ISO 26262 Part 10 Safety-Element-out-of-Context — the structurally
honest form for a component **without an item**.
**Author**: FSE (functional-safety-engineer), 2026-08-16
**Status**: PRODUCER artifact. **Not self-audited.** Submitted for independent
audit to AAA + DIA; both returned 2026-08-16 and their findings are applied
below. Attaches to `SAFETY_BOUNDARY.md`; replaces nothing in it.

> *This line read "independently audited" while no audit had yet happened.
> **AAA named it as the certification-adjacent overclaim its charter forbids** —
> on an ISO-26262-Part-10-shaped document an integrator reads that as assurance
> that existed. Corrected same-day on the finding. The sibling
> `SOTIF_INSUFFICIENCIES.md` said "Not self-audited" and was right.*

## What an SEooC statement is, and why this package needs one

This package has **no item, no vehicle, no actuator, and no ASIL.** It cannot
perform your hazard analysis and does not pretend to. What it can do is state,
precisely, **the assumptions you would otherwise have to guess** — so that when
you do perform your analysis, the part of it that rests on us rests on something
written down rather than on inference from a doc comment.

An assumption you inherit without being told is the failure mode this file
exists to prevent. Every row below is a thing that, if you assumed the opposite,
would put a wrong sentence in front of a driver.

---

## AoU-CA-001 — You own the hazard analysis; we own the honesty of the input

**Assumption**: the integrator performs the vehicle-level hazard analysis and
holds all control authority. This package delivers **advisory information only**
and never actuates, brakes, steers, routes, or suppresses.

**If violated**: a control decision taken directly on `advisories` inherits a QM
component into a rated path. Nothing in this package is rated.

---

## AoU-CA-002 — An empty advisory list is not an all-clear. Gate on the predicate.

**Assumption**: you never render "no advisory in force", "clear", "安全",
"問題なし" or any positive-calm surface from `advisories.isEmpty` alone. You gate
it on `canAssertNoAdvisory`, or use `fold` / `AdvisoryLookup`, which will not let
you skip the case.

**If violated**: total feed outage, coverage gap and frozen feed all render as a
clear road. This is the package's oldest and most consequential assumption.

---

## AoU-CA-003 — `canAssertNoAdvisory` means "complete AND current", from 0.0.10

**Assumption**: you read the predicate as *"every source answered, and no source
reported its own document stale."*

**Changed in 0.0.10.** Through 0.0.9 the predicate was defined over
**reachability only**, and a publisher whose document had stopped being written
satisfied it — measured live on 2026-08-16 at 81.8 days (SOTIF-CA-001). From
0.0.10 a source that reports itself stale makes the predicate `false`, and that
propagates to `fold`, `toLookup` and `requireCompleteLookup` from the single
predicate.

**Behavioural consequence for you**: if you use an adapter that opts into
freshness reporting, a previously-`complete` lookup can now be `partial`. That
is the fix, not a regression — but it is a behaviour change and you are being
told plainly rather than left to find it. **No adapter opted in as of
2026-08-16**, so this is inert until one does.

---

## AoU-CA-004 — ⚑ THE ONE THAT COSTS YOU: freshness is opt-in, and nobody has opted in

**Assumption**: you do **not** read an empty `staleSources` as proof that your
sources are current.

Empty means *"no source reported itself stale"*, and that includes *"no source
is capable of reporting."* Freshness reporting requires the adapter to implement
`AdvisoryFeedFreshnessReporting`. **As of 2026-08-16, zero of the five adapter
packages implementing `AdvisoryProvider` do** — `condition_aggregator_jma`,
`condition_aggregator_nws`, `condition_aggregator_met_norway`,
`condition_aggregator_digitraffic`, `condition_aggregator_owm_road_risk`.

*(Corrected 2026-08-16 on DIA's audit finding: an earlier draft of this row said
"six" and counted `driving_weather`, which **consumes** this interface but does
not implement `AdvisoryProvider`. The error overstated unfixed exposure — the
safe direction — but it sat in a document integrators quote, so it is corrected
here and the correction is named rather than silently applied.)*

**So: the guard added in 0.0.10 is armed and unfed.** Against the adapters that
exist today it changes nothing, and a frozen feed still satisfies
`canAssertNoAdvisory` through every one of them.

**Two rosters, because they are different questions and conflating them was an
error in the first draft:**

* **Who CAN report freshness** — the **five** packages implementing
  `AdvisoryProvider`: `condition_aggregator_jma`, `_nws`, `_met_norway`,
  `_digitraffic`, `_owm_road_risk`. **Zero do.**
* **Who is AFFECTED by this release** — **seven** direct consumers: those five
  plus `driving_weather` and `drive_situation_fusion`, which consume the
  interface without implementing the provider contract. *`drive_situation_fusion`
  was missing from this row's first draft and from every verification claim
  FSE made; AAA found it and independently confirmed all seven analyze clean
  and pass their tests unchanged.*

**⚑ The sharpest fact, and it is AAA's catch, not FSE's:**
`condition_aggregator_jma` **already holds the measurement.** It parses
`reportDatetime`, carries `kJmaDefaultStaleFeedThreshold` and
`buildStaleFeedNotice`, and knows the Niigata document is 81.9 days old — and
it does not implement `AdvisoryFeedFreshnessReporting`. **The adapter holding
the plug is not plugged in, in HER mother's prefecture.** One edit closes it.
Routed to **NDI** (adapter-family steward) and **CT** (build-track lead).

**What you must do if feed-freshness matters to you** — and on a winter-driving
surface it does:

1. Prefer an adapter that implements `AdvisoryFeedFreshnessReporting`, or
2. Wrap the adapter yourself — the interface is public and small — reading the
   publisher's own document timestamp and reporting it, or
3. Measure freshness out of band, as this unit's own winter instrument does,
   and treat the result as an input to your own gate.

We chose to state this rather than default unmeasured sources to "stale", which
would manufacture doubt on a clear day, or to "fresh", which is the defect being
fixed. **Neither default is honest, so there is no default and there is this
paragraph instead.**

---

## AoU-CA-005 — The staleness threshold is the adapter's, and it is a domain judgement

**Assumption**: you understand that "stale" is defined by the adapter against
its own publisher's cadence, not by this package. A JMA warning document and an
NWS CAP feed have different natural update rates; a single interface-wide
constant would be wrong for both.

**Consequence**: two adapters may disagree about whether the same elapsed time is
stale, correctly. If you need one policy, impose it in your wrapper.

---

## AoU-CA-006 — Coverage is not asserted (SOTIF-CA-002, OPEN)

**Assumption**: you know which geographic areas each configured adapter actually
catalogues, because **this interface cannot tell you.** A point outside an
adapter's catalogue produces a successful, empty answer that is arithmetically
identical to a measured calm, and `canAssertNoAdvisory` will be `true` for a
point no source ever looked at.

**This is unmitigated.** It is a named open row, not an oversight. Measured
2026-08-16 at Maebashi (42251) and Karuizawa (48331), both of which rendered as
clear roads outside the JMA adapter's six-prefecture catalogue.

---

## AoU-CA-009 — ⚑ Completeness does not survive into `compound_failure_advisor` (SOTIF-CA-004, OPEN)

**Assumption**: if you compose this interface with `compound_failure_advisor`,
you understand that **everything AoU-CA-003 establishes is discarded at that
seam.** That package does not receive `AdvisoryAggregateResult` at all — its
input is a bare `AdvisoryLevel?`, and zero references to `canAssertNoAdvisory`,
`AdvisoryLookup`, `staleSources` or `AdvisoryAggregateResult` exist in
`compound_failure_advisor/lib` or `driving_weather/lib`.

**Worse than dropped — inverted.** `drive_situation.dart` declares
**`null` = no advisory in force**, a positive assertion of calm, while four
fields above it `visibilityMeters` declares **`null` = NO real reading in hand…
never coerced to "clear"**. The same sentinel, opposite semantics, adjacent
fields of one class. `in_drive_advisor.dart:294` then folds them:
`case null: case AdvisoryLevel.minor: return 0;`

**Consequence**: not-knowing and knowing-it-is-mild are the same fact to that
advisor. There is no way to express "advisory state unknown" — the input state
does not exist. Reproduced RED 2026-08-16.

**Status: OPEN**, routed to CT + SDE/FDD. Not fixed here: it changes a
published, HER-facing advisor's API, which is not an interface seat's
unilateral edit.

---

## AoU-CA-007 — Snapshot semantics; you own refresh cadence

**Assumption**: each query is a point-in-time snapshot. The aggregator holds no
cache, no stream, no polling and no retry; freshness reports describe the
**most recent** fetch on that adapter instance. An adapter shared across
concurrent queries is contracted to key its report per query or report `null`.

**If violated**: you may attribute one query's freshness to another's data.

---

## AoU-CA-008 — A hazard seen is a hazard real

**Assumption**: you act on `advisories` even when the lookup was incomplete.
Positive evidence fires on partial knowledge; only the *negative* conclusion
requires whole knowledge. Suppressing a seen hazard because the lookup was
partial inverts the asymmetry the package is built on.

---

## Verification status of these assumptions

| AoU | Enforced by code? | Where |
|---|---|---|
| CA-001 | No — stated only. Architectural, unenforceable at this layer. | — |
| CA-002 | Partially — `fold` / sealed `AdvisoryLookup` make skipping it hard; `advisories.isEmpty` remains reachable. | `advisory_lookup.dart` |
| CA-003 | **Yes** | `canAssertNoAdvisory`; `test/frozen_feed_test.dart` (8 tests, proven RED then GREEN) |
| CA-004 | **No — this is the residual.** Stated, not enforced. | `test/frozen_feed_test.dart` group "no cry-wolf" pins the deliberate no-op |
| CA-005 | No — delegated by design. | `AdvisoryFeedStaleness` doc |
| CA-006 | **No — OPEN**, SOTIF-CA-002. | — |
| CA-007 | No — contract, not mechanism. | `AdvisoryFeedFreshnessReporting.feedStaleness` doc |
| CA-008 | No — inverting it is the integrator's choice to make wrongly. | — |
| CA-009 | **No — OPEN**, SOTIF-CA-004, and it is the row standing between CA-003 and the driver. | reproduction in `SOTIF_INSUFFICIENCIES.md` |

**Three of nine are enforced or partially enforced. Six are stated.** That
ratio is the honest state of this component and is written here rather than
smoothed, because an assumptions-of-use document whose rows all claim
enforcement is the failure mode it exists to prevent.

**And two of the unenforced rows — CA-004 and CA-009 — sit between the CA-003
fix and any real driver.** No adapter feeds the guard, and the advisor could not
receive it if one did. **This release therefore changes nothing HER would
experience**, and that sentence belongs here rather than in a footnote.

## Audit

FSE **produces**; it is never its own auditor (FSE bylaws C1). Submitted to
**AAA** (auditor-veto on the QM/SEooC boundary) and **DIA** (integrity /
propagation). Verdicts ride with the delivery record.
