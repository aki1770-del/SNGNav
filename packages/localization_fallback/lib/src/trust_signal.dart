/// The trust verdict the caller attaches to each raw fix.
library;

/// Whether a raw fix can be believed.
///
/// **You must compute this yourself.** This package never computes trust — it
/// only orchestrates the honest handoff once trust is known. There is no
/// published package in this catalog that produces the verdict for you; earlier
/// docs pointed at a `position_integrity` package that is **not on pub.dev**,
/// and that reference was wrong.
///
/// A workable verdict from the fields a platform locator already gives you.
/// The full, copy-pasteable version — including the distance helper — is in the
/// README under "Computing the trust signal":
///
/// ```dart
/// TrustSignal assess(RawFix fix, RawFix? previous, double Function(RawFix, RawFix) metresBetween) {
///   // 1. Geometry that cannot be true.
///   if (!fix.hasFiniteGeometry) return TrustSignal.failed;
///
///   // 2. Accuracy the receiver itself does not believe.
///   final acc = fix.accuracyMeters;
///   if (acc == null || acc > 100) return TrustSignal.suspect;
///
///   // 3. A jump no vehicle could have made (multipath / teleport).
///   if (previous != null) {
///     final seconds =
///         fix.timestamp.difference(previous.timestamp).inMilliseconds / 1000.0;
///     if (seconds > 0 && metresBetween(previous, fix) / seconds * 3.6 > 250) {
///       return TrustSignal.suspect;
///     }
///   }
///   return TrustSignal.trusted;
/// }
/// ```
///
/// Tune the thresholds to your vehicle and receiver. The point is that *some*
/// verdict is computed: if you never supply one, [LocalizationController.onFix]
/// defaults to [trusted] — it believes the fix — and a teleported or multipath
/// position will be presented as a confident dot.
enum TrustSignal {
  /// The fix passed integrity checks and may be used as ground truth.
  trusted,

  /// The fix is present but integrity is doubtful (e.g. innovation gate
  /// flagged it). It MUST NOT be blended in as if trusted.
  suspect,

  /// The fix failed integrity outright, or no usable fix is available.
  failed,
}
