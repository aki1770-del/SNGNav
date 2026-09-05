# The SNGNav Way

**What we build. Why it qualifies. Where it goes next.**

*Version 2 — 2026-06-08. Version 1 is superseded; a v1 → v2 changelog is at the end of this document.*

**An honesty note up front.** This document describes what SNGNav *is* and what it *honestly is not yet*. Where a capability is an aspiration rather than a shipped fact, it says so. "We will not optimize for metrics" and "evidence over aspiration" are not slogans here — they are the reason several v1 claims were removed.

---

## §1 What is SNGNav?

SNGNav is a **driver-assisting navigation architecture** and a working reference product. It shows edge developers how to build low-latency, map-aware, weather-relevant, consent-respecting navigation assistance **on the device** — the kind that keeps helping when the cloud, the network, and even GPS have gone away.

**It is about helping every driver's daily life** — the snow road, the rural route, the moment the forecast was wrong. **It is NOT about harvesting data from every driver.** Data is collected with consent or not at all.

**Who this is for**: edge developers — the engineers who build real-time experiences on embedded hardware at the boundary between the vehicle and the world. They process on-device, not in the cloud. They collect data with consent, not by default. They render a glanceable scene on ARM, not on a gaming GPU.

**And we are one of them.** We build SNGNav on the same embedded-Flutter terrain our edge developers work in, and we hit the same walls they hit — the missing aarch64 build target, the Yocto recipe, the embedder, the plugin that silently fails to load on ARM. When we solve one of those walls for ourselves, we solve it for every edge developer standing at it.

**Why we build this**: Sakichi Toyoda built a loom that stopped itself when a thread broke — the machine protected the weaver's work rather than relying on the weaver to notice. We build navigation that protects the driver when conditions break. The architecture serves the edge developer; the edge developer serves the driver.

**The worst case is the design target.** SNGNav is not measured against a clear day. It is measured against the compound failure: **Google Maps is gone AND GPS is gone AND the driver no longer knows where she is** — at once, in unexpected snow. When every standard piece of infrastructure has failed, what we shipped must still help her. Everything below traces to that one moment.

---

## §2 The Five Principles

Every feature, package, and line of code in SNGNav must satisfy these five. If it doesn't, it doesn't ship.

### 1. Offline-First
The system works when the network fails. GPS dies in a tunnel; the routing server is unreachable; the weather API times out — SNGNav continues, with dead reckoning, local tiles, cached routes, and stale-but-present conditions. The driver never sees a blank screen. *Rules out*: any feature that requires a cloud connection to function.

### 2. Consent by Default
Data collection is deny-by-default, per-purpose, and revocable. Fleet telemetry, location history, condition reports — none flow until the driver says yes, and she can revoke at any time. *Rules out*: implicit collection, opt-out models, assumed permission.

### 3. Display-Only Safety Boundary
SNGNav is a navigation **display aid**, classified ASIL-QM. It does not control the vehicle. Dead-reckoning positions are estimates — always shown with an accuracy indicator, never as false certainty. Advisories are never suppressed, hidden, or overridden by application logic. *Rules out*: steering, braking, ADAS commands. **And it rules out the dishonest scene**: when position is uncertain, the display degrades honestly (it says so) rather than painting confidence it does not have.

### 4. Clean, Extractable Boundaries — and the catalog is frozen
Every domain boundary must be cleanly extractable; pure-Dart cores stay Flutter-free so an edge developer can reuse a model in a CLI, a server, or a test harness. **This architectural virtue stays.** What changed: **we no longer grow a pub.dev catalog of our own.** Publishing net-new packages became a building-for-ourselves anti-pattern — a catalog with zero external adoption is not service (see §4, §5). Clean boundaries: always. Net-new packages on pub.dev: frozen. *Rules out*: core models that depend on Flutter widgets or platform channels; and net-new catalog packages absent a real edge-developer pull.

### 5. Evidence over Aspiration
We ship only what is verified — a passing test, a measured benchmark, a build whose real output we read. Every claim traces: **Evidence → Contribution → Architecture → Edge Developer → Driver.** This principle has teeth: a claim authored *ahead of* the evidence it depends on is a stop-the-line event, not a rounding error. *Rules out*: speculative features, unverified performance claims, documentation that describes intent as if it were reality. **This is the principle that rewrote this document** — several v1 claims were aspirations wearing the present tense, and they are corrected below.

---

## §3 What's In Scope

| Domain | Guardian | What it does |
|--------|----------|-------------|
| **Position** | Dead Reckoning (Kalman filter) | Predicts location when GPS is lost |
| **Routing** | Local Routing (OSRM / Valhalla) | Calculates routes without cloud access |
| **Conditions** | Conditions Awareness | Monitors snow, ice, visibility, road surface |
| **Consent** | Consent Lifecycle | Per-purpose, revocable data permissions |
| **Fleet** | Hazard Aggregation | Clusters fleet reports into hazard zones |

### Out of Scope
- Vehicle control (steering / braking / ADAS) — ASIL-QM, display only.
- Cloud-required features — violates Offline-First.
- Non-consensual data collection — violates Consent by Default.
- **Net-new pub.dev catalog packages** — frozen (see §4 / §5); the energy goes to the tools edge developers already use.

### The 3D scene — the honest position
SNGNav's foundation is 2D. The aspiration is a **glanceable 3D scene** — road state, weather, and position rendered as something the driver understands in a glance, on her real ARM IVI target, offline. **That invariant is non-negotiable.**

**What changed since v1 (the destination re-anchoring, 2026-06-03):** v1 bound this scene to **Fluorite / Filament PBR**, Toyota's Flutter-integrated game engine. We do not own Fluorite and its source is not open; native GPU-3D on Flutter-Linux is also blocked upstream (flutter/flutter #183495). So:

- **Fluorite / Filament PBR is retired as a *current capability*** and kept as a named ***contribute-when-open* aspiration** — a bet for the day its source opens, never a present-tense claim.
- We render the glanceable scene at the **honest fidelity we can ship today — CPU/Skia** — and upgrade through a path we control (**flutter_scene / Impeller**), on her real ARM target, offline.
- The earlier **"60fps on ARM"** language was an aspiration; it is not a present capability and no longer appears as one.

**Where the product honestly is today**: a real glanceable perspective scene exists in SNGNav, driven by live road-condition severity (Digitraffic), and it has rendered on the host and **under QEMU-emulated aarch64** (first frames proven). **It has not yet rendered on a physical board.** The line stays stopped until one measured rung renders on her actual hardware. That rung — the scene on a real aarch64 board — is the **primary product objective** (§5).

---

## §4 The Catalog — a means we paused, not the product

The monorepo holds **29 packages** (28 publish-eligible; the bulk already on pub.dev) — dead reckoning (`kalman_dr`), routing (`routing_engine`), conditions (`driving_conditions`, `driving_weather`), consent (`driving_consent`), fleet hazard (`fleet_hazard`), the navigation-safety and viewport BLoCs, and the condition-aggregator adapter family (Digitraffic, JMA, MET Norway, NWS, …).

**The honest finding (2026-05-31 → 2026-06-08):** external adoption of this catalog is **zero** — every package that depends on one of ours is another of ours. A catalog no edge developer outside the project pulls is not service; it is building for ourselves. So we **froze net-new catalog production** and made the freeze the standing default. The packages remain real, tested, and maintained; correctness fixes still ship. **What stops is *growing the catalog as if shipping a package were the same as serving someone.* It is not.**

The catalog's real value now is twofold: (1) it is the **evidence** that we understand the domain — the thing that earns a hearing when we contribute upstream; and (2) its clean boundaries let pieces of it ride into the projects edge developers actually use.

*(The canonical contracts — viewport Z-order and camera modes, the offline-tile resolution order, the routing lifecycle, the driving-conditions computation models — remain as specified in the package READMEs and ARCHITECTURE.md; they are unchanged by the freeze.)*

---

## §5 Where It Goes Next — contribute upstream; render on her hardware

v1's roadmap was "more extraction candidates." That is retired. Two directions now.

### Direction 1 — Contribution-as-service to existing projects (the channel that lands)
The channel that actually reaches an edge developer is **contributing to the open-source projects they already use**, not publishing our own packages. This is the operating mode now, and it has begun to land:

- **flutter-geolocator #1783 — MERGED** (2026-06-08): a `Position.heading` correctness clarification, maintainer-invited and merged.
- **COVESA VSS — MERGED**: a winter-condition signal into the vehicle-signal standard, reaching the actual demand-holders.
- **flutter/flutter #187018** — engaged: the missing `linux_arm` target that silently disables FFI plugins on embedded ARM — the wall *we* hit on our own bring-up, which is every embedded-Flutter developer's wall.

Every such engagement runs the same discipline: verify the build before contributing, cite evidence, read the live thread, no fabricated claims, defer to the maintainer. We contribute *to* the project; we do not route around a maintainer; we do not grow our catalog.

### Direction 2 — The product on her hardware (the primary objective)
The glanceable scene must render on a **real aarch64 IVI board**, offline, with live conditions — the rung above the host and QEMU rungs already proven. This is the standing objective; the release gate stays closed until it renders on real silicon. Progress on the embedded path (the aarch64 build target, the Yocto recipe, the embedder, on-target bring-up) serves this objective **and**, contributed upstream, serves every edge developer on the same path — the two directions are one road.

**What is no longer "next":** growing the catalog; any feature that needs Fluorite before it opens; any 3D claim ahead of a frame on her board.

---

## §6 How Decisions Are Made

Every proposed feature traces to one question:

> **"How does this help the driver when conditions are worst — Google Maps gone, GPS gone, and she no longer knows where she is, in unexpected snow?"**

through five filters:

| # | Filter | Filter question |
|:-:|--------|----------------|
| 1 | **Purpose** (anchor) | Does it help a driver in the compound-failure worst case? |
| 2 | **Dignity** | Does it make the edge developer's life easier — every edge developer, not just the ones we can see? |
| 3 | **Customer** | Is the edge developer the one we serve? (and we are one of them) |
| 4 | **Chain** | Can we trace Evidence → Contribution → Architecture → Edge Developer → Driver? |
| 5 | **Product** | Does it fit a driver-assisting navigation architecture? |

If a feature can't answer all five, it doesn't ship.

### Where this document sits
- **WHY** — the architecture protects the driver when conditions break.
- **HOW** — `ARCHITECTURE.md` (the guardians, the provider system, offline-first design).
- **WHAT** — this document: the product-level answer to "what qualifies as SNGNav."

---

## v1 → v2 changelog
- **Fluorite retired as a current capability** → *contribute-when-open* aspiration; honest CPU/Skia → flutter_scene/Impeller path (2026-06-03). [§1, §3, §5]
- **"60fps on ARM" present-tense claim removed** — it was an aspiration. [§1, §3]
- **Package portfolio (11 extracted / 10 published) → catalog of 29, frozen** — net-new publication paused as standing default; the catalog-as-product framing corrected (external adoption = 0; building for ourselves). [§2.4, §4, §5]
- **Roadmap "more extraction" → contribution-as-service to existing projects + render-on-her-hardware.** [§5]
- **Added "we are edge developers too"** (2026-06-08). [§1]
- **Anchor sharpened to the compound-failure worst case.** [§1, §6]
- **Evidence-over-Aspiration given teeth; honest product state stated** (host + QEMU-aarch64 proven; physical board pending). [§2.5, §3]
- **Five Principles + driver-test decision filter retained** (Principle 4 evolved; the rest intact).
