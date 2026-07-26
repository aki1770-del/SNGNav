/// What is under the tyre, along the route — the surface read.
///
/// The per-segment forecasts carry weather ([SegmentConditionForecast.condition]);
/// the family's surface classifier (`snow_rendering`'s
/// [RoadSurfaceState.fromCondition]) turns weather into what actually matters to
/// grip. This seam applies the classifier along the route ONCE, correctly, so an
/// integrator never re-derives it per segment — and cannot get the one
/// safety-critical fold wrong:
///
/// **An unclassifiable segment is never dry.** `fromCondition` returns `null`
/// when the data cannot support a classification (Measured-or-Absent: absence of
/// data must not become maximum grip). A naive fold that skips null segments
/// would tell the driver about the worst *measured* surface while silently
/// passing over the stretches nobody measured. So the fold returns both — the
/// worst classified surface AND the count of unknown segments — and a consumer
/// that shows one without the other is misusing it. Unknown is a thing the
/// driver is TOLD.
library;

import 'package:snow_rendering/snow_rendering.dart';

import '../models/segment_condition_forecast.dart';

/// Surface classification for one forecast segment, or `null` when the
/// segment's weather cannot support a classification (never dry-by-default).
extension SegmentSurface on SegmentConditionForecast {
  RoadSurfaceState? get surfaceState =>
      RoadSurfaceState.fromCondition(condition);
}

/// The honest fold of surface state along a route.
class RouteSurfaceRead {
  /// The worst (lowest-grip) surface among the segments that COULD be
  /// classified, or `null` when no segment classified.
  final RoadSurfaceState? worstClassified;

  /// Index of the first segment where [worstClassified] occurs, or `null`.
  /// Lets a consumer say "from segment N" (approaching, not just somewhere).
  final int? worstSegmentIndex;

  /// Segments whose weather could not support a classification. These are
  /// unknown — NOT clear. A briefing that reports [worstClassified] without
  /// mentioning these is claiming measurements it does not have.
  final int unclassifiedSegmentCount;

  /// Total segments folded.
  final int segmentCount;

  const RouteSurfaceRead({
    required this.worstClassified,
    required this.worstSegmentIndex,
    required this.unclassifiedSegmentCount,
    required this.segmentCount,
  });
}

/// Classify every segment and fold to the worst surface + the unknown count.
///
/// Worst = lowest [RoadSurfaceState.gripFactor] among classified segments;
/// ties keep the EARLIEST segment (the first place she meets that surface).
RouteSurfaceRead surfaceAlongRoute(List<SegmentConditionForecast> segments) {
  RoadSurfaceState? worst;
  int? worstIndex;
  var unclassified = 0;
  for (var i = 0; i < segments.length; i++) {
    final s = segments[i].surfaceState;
    if (s == null) {
      unclassified++;
      continue;
    }
    if (worst == null || s.gripFactor < worst.gripFactor) {
      worst = s;
      worstIndex = i;
    }
  }
  return RouteSurfaceRead(
    worstClassified: worst,
    worstSegmentIndex: worstIndex,
    unclassifiedSegmentCount: unclassified,
    segmentCount: segments.length,
  );
}
