# Safety Statement

## Classification

This software is classified **ASIL-QM** (Quality Management) under ISO 26262.

It is a **display-only navigation aid**. It does not control any vehicle
function — no steering, braking, throttle, or ADAS intervention.

## What This Software Does

- Displays map tiles, route geometry, and turn-by-turn instructions.
- Shows weather conditions from configurable data sources.
- Shows fleet-reported hazard zones (consent-gated).
- Estimates position via dead reckoning when GPS signal is lost.
- Displays safety alerts (weather hazards, ice risk, low visibility).

## What This Software Does NOT Do

- It does not control the vehicle.
- It does not make driving decisions.
- It does not replace the driver's judgment.
- It does not guarantee the accuracy of weather, route, or position data.
- It does not use AI to generate, alter, or interpret driving scene imagery.
- It does not provide autonomous driving recommendations or override driver
  input.
- Dead reckoning estimates degrade over time and are explicitly marked with
  increasing accuracy radius.

All visual output is deterministic: map tiles from known sources, route
geometry from open routing engines, weather data from declared providers.
No generative model produces or modifies what the driver sees.

When 3D rendering capability arrives (via the Fluorite engine integration
point), the same display-only boundary applies. Rendered scenes will
visualize data — not generate or infer road conditions from imagery.

## Safety Alerts Are Advisory

All safety alerts (weather warnings, ice risk, hazard zones) are
**informational and advisory only**. The driver is always responsible for
assessing road conditions and making driving decisions.

Alert severities:

| Level | Meaning | Example |
|-------|---------|---------|
| Info | Conditions worth noting | Light snow beginning |
| Warning | Conditions require attention | Moderate snow, reduced visibility |
| Critical | Hazardous conditions detected | Heavy snow, visibility < 200m, ice risk |

Critical alerts are modal (block map interaction until dismissed) to ensure
the driver acknowledges the information. This is a display behavior, not a
vehicle control action.

## Safety Overlay Design

The safety overlay follows five rules:

1. **Always rendered** — never removed from the widget tree.
2. **Always on top** — Z-layer 2, above navigation (Z-layer 1).
3. **Passthrough when inactive** — does not interfere with normal use.
4. **Modal when active** — requires acknowledgment for critical alerts.
5. **Independent state** — not affected by navigation session resets.

## Dead Reckoning

When GPS signal is lost (e.g., tunnels), the system estimates position using
the last known speed and heading. Two algorithms are available:

- **Linear extrapolation**: constant speed/heading projection.
- **Kalman filter (EKF)**: 4D state estimation with covariance tracking.

Dead reckoning positions are clearly distinguished from GPS-derived positions
through increasing accuracy radius values. The system does not represent
estimated positions as verified positions.

## Consent and Privacy

Fleet telemetry (vehicle position sharing) requires explicit, per-purpose
driver consent. The consent model follows a "deny by default" principle:
unknown consent status is treated as denied. No data leaves the device
without explicit grant.

Consent is per-purpose (fleet location, weather telemetry, diagnostics) and
revocable at any time.

## Data Sources

All data providers are configurable and documented. Default configuration
uses simulated data that requires no network or GPS hardware. Real data
providers (Open-Meteo weather, GeoClue2 GPS, OSRM/Valhalla routing) are
opt-in via build flags.

No provider is assumed to be always available. The system degrades gracefully
when data sources are unavailable.

## Intended Use

This software is intended for:

- Research and development of navigation user interfaces.
- Demonstration of offline-first navigation architecture.
- Educational reference for Flutter-based automotive displays.

It is **not certified for production vehicle deployment**. Any integration
into a production vehicle system requires independent safety assessment
appropriate to the target ASIL level.

---

## Regulatory Awareness

This section documents how SNGNav's architecture relates to emerging
regulations. These are design observations, not compliance certifications.
Independent assessment is required for any production deployment.

### EU AI Act (Regulation EU 2024/1689)

The EU AI Act classifies AI safety components in critical infrastructure
(including transport) as **high-risk**. High-risk AI systems face
requirements for risk assessment, data governance, traceability, human
oversight, robustness, and cybersecurity. These rules take effect in
August 2026.

**SNGNav's architectural position**:

SNGNav is not an AI system. It does not use machine learning models to
interpret driving scenes, generate navigation imagery, or make route
decisions. Its outputs are deterministic: map tiles rendered from known
tile servers, route geometry computed by open routing engines (OSRM,
Valhalla), weather data from declared API providers.

The display-only, ASIL-QM classification means the system sits below the
high-risk threshold — it provides information to the driver without
controlling or autonomously influencing vehicle behavior.

### UNECE WP.29 — Driver Distraction

UNECE Working Party 29 develops guidelines on human-machine interfaces
for vehicles, including driver distraction limits for in-vehicle displays.

**SNGNav's architectural position**:

- Safety alerts are modal when critical — requiring driver acknowledgment
  ensures the driver is aware of hazardous conditions without creating a
  secondary attention demand during normal driving.
- The safety overlay's five rules (always rendered, always on top,
  passthrough when inactive, modal when active, independent state) follow
  the principle that safety information must be accessible without
  competing with the driving task.

### ISO 26262 — Functional Safety

SNGNav is classified ASIL-QM (Quality Management) — the lowest functional
safety level under ISO 26262. This classification is appropriate because:

- The system has no vehicle control interface.
- No actuator command is generated.
- Display failure results in loss of advisory information, not loss of
  vehicle control.
- The driver retains full authority at all times.

---

## Compliance by Design

SNGNav's architectural decisions align with regulatory principles not
because compliance was retrofitted, but because the same engineering
values that drive safety also satisfy regulatory requirements.

| Architectural Decision | Safety Rationale | Regulatory Alignment |
|----------------------|-----------------|---------------------|
| **On-device processing** | Works without connectivity; no cloud dependency in safety-critical moments | Audit trail stays local (traceability). No cross-border data transfer concerns. |
| **Consent by default** | Driver controls data sharing; deny-by-default prevents accidental exposure | Data governance by design. Clear data provenance chain. |
| **Display-only boundary** | System cannot cause physical harm through actuation | Human oversight inherently satisfied. Driver retains full authority. |
| **Advisory alerts with uncertainty** | Dead reckoning accuracy radius shown; weather data staleness visible | No false authority. System communicates its own limitations. |
| **Configurable providers** | Every data source is declared, swappable, documented | Transparency of inputs. No hidden data dependencies. |
| **Graceful degradation** | Loss of any single data source never produces a blank screen or misleading output | Robustness under failure conditions. |
| **Open source (BSD-3-Clause)** | Full code available for inspection and audit | Auditability without vendor dependency. |
