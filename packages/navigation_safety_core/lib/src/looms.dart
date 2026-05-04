/// Runtime looms — guards that fire INSIDE the consuming app to catch
/// failure modes the Loom Protocol vocabulary names.
///
/// Each loom in this barrel carries a 3-slot vision attribution
/// (`sakichi_vision_id` / `method_vision_ids` / `stance_vision_ids`)
/// in its class-level doc-comment, matching the convention documented
/// in the SPA AI loom-authoring guide:
/// https://github.com/aki1770-del/spa-ai/blob/main/docs/loom_authoring_guide.md
///
/// SPA AI ships *build-time* looms in Python (one Jidoka halt per loom,
/// installed via PR). `navigation_safety_core` ships *runtime* looms in
/// Pure Dart (one Jidoka halt per loom, instantiated by the consuming
/// app). Both sets share the same Loom Protocol vocabulary; the 3-slot
/// vision attribution is the cross-language binding.
///
/// See `LOOMS.md` at the package root for the cross-reference table
/// and per-loom vision attribution.
library;

export 'alert_density_throttle.dart';
export 'alert_explainer.dart';
export 'loom_fit_telemetry.dart';
