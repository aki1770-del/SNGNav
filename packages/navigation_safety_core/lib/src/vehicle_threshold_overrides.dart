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
/// `warningScoreFloor`), the critical thresholds, the info thresholds,
/// or the alerts-per-minute cap override.
///
/// **What the checks below cover, exactly: all ten threshold fields.**
/// `warningVisibilityMeters` and `warningTemperatureCelsius` may not
/// decrease. Every other field may not change, in either direction:
/// the three score floors, `criticalVisibilityMeters`,
/// `criticalTemperatureCelsius`, `infoVisibilityMeters`,
/// `infoTemperatureCelsius` and `alertsPerMinuteCapOverride`, where a
/// `null` cap must stay `null` and NaN counts as a change. A tighter
/// value is refused too, because it is not safe by construction: a
/// critical alert bypasses `AlertDensityThrottle`'s cap but still takes
/// a slot in its rolling window, info alerts take slots exactly as
/// warnings do, and a transform is never shown the driver's profile, so
/// a cap it writes is the same for every profile. Through 0.11.6 only
/// the two warning thresholds and the three score floors were checked.
///
/// ## Where the refusal lives — registration, not the drive path
///
/// The checks run at **registration** in
/// [VehicleThresholdOverrides.validated], which probes every
/// registered transform against a battery of baselines and throws
/// [ArgumentError] naming the token, every field the probe refused,
/// and the probe. That is the moment a mistake is actually made — an
/// integrator wires a registry once, at startup — and it is the only
/// moment at which throwing is safe.
///
/// [applyOverrideForToken] runs on the **drive path**, potentially
/// once per vehicle-bus frame while the car is moving. It runs the
/// same checks again and **never throws**. Each field is judged on its
/// own: a field that breaks its rule goes back to its `baseline` value,
/// every legal part of the override is kept, and each refused field is
/// reported to the `onRejected` handler passed to the constructor (or,
/// absent a handler, to [rejectionReporter], once per token, field and
/// invariant). A transform that throws has produced no config to
/// check, so it alone is refused whole and `baseline` is returned.
///
/// The history is worth keeping, because every earlier shape was
/// wrong, and the first two were wrong in opposite directions:
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
/// - 0.11.6 moved the refusal off the drive path, but refused a
///   violating override WHOLE there, and checked five of the ten
///   fields. A legal warning-floor raise was thrown away because a
///   DIFFERENT field was wrong, so that warning fired later than the
///   legal part of the override asked for; a changed critical
///   threshold, info threshold or cap was applied as written.
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
/// Every per-profile baseline carries a `null`
/// `alertsPerMinuteCapOverride`, but two of the probes carry a non-null
/// cap. A transform that rewrites a non-null cap, or drops it to `null`,
/// is therefore refused at registration, even if every config it meets
/// through this package's own factories carries a `null` cap.
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

/// Which load-bearing invariant a refused field of an override violated,
/// or that the transform itself threw.
enum VehicleOverrideInvariant {
  /// A warning threshold moved toward LATER warning. Vehicle-class
  /// overrides may only make the warning fire earlier.
  cautionAddOnly,

  /// A field a vehicle-class override may not change was changed, in
  /// either direction: a score floor (`safeScoreFloor`,
  /// `infoScoreFloor`, `warningScoreFloor`), a critical threshold
  /// (`criticalVisibilityMeters`, `criticalTemperatureCelsius`), an info
  /// threshold (`infoVisibilityMeters`, `infoTemperatureCelsius`) or
  /// `alertsPerMinuteCapOverride`. Vehicle-class tunes the two warning
  /// thresholds, and nothing else.
  ///
  /// Through 0.11.6 only the three score floors were checked and
  /// reported here. The critical thresholds, the info thresholds and the
  /// cap were added in 0.11.7 under this same value, not a new one, so
  /// an exhaustive `switch` over this enum keeps compiling; read
  /// [VehicleOverrideRejection.field] to tell them apart.
  severityNotProfile,

  /// The registered transform itself threw. Not an invariant on the
  /// produced config — there was no produced config. Reported through
  /// the same channel because the consequence for the driver is
  /// identical: the override cannot be applied.
  transformThrew,
}

/// One refusal of a vehicle-class override: a field that broke its
/// rule, or a transform that threw.
///
/// One call can produce several, one per refused field. Produced by
/// [VehicleThresholdOverrides.applyOverrideForToken] on the drive path,
/// where throwing would kill the caller's stream, and by
/// [VehicleThresholdOverrides.validated] at registration, where every
/// refusal a probe produced is described in the thrown [ArgumentError].
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

  /// The stack trace captured with [error], when [invariant] is
  /// [VehicleOverrideInvariant.transformThrew]; otherwise `null`.
  ///
  /// Its top frames are the integrator's own transform. Through 0.11.5
  /// the exception propagated and carried this trace with it; catching
  /// the exception without keeping the trace would take that line away
  /// from the developer who has to fix the transform.
  final StackTrace? stackTrace;

  const VehicleOverrideRejection({
    required this.token,
    required this.field,
    required this.invariant,
    this.baselineValue,
    this.rejectedValue,
    this.error,
    this.stackTrace,
  });

  /// Human-readable explanation: what was refused, and the rule it
  /// broke. [toString] adds what was applied instead.
  String get explanation {
    switch (invariant) {
      case VehicleOverrideInvariant.cautionAddOnly:
        return 'overrides["$token"] relaxed $field '
            '($baselineValue -> $rejectedValue); caution-add-only '
            'invariant violated -- a vehicle-class override may only '
            'make the warning fire EARLIER, never later';
      case VehicleOverrideInvariant.severityNotProfile:
        final rule = _mayNotChangeRule(field);
        if (rule == null) {
          return 'overrides["$token"] modified $field '
              '($baselineValue -> $rejectedValue); severity-not-profile '
              'invariant violated -- a vehicle-class override adjusts '
              'TIMING, never SEVERITY';
        }
        return 'overrides["$token"] changed $field '
            '($baselineValue -> $rejectedValue); $rule';
      case VehicleOverrideInvariant.transformThrew:
        return 'overrides["$token"] threw while transforming the '
            'baseline config: $error';
    }
  }

  /// The rule a changed critical threshold, info threshold or
  /// alerts-per-minute cap override broke, in the words a developer
  /// fixing the transform needs; `null` for any other field.
  ///
  /// These fields are reported as
  /// [VehicleOverrideInvariant.severityNotProfile] so that no enum value
  /// is added, but "adjusts TIMING, never SEVERITY" would not tell the
  /// developer which rule a refused cap broke. The score floors keep
  /// that wording: it is their rule.
  static String? _mayNotChangeRule(String field) => switch (field) {
    'criticalVisibilityMeters' || 'criticalTemperatureCelsius' =>
      'a vehicle-class override may not change a critical threshold, '
          'in either direction',
    'infoVisibilityMeters' || 'infoTemperatureCelsius' =>
      'a vehicle-class override may not change an info threshold, '
          'in either direction',
    'alertsPerMinuteCapOverride' =>
      'a vehicle-class override may not change the alerts-per-minute '
          "cap override: return the baseline's value, null included",
    _ => null,
  };

  /// One line, always: the explanation, what was applied instead, and
  /// for a transform that threw, its [stackTrace].
  ///
  /// Line breaks inside the error text and the stack trace are written
  /// as the two characters `\n`. A `FormatException` from `int.parse`,
  /// for example, prints its source and caret on following lines; left
  /// as they are, one report would become several stdout lines, and a
  /// log reader that takes one line per entry would split the stack
  /// trace away from the `navigation_safety_core:` prefix that says
  /// where it came from.
  @override
  String toString() {
    final trace = stackTrace;
    // Only a transform that threw is refused whole: there is no produced
    // config to check field by field. Any other rejection names one
    // field, and the rest of the override was judged on its own.
    final appliedInstead = invariant == VehicleOverrideInvariant.transformThrew
        ? 'the override was REFUSED WHOLE and the un-overridden baseline '
              'was applied instead'
        : 'this field alone went back to its un-overridden value, and the '
              'rest of the override was checked on its own';
    final text =
        'VehicleOverrideRejection($explanation; $appliedInstead)'
        '${trace == null ? '' : '; stack trace: $trace'}';
    return text.trimRight().replaceAll(_lineBreak, r'\n');
  }

  static final RegExp _lineBreak = RegExp(r'\r\n|\r|\n');
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
  /// both `>=` the baseline. Every other field MUST come back
  /// unchanged: the score-floor tiers, the critical thresholds, the info
  /// thresholds and `alertsPerMinuteCapOverride`, `null` included.
  final Map<
    String,
    NavigationSafetyConfig Function(NavigationSafetyConfig baseline)
  >
  overrides;

  /// Integrator-supplied sink for overrides refused on the drive path,
  /// passed as `onRejected` to any constructor.
  ///
  /// When non-null this handler replaces the default reporter and is
  /// called on EVERY rejection, with no de-duplication — the
  /// integrator owns the policy. A handler that throws is caught and
  /// swallowed: moving the throw from this package into the
  /// integrator's logger would kill the driver's advisory stream just
  /// as surely, and this method's whole contract is that it does not.
  ///
  /// Private on purpose. A public field is part of the class's implicit
  /// interface, so a class that `implements VehicleThresholdOverrides`
  /// would have to add it and would stop compiling on upgrade. Such a
  /// class supplies its own [applyOverrideForToken], which is the only
  /// reader of this field, so it would gain nothing for the break.
  final void Function(VehicleOverrideRejection rejection)? _onRejected;

  /// Construct a registry WITHOUT registration-time validation.
  ///
  /// `const`-capable, with the same positional signature since 0.9.0,
  /// so existing consumers keep compiling. Prefer
  /// [VehicleThresholdOverrides.validated]: a registry built this way
  /// defers every refusal to the drive path, where each refused field
  /// is reset and reported rather than fixed.
  const VehicleThresholdOverrides(
    this.overrides, {
    void Function(VehicleOverrideRejection rejection)? onRejected,
  }) : _onRejected = onRejected;

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
  /// `warningTemperatureCelsius`; changes any other threshold field, in
  /// either direction (`safeScoreFloor`, `infoScoreFloor`,
  /// `warningScoreFloor`, `criticalVisibilityMeters`,
  /// `criticalTemperatureCelsius`, `infoVisibilityMeters`,
  /// `infoTemperatureCelsius` or `alertsPerMinuteCapOverride`); or
  /// throws. The message names every field that probe refused, and the
  /// rule each one broke.
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
        final rejections = _evaluate(entry.key, entry.value, probe).rejections;
        if (rejections.isNotEmpty) {
          // Every field this probe refused is named, not only the first,
          // so one run shows the developer everything to fix.
          throw ArgumentError.value(
            entry.key,
            'overrides',
            'rejected at registration -- '
                '${rejections.map((r) => r.explanation).join('. ')}. '
                'Probe baseline: warningVisibilityMeters='
                '${probe.warningVisibilityMeters}, '
                'warningTemperatureCelsius='
                '${probe.warningTemperatureCelsius}, '
                'safeScoreFloor=${probe.safeScoreFloor}, '
                'alertsPerMinuteCapOverride='
                '${probe.alertsPerMinuteCapOverride}. '
                'Fix the transform: a vehicle-class override may only '
                'move the two warning thresholds, and only toward EARLIER '
                'warning; it may not change a score floor, a critical '
                'threshold, an info threshold or the alerts-per-minute cap '
                'override',
          );
        }
      }
    }
    final registry = VehicleThresholdOverrides(
      overrides,
      onRejected: onRejected,
    );
    _probedAtRegistration[registry] = true;
    return registry;
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
  /// Every field of the transform's result is judged on its own. A
  /// lowered warning threshold goes back to its [baseline] value, and a
  /// raised one is kept. Any change to any other field (a score floor,
  /// a critical threshold, an info threshold or
  /// `alertsPerMinuteCapOverride`, in either direction) goes back to its
  /// [baseline] value. Each refused field is reported as its own
  /// [VehicleOverrideRejection] to the `onRejected` handler passed to
  /// the constructor, or absent a handler to [rejectionReporter] once
  /// per token, field and invariant, so a handler can be called more
  /// than once for one call. The result is always a config that some
  /// fully legal transform could have produced. A transform that throws
  /// has produced nothing to check, so it is refused whole: [baseline]
  /// is returned and the error is reported.
  ///
  /// Refusing field by field, rather than refusing the whole override,
  /// is deliberate. Through 0.11.6 this method refused the whole
  /// override, on the reasoning that a transform with one wrong field
  /// has not earned trust on the others. For a warning floor that
  /// reasoning points the wrong way: returning [baseline] for a legal
  /// raise makes that warning fire LATER than the legal part of the
  /// override asked for, because a DIFFERENT field was wrong. Measured
  /// on 0.11.6 with the `ageingRural` profile, an override that raised
  /// `warningVisibilityMeters` by 50 m and lowered
  /// `warningTemperatureCelsius` by 1 °C came back with a 300 m
  /// visibility floor instead of 350 m. The defect stays visible either
  /// way: the refused field comes back at its baseline value, and every
  /// refused field is reported, not only the first.
  ///
  /// What it does NOT do is apply a relaxation, or any change to a
  /// field an override may not change. Silently accepting a relaxation
  /// is the 0.11.5 defect and is not available here.
  NavigationSafetyConfig applyOverrideForToken(
    String? token,
    NavigationSafetyConfig baseline,
  ) {
    if (token == null) return baseline;
    final transform = overrides[token];
    if (transform == null) return baseline;

    final outcome = _evaluate(token, transform, baseline);
    for (final rejection in outcome.rejections) {
      _report(rejection);
    }
    return outcome.config;
  }

  void _report(VehicleOverrideRejection rejection) {
    final handler = _onRejected;
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
  // ONE checker, used by BOTH `.validated()` (which throws when a probe
  // produces any rejection) and `applyOverrideForToken` (which reports
  // every rejection and returns the checked config). Registration and
  // drive-path cannot drift apart, because there is only one statement
  // of the invariant to drift from.

  static _OverrideOutcome _evaluate(
    String token,
    NavigationSafetyConfig Function(NavigationSafetyConfig) transform,
    NavigationSafetyConfig baseline,
  ) {
    final NavigationSafetyConfig adjusted;
    try {
      adjusted = transform(baseline);
    } catch (error, stackTrace) {
      // A transform that throws kills an `async*` caller exactly as
      // an invariant throw did. Guarded here rather than left to
      // escape; through 0.11.5 nothing covered this case at all.
      //
      // The stack trace is kept. Through 0.11.5 the exception
      // propagated, and its top frame was the integrator's own
      // transform; a catch that drops the trace takes that line away.
      //
      // There is no produced config to check field by field, so this
      // one case is still refused whole: the baseline is returned.
      return _OverrideOutcome(baseline, [
        VehicleOverrideRejection(
          token: token,
          field: '(transform)',
          invariant: VehicleOverrideInvariant.transformThrew,
          error: error,
          stackTrace: stackTrace,
        ),
      ]);
    }

    // Every field is checked, and every field that breaks its rule is
    // collected, not only the first. A refused field goes back to its
    // baseline value; every other field is judged on its own.
    final rejections = <VehicleOverrideRejection>[];

    // Caution-add-only invariant: the two warning thresholds may only
    // move toward earlier-warn (higher visibility floor, higher
    // temperature floor). Lower values mean later-warn = relaxing.
    //
    // Written as the NEGATION of the invariant, never as `<`. Both
    // fields are `int` today, so the two forms agree; if either is
    // ever widened to `double`, `a < b` silently stops rejecting NaN
    // while `!(a >= b)` keeps rejecting it.
    int warnNoLater(String field, int adjustedValue, int baselineValue) {
      if (!(adjustedValue >= baselineValue)) {
        rejections.add(
          VehicleOverrideRejection(
            token: token,
            field: field,
            invariant: VehicleOverrideInvariant.cautionAddOnly,
            baselineValue: baselineValue,
            rejectedValue: adjustedValue,
          ),
        );
        return baselineValue;
      }
      return adjustedValue;
    }

    // Every other threshold field may not change, in EITHER direction:
    // the three score floors, the two critical thresholds, the two info
    // thresholds and the alerts-per-minute cap override. A tighter value
    // is not safe by construction: a critical alert bypasses the density
    // cap but still takes a slot in its rolling window, info alerts
    // share the cap with warnings, and a transform is never shown the
    // driver's profile, so a cap it writes is the same for every driver
    // profile. Reported as
    // `severityNotProfile`: a new enum value would stop an integrator's
    // exhaustive `switch` from compiling on an in-range upgrade.
    //
    // `!=` is deliberate over `!(a == b)`: `NaN != anything` is true, so
    // a NaN is refused rather than waved through, and `null == null`
    // holds, so a null cap that stays null passes.
    void mayNotChange(String field, num? adjustedValue, num? baselineValue) {
      if (adjustedValue != baselineValue) {
        rejections.add(
          VehicleOverrideRejection(
            token: token,
            field: field,
            invariant: VehicleOverrideInvariant.severityNotProfile,
            baselineValue: baselineValue,
            rejectedValue: adjustedValue,
          ),
        );
      }
    }

    final warningVisibility = warnNoLater(
      'warningVisibilityMeters',
      adjusted.warningVisibilityMeters,
      baseline.warningVisibilityMeters,
    );
    final warningTemperature = warnNoLater(
      'warningTemperatureCelsius',
      adjusted.warningTemperatureCelsius,
      baseline.warningTemperatureCelsius,
    );
    mayNotChange(
      'safeScoreFloor',
      adjusted.safeScoreFloor,
      baseline.safeScoreFloor,
    );
    mayNotChange(
      'infoScoreFloor',
      adjusted.infoScoreFloor,
      baseline.infoScoreFloor,
    );
    mayNotChange(
      'warningScoreFloor',
      adjusted.warningScoreFloor,
      baseline.warningScoreFloor,
    );
    mayNotChange(
      'criticalVisibilityMeters',
      adjusted.criticalVisibilityMeters,
      baseline.criticalVisibilityMeters,
    );
    mayNotChange(
      'criticalTemperatureCelsius',
      adjusted.criticalTemperatureCelsius,
      baseline.criticalTemperatureCelsius,
    );
    mayNotChange(
      'infoVisibilityMeters',
      adjusted.infoVisibilityMeters,
      baseline.infoVisibilityMeters,
    );
    mayNotChange(
      'infoTemperatureCelsius',
      adjusted.infoTemperatureCelsius,
      baseline.infoTemperatureCelsius,
    );
    mayNotChange(
      'alertsPerMinuteCapOverride',
      adjusted.alertsPerMinuteCapOverride,
      baseline.alertsPerMinuteCapOverride,
    );

    if (rejections.isEmpty) return _OverrideOutcome(adjusted, rejections);

    // The legal part of the transform, and nothing else: each warning
    // floor at the higher of the transform's value and the baseline's,
    // every other field at the baseline's. It is always a config some
    // fully legal transform could have produced.
    //
    // This construction cannot throw. The constructor checks only the
    // three score floors, and all three are the baseline's, which
    // already passed those checks.
    return _OverrideOutcome(
      NavigationSafetyConfig(
        safeScoreFloor: baseline.safeScoreFloor,
        infoScoreFloor: baseline.infoScoreFloor,
        warningScoreFloor: baseline.warningScoreFloor,
        infoTemperatureCelsius: baseline.infoTemperatureCelsius,
        warningTemperatureCelsius: warningTemperature,
        criticalTemperatureCelsius: baseline.criticalTemperatureCelsius,
        infoVisibilityMeters: baseline.infoVisibilityMeters,
        warningVisibilityMeters: warningVisibility,
        criticalVisibilityMeters: baseline.criticalVisibilityMeters,
        alertsPerMinuteCapOverride: baseline.alertsPerMinuteCapOverride,
      ),
      rejections,
    );
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
  ///    baseline: a precipitation-history margin, and at speeds above
  ///    133 km/h a speed margin, push `warningVisibilityMeters` above
  ///    the profile's own value (measured: 359m for snowZoneExperienced
  ///    30 minutes after precipitation, from the precipitation margin
  ///    alone; at 80 km/h the speed margin adds nothing). A constant of,
  ///    say, 400m passes against every profile baseline, and 30 minutes
  ///    after precipitation it would make the warning later for three
  ///    profiles (`ageingRural` 538m, `noviceUrban` 574m,
  ///    `foreignTouristSnowZone` 717m). The HIGH probe is what refuses
  ///    it.
  ///
  /// The two synthetics also carry a non-null
  /// `alertsPerMinuteCapOverride`, HIGH above and LOW below every
  /// per-profile default cap. Every profile baseline carries a `null`
  /// cap, so without them a transform that rewrites only a non-null cap
  /// (scales it, clamps it, or drops it to `null`) would pass
  /// registration however the comparison is written. Carried by the two
  /// existing synthetics rather than by an extra probe, so
  /// [registrationProbeCount] is unchanged.
  static final List<NavigationSafetyConfig> _registrationProbes = [
    for (final profile in DriverProfile.values)
      NavigationSafetyConfig.forProfile(profile),
    // HIGH: above any plausible post-context threshold and cap.
    NavigationSafetyConfig(
      infoTemperatureCelsius: 20,
      warningTemperatureCelsius: 15,
      criticalTemperatureCelsius: 10,
      infoVisibilityMeters: 20000,
      warningVisibilityMeters: 5000,
      criticalVisibilityMeters: 2000,
      alertsPerMinuteCapOverride: 10.0,
    ),
    // LOW: below any plausible post-context threshold and cap.
    NavigationSafetyConfig(
      infoTemperatureCelsius: -25,
      warningTemperatureCelsius: -30,
      criticalTemperatureCelsius: -40,
      infoVisibilityMeters: 5,
      warningVisibilityMeters: 1,
      criticalVisibilityMeters: 0,
      alertsPerMinuteCapOverride: 0.5,
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
  /// supplied no `onRejected` handler.
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

  /// The default [rejectionReporter]: one line to stdout, prefixed
  /// `navigation_safety_core:`, carrying the transform's stack trace
  /// when it threw (see [VehicleOverrideRejection.toString]).
  static void printRejection(VehicleOverrideRejection rejection) {
    // ignore: avoid_print
    print('navigation_safety_core: $rejection');
  }

  static final Set<String> _reportedKeys = <String>{};

  /// Registries built by [VehicleThresholdOverrides.validated].
  ///
  /// An [Expando] rather than a field, for the same reason `_onRejected`
  /// is private: a public field would join the implicit interface and
  /// break every hand-written implementer. It keeps nothing alive, and
  /// a registry that never went through `validated` is simply absent.
  static final Expando<bool> _probedAtRegistration = Expando<bool>(
    'VehicleThresholdOverrides.validated',
  );

  /// Clear the once-per-token, field and invariant de-duplication state
  /// and restore [rejectionReporter] to [printRejection].
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

/// Registration status of a [VehicleThresholdOverrides] registry.
///
/// An extension, not a member, so it stays off the class's implicit
/// interface: a class that `implements VehicleThresholdOverrides`
/// compiles exactly as it did on 0.11.5.
extension VehicleThresholdOverridesRegistration on VehicleThresholdOverrides {
  /// Whether this registry was probed by
  /// [VehicleThresholdOverrides.validated] at construction.
  ///
  /// Informational. For a registry built with a
  /// [VehicleThresholdOverrides] constructor, the drive-path check in
  /// [VehicleThresholdOverrides.applyOverrideForToken] runs either way,
  /// because registration-time probing is a filter and not a proof (see
  /// library docs). `false` for a registry built with the plain
  /// constructor, and for any class that implements or extends
  /// [VehicleThresholdOverrides]; it never throws. A class that
  /// implements [VehicleThresholdOverrides], or extends it and replaces
  /// [VehicleThresholdOverrides.applyOverrideForToken], gets the
  /// drive-path check only if its own method returns what the one
  /// [VehicleThresholdOverrides] defines returns; otherwise what its
  /// method returns is applied unchecked. What its method throws is not
  /// caught.
  bool get validatedAtRegistration =>
      VehicleThresholdOverrides._probedAtRegistration[this] ?? false;
}

/// Result of evaluating one transform against one baseline: the config
/// to apply, and every rejection found on the way to it.
///
/// With no rejections, [config] is the transform's own result. With
/// field rejections, it is the legal part of that result. When the
/// transform threw, it is the baseline.
class _OverrideOutcome {
  final NavigationSafetyConfig config;
  final List<VehicleOverrideRejection> rejections;

  const _OverrideOutcome(this.config, this.rejections);
}
