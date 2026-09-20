# condition_aggregator — SOTIF (ISO 21448) performance-insufficiency table

**Package**: `condition_aggregator`
**Applies from**: 0.0.10 (the row SOTIF-CA-001 mitigation lands in)
**Author**: the SNGNav maintainers (functional-safety review), 2026-08-16
**Status**: Not self-audited — see "Audit" at the foot.

> **ATTACHES TO, does not replace, `SAFETY_BOUNDARY.md`** (the package's
> safety-class boundary record, revision 1.1; first dated 2026-05-03). That
> record states the package's SOTIF *posture*; this file tabulates the
> *insufficiencies* that posture leaves, which the record's §3 declares as
> prose and never enumerates. Nothing here re-authors it.

## Scope and ceiling

QM / advisory / information-only. **No ASIL, no item, no actuator, no control
authority.** This is not a vehicle-level HARA and cannot be one: a reusable
library has no vehicle. The integrator performs the hazard analysis; this table
tells the integrator what our part of it cannot do, so their analysis is not
built on an assumption we never earned.

ISO 21448 vocabulary is used as intended for a component: **intended function**,
**triggering condition**, **performance insufficiency**, **functional
insufficiency**. Severity/exposure/controllability ratings are deliberately
absent — those are vehicle-level and belong to the integrator.

## Intended function (the thing whose insufficiency we are tabulating)

> Given a geographic point, report the meteorological advisories in force at
> that point across all configured publishers, **and state whether that report
> is complete enough to support the sentence "no advisory is in force."**

The second clause is the safety-relevant half. The first clause failing is
visible. The second clause failing is not.

---

## Insufficiency rows

### SOTIF-CA-001 — a source that answers with a document that has stopped being updated

| field | value |
|---|---|
| **ID** | SOTIF-CA-001 |
| **Class** | Performance insufficiency (of the completeness predicate, not of the data path) |
| **Intended function clause** | "state whether the report is complete enough to support *no advisory is in force*" |
| **Triggering condition** | An upstream publisher serves a syntactically valid, successfully-fetched document whose **content is temporally frozen** — publisher-side pipeline stall, mirror freeze, origin object pinned, endpoint quietly deprecated while still served. |
| **Insufficiency** | `AdvisoryAggregateResult.canAssertNoAdvisory` was defined over **reachability** (`providerErrors.isEmpty && sourcesQueried > 0`). A frozen source is *reachable*. It therefore satisfied the predicate, and `fold` → `complete`, `toLookup` → `AdvisoryLookupComplete`, `requireCompleteLookup` → silent. |
| **Output to the integrator** | An empty advisory list flagged as a **measured calm**, indistinguishable from a genuinely clear sky. |
| **Foreseeable misuse it invites** | None required. The failure needs no misuse: the package's own documented, recommended usage (`if (r.canAssertNoAdvisory) showNoAdvisory()`) produces the wrong output. That is what makes it an insufficiency rather than a usage error. |
| **Detectability before mitigation** | **Nil at this interface.** Per-advisory freshness (`Advisory.effective` / `stalenessAt` / `isStaleAt`) exists and is correct, but is structurally unreachable when the frozen document lists zero advisories — there is no `Advisory` object to carry a timestamp. This project's own winter monitoring could only observe this by reading `reportDatetime` **out of band**, bypassing the package. |
| **Measured occurrence** | 2026-08-16, live. JMA `bosai/warning/data/warning/` — Niigata `150000` last written **2026-05-26T15:45+09:00** (**81.8 days**, zero warnings); Akita `050000` **2026-05-28T06:11+09:00**; Yamagata `060000` **2026-05-28T09:48+09:00**. Not lockstep, so no single "frozen at T" holds. Origin `last-modified` confirmed the age at origin — not a cache artifact. Nationwide, not regional. JMA's official developer feed was live and carrying 515 警報・注意報 entries the same minute, so **the publisher was not down; this path was.** |
| **Consequence observed in our own stack** | A winter monitoring record kept outside this package, run `2026-08-16T02:07:02Z`, judging published `condition_aggregator 0.0.9` / `condition_aggregator_jma 0.3.1` / `driving_weather 0.5.0` / `compound_failure_advisor 0.1.2`, Niigata (54232). **The record carries both branches and instructs that neither be quoted alone, so both are here.** `drive` (true reading age) = **`heightenedCaution`**, reasons `[staleVisibility, highSpeedInDegradedConditions]`, unknowns `[visibilityReadingIsStale]`. `driveOnboard` (age zeroed, the in-car-sensor counterfactual) = **`continueDriving`, reasons `[]`, unknowns `[]`**. **The finding is what survives BOTH:** every reason and unknown in the `drive` branch concerns the *visibility reading's* age. **Neither branch says one word about the advisory feed being 81 days dead** — the caution she gets on the primary branch is the right caution for the wrong reason, and on the onboard branch she gets none at all. *An earlier draft quoted `driveOnboard` alone — the more dramatic branch — against the record's explicit instruction. Caught in review.* |
| **Mitigation (code, 0.0.10)** | `AdvisoryFeedFreshnessReporting` — opt-in adapter capability reporting `AdvisoryFeedStaleness`. `AdvisoryAggregateResult.staleSources` carries it; **`canAssertNoAdvisory` returns `false` when it is non-empty**, which propagates to `fold`, `toLookup` and `requireCompleteLookup` from the single predicate. `AdvisoryLookupPartial.staleSources` carries the fact onto the sealed type so the integrator can say *which* source went quiet and *how long ago*. |
| **Verifying test** | `test/frozen_feed_test.dart` — 8 tests, GREEN. **The RED proof is `tool/red_proof/`**, separate by necessity: the guard file references 0.0.10 types, so against 0.0.9 it does not fail, it fails to *load* — which proves nothing. `tool/red_proof/run_red_proof.sh` rebuilds pristine 0.0.9 from the pub-cache tarball and asserts a 0.0.9-API-only reproduction FAILS: verified 2026-08-16, **4/4 across `canAssertNoAdvisory` / `fold` / `requireCompleteLookup` / `toLookup`**, exit 0. *An earlier draft of this row said the 8-test file was "proven RED on unmodified 0.0.9" — a result that file cannot produce. Caught independently by two reviewers; corrected, and the correction named rather than quietly applied.* |
| **Residual after mitigation** | **AoU-CA-004.** Reporting is opt-in and positive-only. An adapter that does not implement the capability can still serve a frozen document and still satisfy `canAssertNoAdvisory`. As of 2026-08-16, **zero of the five `AdvisoryProvider` implementations implemented it.** *(Was "six" in the first draft, counting `driving_weather`, which consumes but does not implement the contract — corrected on an audit finding, 2026-08-16.)* **Measured 2026-09-20, against the latest version of each adapter on pub.dev: one of the five implements it.** `condition_aggregator_jma` 0.7.0 (published 2026-08-28) does. JMA first implemented it in 0.3.2 (2026-08-16), dropped it in 0.5.0 (2026-08-21) and restored it in 0.7.0, so a project resolved to JMA 0.5.0, or to any version before 0.3.2, does not get it. `condition_aggregator_digitraffic` 0.0.8, `condition_aggregator_met_norway` 0.0.8, `condition_aggregator_nws` 0.0.7 and `condition_aggregator_owm_road_risk` 0.1.5 do not implement it. The guard is fed through the JMA adapter and unfed through the other four. |
| **Why the residual was accepted rather than closed by default** | Defaulting unmeasured sources to "stale" would manufacture doubt on a clear day — the same class of lie as manufacturing calm, pointed the other way, and it would break every working integration to score a point. Defaulting to "fresh" is the defect being fixed. The honest third option is to report only what was measured and to **state the gap here** rather than pick a default that lies in one direction. |

### SOTIF-CA-002 — coverage gap renders as measured calm (OPEN, not mitigated here)

| field | value |
|---|---|
| **ID** | SOTIF-CA-002 |
| **Class** | Functional insufficiency (specification gap) |
| **Triggering condition** | The query point lies outside an adapter's declared catalogue. The adapter answers successfully with an empty list **by design**. |
| **Insufficiency** | The interface has no vocabulary for "this source does not cover this point." An out-of-catalogue empty answer is arithmetically identical to an in-catalogue calm, so `canAssertNoAdvisory` is `true` for a point no source ever looked at. |
| **Measured occurrence** | Same run, Maebashi (42251) and Karuizawa (48331): `adapterCoversPoint: false`, `jmaCoverage: "OUTSIDE-ADAPTER-CATALOG"`, and the record's own words — *"An empty advisory list at this point is a COVERAGE GAP, not 'no warnings in force', and must never be read as a clear road."* Both served **`continueDriving` with empty reasons and empty unknowns.** |
| **Status** | **OPEN. Not fixed in 0.0.10.** Named here rather than bundled: the mitigation is a per-adapter coverage predicate (`coversPoint(lat, lon)`) on the provider contract, which is a larger interface change and needs the adapter owners' consent, not a unilateral edit by this table's author. **Measured 2026-09-20:** `condition_aggregator_jma` 0.7.0 no longer answers an out-of-catalogue point with an empty list. Without fetching anything, it returns one `minor` notice (`kJmaOutsideCoverageEventClass`) saying the point is outside the adapter's coverage and that no warning shown does not mean safe. The gap is now visible in the list, but nothing from that adapter makes `canAssertNoAdvisory` false: nothing was fetched, so nothing lands in `providerErrors` or `staleSources`. This interface still has no way to say "not covered", so the row stays OPEN. |
| **Routed to** | The maintainers of the adapter packages. This table holds the row; it does not own the five adapter packages. |

### SOTIF-CA-003 — silence has no maximum age (OPEN, upstream)

| field | value |
|---|---|
| **ID** | SOTIF-CA-003 |
| **Class** | Performance insufficiency (upstream publisher, outside our control) |
| **Triggering condition** | A publisher issues an advisory with **no expiry** and then stops updating. |
| **Insufficiency** | `Advisory.expires` is honestly `null` (the publisher declared nothing, and fabricating a value would be a worse defect — see the `condition_aggregator_jma` ruling of 2026-08-16). `isExpiredAt` therefore answers "not expired" forever. An advisory can be served as active indefinitely. |
| **Measured occurrence** | Akita 雷注意報, `status=発表`, served **230 times over Akita Prefecture** with nothing marking the document dead; 307 advisories across 624 hourly records, **100 % with `expires: null`**. |
| **Status** | **OPEN upstream; partially compensated.** SOTIF-CA-001's mitigation makes the *feed's* age reportable, which is the honest signal. It does not give the *advisory* an expiry, and it must not. |

### SOTIF-CA-004 — ⚑ the completeness fact does not survive the hop into the advisor (OPEN — and it is the one that reaches her)

| field | value |
|---|---|
| **ID** | SOTIF-CA-004 |
| **Class** | Functional insufficiency (integration / information loss across a package seam) |
| **Triggering condition** | Any state in which advisory completeness is in doubt — feed outage, frozen feed (CA-001), coverage gap (CA-002). |
| **Insufficiency** | `compound_failure_advisor` never receives `AdvisoryAggregateResult`. Its input is a bare `AdvisoryLevel? advisorySeverity`, and **zero references to `canAssertNoAdvisory`, `AdvisoryLookup`, `staleSources` or `AdvisoryAggregateResult` exist anywhere in `driving_weather/lib` or `compound_failure_advisor/lib`** (measured 2026-08-16). Everything this table's CA-001 mitigation establishes is **discarded at that seam.** |
| **The two lines that do it** | `compound_failure_advisor/lib/src/drive_situation.dart` declares *"`null` = no advisory in force"* — a positive assertion of calm. Two fields above it, `visibilityMeters` declares *"`null` = NO real reading in hand. `null` is a first-class unknown, never coerced to 'clear'."* **The same sentinel, opposite semantics, two fields apart in the same class.** Then `in_drive_advisor.dart:294` folds them: `case null: case AdvisoryLevel.minor: return 0;` *(This row said "four fields above" and "adjacent fields" until 2026-09-20. Only `visibilityAgeSeconds` stands between them, and the file has not changed since 2026-06-27, so the count was wrong when it was written. Found on re-measurement.)* |
| **Consequence** | Not-knowing and knowing-it-is-mild are **the same fact** to the advisor. Both yield concern 0, no escalation, `continueDriving`. There is no way to express "advisory state unknown" at all — the input state does not exist. |
| **Reproduced** | 2026-08-16, scratch copy, 2 tests RED: *"an UNKNOWN advisory state must not render as a calm road"* → `Expected: not continueDriving / Actual: continueDriving`; *"UNKNOWN must be distinguishable from a MEASURED minor"* → identical action, reasons and unknowns. |
| **Status** | **OPEN. NOT fixed here, and deliberately not fixed unilaterally.** The mitigation is a new input state on a published, driver-facing advisor's API. That decision belongs to that package's maintainers, not to this table's author. |
| **Routed to** | The maintainers of `compound_failure_advisor`. Reproduction is above and re-runnable. |

> ### ⚑ What this row costs the CA-001 fix — stated here, not buried
>
> On 2026-08-16 two independent gaps sat between the CA-001 mitigation and the
> driver: no adapter fed it (AoU-CA-004), and the advisor cannot receive it
> (CA-004). **Measured 2026-09-20, one is closed and one is open.**
>
> - **Closed through the JMA adapter.** `condition_aggregator_jma` 0.7.0 reports
>   a frozen feed, so a JMA document at least as old as that adapter's threshold
>   (six hours by default) makes `canAssertNoAdvisory` false. That package's own test
>   `test/defect_proof_current_api_test.dart` asserts it on the real Niigata
>   document that was 81 days old on 2026-08-16. The other four adapters still
>   do not report it (SOTIF-CA-001, residual).
> - **Open.** `compound_failure_advisor` still cannot receive it (this row).
>   Published `compound_failure_advisor` 0.1.2 and `driving_weather` 0.5.2
>   contain no reference to `canAssertNoAdvisory`, `staleSources` or
>   `AdvisoryAggregateResult`.
>
> So the mitigation reaches a driver only through integrator code that itself
> reads `canAssertNoAdvisory` (directly, or through `fold`, `toLookup` or
> `requireCompleteLookup`) or `staleSources`. Through `compound_failure_advisor`
> it does not. What CA-001 fixes is the **interface contract an integrator
> programs against**. This file claims no observation of it on a driver's
> screen: claiming one without seeing it would overstate what was verified.

---

## What this table does NOT do

No ASIL rating, no ASIL decomposition, no FFI, no FMEDA, no safety goals, no
FSC/TSC, no vehicle-level HARA. Those are not performed on this asset; they are
the integrator's, at their item boundary. A component that claimed to have done
them would be over-claiming in exactly the shape this table exists to avoid.

## Finding against the existing boundary record (corrected in its revision 1.1)

In revision 1.0, `SAFETY_BOUNDARY.md` §3 stated, of the five honesty
disciplines:

> "Per-provider fetch failures (transport timeout, transient parse error) are
> captured into `result.providerErrors` so the integrator can render
> **staleness** honestly without losing surviving providers' data."

**That sentence conflated fetch-failure with staleness.** A frozen feed produces
*no* fetch failure and *is* stale, so the named mechanism did not cover the
named property — and the record read as though it did. SOTIF-CA-001 is the
measured proof.

**The safety-boundary review confirmed the finding and returned it enlarged**: the same conflation sat
a second time in **§8**, the *driver-facing* declaration — *"she sees the
other's advisories plus a staleness indicator the integrator chose to render
from `result.providerErrors`."* That occurrence was the worse of the two,
because it states what her experience is. This table named only §3; the §8
catch came from that review.

**Status: corrected in revision 1.1 of `SAFETY_BOUNDARY.md`, the revision that
ships beside this file.** This table's author did not edit that record. What
revision 1.1 changed, read from its diff:

- **§3** now says `result.providerErrors` shows which sources could not be
  read, and that *"a fetch failure is not staleness"*. A frozen feed raises no
  error, so it is not in `providerErrors`. Only an adapter that implements
  `AdvisoryFeedFreshnessReporting` can report it, in `result.staleSources`,
  which makes `canAssertNoAdvisory` false. From any other adapter, a frozen
  document that lists no advisories looks exactly like a current one.
- **§8** now says that the notice an integrator renders from `providerErrors`
  means a source could not be reached, and says nothing about how old any data
  is. Unless the adapter reports staleness in `result.staleSources`, nothing at
  this interface tells the integrator, and she can be shown "no advisory" over
  a document that is no longer being written.
- Its header gives the revision as 1.1 and says that the rest of the record
  states the boundary as written for 0.0.5.

**What revision 1.1 does not do.** The safety-boundary review recorded its own
debt on 2026-08-16: the
record was written against 0.0.5, and its promise to be re-audited on material
driver-experience change had gone unkept for five versions. Revision 1.1
corrects §3 and §8 against the 0.0.10 code; outside those two sections the
record is still as written for 0.0.5, as its own header says. This file does
not rule on whether that meets the promise.

## Audit

The author of this table never audits its own work. This table and its
mitigation were submitted for independent review of standards mapping
(including the QM / SEooC boundary) and of document integrity. Those verdicts,
unsoftened, are kept with the project's delivery record rather than in this
file, which is the thing being reviewed.
