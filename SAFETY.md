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
- Dead reckoning estimates degrade over time and are explicitly marked with
  increasing accuracy radius.

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
