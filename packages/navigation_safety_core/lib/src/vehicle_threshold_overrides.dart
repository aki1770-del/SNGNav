/// Vehicle-class threshold-override registry for caution-adding-only
/// adjustments to per-profile baseline thresholds.
///
/// `VehicleThresholdOverrides` is an integrator-supplied registry of
/// vehicle-class-token → threshold-transform-function mappings. It is
/// passed (optionally) to
/// [NavigationSafetyConfig.forProfileWithContext]. When the
/// [DrivingContext.vehicleClassToken] field matches a registered key,
/// the registered transform applies to the baseline-plus-context
/// threshold config produced by the factory's earlier stages.
///
/// **Caution-add-only invariant** (load-bearing): a registered
/// transform MUST produce a config whose `warningVisibilityMeters` is
/// `>=` the input baseline AND whose `warningTemperatureCelsius` is
/// `>=` the input baseline. (Both fields use the convention that
/// HIGHER values mean EARLIER warning — a longer visibility floor and
/// a higher temperature floor each fire the warning sooner.)
/// Registering a transform that relaxes either threshold is a
/// programmer error.
///
/// **Severity-not-profile invariant** (load-bearing): vehicle-class
/// adjustments tune TIMING (warn-earlier-floors) only. They MUST NOT
/// modify the score-floor tiers (`safeScoreFloor`, `infoScoreFloor`,
/// `warningScoreFloor`), the critical thresholds, or the
/// alerts-per-minute cap override.
///
/// ## Where the refusal lives — registration, not the drive path
///
/// Both invariants are refused at **registration** by
/// [VehicleThresholdOverrides.validated], which probes every
/// registered transform against a battery of baselines and throws
/// [ArgumentError] naming the token, the field and the probe. That is
/// the moment a mistake is actually made — an integrator wires a
/// registry once, at startup — and it is the only moment at which
/// throwing is safe.
///
/// [applyOverrideForToken] runs on the **drive path**, potentially
/// once per vehicle-bus frame while the car is moving. It re-checks
/// both invariants and **never throws**. A violating override is
/// refused whole: the method returns the unmodified `baseline` and
/// reports the rejection through [onRejected] (or, absent a handler,
/// [rejectionReporter], once per token+field).
///
/// The history is worth keeping, because both previous shapes were
/// wrong and they were wrong in opposite directions:
///
/// - Through 0.11.5 the guards were `assert`s. In a shipped integrator
///   build the assertion is elided, so a relaxing override was
///   silently ACCEPTED: the invariant was not merely unenforced, it
///   was inverted, and the driver got a LATE warning.
/// - The 2026-09-13 repair promoted them to unconditional `throw`s.
///   That refused the relaxation correctly but put the refusal on the
///   drive path — and this package's own
///   `example/can_bus_integration.dart` derives its config inside an
///   `await for` in an `async*` body, where an uncaught throw
///   TERMINATES the stream. Measured on a per-frame harness: 0 of 5
///   advisories delivered, nav surface dead. A guard that removes the
///   warning is not a stronger halt; it is the absence of one.
///
/// Hence the present shape, which is the poka-yoke ordering: the
/// mistake is refused where it is made (once, loudly, at
/// registration), and the place it is exercised (every frame) is
/// non-fatal but never silent.
///
/// ## Honest bound on registration-time validation
///
/// [VehicleThresholdOverrides.validated] probes each transform against
/// a finite battery of baselines (see [registrationProbeCount]). It is
/// a strong filter, **not a proof**: a transform that branches on a
/// field the battery does not vary, or that is discontinuous between
/// probe points, can pass registration and still violate an invariant
/// on a live config. That is exactly why [applyOverrideForToken] keeps
/// checking. Registration is the fixture; the drive-path check is the
/// last line, and it refuses rather than crashes.
///
/// **HER kei-car-at-65 cohort default**: the [withKeiCarDefault]
/// factory ships a built-in override for the `'kei-car'` token. The
/// override raises `warningVisibilityMeters` by `+50m` and
/// `warningTemperatureCelsius` by `+1°C` relative to the input
/// baseline. The deltas are **design-default hypotheses** pending
/// field-measurement validation (kei-car-specific visibility and
/// thermal-mass calibration not yet anchored in published literature
/// at the vehicle-class layer specifically; flagged in
/// `CHANGELOG.md` 0.9.0 entry). The factory routes through
/// [VehicleThresholdOverrides.validated], so the shipped default is
/// probed on every construction rather than trusted.
///
/// Typical wiring:
///
/// ```dart
/// // Use the built-in kei-car default (already validated):
/// final overrides = VehicleThresholdOverrides.withKeiCarDefault();
///
/// // Or compose a custom registry. Build it ONCE, at startup, with
/// // `.validated()` — never inside a per-frame loop. The transform
/// // receives the baseline config and returns a new config (no
/// // mutation):
/// final overrides = VehicleThresholdOverrides.validated({
///   'commercial-light': (base) => NavigationSafetyConfig(
///         safeScoreFloor: base.safeScoreFloor,
///         infoScoreFloor: base.infoScoreFloor,
///         warningScoreFloor: base.warningScoreFloor,
///         infoTemperatureCelsius: base.infoTemperatureCelsius,
///         warningTemperatureCelsius: base.warningTemperatureCelsius,
///         criticalTemperatureCelsius: base.criticalTemperatureCelsius,
///         infoVisibilityMeters: base.infoVisibilityMeters,
///         warningVisibilityMeters: base.warningVisibilityMeters + 30,
///         criticalVisibilityMeters: base.criticalVisibilityMeters,
///         alertsPerMinuteCapOverride: base.alertsPerMinuteCapOverride,
///       ),
/// });
/// ```
library;

import 'driver_profile.dart';
import 'navigation_safety_config.dart';

/// Which load-bearing invariant a rejected override violated.
enum VehicleOverrideInvariant {
  /// A warning threshold moved toward LATER warning. Vehicle-class
  /// overrides may only make the warning fire earlier.
  cautionAddOnly,

  /// A score-floor tier moved. Vehicle-class adjusts TIMING, never
  /// SEVERITY.
  severityNotProfile,

  /// The registered transform itself threw. Not an invariant on the
  /// produced config — there was no produced config. Reported through
  /// the same channel because the consequence for the driver is
  /// identical: the override cannot be applied.
  transformThrew,
}

/// A vehicle-class override that was refused rather than applied.
///
/// Produced by [VehicleThresholdOverrides.applyOverrideForToken] on
/// the drive path, where throwing would kill the caller's stream, and
/// by [VehicleThresholdOverrides.validated] at registration, where it
/// is wrapped in the thrown [ArgumentError].
class VehicleOverrideRejection {
  /// The registry key whose transform was refused.
  final String token;

  /// The config field that violated the invariant, or `'(transform)'`
  /// when the transform itself threw.
  final String field;

  /// The value the baseline carried. `null` for
  /// [VehicleOverrideInvariant.transformThrew].
  final num? baselineValue;

  /// The value the transform produced. `null` for
  /// [VehicleOverrideInvariant.transformThrew].
  final num? rejectedValue;

  /// Which invariant was violated.
  final VehicleOverrideInvariant invariant;

  /// The error the transform threw, when [invariant] is
  /// [VehicleOverrideInvariant.transformThrew]; otherwise `null`.
  final Object? error;

  const VehicleOverrideRejection({
    required this.token,
    required this.field,
    required this.invariant,
    this.baselineValue,
    this.rejectedValue,
    this.error,
  });

  /// Human-readable explanation, including what was applied instead.
  String get explanation {
    switch (invariant) {
      case VehicleOverrideInvariant.cautionAddOnly:
        return 'overrides["$token"] relaxed $field '
            '($baselineValue -> $rejectedValue); caution-add-only '
            'invariant violated -- a vehicle-class override may only '
            'make the warning fire EARLIER, never later';
      case VehicleOverrideInvariant.severityNotProfile:
        return 'overrides["$token"] modified $field '
            '($baselineValue -> $rejectedValue); severity-not-profile '
            'invariant violated -- a vehicle-class override adjusts '
            'TIMING, never SEVERITY';
      case VehicleOverrideInvariant.transformThrew:
        return 'overrides["$token"] threw while transforming the '
            'baseline config: $error';
    }
  }

  @override
  String toString() =>
      'VehicleOverrideRejection($explanation; the override was REFUSED '
      'WHOLE and the un-overridden baseline was applied instead)';
}

/// Registry of vehicle-class-token → threshold-transform-function
/// mappings consumed by
/// [NavigationSafetyConfig.forProfileWithContext]. See library
/// documentation for the caution-add-only invariant, the
/// severity-not-profile invariant, where each is refused, and the
/// HER kei-car-at-65 cohort default.
class VehicleThresholdOverrides {
  /// Map of vehicle-class token (e.g. `'kei-car'`) to a function that
  /// produces a caution-adding-only override of the supplied baseline
  /// config.
  ///
  /// The function receives the per-profile-baseline config (post
  /// live-context adjustment) and MUST return a config whose
  /// `warningVisibilityMeters` and `warningTemperatureCelsius` are
  /// both `>=` the baseline. Score-floor tiers and the critical
  /// thresholds MUST be preserved.
  final Map<
    String,
    NavigationSafetyConfig Function(NavigationSafetyConfig baseline)
  >
  overrides;

  /// Integrator-supplied sink for overrides refused on the drive path.
  ///
  /// When non-null this handler replaces the default reporter and is
  /// called on EVERY rejection, with no de-duplication — the
  /// integrator owns the policy. A handler that throws is caught and
  /// swallowed: moving the throw from this package into the
  /// integrator's logger would kill the driver's advisory stream just
  /// as surely, and this method's whole contract is that it does not.
  final void Function(VehicleOverrideRejection rejection)? onRejected;

  /// Whether this registry was probed by
  /// [VehicleThresholdOverrides.validated] at construction.
  ///
  /// Informational. The drive-path check in [applyOverrideForToken]
  /// runs either way, because registration-time probing is a filter
  /// and not a proof (see library docs).
  final bool validatedAtRegistration;

  /// Construct a registry WITHOUT registration-time validation.
  ///
  /// `const`-capable and unchanged since 0.9.0, so existing consumers
  /// keep compiling. Prefer [VehicleThresholdOverrides.validated]: a
  /// registry built this way defers every refusal to the drive path,
  /// where the override is discarded and reported rather than fixed.
  const VehicleThresholdOverrides(this.overrides, {this.onRejected})
    : validatedAtRegistration = false;

  const VehicleThresholdOverrides._validated(this.overrides, {this.onRejected})
    : validatedAtRegistration = true;

  /// Construct a registry, probing every registered transform against
  /// a battery of baselines FIRST and throwing [ArgumentError] if any
  /// probe violates an invariant.
  ///
  /// This is where a vehicle-class override should be refused: a
  /// registry is wired once, at startup, by a developer who can read
  /// the stack trace and fix the transform. Refusing here leaves
  /// [applyOverrideForToken] — which may run once per vehicle-bus
  /// frame, mid-drive — free of any throw.
  ///
  /// Throws [ArgumentError] when, for ANY probe baseline, a registered
  /// transform lowers `warningVisibilityMeters` or
  /// `warningTemperatureCelsius`, changes `safeScoreFloor`,
  /// `infoScoreFloor` or `warningScoreFloor`, or throws.
  ///
  /// **Bound**: the probe battery is finite (see
  /// [registrationProbeCount]). Passing validation is strong evidence,
  /// not a guarantee, for transforms that branch on unprobed fields.
  factory VehicleThresholdOverrides.validated(
    Map<String, NavigationSafetyConfig Function(NavigationSafetyConfig)>
    overrides, {
    void Function(VehicleOverrideRejection rejection)? onRejected,
  }) {
    for (final entry in overrides.entries) {
      for (final probe in _registrationProbes) {
        final rejection = _evaluate(entry.key, entry.value, probe).rejection;
        if (rejection != null) {
          throw ArgumentError.value(
            entry.key,
            'overrides',
            'rejected at registration -- ${rejection.explanation}. '
                'Probe baseline: warningVisibilityMeters='
                '${probe.warningVisibilityMeters}, '
                'warningTemperatureCelsius='
                '${probe.warningTemperatureCelsius}, '
                'safeScoreFloor=${probe.safeScoreFloor}. '
                'Fix the transform: a vehicle-class override may only '
                'move warning thresholds toward EARLIER warning, and '
                'must preserve every score floor',
          );
        }
      }
    }
    return VehicleThresholdOverrides._validated(
      overrides,
      onRejected: onRejected,
    );
  }

  /// Construct a registry pre-loaded with the HER kei-car-at-65
  /// cohort default override. The default keys on the `'kei-car'`
  /// token and applies caution-adding-only deltas:
  ///
  /// - `warningVisibilityMeters` += 50m (kei-car windscreen +
  ///   headlight cluster smaller than compact-sedan baseline; warn
  ///   earlier on visibility loss to preserve reaction-margin)
  /// - `warningTemperatureCelsius` += 1°C (kei-car cabin lower
  ///   thermal mass + faster glass condensation in winter; warn
  ///   earlier on cold-temperature transitions)
  ///
  /// Both deltas are **design-default hypotheses** pending
  /// field-measurement validation; see `CHANGELOG.md` 0.9.0 entry
  /// for the UNVERIFIED-magnitude flag and the
  /// kei-car-class-calibration-validation follow-up note.
  ///
  /// Routes through [VehicleThresholdOverrides.validated], so the
  /// shipped default is probed on every construction. We do not ask
  /// integrators to validate what we decline to validate ourselves.
  ///
  /// To compose with additional integrator-defined overrides, build
  /// the registry directly via [VehicleThresholdOverrides.validated]
  /// and merge.
  factory VehicleThresholdOverrides.withKeiCarDefault({
    void Function(VehicleOverrideRejection rejection)? onRejected,
  }) {
    return VehicleThresholdOverrides.validated({
      'kei-car': _keiCarOverride,
    }, onRejected: onRejected);
  }

  /// Apply the override registered for [token] to [baseline], or
  /// return [baseline] unchanged if [token] is `null` or unregistered.
  ///
  /// **This method never throws.** It runs on the drive path — a
  /// caller may derive a config once per vehicle-bus frame while the
  /// car is moving, and in an `async*` body an uncaught throw
  /// terminates the stream, taking the driver's advisories with it.
  ///
  /// When the registered transform violates the caution-add-only or
  /// severity-not-profile invariant, or throws, the override is
  /// **refused whole**: this method returns the unmodified [baseline]
  /// and reports a [VehicleOverrideRejection] through [onRejected], or
  /// absent a handler through [rejectionReporter] once per
  /// token+field+invariant.
  ///
  /// Refusing WHOLE rather than repairing field-by-field is deliberate
  /// and is the safer of the two:
  ///
  /// - [baseline] is the config this package designed and tested for
  ///   that profile and context. It is exactly what an integrator who
  ///   registered no override receives, so it is never itself unsafe.
  /// - A transform that got one field wrong has not earned trust on
  ///   the others.
  /// - Half-applying a broken override produces a config nobody
  ///   designed and makes the defect HARDER to notice: the behaviour
  ///   looks nearly right and the report becomes the only signal.
  ///   A whole refusal is a larger, more visible delta — detected
  ///   instantly beats silently half-repaired.
  ///
  /// What it does NOT do is apply the relaxation. Silently accepting
  /// it is the 0.11.5 defect and is not available here.
  NavigationSafetyConfig applyOverrideForToken(
    String? token,
    NavigationSafetyConfig baseline,
  ) {
    if (token == null) return baseline;
    final transform = overrides[token];
    if (transform == null) return baseline;

    final outcome = _evaluate(token, transform, baseline);
    final rejection = outcome.rejection;
    if (rejection != null) {
      _report(rejection);
      return baseline;
    }
    // A null rejection guarantees a non-null adjusted config; the
    // fallback keeps this method total rather than asserting it.
    return outcome.adjusted ?? baseline;
  }

  void _report(VehicleOverrideRejection rejection) {
    final handler = onRejected;
    if (handler != null) {
      try {
        handler(rejection);
      } catch (_) {
        // An integrator logger that throws must not do what the
        // throw we removed was doing.
      }
      return;
    }
    final key = '${rejection.token}/${rejection.field}/${rejection.invariant}';
    if (!_reportedKeys.add(key)) return;
    try {
      rejectionReporter(rejection);
    } catch (_) {
      // Same reason.
    }
  }

  // ── Shared invariant evaluation ────────────────────────────────────
  //
  // ONE checker, used by BOTH `.validated()` (which throws on the
  // returned rejection) and `applyOverrideForToken` (which reports it
  // and returns the baseline). Registration and drive-path cannot
  // drift apart, because there is only one statement of the
  // invariant to drift from.

  static _OverrideOutcome _evaluate(
    String token,
    NavigationSafetyConfig Function(NavigationSafetyConfig) transform,
    NavigationSafetyConfig baseline,
  ) {
    final NavigationSafetyConfig adjusted;
    try {
      adjusted = transform(baseline);
    } catch (error) {
      // A transform that throws kills an `async*` caller exactly as
      // an invariant throw did. Guarded here rather than left to
      // escape; through 0.11.5 nothing covered this case at all.
      return _OverrideOutcome.rejected(
        VehicleOverrideRejection(
          token: token,
          field: '(transform)',
          invariant: VehicleOverrideInvariant.transformThrew,
          error: error,
        ),
      );
    }

    // Caution-add-only invariant: warning thresholds may only move
    // toward earlier-warn (higher visibility floor, higher
    // temperature floor). Lower values mean later-warn = relaxing.
    //
    // Each is written as the NEGATION of the invariant, never as `<`.
    // Both fields are `int` today, so the two forms agree; if either
    // is ever widened to `double`, `a < b` silently stops rejecting
    // NaN while `!(a >= b)` keeps rejecting it.
    if (!(adjusted.warningVisibilityMeters >=
        baseline.warningVisibilityMeters)) {
      return _OverrideOutcome.rejected(
        VehicleOverrideRejection(
          token: token,
          field: 'warningVisibilityMeters',
          invariant: VehicleOverrideInvariant.cautionAddOnly,
          baselineValue: baseline.warningVisibilityMeters,
          rejectedValue: adjusted.warningVisibilityMeters,
        ),
      );
    }
    if (!(adjusted.warningTemperatureCelsius >=
        baseline.warningTemperatureCelsius)) {
      return _OverrideOutcome.rejected(
        VehicleOverrideRejection(
          token: token,
          field: 'warningTemperatureCelsius',
          invariant: VehicleOverrideInvariant.cautionAddOnly,
          baselineValue: baseline.warningTemperatureCelsius,
          rejectedValue: adjusted.warningTemperatureCelsius,
        ),
      );
    }

    // Severity-not-profile invariant: vehicle-class adjusts TIMING,
    // never SEVERITY tiers. Score floors MUST be preserved.
    //
    // `!=` is deliberate over `!(a == b)`: these three are `double`,
    // and `NaN != anything` is true, so a NaN floor is refused rather
    // than waved through.
    if (adjusted.safeScoreFloor != baseline.safeScoreFloor) {
      return _OverrideOutcome.rejected(
        VehicleOverrideRejection(
          token: token,
          field: 'safeScoreFloor',
          invariant: VehicleOverrideInvariant.severityNotProfile,
          baselineValue: baseline.safeScoreFloor,
          rejectedValue: adjusted.safeScoreFloor,
        ),
      );
    }
    if (adjusted.infoScoreFloor != baseline.infoScoreFloor) {
      return _OverrideOutcome.rejected(
        VehicleOverrideRejection(
          token: token,
          field: 'infoScoreFloor',
          invariant: VehicleOverrideInvariant.severityNotProfile,
          baselineValue: baseline.infoScoreFloor,
          rejectedValue: adjusted.infoScoreFloor,
        ),
      );
    }
    if (adjusted.warningScoreFloor != baseline.warningScoreFloor) {
      return _OverrideOutcome.rejected(
        VehicleOverrideRejection(
          token: token,
          field: 'warningScoreFloor',
          invariant: VehicleOverrideInvariant.severityNotProfile,
          baselineValue: baseline.warningScoreFloor,
          rejectedValue: adjusted.warningScoreFloor,
        ),
      );
    }

    return _OverrideOutcome.accepted(adjusted);
  }

  // ── Registration probe battery ─────────────────────────────────────

  /// Baselines every transform is probed against by
  /// [VehicleThresholdOverrides.validated].
  ///
  /// Two groups, for two different mistakes:
  ///
  /// 1. Every [DriverProfile]'s designed baseline — catches a
  ///    transform that is only correct for the profile its author
  ///    happened to test.
  /// 2. A HIGH and a LOW synthetic — catches a transform that returns
  ///    a CONSTANT threshold. The live config reaching
  ///    [applyOverrideForToken] is post-context, not the raw profile
  ///    baseline: speed and precipitation-history margins push
  ///    `warningVisibilityMeters` well above every profile value
  ///    (measured: 359m for snowZoneExperienced at 80 km/h). A
  ///    constant of, say, 400m passes against every profile baseline
  ///    and relaxes in the car. The HIGH probe is what refuses it.
  static final List<NavigationSafetyConfig> _registrationProbes = [
    for (final profile in DriverProfile.values)
      NavigationSafetyConfig.forProfile(profile),
    // HIGH: above any plausible post-context threshold.
    NavigationSafetyConfig(
      infoTemperatureCelsius: 20,
      warningTemperatureCelsius: 15,
      criticalTemperatureCelsius: 10,
      infoVisibilityMeters: 20000,
      warningVisibilityMeters: 5000,
      criticalVisibilityMeters: 2000,
    ),
    // LOW: below any plausible post-context threshold.
    NavigationSafetyConfig(
      infoTemperatureCelsius: -25,
      warningTemperatureCelsius: -30,
      criticalTemperatureCelsius: -40,
      infoVisibilityMeters: 5,
      warningVisibilityMeters: 1,
      criticalVisibilityMeters: 0,
    ),
  ];

  /// How many baselines [VehicleThresholdOverrides.validated] probes
  /// each transform against.
  ///
  /// Exposed so the bound on registration-time validation is a number
  /// an integrator can read, not an adjective in a doc comment.
  static int get registrationProbeCount => _registrationProbes.length;

  // ── Default rejection reporting ────────────────────────────────────

  /// Process-wide sink for drive-path rejections on registries that
  /// supplied no [onRejected] handler.
  ///
  /// Defaults to [printRejection]. Deliberately `print`-based and NOT
  /// `dart:developer`'s `log`: measured 2026-09-13 on Dart 3.11.1,
  /// `developer.log` emits nothing under either `dart run` or
  /// `dart compile exe` without an attached VM service. Routing the
  /// report there would have made it silent in precisely the shipped
  /// build where it matters — which is the 0.11.5 elided-assert defect
  /// wearing a different hat.
  ///
  /// Assignable so an integrator (or a test) can redirect it without
  /// touching each registry.
  static void Function(VehicleOverrideRejection rejection) rejectionReporter =
      printRejection;

  /// The default [rejectionReporter]: one line to stdout.
  static void printRejection(VehicleOverrideRejection rejection) {
    // ignore: avoid_print
    print('navigation_safety_core: $rejection');
  }

  static final Set<String> _reportedKeys = <String>{};

  /// Clear the once-per-token+field de-duplication state and restore
  /// [rejectionReporter] to [printRejection].
  ///
  /// Intended for tests, which need each case to observe its own
  /// report. De-duplication exists because the drive path may run at
  /// vehicle-bus frame rate, and a broken override would otherwise
  /// flood an IVI log for the whole journey.
  static void resetRejectionReporting() {
    _reportedKeys.clear();
    rejectionReporter = printRejection;
  }

  /// Built-in HER kei-car-at-65 default override. See
  /// [VehicleThresholdOverrides.withKeiCarDefault] for delta semantics
  /// and the design-default-hypothesis flag.
  static NavigationSafetyConfig _keiCarOverride(
    NavigationSafetyConfig baseline,
  ) {
    return NavigationSafetyConfig(
      safeScoreFloor: baseline.safeScoreFloor,
      infoScoreFloor: baseline.infoScoreFloor,
      warningScoreFloor: baseline.warningScoreFloor,
      infoTemperatureCelsius: baseline.infoTemperatureCelsius,
      warningTemperatureCelsius: baseline.warningTemperatureCelsius + 1,
      criticalTemperatureCelsius: baseline.criticalTemperatureCelsius,
      infoVisibilityMeters: baseline.infoVisibilityMeters,
      warningVisibilityMeters: baseline.warningVisibilityMeters + 50,
      criticalVisibilityMeters: baseline.criticalVisibilityMeters,
      alertsPerMinuteCapOverride: baseline.alertsPerMinuteCapOverride,
    );
  }
}

/// Result of evaluating one transform against one baseline: either an
/// accepted config or the rejection that refused it, never both.
class _OverrideOutcome {
  final NavigationSafetyConfig? adjusted;
  final VehicleOverrideRejection? rejection;

  const _OverrideOutcome.accepted(NavigationSafetyConfig this.adjusted)
    : rejection = null;

  const _OverrideOutcome.rejected(VehicleOverrideRejection this.rejection)
    : adjusted = null;
}
