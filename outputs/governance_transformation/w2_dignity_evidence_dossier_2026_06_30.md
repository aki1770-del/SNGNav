# W2 Dignity Evidence Dossier (genchi-genbutsu)

**Date:** 2026-06-30 · **Author:** VAA-as-SEO · **Method:** direct reads of the real source this turn (file:line cited). No panel narration — every claim below was read at the genba. **Class:** D4 dignity / substrate-class (§1) — the *design* choices here are the Chair's; this dossier is the evidence on which to choose.

**Mission anchor (OPS-060B):** HER is the **driver** (a sovereign subject), and the *other* drivers whose reports feed the fleet are edge developers' users too. D4: never instrument HER body/cabin as an object; never expose another driver as a re-identifiable subject. PHIL-001 §What-We-Do-Not-Build #1: *"the driver's personal incident data is never the product."* These three fixes make the consent/fleet packages keep that promise in **code**, not just in docstrings.

---

## D1 — `driving_consent`: `readEvents` is not consent-gated; revoke does not stop reads

**Ground truth (read this turn):**
- `InMemoryInstrumentationService` holds a `ConsentService _consentService` (`in_memory_instrumentation_service.dart:26`).
- `recordEvent` **is** gated: it calls `_consentService.getConsent(purpose)` and throws `StateError` unless `isEffectivelyGranted` (`in_memory_instrumentation_service.dart:64–75`). UNKNOWN=DENIED. ✅
- `readEvents` (`in_memory_instrumentation_service.dart:84–103`) **never consults `_consentService`** — it returns straight from the `_events` map.
- `revoke()` (`consent_service.dart:32–36`) only flips consent to `denied`; it does **not** delete events. `deleteAllEvents` is a separate affordance (`instrumentation_service.dart:62–68`), by design.
- **Consequence:** after HER revokes a purpose, every event already recorded under it stays fully readable via `readEvents`. "Revoke" stops *writing*, not *reading*.
- **Overstated docstring:** the contract says *"readEvents only returns events whose purpose has consent…"* (`instrumentation_service.dart:12`) — which reads like enforcement — then quietly delegates the gate to the caller (line 13–15). A careless integrator believes reads are gated when they are not.

**Why it's a dignity gap:** when HER says "stop," she means stop *using* it, not just stop *collecting* more. The package can enforce that (it already holds the ConsentService) and doesn't.

---

## D2 — `driving_consent`: instrumentation records driver-as-subject fields

**Ground truth (read this turn, `instrumentation_event.dart`):** four event types, all coarse classes, keyed to a stable per-install `driverPseudonym` (L34–36). Header claims *"Zero GPS, zero destination, zero PII"* (L6). But the recorded fields include:
- `PassengerPresenceClass` — `driverOnly / driverPlusOne / driverPlusMany` (L146–159): **cabin occupancy** — who is in HER car.
- `ConsecutiveDrivingDayClass` — `firstDay / twoToThree / fourToSix / sevenPlus` (L176–189): a **fatigue-adjacent** driving-streak signal.
- `CohortMultiplierClass.ageingRural` / `DriverProfileClass.ageingRural` (L103, L201): an **aging** cohort label.
- All bound to a stable `driverPseudonym` → a coarse-but-real **profile of the driver-as-monitored-subject**.

**Why it's a dignity tension (not a clear bug):** the package's defense is genuine — coarse classes, no GPS/PII, consent-gated, integrator-supplied, feedback-not-control. But cabin-occupancy + driving-streak + aging, keyed to a stable ID, is exactly the *shape* of the forbidden 見守り / occupant-instrumentation line that [[understanding-her-the-driver-2026-06-22]] says we do not cross. The question is a **scope** decision: should these fields exist at all in a package whose job is to *protect* HER?

---

## D3 — `fleet_hazard`: the "anonymized aggregate" retains re-identifiable per-vehicle trails

**Ground truth (read this turn):**
- `HazardZone.reports` is `final List<FleetReport> reports;` (`hazard_zone.dart:26`) — the "aggregate" **holds the full list** of raw constituent reports.
- Each `FleetReport` carries `vehicleId` (String), **exact** `position` (LatLng), `timestamp`, condition, confidence (`fleet_report.dart:28–50`).
- `vehicleCount` / `averageConfidence` are derived **from** that retained list (`hazard_zone.dart:32–40`); `toString()` exposes counts.
- **Consequence:** any consumer of a `HazardZone` can read `zone.reports` and reconstruct each vehicle's path: `vehicleId → [(position, timestamp), …]`. A stable id + a location trail **is** re-identifiable (GDPR/APPI), regardless of whether *this package* maps it to a name.

**The contradicted claims:**
- `SAFETY_BOUNDARY.md:53`: *"consent-based fleet insights (anonymized, aggregated)."*
- `SAFETY_BOUNDARY.md:58`: *"not raw per-vehicle dots … but clustered zones."*
- `SAFETY_BOUNDARY.md:34`: *"vehicleId is opaque-token-class … never PII"* — true that the package doesn't resolve identity, but the retained id+trail is still re-identifiable, so "anonymized" overstates.

**Why it's a dignity gap:** it exposes the *other* drivers (the fleet contributors) as re-identifiable subjects inside an object the docs call anonymized — the "personal incident data is never the product" line, at the data-structure level.

---

## S3 (rides this wave) — `driving_consent` README regulatory overclaim

`README.md:12` *"GDPR/CCPA/APPI-ready consent management"* and `:18` *"GDPR, CCPA, APPI — design for GDPR, deploy everywhere"* overclaim for what is a per-purpose consent **state machine** (compliance is the integrator's, at their persistence/jurisdiction layer). Held back from W4 to ride the driving_consent dignity republish.

---

## Design forks for the Chair (each is a real choice; my recommendation marked)

- **D1:** (a) **gate `readEvents` on consent** so revoke immediately stops reads + fix the docstring *(recommended — strongest HER sovereignty; low risk; deleteAllEvents stays the separate erasure)*; or (b) docstring-only honesty fix, behavior unchanged.
- **D2:** (a) **remove** the driver-as-subject fields (cabin-occupancy + driving-streak + aging cohort); (b) keep, tighten docs to the coarse-class/consent-gated justification; (c) **narrow** — drop the most occupant/body-adjacent (cabin-occupancy + driving-streak), keep profile/cohort for rendering *(my lean: (c) or (a) — pull back from the 見守り line)*.
- **D3:** (a) **true-aggregate** — `HazardZone` drops the raw reports, precomputes vehicleCount/averageConfidence/severity, retains no trail (breaking API, matches the "anonymized" claim); (b) honest-reclaim — keep reports, correct the docs to stop claiming anonymized; (c) **strip `vehicleId`** from retained reports (keep position/condition for rendering, drop the re-id key) *(my lean: (c) — protects the other drivers while keeping rendering, smaller break than (a))*.

All three are dignity-protective in the recommended directions. None ships without your ratification (§1). After your choice I build on the build-track, run the OPS-068 gate with an AAA D4-dignity lens (advocate≠verifier), render/observe where applicable, and bring you the verified diff for the republish ratification.
