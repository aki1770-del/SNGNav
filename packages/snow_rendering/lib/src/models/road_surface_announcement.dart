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
/// this variant when its own gate knows it took that path. Freezing
/// rain is ALSO an invisible-ice phenomenon, but no classifier path
/// currently routes it here; a consumer wiring freezing-rain detection
/// may use this variant deliberately. On every other path — including
/// the feed ice flag, which typically fires during visible
/// precipitation — the general [RoadSurfaceState.blackIce] announcement
/// applies instead: telling a driver in falling snow that the road
/// "looks wet" is false.
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
