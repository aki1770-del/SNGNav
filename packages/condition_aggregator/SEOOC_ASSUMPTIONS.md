# condition_aggregator — SEooC assumptions of use

**Package**: `condition_aggregator`
**Applies from**: 0.0.10
**Form**: ISO 26262 Part 10 Safety-Element-out-of-Context — the structurally
honest form for a component **without an item**.
**Author**: the SNGNav maintainers (functional-safety review), 2026-08-16
**Status**: **Not self-audited.** Submitted for independent review of standards
mapping and of document integrity; both returned 2026-08-16 and their findings
are applied below. Attaches to `SAFETY_BOUNDARY.md`; replaces nothing in it.

> *This line read "independently audited" while no audit had yet happened.
> **The standards review named it a certification-adjacent overclaim** — on an
> ISO-26262-Part-10-shaped document an integrator reads that as assurance that
> existed. Corrected same-day on the finding. The sibling
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
told plainly rather than left to find it. **No adapter had opted in on
2026-08-16.** Measured 2026-09-20: `condition_aggregator_jma` 0.7.0 has, so on
that adapter this is live, not inert.

---

## AoU-CA-004 — ⚑ THE ONE THAT COSTS YOU: freshness is opt-in, and only one adapter has opted in

**Assumption**: you do **not** read an empty `staleSources` as proof that your
sources are current.

Empty means *"no source reported itself stale"*, and that includes *"no source
is capable of reporting."* Freshness reporting requires the adapter to implement
`AdvisoryFeedFreshnessReporting`. **On 2026-08-16, none of the five adapter
packages implementing `AdvisoryProvider` did** — `condition_aggregator_jma`,
`condition_aggregator_nws`, `condition_aggregator_met_norway`,
`condition_aggregator_digitraffic`, `condition_aggregator_owm_road_risk`.

**Measured 2026-09-20, against the latest version of each on pub.dev: one of the
five does.** `condition_aggregator_jma` 0.7.0 (published 2026-08-28) implements
it; it first did so in 0.3.2 (2026-08-16), dropped it in 0.5.0 (2026-08-21) and
restored it in 0.7.0. `condition_aggregator_nws` 0.0.7,
`condition_aggregator_met_norway` 0.0.8, `condition_aggregator_digitraffic`
0.0.8 and `condition_aggregator_owm_road_risk` 0.1.5 do not.

*(Corrected 2026-08-16 on an audit finding: an earlier draft of this row said
"six" and counted `driving_weather`, which **consumes** this interface but does
not implement `AdvisoryProvider`. The error overstated unfixed exposure — the
safe direction — but it sat in a document integrators quote, so it is corrected
here and the correction is named rather than silently applied.)*

**So: the guard added in 0.0.10 is fed through one adapter and unfed through the
other four.** Through the JMA adapter at 0.7.0, a frozen feed makes
`canAssertNoAdvisory` false. Through the other four, a frozen feed still
satisfies it.

**Two rosters, because they are different questions and conflating them was an
error in the first draft:**

* **Who CAN report freshness** — the **five** packages implementing
  `AdvisoryProvider`: `condition_aggregator_jma`, `_nws`, `_met_norway`,
  `_digitraffic`, `_owm_road_risk`. **One does** — `_jma`, from 0.7.0 (measured
  2026-09-20). None did on 2026-08-16.
* **Who was AFFECTED by the 0.0.10 change** (measured 2026-08-16) — **seven**
  direct consumers: those five
  plus `driving_weather` and `drive_situation_fusion`, which consume the
  interface without implementing the provider contract. *`drive_situation_fusion`
  was missing from this row's first draft and from every verification claim
  this file's author made; the review found it and independently confirmed all
  seven analyze clean and pass their tests unchanged.*

**⚑ The sharpest fact on 2026-08-16, and it was found in review, not by this
file's author:** `condition_aggregator_jma` **already held the measurement.** It
parses `reportDatetime`, carries `kJmaDefaultStaleFeedThreshold` and
`buildStaleFeedNotice`, and knew the Niigata document was 81.9 days old — and it
did not implement `AdvisoryFeedFreshnessReporting`. The adapter holding the plug
was not plugged in, in the snow-country prefecture this project is built for.
**Closed since:** 0.3.2 implemented it, 0.5.0 dropped it, and it has been
implemented again from 0.7.0.

**What you must do if feed-freshness matters to you** — and on a winter-driving
surface it does:

1. Prefer an adapter that implements `AdvisoryFeedFreshnessReporting`, or
2. Wrap the adapter yourself — the interface is public and small — reading the
   publisher's own document timestamp and reporting it, or
3. Measure freshness out of band, as this project's own winter monitoring does,
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

**Measured 2026-09-20:** the JMA adapter at 0.7.0 no longer answers an
out-of-catalogue point with an empty list. Without fetching anything it returns
one `minor` notice saying the point is outside that adapter's coverage and that
no warning shown does not mean safe. The gap is now visible in the list, but
nothing from that adapter makes `canAssertNoAdvisory` false there, so this
assumption stands unchanged.

---

## AoU-CA-009 — ⚑ Completeness does not survive into `compound_failure_advisor` (SOTIF-CA-004, OPEN)

**Assumption**: if you compose this interface with `compound_failure_advisor`,
you understand that **everything AoU-CA-003 establishes is discarded at that
seam.** That package does not receive `AdvisoryAggregateResult` at all — its
input is a bare `AdvisoryLevel?`, and zero references to `canAssertNoAdvisory`,
`AdvisoryLookup`, `staleSources` or `AdvisoryAggregateResult` exist in
`compound_failure_advisor/lib` or `driving_weather/lib`.

**Worse than dropped — inverted.** `drive_situation.dart` declares
**`null` = no advisory in force**, a positive assertion of calm, while two
fields above it `visibilityMeters` declares **`null` = NO real reading in hand…
never coerced to "clear"**. The same sentinel, opposite semantics, two fields
apart in one class. *(This paragraph said "four fields above" and "adjacent"
until 2026-09-20; only `visibilityAgeSeconds` stands between them, and that file
has not changed since 2026-06-27, so the count was wrong when written.)*
`in_drive_advisor.dart:294` then folds them:
`case null: case AdvisoryLevel.minor: return 0;`

**Consequence**: not-knowing and knowing-it-is-mild are the same fact to that
advisor. There is no way to express "advisory state unknown" — the input state
does not exist. Reproduced RED 2026-08-16.

**Status: OPEN**, raised with the maintainers of `compound_failure_advisor`.
Not fixed here: it changes a published, driver-facing advisor's API, which is
not this file's author's to change unilaterally.

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
| CA-003 | **Yes** | `canAssertNoAdvisory`; `test/frozen_feed_test.dart` (8 tests, GREEN). The RED proof against 0.0.9 is `tool/red_proof/` (4/4): that guard file references types 0.0.10 introduced, so against 0.0.9 it does not fail, it fails to load, and cannot be the RED evidence. *(This cell read "proven RED then GREEN" until 2026-09-20; the sibling `SOTIF_INSUFFICIENCIES.md` had already retracted that claim.)* |
| CA-004 | **No — this is the residual.** Stated, not enforced. | `test/frozen_feed_test.dart` group "no cry-wolf" pins the deliberate no-op |
| CA-005 | No — delegated by design. | `AdvisoryFeedStaleness` doc |
| CA-006 | **No — OPEN**, SOTIF-CA-002. | — |
| CA-007 | No — contract, not mechanism. | `AdvisoryFeedFreshnessReporting.feedStaleness` doc |
| CA-008 | No — inverting it is the integrator's choice to make wrongly. | — |
| CA-009 | **No — OPEN**, SOTIF-CA-004, and it is the row standing between CA-003 and the driver. | reproduction in `SOTIF_INSUFFICIENCIES.md` |

**Two of nine are enforced or partially enforced. Seven are stated.** That
ratio is the honest state of this component and is written here rather than
smoothed, because an assumptions-of-use document whose rows all claim
enforcement is the failure mode it exists to prevent. *(This paragraph said
"three" and "six" until 2026-09-20; the table above it says CA-002 partially and
CA-003 yes, and nothing else.)*

**And two of the unenforced rows — CA-004 and CA-009 — sit between the CA-003
fix and any real driver.** On 2026-08-16 no adapter fed the guard and the
advisor could not receive it if one did, so 0.0.10 changed nothing a driver
would experience. **Measured 2026-09-20: the first of those two is closed** —
the JMA adapter feeds the guard from 0.7.0 — **and the second is open**:
`compound_failure_advisor` 0.1.2 and `driving_weather` 0.5.2 contain no
reference to `canAssertNoAdvisory`, `staleSources` or `AdvisoryAggregateResult`.
The fix therefore reaches a driver only through integrator code that reads the
predicate or `staleSources` itself, and that sentence belongs here rather than
in a footnote.

## Audit

The author of this document never audits its own work. It was submitted for
independent review of standards mapping (including the QM / SEooC boundary) and
of document integrity. Those verdicts are kept with the project's delivery
record.
