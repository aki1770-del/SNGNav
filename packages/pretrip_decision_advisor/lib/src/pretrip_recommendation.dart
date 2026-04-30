/// Strength classes a [PretripRecommendation] may carry.
enum RecommendationStrength {
  /// Soft suggestion. Caller may surface as a non-blocking hint.
  advisoryWeak,

  /// Strong suggestion. Caller should surface prominently.
  advisoryStrong,

  /// Honest non-suggestion: the advisor has reason to speak but cannot
  /// recommend a delay (for example a required-attendance commute, or
  /// degraded inputs). The caller should communicate uncertainty and
  /// MUST NOT translate this into an `advisoryStrong` delay.
  honestyMode,
}

/// Output of [PretripAdvisor.advise].
///
/// A `null` return from the advisor means "no recommendation"; an
/// instance of this class means the advisor has something to say,
/// classified by [strength]. A [delay] of [Duration.zero] is meaningful
/// and indicates "depart as planned" with the given strength.
class PretripRecommendation {
  const PretripRecommendation({
    required this.strength,
    required this.delay,
    this.rationaleTag,
  });

  /// Strength class. See [RecommendationStrength].
  final RecommendationStrength strength;

  /// Suggested departure delay relative to the caller's intended
  /// departure time. Zero means "no delay".
  final Duration delay;

  /// Optional opaque rationale tag chosen by the implementation,
  /// for example `"ice_window_clears_after_0800"`. Not localized;
  /// callers map to human-facing strings at their own boundary.
  final String? rationaleTag;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PretripRecommendation &&
        other.strength == strength &&
        other.delay == delay &&
        other.rationaleTag == rationaleTag;
  }

  @override
  int get hashCode => Object.hash(strength, delay, rationaleTag);
}
