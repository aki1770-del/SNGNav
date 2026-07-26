# SNGNav Architecture — Derived From HER's Use Case

*2026-07-26. Designed forward from the driver's actual moment (`DRIVER_VOICES.md`), not backward from the package catalog. Where the use case demands something the parts under-serve, this says so. Subordinate to PHIL-001 (L2) and the constitution (L3); a design lens on `ARCHITECTURE.md`, not a replacement.*

---

## §0 The method: from her moment, not from the parts

We have ~40 packages. It would be easy to draw the architecture as boxes named after them (`kalman_dr`, `condition_aggregator`, `voice_guidance`) and call the wiring the design. That is designing backward from what we happen to own — and the Board already found the catalog has **zero external adoption**: a package is not service. So this document does the opposite. It starts at **the one moment SNGNav exists for** and asks, at each step, *what does she actually need here* — then names the component only after the need is established. A part earns a place only by answering a need in her moment.

## §1 Her actual moment (the genba)

She is on a rural mountain road in Akita in unexpected snow. The compound failure hits at once: **the map is gone, GPS is gone, and she no longer knows where she is** — at ten metres' visibility. That is the design target. But the voices in `DRIVER_VOICES.md` make the moment far more specific than "snow," and the architecture answers *these* facts:

- **The hazard is the surface, not the weather.** A frozen rut (轍) defeats ABS and ESC for an *experienced* driver (JAF Mate). A tourist totals a car at a TOMARE sign because a complete stop is *impossible on this friction* — the failure mode silently shifted from "missed sign" to "can't stop," with no warning. A bridge freezes before the road. "Snow" is the weather; the thing that hurts her is the **surface under this tyre, here, now.**
- **Abandonment is a real response, not the bottom of a speed dial.** The Sapporo driver *turned around*. JAF's official whiteout guidance is *"stop at a safe place"* — not "slow down and continue." The response space is `proceed → reduceSpeed → considerTurningBack → halt/abandon`, and the top of it is where snow-zone survival actually lives.
- **She usually cannot look, and often cannot hear.** In a whiteout her eyes are on the vanishing road; a screen is secondary. Audio is not universal: a deaf driver receives *nothing* from an audio alert (SafeDrive4Deaf, n=25, 100%), and neither does a hearing driver inside roaring-wind whiteout. And voice itself *costs* — hands-free interaction cuts hazard-detection ERP amplitude ~50% (AAA). So talking more is not helping more.
- **The most consequential surface is before she leaves.** JAF puts the load-bearing weight on **pre-trip** — condition + route + equipment review days ahead. The Sapporo abandon-decision, made at home, is the safest one she can make.
- **She is a specific person, not "a driver."** Foreign-tourist-in-snow, experienced-but-defeated-by-a-rut, deaf/HoH — road-safety institutions treat these as *distinct cohorts with distinct guidance*. Collapsing them to one "drive carefully" under-serves each.

## §2 What her moment demands of the architecture (requirements, derived)

| # | Her moment says | The architecture must therefore |
|---|---|---|
| R1 | GPS/map/orientation all fail at once | **Keep working with each input removed** — degrade, never blank; and degrade **honestly** (say when position is a guess). |
| R2 | The surface is the hazard | Assess the **road-surface state at her position and along her path ahead**, not just ambient weather. |
| R3 | Turning back is a valid answer | Carry **halt/abandon as a first-class response tier**, reachable from the assessment, not bolted on. |
| R4 | She can't look; audio isn't universal | Deliver every warning on **≥2 channels off one severity gate** — voice *and* haptic carry the **same** set, differentiated by tier; screen is a glance, not the plan. |
| R5 | Voice costs attention | **Parsimony is a safety property.** Say the least that lets her act. Fewer words, later, is safer. |
| R6 | Pre-trip is load-bearing | Make **pre-trip a first-class lifecycle stage**, not an in-trip afterthought — the abandon-decision belongs at the kitchen table. |
| R7 | She is a specific cohort | Let the **cohort shape assessment thresholds and delivery**, without collapsing the honesty of the underlying hazard. |
| R8 | It runs on her real hardware | Everything above holds **offline, on an aarch64 IVI, at ARM-honest fidelity** — the Andon-held objective. |

## §3 The architecture: one spine, one lifecycle, four laws

Her moment resolves to a single perception-to-delivery **spine**, wrapped in a **trip lifecycle**, governed by four **cross-cutting laws**. Every box below traces to a row in §2.

```
                    ┌──────────────── TRIP LIFECYCLE ────────────────┐
                    │  PRE-TRIP  →      IN-TRIP loop     →  HALT/END  │
                    └────────────────────┬───────────────────────────┘
                                         │
   ┌─────────────┐   ┌─────────────┐   ┌─────────────┐   ┌──────────────────┐
   │ PERCEPTION  │→  │ ASSESSMENT  │→  │  RESPONSE   │→  │     DELIVERY     │
   │ where am I  │   │ what is     │   │ what should │   │ how she receives │
   │ + surface   │   │ dangerous   │   │ she do      │   │ it (multi-chan)  │
   │ + what I    │   │ HERE, now   │   │ proceed..   │   │ voice ∥ haptic ∥ │
   │ can perceive│   │             │   │ ..abandon   │   │ glance, 1 gate   │
   └─────────────┘   └─────────────┘   └─────────────┘   └──────────────────┘
        R1,R2             R2,R7             R3               R4,R5
   ─────────────────── LAWS: offline-first · honest-degradation · one-severity-gate · consent ──────────────────
                                          R1,R8                    R4
```

### The spine (the in-trip loop)

**1. PERCEPTION — "where am I, and what is under me?"** (R1, R2)
Fuses the inputs that *survive* infrastructure loss into a single situational estimate:
- **Position that holds when GPS drops** — dead-reckoning from vehicle motion (wheel speed, IMU, heading), carrying an *explicit accuracy* that widens as the fix ages. Its output is never a bare lat/long; it is a lat/long **plus how much to trust it** (Law of honest degradation).
- **Surface state, not weather** — the perception layer's first-class output is the *road-surface condition at her position and along the near path*: friction class, ice, frozen-rut, bridge-deck, packed-snow — assembled from cached + live condition sources when reachable, and from last-known + forecast when not.
- **What she can perceive** — a visibility estimate that speaks her language of cues: "next reflector invisible" = whiteout tier, because that is how a driver actually detects it.
The design test: remove GPS → position holds (wider accuracy). Remove the network → surface state falls back to cached+forecast, flagged stale. Remove the map → last tiles + dead-reckoned position. **Never blank.**

**2. ASSESSMENT — "what is dangerous, right here, right now?"** (R2, R7)
Turns perception into a *hazard specific to her trajectory*: not "it is icy" but "the bridge 200 m ahead freezes before the road," "the rut you are in will beat your ESC," "you cannot make the TOMARE stop on this friction." It fuses {position + motion + path-ahead} × {surface + weather + forecast} and is **cohort-aware** (R7): the *same* measured hazard yields a firmer recommendation for the tourist who does not know friction-stop than for a snow-zone local — while the underlying hazard reported stays honest for both. This is where the surface micro-features the voices name (轍, bridge-first, friction-stop) live as first-class cases, not footnotes.

**3. RESPONSE — "what should she do?"** (R3)
Maps the hazard to a tier in a **closed, ordered response grammar**: `proceed · reduceSpeed · considerTurningBack · halt/abandon`. Two properties the voices force:
- **Abandon is reachable** — a whiteout or a compound-failure worst case can resolve *directly* to halt/abandon; the grammar does not top out at "slow down."
- **It says what to do, structured by JAF's hierarchy** — equipment (before), prediction (ahead), in-condition inputs (no abrupt actions), whiteout halt — not a single collapsed severity word.
The response is *advisory only* (ASIL-QM, Law of the display-only boundary) and is **never suppressed by app logic** — an advisory, once earned, is delivered.

**4. DELIVERY — "how does she receive it, when she can neither look nor hear?"** (R4, R5)
The load-bearing, and most under-appreciated, stage. One **severity gate** feeds *every* channel; a warning that reaches voice reaches haptic at the **same tier**:
- **Voice** — parsimonious Japanese; the *least* that lets her act (R5). Ducks or defers under load.
- **Haptic** — the **same severity set as voice**, differentiated by tier (a distinct pattern per `proceed/reduceSpeed/considerTurningBack/halt`), never one undifferentiated buzz. This is the channel that carries when wind kills speech and the only channel a deaf driver has — so it is a **D4 dignity floor (OPS-059)**, not an add-on. A haptic grammar that silently drops the top tier for the driver who can least afford to miss it is the failure this stage exists to forbid.
- **Glance** — the scene she understands *in a glance* on her ARM IVI; primary when she *can* look, secondary by design because she often cannot.
The invariant: **no channel is a reduced subset of another at the top of the severity scale.**

### The lifecycle wrapper (R6)
- **PRE-TRIP** — a first-class stage, not a screen she skips: route × forecast-conditions × equipment, resolving to a *go / prepare / do-not-go* recommendation before she leaves. This is where JAF puts the weight and where the Sapporo turn-around ideally happens — at home, not at the shoulder.
- **IN-TRIP** — the spine loop above.
- **HALT / END** — whiteout-halt ("stop at a safe place, hazards on") as a designed terminal state with its own delivery, not an absence of guidance.

### The four laws (cross-cutting, non-negotiable)
1. **Offline-first (R1, R8)** — every stage has a defined behaviour with the network, GPS, or map removed. The system's *contract* is what it does when infrastructure is gone.
2. **Honest degradation (R1)** — uncertainty is shown, never painted over. A guessed position looks like a guess. The dishonest confident scene is ruled out — this is what makes a *display-only* aid safe.
3. **One severity gate (R4)** — a single assessment→severity mapping feeds voice, haptic, and glance identically; channels differ in *form*, never in *which warnings they carry* at the top tier.
4. **Consent (Principle 2)** — every datum that leaves the device is deny-by-default, per-purpose, revocable. Perception can run wholly on-device; sharing is her choice.

## §4 Where her use case goes *deeper* than the parts — the honest gaps

Delving into the moment (not the catalog) surfaces four places where the need is sharper than a package-shaped view of it:

- **G1 — Delivery-severity parity is an architecture invariant, not a `voice_guidance` feature.** The deaf-driver / whiteout-wind voices make "voice and haptic carry the same gated set" a *cross-cutting law*. If it lives only inside the voice package, the haptic path can drift to a subset. It must be enforced at the **one gate** feeding both. *(VERIFIED at the genba 2026-07-26, in the deployable app `aki1770-del/sngnav-app`: `AlertAnnouncer` fires haptic first + guarded then audio, neither suppressing the other, off the one severity gate `hapticCueForCoreSeverity` — "the deaf driver's cue set equals the hearing driver's warning set" — and `MobileAlertActuators` renders differentiated `Vibration.vibrate` waveforms per tier, not one buzz. Honest bounds that remain open: (a) on-device "she FEELS it" is DEFERRED per OPS-066 until a physical device; (b) this monorepo's own demo app displays the spoken strings but wires no haptic — parity lives in the deployable app, and any future in-repo delivery surface must route through the same announcer pattern; (c) no queue exists in the deployable haptic path (announcer→actuator→vibrate is direct) — the "unbounded critical haptic queue" note concerns the `voice_guidance` bloc lane the deployable app does not use for announcements.)*
- **G2 — The first-class object is the surface state, not the weather.** Much condition machinery is organized by *source* (JMA, Digitraffic, MET). Her moment needs them collapsed into one **road-surface-state-at-a-point** object (friction/ice/rut/bridge), so assessment reasons about *what is under the tyre*, not about which API said what. Sources are adapters *into* that object; the object is the architecture.
- **G3 — Abandon must be first-class in the response type, not an app-level branch.** If `considerTurningBack`/`halt` are strings some UI decides to show, they are suppressible. The response *grammar* must make abandon a tier the assessment can command and the delivery cannot silently drop (couples to Law 2 of the display-only boundary: advisories are never overridden). *(CORRECTED at the genba 2026-07-26: the deployable app's ceiling is deliberate doctrine, not a gap — "the advisory ceiling is* consider stopping*; the worst case demotes the MAP, never the JOURNEY to her mother." That IS JAF's "stop at a safe place" as a designed terminal tier, chosen over "turn back." What stays open is only keeping that tier in the response* type *(the catalog's `considerTurningBack` / the app's stop-counsel) rather than as suppressible UI strings — which the deployable app's announcer already honors.)*
- **G4 — Cohort shapes thresholds without touching honesty.** The tourist and the local get different *recommendations* off the *same* measured hazard. This belongs in assessment (a threshold/verbosity policy), not smeared across delivery — so the reported hazard stays one truth and only the counsel adapts.

## §5 The HER-trace, made concrete (contrast with the nav2 case)

The nav2 costmap-filter trace to HER is ~4 hops through an integrator — real but indirect, "general safety quality." **This** architecture's trace is the point of the whole design: every stage terminates in her hands, one hop.

| Stage | Her, in the moment |
|---|---|
| Perception | GPS died on the pass — she still sees *where she is* (honestly, as a guess). |
| Assessment | She learns the **bridge ahead freezes first** — before she is on it. |
| Response | The system reaches **considerTurningBack** — the Sapporo decision, offered in time. |
| Delivery | Wind has killed the speaker and she cannot look — she **feels** the halt-tier pattern. |
| Pre-trip | She decided **not to go** this afternoon — the safest outcome, at home. |

That column is the "concrete structure for HER trace." No integrator hop, no "eventually." When this renders on her real aarch64 board, offline, at ARM-honest fidelity (the Andon-held objective, §3 R8), each row is a thing that happened *to her*, not a capability that *could* help *someone*.

---

**Bottom line.** The architecture is not the 40 boxes. It is one spine — *know where she is → know what is dangerous here → know what to do → make sure she receives it when she can neither look nor hear* — wrapped by *before/during/abandon*, under four laws that hold when the infrastructure is gone. The parts serve the spine; where a part's shape (source-organized conditions, voice-local severity, string-level abandon) diverges from her moment, her moment wins, and §4 names the four places it does.
