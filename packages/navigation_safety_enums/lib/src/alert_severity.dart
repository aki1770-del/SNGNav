/// Alert severity levels for safety presentation.
library;

/// Maps to visual treatment in the safety overlay.
///
/// Declaration order is load-bearing: callers compare severities via
/// `.index` (e.g., `NavigationBloc._canUpdateSeverity`) to enforce
/// monotonic upgrades (lower severity never replaces higher). Reordering
/// or inserting values mid-list will silently change safety behavior.
/// Locked by `packages/navigation_safety/test/bloc/severity_ordering_lock_test.dart`.
enum AlertSeverity {
  /// Informational - increase awareness.
  info,

  /// Warning - behavior change recommended.
  warning,

  /// Critical - immediate caution required.
  critical,
}
