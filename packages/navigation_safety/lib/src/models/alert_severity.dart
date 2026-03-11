/// Alert severity levels for safety presentation.
library;

/// Maps to visual treatment in the safety overlay.
enum AlertSeverity {
  /// Informational - increase awareness.
  info,

  /// Warning - behavior change recommended.
  warning,

  /// Critical - immediate caution required.
  critical,
}