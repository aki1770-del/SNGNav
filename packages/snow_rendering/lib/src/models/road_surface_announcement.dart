/// Driver-facing announcement text for a classified road surface,
/// drawing the precise JP-domestic vocabulary term for the surface
/// class instead of a generic English label.
///
/// Why this exists: the in-drive classifier can now specifically
/// detect black ice ([RoadSurfaceState.blackIce]) — the surface that
/// *looks* like wet asphalt but is frozen — yet the warning a driver
/// hears or reads has historically been a generic English phrase
/// ("Black ice risk"). A Japanese driver in unexpected snow knows the
/// hazard by its precise name, ブラックアイスバーン, and the term
/// itself carries the load-bearing fact: the road looks normal. This
/// module maps each classified surface to (a) a short TTS-ready
/// spoken line in Japanese and English and (b) the authoritative
/// JAF vocabulary entry from `japanese_snow_vocabulary`, whose
/// `safeDrivingResponseJa` is relayed verbatim for display surfaces.
///
/// Honesty boundary, two clauses:
///
/// 1. *Composed, not verbatim.* The spoken lines here are composed by
///    this package, grounded in the JAF advisory but NOT verbatim
///    relays of it. The verbatim JAF text travels untouched on
///    [RoadSurfaceAnnouncement.vocabulary] (`safeDrivingResponseJa` /
///    `safeDrivingResponseEn`), subject to the vocabulary package's
///    verbatim-relay binding.
/// 2. *Certainty is graded, not asserted.* The classifier's black-ice
///    determinations are inferences (a feed flag, or a dew-point
///    heuristic), not surface measurements — so the composed lines say
///    凍結しているおそれ ("may be frozen"), mirroring JAF's own 可能性
///    phrasing, never flat certainty. The "looks merely wet" fact is
///    TRUE only on the invisible-ice paths (radiative frost, freezing
///    rain) and is therefore carried ONLY on the separate
///    [invisibleBlackIceAnnouncement] — spoken line AND the JAF
///    vocabulary entry alike, because the JAF verbatim advisory itself
///    opens with the looks-wet description. The general
///    [RoadSurfaceState.blackIce] announcement (reachable during
///    visible snowfall, where the road does not look wet) carries
///    neither: no looks-wet spoken claim, and no vocabulary entry a
///    display-untouched consumer could surface falsely.
library;

import 'package:driving_weather/driving_weather.dart';
import 'package:japanese_snow_vocabulary/japanese_snow_vocabulary.dart';

import 'road_surface_state.dart';

/// Announcement content for one classified road surface.
class RoadSurfaceAnnouncement {
  /// Short, TTS-ready Japanese spoken line. Leads with the precise
  /// surface term (e.g. ブラックアイスバーン) so the driver hears the
  /// name she knows, then the immediate response.
  final String jaSpokenText;

  /// Short, TTS-ready English spoken line (foreign-driver /
  /// EN-locale fallback).
  final String enSpokenText;

  /// The precise Japanese surface term this announcement leads with
  /// (e.g. `ブラックアイスバーン`), or `null` when the surface has no
  /// JP-domestic snow-vocabulary class (wet / standing water).
  final String? termJa;

  /// The authoritative JAF vocabulary entry for this surface class,
  /// or `null` when the surface has no snow-vocabulary class.
  ///
  /// `vocabulary.safeDrivingResponseJa` is verbatim JAF text —
  /// display it untouched (verbatim-relay binding); do not edit or
  /// truncate it.
  final JapaneseSnowVocabularyEntry? vocabulary;

  const RoadSurfaceAnnouncement({
    required this.jaSpokenText,
    required this.enSpokenText,
    this.termJa,
    this.vocabulary,
  });
}

/// Announcement for the INVISIBLE-ice paths — where the load-bearing
/// fact is that the road looks merely wet or normal while frozen. This
/// is JAF's defining description of ブラックアイスバーン, relayed
/// verbatim on [RoadSurfaceAnnouncement.vocabulary].
///
/// Use this ONLY when the detection path itself implies invisibility.
/// Today that is the radiative-frost window (clear sky, ambient a few
/// degrees above zero, dew point at/below 0 °C) — the consumer selects
/// this variant when its own gate knows it took that path, or lets
/// [announcementFor] select it (the window predicate is exported as
/// [RoadSurfaceState.isInvisibleIceWindow]; re-implementing the gate
/// at the call site is the drift seam that predicate closes). Freezing
/// rain is ALSO an invisible-ice phenomenon — glare ice from rain looks
/// merely wet — but no classifier path routes it here, deliberately:
/// the rain-at-≤0 °C branch cannot distinguish a true freezing-rain
/// event from a marginal or erroneous temperature reading during cold
/// rain, so this variant's strong looks-wet claim is withheld on that
/// path. A consumer with genuine freezing-rain detection (a dedicated
/// feed signal, not the temperature heuristic) may use this variant
/// deliberately. On every other path — including the feed ice flag,
/// which typically fires during visible precipitation — the general
/// [RoadSurfaceState.blackIce] announcement applies instead: telling a
/// driver in falling snow that the road "looks wet" is false.
final RoadSurfaceAnnouncement invisibleBlackIceAnnouncement =
    RoadSurfaceAnnouncement(
  jaSpokenText:
      'ブラックアイスバーンに注意。路面は濡れて見えても、'
      '凍結しているおそれがあります。'
      '急ハンドル、急ブレーキは厳禁。速度を落としてください。',
  enSpokenText:
      'Black ice warning. The road may look merely wet but may be '
      'frozen. No abrupt steering or braking. Reduce speed.',
  termJa: 'ブラックアイスバーン',
  vocabulary: jafAuthoritativeData[JapaneseSnowSurfaceClass.blackIceBahn],
);

/// Provenance-carrying announcement lookup: classify [condition] and
/// select the announcement variant whose claims are TRUE for the path
/// the classification actually took.
///
/// [RoadSurfaceState.fromCondition] returns a bare enum value, and an
/// enum value cannot carry HOW it was reached — so the two-step chain
/// `fromCondition(condition).announcement` always yields the general,
/// provenance-neutral black-ice announcement, even on the invisible
/// radiative-frost morning where the stronger
/// [invisibleBlackIceAnnouncement] — the looks-wet surprise clause and
/// the verbatim JAF vocabulary entry — is the true one. Under-warning
/// on the invisible morning is exactly the failure this package exists
/// to prevent; prefer this function over `.announcement` on the
/// classified value whenever the [WeatherCondition] is still in hand.
///
/// Selection, stated honestly:
///
/// - [RoadSurfaceState.isInvisibleIceWindow] true → the invisible-ice
///   variant [invisibleBlackIceAnnouncement].
/// - Every other classification → that state's general announcement
///   ([RoadSurfaceStateAnnouncement.announcement]); `null` for
///   [RoadSurfaceState.dry] (nothing to announce). In particular, the
///   feed ice flag during visible precipitation and the cold-dry
///   (≤ −3 °C) regime stay on the general black-ice announcement — the
///   looks-wet claim is not established on those paths — and freezing
///   rain stays general for a different, deliberate reason: it IS
///   invisible-ice phenomenology, but the rain-at-≤0 °C branch cannot
///   distinguish a true freezing-rain event from a marginal or
///   erroneous temperature reading during cold rain, so the strong
///   looks-wet claim is withheld (see [invisibleBlackIceAnnouncement]).
/// - Caution-add-only: relative to the two-step chain this only ever
///   UPGRADES a black-ice announcement to the invisible-ice variant;
///   it never changes which surface is classified and never weakens
///   any announcement.
///
/// Two bounds every consumer must hold:
///
/// - **`null` is NOT all-clear on this 0.2.x line.** [fromCondition]
///   cannot say "I don't know": a [WeatherCondition] built from filler
///   or unmeasured values classifies as [RoadSurfaceState.dry], and
///   this function then returns `null` — a silent surface for a road
///   nobody measured, which a driver reads as reassurance. Gate
///   absence at your call site (never construct a condition from
///   fields you did not measure) and surface "unknown" to your user
///   yourself; see the 0.2.9 safety notice in the CHANGELOG. The
///   0.3.x line fixes this in the type system.
/// - **This is a provenance selector, NOT an alert-cadence gate.** It
///   chooses WHICH announcement text is true for the path the
///   classification took; it says nothing about WHEN or HOW OFTEN to
///   alert. In particular, in the no-precipitation (−3, 0] °C band the
///   dew-point window holds on essentially every valid-humidity
///   reading (the dew point cannot exceed a sub-zero ambient), so
///   announcing every non-`null` return verbatim would alarm
///   continuously through ordinary cold mornings — cry-wolf that
///   trains the driver to ignore the one warning that matters. Alert
///   frequency, deduplication, and escalation policy belong to the
///   consumer.
RoadSurfaceAnnouncement? announcementFor(WeatherCondition condition) {
  final state = RoadSurfaceState.fromCondition(condition);
  // The state check is logically implied by the predicate (the tested
  // alignment guarantee: window true ⇒ blackIce) — kept as a belt so
  // this function can never swap a non-black-ice surface's
  // announcement even if a future decision-tree edit breaks alignment.
  if (state == RoadSurfaceState.blackIce &&
      RoadSurfaceState.isInvisibleIceWindow(condition)) {
    return invisibleBlackIceAnnouncement;
  }
  return state.announcement;
}

/// Announcement lookup for [RoadSurfaceState].
extension RoadSurfaceStateAnnouncement on RoadSurfaceState {
  /// The driver-facing announcement for this surface, or `null` for
  /// [RoadSurfaceState.dry] (nothing to announce).
  ///
  /// The switch is exhaustive and compile-checked: adding a surface
  /// state without deciding its announcement fails the build rather
  /// than silently announcing nothing.
  RoadSurfaceAnnouncement? get announcement {
    switch (this) {
      case RoadSurfaceState.dry:
        return null;

      case RoadSurfaceState.wet:
        return const RoadSurfaceAnnouncement(
          jaSpokenText: '路面が濡れています。制動距離が伸びます。速度を控えてください。',
          enSpokenText:
              'Wet road surface. Stopping distance increases. Reduce speed.',
        );

      case RoadSurfaceState.slush:
        return RoadSurfaceAnnouncement(
          jaSpokenText:
              'シャーベット状の路面です。下が凍結している可能性があります。'
              '油断せず、速度を落としてください。',
          enSpokenText:
              'Slush on the road. The surface beneath may be frozen. '
              'Stay alert and reduce speed.',
          termJa: 'シャーベット',
          vocabulary: jafAuthoritativeData[JapaneseSnowSurfaceClass.slush],
        );

      case RoadSurfaceState.compactedSnow:
        return RoadSurfaceAnnouncement(
          jaSpokenText:
              '圧雪路面です。急のつく操作を避け、車間距離を多めにとってください。',
          enSpokenText:
              'Compacted snow surface. Avoid abrupt maneuvers and '
              'increase following distance.',
          termJa: '圧雪',
          vocabulary:
              jafAuthoritativeData[JapaneseSnowSurfaceClass.compactedSnow],
        );

      case RoadSurfaceState.blackIce:
        // Provenance-neutral: reachable from a feed ice flag during
        // visible snowfall, so it must NOT claim the road "looks wet".
        // The JAF vocabulary entry is deliberately ABSENT here: its
        // verbatim advisory text OPENS with the looks-wet description
        // (一見すると濡れたアスファルト路面のように…), which is true only
        // on invisible-ice paths — a consumer following the display-
        // untouched contract would show precise-but-false text during
        // visible snowfall. [invisibleBlackIceAnnouncement] carries the
        // entry for the paths where it is true.
        return const RoadSurfaceAnnouncement(
          jaSpokenText:
              'ブラックアイスバーンに注意。路面が凍結しているおそれがあります。'
              '急ハンドル、急ブレーキは厳禁。速度を落としてください。',
          enSpokenText:
              'Black ice warning. The road surface may be frozen. '
              'No abrupt steering or braking. Reduce speed.',
          termJa: 'ブラックアイスバーン',
        );

      case RoadSurfaceState.standingWater:
        return const RoadSurfaceAnnouncement(
          jaSpokenText:
              '路面に水がたまっています。ハイドロプレーニングに注意し、'
              '速度を落としてください。',
          enSpokenText:
              'Standing water on the road. Risk of aquaplaning. '
              'Reduce speed.',
        );
    }
  }
}
