/// Expandable sheet widget that surfaces an `AlertExplainer` at two
/// levels of detail (collapsed source-line / expanded full attribution).
///
/// Why this exists:
///
/// `navigation_safety_core` ships `AlertExplainer.forConditionAndProfile`
/// which returns the per-(condition, profile) action string + verbosity
/// + locale + source attribution. That tuple is a substrate; integrators
/// historically rendered just the `action` string and absorbed the
/// attribution-rendering responsibility silently. This widget closes
/// that loom by shipping a per-cohort default rendering policy at the
/// integrator-package boundary.
///
/// Two states:
///
/// - **Collapsed** — source-line provenance only (e.g. `'AlertExplainer
///   (JAF / MLIT / NEXCO)'`). Plus a tap-to-expand affordance.
/// - **Expanded** — `AlertExplainer.action` text VERBATIM + the
///   verbosity name + locale tag + source-line provenance full-form.
///
/// Per-cohort default expansion (driver-class equal-dignity discipline):
///
/// - `ageingRural` -> default-EXPANDED (cognitive-load support).
/// - `foreignTouristSnowZone` -> default-EXPANDED (unfamiliar snow zone;
///   needs source attribution to trust the recommendation).
/// - `noviceUrban` -> default-EXPANDED (low-experience cohort).
/// - `agriculturalForestry` -> default-COLLAPSED (experienced cohort).
/// - `snowZoneExperienced` -> default-COLLAPSED (high-experience cohort).
/// - `professional` -> default-COLLAPSED (terse-verbosity expectation).
///
/// Per-cohort defaults are **design-default hypotheses** (UNVERIFIED-
/// magnitude pending field validation that integrator-default expansion
/// per cohort produces the intended cognitive-load support without
/// crowding attention). Integrators may override per-instance via
/// [AlertExplainerExpandableSheet.defaultExpanded].
///
/// **Article 17 (β) verbatim-relay invariant** (load-bearing): the
/// `action` text from `AlertExplainer.forConditionAndProfile` is
/// preserved VERBATIM in BOTH states. The collapsed state HIDES the
/// expanded section but does not paraphrase or truncate the action
/// text. Expanded state renders the action text exactly as the
/// explainer returned it.
///
/// **Driver-always-drives invariant**: this widget is presentation-
/// class only. It renders information; it does not actuate the vehicle
/// or modify any driver-control surface.
///
/// **Severity-not-profile invariant preserved**: this widget renders
/// at the same severity-class regardless of expansion state. Severity
/// gating happens upstream in `NavigationBloc`; this widget does not
/// modify severity.
library;

import 'package:flutter/material.dart';
import 'package:navigation_safety_core/navigation_safety_core.dart';

/// Expandable sheet rendering `AlertExplainer.forConditionAndProfile`
/// at two levels of detail. See library-level documentation for
/// invariants and per-cohort defaults.
class AlertExplainerExpandableSheet extends StatefulWidget {
  /// Road-surface condition driving the explainer lookup.
  final RoadSurfaceCondition condition;

  /// Driver profile driving the per-cohort verbosity / locale / default
  /// expansion behaviour.
  final DriverProfile profile;

  /// Override for the per-cohort default expansion. When `null` the
  /// widget consults [defaultExpansionForProfile] for the active
  /// profile. When non-null this value is used at construction time
  /// (subsequent user taps still toggle expansion).
  final bool? defaultExpanded;

  /// Optional callback fired when the expansion state changes (e.g.
  /// integrator analytics or persistence).
  final ValueChanged<bool>? onExpansionChanged;

  /// Optional source-line text shown in both states. Defaults to a
  /// short attribution string. Integrators may localise or extend.
  final String sourceLine;

  const AlertExplainerExpandableSheet({
    super.key,
    required this.condition,
    required this.profile,
    this.defaultExpanded,
    this.onExpansionChanged,
    this.sourceLine = 'AlertExplainer (JAF / MLIT / NEXCO)',
  });

  /// Per-cohort default expansion. Profiles benefiting from cognitive-
  /// load support default to expanded; experienced cohorts default to
  /// collapsed.
  static bool defaultExpansionForProfile(DriverProfile profile) {
    switch (profile) {
      case DriverProfile.ageingRural:
      case DriverProfile.foreignTouristSnowZone:
      case DriverProfile.noviceUrban:
        return true;
      case DriverProfile.agriculturalForestry:
      case DriverProfile.snowZoneExperienced:
      case DriverProfile.professional:
        return false;
    }
  }

  @override
  State<AlertExplainerExpandableSheet> createState() =>
      _AlertExplainerExpandableSheetState();
}

class _AlertExplainerExpandableSheetState
    extends State<AlertExplainerExpandableSheet> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.defaultExpanded ??
        AlertExplainerExpandableSheet.defaultExpansionForProfile(
          widget.profile,
        );
  }

  void _toggle() {
    setState(() {
      _expanded = !_expanded;
    });
    widget.onExpansionChanged?.call(_expanded);
  }

  @override
  Widget build(BuildContext context) {
    final explainer = AlertExplainer.forConditionAndProfile(
      widget.condition,
      widget.profile,
    );

    final theme = Theme.of(context);
    final textTheme = theme.textTheme;

    return Card(
      child: InkWell(
        onTap: _toggle,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.sourceLine,
                      style: textTheme.bodySmall,
                    ),
                  ),
                  Icon(
                    _expanded
                        ? Icons.expand_less
                        : Icons.expand_more,
                    size: 20,
                  ),
                ],
              ),
              if (_expanded) ...[
                const SizedBox(height: 8),
                // Action text VERBATIM (Article 17 (β) verbatim-relay
                // invariant). Renders the string returned by the
                // explainer with no paraphrase, no truncation, no
                // synthesis.
                Text(
                  explainer.action,
                  style: textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Verbosity: ${explainer.verbosity.name} · '
                  'Locale: ${explainer.localeTag}',
                  style: textTheme.bodySmall?.copyWith(
                    fontStyle: FontStyle.italic,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.sourceLine,
                  style: textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
