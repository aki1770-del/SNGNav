/// The trust verdict the caller attaches to each raw fix.
library;

/// Whether a raw fix can be believed.
///
/// The caller maps this from a position-trust verdict — for example the
/// `trusted` / `suspect` / `failed` outcome of the `position_integrity`
/// package — and passes it alongside the fix. This package never computes
/// trust itself; it only orchestrates the honest handoff once trust is known.
enum TrustSignal {
  /// The fix passed integrity checks and may be used as ground truth.
  trusted,

  /// The fix is present but integrity is doubtful (e.g. innovation gate
  /// flagged it). It MUST NOT be blended in as if trusted.
  suspect,

  /// The fix failed integrity outright, or no usable fix is available.
  failed,
}
