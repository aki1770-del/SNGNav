/// Per-profile modal-alert duration primitive.
///
/// The threshold layer (`navigation_safety_core`) decides whether to
/// fire and at what severity. The voice layer (`voice_guidance`) decides
/// the speaking-pace. This primitive decides **how long the modal
/// alert remains on screen** before consuming apps can choose to
/// auto-dismiss it.
///
/// One product, three axes: alert-magnitude × duration × pace. Bian
/// et al (PubMed 38669900) document that earlier-or-louder alerts
/// without matching display duration produce the same comprehension
/// gap as no per-profile differentiation at all — the message arrives,
/// but the slower-cognitive-load profiles cannot read-and-process it
/// before it disappears, erasing the threshold-layer benefit.
///
/// This primitive is **advisory not control**: it returns a `Duration`
/// the consuming app uses to time its own auto-dismiss policy. The
/// package emits no actuator signal and mounts no auto-dismiss timer
/// itself — the integrator owns the dismiss surface. Per AAA Article
/// 17 (β) ASIL-QM advisory class.
///
/// **Driver-facing loom**: modal alert stays on screen long enough for
/// each driver-class to read it without rushing.
library;

import 'package:navigation_safety_core/navigation_safety_core.dart';

/// Base modal-alert display duration (engine-base; profile-neutral).
///
/// Five seconds is the conservative engine-base anchor: long enough to
/// read a single conservative advisory line, short enough to avoid
/// stale alerts lingering after the condition has passed. Per-profile
/// multipliers tune this by `DriverProfile`; see [kModalAlertDurationMultiplierByProfile].
const Duration kModalAlertDurationBase = Duration(seconds: 5);

/// Per-profile multipliers on top of [kModalAlertDurationBase].
///
/// **Source anchor**: Bian et al PubMed 38669900 (alert-magnitude ×
/// duration as a single product); 100-insights #56 substrate; AAA
/// spawn -50 dignity-anchor for per-profile rendering discipline.
///
/// **Conservative-only direction**: multipliers are 1.0 or larger;
/// no profile gets a SHORTER display duration than engine-base. The
/// shortest-duration profiles are the ones with the highest cognitive
/// budget for the read-task; lengthening for slower-cognitive-load
/// profiles is the safe direction.
///
/// Profile design rules:
/// - `snowZoneExperienced`, `professional` (× 1.0) — engine-base; the
///   profile baseline is highest cognitive budget for road-state-class
///   advisories; lengthening adds clutter without adding comprehension.
/// - `agriculturalForestry` (× 1.2) — slight lengthening; off-road
///   cadence is slower than highway, so the on-screen line can dwell
///   slightly longer without becoming stale.
/// - `noviceUrban` (× 1.3) — explicit lengthening; less low-vis /
///   icy-road experience, so the read-and-process step takes longer.
/// - `ageingRural`, `foreignTouristSnowZone` (× 1.5) — strong
///   lengthening; ageingRural has age-related read-pace differences
///   per JAF older-driver materials; foreignTouristSnowZone may be
///   reading a non-native-language phrase under conditions they have
///   never trained for.
const Map<DriverProfile, double> kModalAlertDurationMultiplierByProfile =
    <DriverProfile, double>{
      DriverProfile.snowZoneExperienced: 1.0,
      DriverProfile.professional: 1.0,
      DriverProfile.agriculturalForestry: 1.2,
      DriverProfile.noviceUrban: 1.3,
      DriverProfile.ageingRural: 1.5,
      DriverProfile.foreignTouristSnowZone: 1.5,
    };

/// Modal-alert display duration for [profile].
///
/// Returns [kModalAlertDurationBase] multiplied by the per-profile
/// factor in [kModalAlertDurationMultiplierByProfile]. The integrator
/// passes the returned `Duration` to whatever auto-dismiss timer
/// surface the integrator owns; the package mounts no timer itself.
///
/// Examples (engine-base = 5 seconds):
/// - `snowZoneExperienced` -> 5.0 seconds
/// - `professional`        -> 5.0 seconds
/// - `agriculturalForestry`-> 6.0 seconds
/// - `noviceUrban`         -> 6.5 seconds
/// - `ageingRural`         -> 7.5 seconds
/// - `foreignTouristSnowZone` -> 7.5 seconds
///
/// **Conservative-only**: integrators may dwell the alert LONGER than
/// the returned duration if their HMI surface gives evidence of
/// post-display benefit, but should not dwell SHORTER — the per-profile
/// multiplier reflects the conservative read-and-process budget for
/// the slowest reasonable case in that profile-class.
///
/// **Severity-not-profile invariant preserved**: severity decides
/// whether/what to display; profile only decides how long the display
/// dwells. Severity-class is upstream of duration; severity gates the
/// alert at the `navigation_safety_core` boundary.
Duration modalAlertDurationFor(DriverProfile profile) {
  final multiplier = kModalAlertDurationMultiplierByProfile[profile];
  if (multiplier == null) {
    // All current DriverProfile values are mapped. If a future profile
    // is added without a multiplier entry, fall back to engine-base
    // rather than throwing — display-duration is advisory; missing
    // entry should not crash the consuming app.
    return kModalAlertDurationBase;
  }
  final scaledMicros = (kModalAlertDurationBase.inMicroseconds * multiplier)
      .round();
  return Duration(microseconds: scaledMicros);
}
