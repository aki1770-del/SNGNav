/// Driver-class profiles for differential UX defaults.
///
/// Today's `NavigationSafetyConfig` ships with one set of defaults that
/// fits a generic driver. Real driver populations are not generic — a
/// 70-year-old novice EV driver in rural Akita has different cognitive
/// load and reaction profile than a 40-year-old snow-zone commuter or
/// a 25-year-old urban novice. Per the V100 equal-dignity principle of
/// the Sakichi Principle Actuator unit, each driver-class deserves
/// defaults that fit them — the same loom should serve all generations,
/// but the loom's defaults should differentiate.
///
/// In v1 (this addition), the differentiation is at the threshold layer:
/// `NavigationSafetyConfig.forProfile(profile)` returns a config tuned
/// for that profile (info / warning / critical thresholds adjusted for
/// the profile's cognitive + experience + role profile).
///
/// In future revisions, the differentiation may extend to UX surfaces
/// (voice verbosity, modal interruption rules, glance-time targets) —
/// those defaults live in the consuming Flutter packages
/// (`navigation_safety`, `voice_guidance`) and would extend this enum's
/// semantic with their own profile-aware factory constructors.
library;

/// Driver-class profile for safety-config defaults.
///
/// Each profile encodes a coherent point in the cognitive-load /
/// experience / role / vehicle-type space. Apps should select one
/// profile per active driver context, not mix profiles. If none of
/// the profiles fit, fall back to [DriverProfile.snowZoneExperienced]
/// (the standard default profile) and document the gap.
enum DriverProfile {
  /// Older drivers (typically 65+) who may be commuting in rural areas
  /// where alternative transit is limited; often novice with EV or
  /// modern ADAS-equipped vehicles. Defaults: warn earlier on weather +
  /// visibility (more conservative), higher score floor for "safe"
  /// classification.
  ageingRural,

  /// Drivers experienced with snow-zone commute conditions (Hokkaido,
  /// Tohoku, mountain prefectures, snow-belt). Standard config defaults
  /// — they have the experience to interpret warnings as designed.
  /// This is the equivalent of the historical default profile.
  snowZoneExperienced,

  /// Newly-licensed or low-mileage drivers (typically first 3 years).
  /// Defaults: warn earlier on visibility (less low-visibility
  /// experience), higher score floor for "safe", explainer-friendly
  /// alert framing (the Flutter UX layer extends this; the core thresholds
  /// shift conservative).
  noviceUrban,

  /// Drivers operating commercially (taxi, freight, delivery,
  /// rideshare). Defaults: standard thresholds but optimized for
  /// minimum-distraction (the Flutter UX layer extends this with
  /// ultra-concise voice + brief modal alerts; thresholds themselves
  /// stay near-standard since these drivers are trained).
  professional,

  /// Drivers operating off-road in agricultural or forestry contexts.
  /// Defaults: standard thresholds; future revisions may add off-route-
  /// awareness semantics (don't fire "off route" alerts when the driver
  /// is intentionally on forest tracks). Today the threshold defaults
  /// match snowZoneExperienced; the off-route semantic is a downstream
  /// extension.
  agriculturalForestry,
}
