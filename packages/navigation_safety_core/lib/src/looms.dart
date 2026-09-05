/// Runtime looms — guards that run INSIDE the consuming app to catch
/// alerting failure modes at the package boundary.
///
/// A *loom*, in this package, is a single guard that catches one named
/// failure mode. The word is this package's own vocabulary and appears
/// in its public API (`LoomFitTelemetry`, `LoomFitOutcome`); it carries
/// no meaning beyond "one guard, one failure mode".
///
/// Each loom in this barrel documents, in its class-level doc comment,
/// the failure mode it prevents, the evidence its behaviour is anchored
/// in, and the boundary it keeps between this package and the
/// integrating application.
///
/// These are *runtime* guards: the consuming app constructs and owns
/// them, and they run in-process on the app's own data. They are
/// advisory-only — none of them actuates the vehicle, performs I/O, or
/// depends on Flutter.
library;

export 'alert_density_throttle.dart';
export 'alert_explainer.dart';
export 'loom_fit_telemetry.dart';
