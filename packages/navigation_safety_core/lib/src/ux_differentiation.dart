/// Scaffolding for profile-aware UX differentiation in consuming
/// Flutter packages.
///
/// `navigation_safety_core` (Pure Dart) sets thresholds per
/// [DriverProfile]. **UX behavior** — voice-guidance verbosity,
/// modal-alert duration, glance-time targets, alert-explainer surfaces
/// — lives in consuming Flutter packages (`navigation_safety`,
/// `voice_guidance`) and is **not yet differentiated per profile** in
/// those packages.
///
/// Today an app developer who calls
/// `NavigationSafetyConfig.forProfile(DriverProfile.ageingRural)` and
/// integrates with `navigation_safety` gets EARLIER alerts but in the
/// SAME format as for `snowZoneExperienced`. Same voice verbosity,
/// modal duration, glance-time, explainer (none).
///
/// The format-mismatch can erase the earlier-alert benefit (Bian et al
/// PubMed 38669900 / Strayer-AAA PMC7283540).
///
/// This file ships an advisory stub for 0.3.0 — [assertUxDifferentiated]
/// is currently a no-op. The full implementation requires coordination
/// with consuming Flutter packages and lands in v0.4+. Calling it today
/// has no effect; it exists so that:
///
/// 1. Call sites can be wired now in app integration code, becoming
///    active when v0.4+ ships.
/// 2. The presence of the call documents the architectural intent at
///    the integration boundary.
/// 3. Consuming Flutter packages can register differentiators against
///    this hook without a public-API break.
///
/// See `KNOWN_LIMITATIONS.md` ("Threshold-only differentiation").
library;

import 'driver_profile.dart';

/// Advisory hook called by integration code to assert that the UX layer
/// has registered profile-aware differentiation for [profile].
///
/// **0.3.0:** no-op stub. Always returns without effect.
///
/// **v0.4+ (planned):** when no differentiator is registered for
/// [profile] in the consuming UX layer, this will emit a runtime
/// advisory (logger / debug-only assert) so the integrator notices the
/// gap before the driver does.
///
/// Calling this from integration code today is safe and forward-compatible.
void assertUxDifferentiated(DriverProfile profile) {
  // Intentional no-op for 0.3.0. See library doc.
}
