/// The first-class localization mode of an estimate.
library;

/// What kind of position the controller is currently emitting.
///
/// This is a HONESTY label first and a status second: it tells the app — and,
/// through the app, the driver — how much to believe the dot on the map.
enum LocalizationMode {
  /// A current, trusted GPS fix. The position is as good as the receiver says.
  gpsTrusted,

  /// GPS is present but its integrity is suspect. The emitted position is held
  /// from dead reckoning / last-known, NOT blended from the suspect fix, and
  /// its confidence radius is growing.
  gpsSuspect,

  /// No usable GPS. Position is driven by the dead-reckoning seam (or frozen at
  /// last-known if no seam is wired), and the confidence radius grows with
  /// every second that passes without a trusted fix.
  deadReckoning,

  /// Beyond the honesty horizon. The controller STILL returns its last-known
  /// position and a radius, but `lost` says plainly: "we do not know where you
  /// are; this is a guess." Never a confident dot.
  lost,
}
