/// Strength of a pre-trip recommendation.
enum RecommendationStrength {
  /// A soft suggestion that the driver may benefit from delaying.
  advisoryWeak,

  /// A firmer suggestion to delay; the forecast points to materially
  /// worse conditions in the planned departure window.
  advisoryStrong,

  /// The commute is required; the advisor explicitly defers to the
  /// driver rather than urging a delay that may carry employer or
  /// other obligation cost.
  honestyMode,
}

/// A recommendation produced by a [PretripAdvisor] implementation.
///
/// A [suggestedDelay] of `Duration.zero` means "depart now". A non-zero
/// delay is the advisor's best estimate of how long to wait. The
/// [confidenceWindow] expresses uncertainty around that delay.
class PretripRecommendation {
  PretripRecommendation({
    required this.suggestedDelay,
    required this.confidenceWindow,
    required this.strength,
    required this.rationale,
  });

  /// Suggested wait before departing. `Duration.zero` means depart now.
  final Duration suggestedDelay;

  /// Width of the uncertainty band around [suggestedDelay].
  final Duration confidenceWindow;

  /// Strength of the recommendation. See [RecommendationStrength].
  final RecommendationStrength strength;

  /// Human-readable reason chips that explain the recommendation.
  /// Plain language; no internal vocabulary.
  final List<String> rationale;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PretripRecommendation &&
        other.suggestedDelay == suggestedDelay &&
        other.confidenceWindow == confidenceWindow &&
        other.strength == strength &&
        _listEquals(other.rationale, rationale);
  }

  @override
  int get hashCode => Object.hash(
    suggestedDelay,
    confidenceWindow,
    strength,
    Object.hashAll(rationale),
  );
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
