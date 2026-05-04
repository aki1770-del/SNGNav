/// Profile-aware UX differentiation registration + assertion.
///
/// `navigation_safety_core` (Pure Dart) sets thresholds per
/// [DriverProfile]. **UX behavior** — voice-guidance verbosity,
/// modal-alert duration, glance-time targets, alert-explainer surfaces
/// — lives in consuming Flutter packages (`navigation_safety`,
/// `voice_guidance`) and historically was **not differentiated per
/// profile** in those packages.
///
/// An app developer who calls
/// `NavigationSafetyConfig.forProfile(DriverProfile.ageingRural)` and
/// integrates with `navigation_safety` historically got EARLIER alerts
/// but in the SAME format as for `snowZoneExperienced`. Same voice
/// verbosity, modal duration, glance-time, explainer (none).
///
/// The format-mismatch can erase the earlier-alert benefit (Bian et al
/// PubMed 38669900 / Strayer-AAA PMC7283540).
///
/// This file ships the activated runtime hook for 0.7.0:
///
/// 1. Consuming UX layers register a differentiator per [DriverProfile]
///    via [registerUxDifferentiator].
/// 2. Integration code calls [assertUxDifferentiated] at composition
///    time. In a debug build, an unregistered profile throws an
///    [AssertionError] with an actionable message naming the profile +
///    naming where to register.
/// 3. In a release build, the assertion is a no-op (Dart `assert` is
///    erased in release), so a misconfiguration never crashes a
///    driver-facing build — it surfaces during integration testing.
///
/// Driver-facing loom (per the package's architectural anchor):
/// *"alert that arrives in time + makes sense + is calm enough to
/// ignore safely."* The threshold layer ensures **arrives in time**;
/// the per-profile UX-differentiation layer ensures **makes sense +
/// calm enough to ignore safely** for the registered profile. Without
/// registration, the second half of the architectural anchor is
/// silently dropped — this hook makes that silent drop audible to the
/// integrator before the driver sees it.
library;

import 'driver_profile.dart';

/// Marker tag describing the registered UX-differentiator for a
/// profile. Consumers pick a tag scheme; the hook does not interpret
/// the tag's contents — it only checks presence.
///
/// Recommended convention: namespace the tag with the consuming
/// package name (e.g. `'voice_guidance:speakingRate-by-profile'`,
/// `'navigation_safety:modalDuration-by-profile'`,
/// `'navigation_safety:explainer-by-profile'`).
typedef UxDifferentiatorTag = String;

/// In-memory registry of UX differentiators keyed by [DriverProfile].
/// Exposed for testability via [debugClearUxDifferentiatorRegistry].
final Map<DriverProfile, Set<UxDifferentiatorTag>> _registry =
    <DriverProfile, Set<UxDifferentiatorTag>>{};

/// Registers a UX differentiator for [profile] under the descriptive
/// [tag]. Idempotent: registering the same tag twice is a no-op.
///
/// Consuming Flutter packages call this at app-bootstrap time. The
/// registration tells [assertUxDifferentiated] that the consuming UX
/// layer has wired profile-aware behavior for [profile] under [tag].
///
/// **What to register**, by package:
///
/// - `voice_guidance` registers per-profile speakingRate / verbosity
///   under tags like `'voice_guidance:speakingRate'`.
/// - `navigation_safety` registers per-profile modal-alert duration +
///   alert-explainer surfaces under tags like
///   `'navigation_safety:modalDuration'`.
///
/// **What does not need registering**: anything purely threshold-class
/// (covered by `NavigationSafetyConfig.forProfile`).
void registerUxDifferentiator(DriverProfile profile, UxDifferentiatorTag tag) {
  _registry.putIfAbsent(profile, () => <UxDifferentiatorTag>{}).add(tag);
}

/// Returns the set of registered tags for [profile]. Empty set means
/// no UX-differentiator is registered for that profile.
Set<UxDifferentiatorTag> registeredUxDifferentiators(DriverProfile profile) =>
    Set<UxDifferentiatorTag>.unmodifiable(
      _registry[profile] ?? const <UxDifferentiatorTag>{},
    );

/// Test-only helper: clears the registry. Production code does not
/// need this; tests use it to isolate cases. Tagged `debug` because
/// it is intended for tests, not for runtime mutation under driver
/// load.
void debugClearUxDifferentiatorRegistry() {
  _registry.clear();
}

/// Asserts that the consuming UX layer has registered profile-aware
/// differentiation for [profile].
///
/// **Behavior**:
///
/// - **Debug build**: if no UX differentiator is registered for
///   [profile], throws [AssertionError] with an actionable message
///   naming the profile and the consuming-package registration sites.
/// - **Release build**: no-op (Dart `assert` is erased). Production
///   driver-facing builds never crash on a misconfigured profile;
///   the gap surfaces during integration testing instead.
///
/// **When to call**: at composition time in app bootstrap, after the
/// consuming UX layers have run their registration phase but before
/// the first navigation session begins. One call per profile the app
/// supports (or a loop over all profiles the app exposes to drivers).
///
/// **What this catches**: an integrator who wires
/// `NavigationSafetyConfig.forProfile(DriverProfile.foreignTouristSnowZone)`
/// but forgets to extend `voice_guidance` with the
/// foreignTouristSnowZone speakingRate — earlier thresholds fire but
/// the voice line is delivered at a rate the foreign-tourist driver
/// cannot follow. Without this assertion, the integrator does not
/// notice; the driver in unexpected snow does, the hard way.
void assertUxDifferentiated(DriverProfile profile) {
  assert(() {
    final tags = _registry[profile];
    if (tags == null || tags.isEmpty) {
      throw AssertionError(
        'No UX differentiator registered for DriverProfile.${profile.name}. '
        'Register one at app-bootstrap time via '
        'registerUxDifferentiator(${profile.name}, '
        "'<package>:<dimension>') for each consuming UX layer "
        '(voice_guidance speakingRate, navigation_safety modalDuration, '
        'navigation_safety explainer). Without per-profile UX '
        'differentiation, the earlier-threshold benefit can be erased '
        'by a UX surface that does not match the profile (Bian et al '
        'PubMed 38669900 / Strayer-AAA PMC7283540).',
      );
    }
    return true;
  }());
}
