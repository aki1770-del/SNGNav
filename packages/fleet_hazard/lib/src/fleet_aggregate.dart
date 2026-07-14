/// Aggregation result that keeps *absence of data* distinct from
/// *data that says the road is clear*.
library;

import 'package:equatable/equatable.dart';

import 'fleet_report.dart';
import 'hazard_zone.dart';

/// The outcome of aggregating fleet reports, carrying the provenance needed to
/// tell three very different worlds apart.
///
/// `HazardAggregator.aggregate()` returns `List<HazardZone>`, and an empty list
/// from it is ambiguous: it is the same value whether nobody reported the road,
/// or the fleet drove the road and found it clear, or every vehicle's sensor
/// returned [RoadCondition.unknown]. Those are not the same fact, and a driver
/// deserves them kept apart — "no car has been down this road" must never be
/// rendered with the same calm as "cars went down this road and it was fine".
///
/// This type carries the counts that separate them:
///
/// | world                        | [reportCount] | [unknownCount] | [zones] |
/// |------------------------------|---------------|----------------|---------|
/// | nobody reported ([isSilent]) | `0`           | `0`            | empty   |
/// | fleet says clear ([isMeasuredClear]) | `> 0`  | `0`            | empty   |
/// | all sensors blind ([isAllUnknown])   | `> 0`  | `== reportCount` | empty |
/// | hazard found                 | `> 0`         | any            | non-empty |
///
/// [zones] is empty in the first three, which is precisely why the empty list
/// alone could never be trusted to mean "clear".
class FleetAggregate extends Equatable {
  /// Hazard zones clustered from the reports that were considered.
  ///
  /// Empty does **not** mean "clear" on its own — see [isMeasuredClear].
  final List<HazardZone> zones;

  /// How many reports were actually considered.
  ///
  /// This counts the reports that survived the recency filter, if one was
  /// applied. Zero means **we were told nothing** — see [isSilent].
  final int reportCount;

  /// How many of the considered reports carried [RoadCondition.unknown].
  ///
  /// A vehicle that reported `unknown` drove the road and *could not tell*.
  /// That is not a clear road. `HazardAggregator.aggregate()` drops these
  /// silently (its hazard filter keeps only snowy/icy), which is how a road
  /// nobody could read came to look identical to a road known to be fine.
  final int unknownCount;

  /// How many reports were discarded as too old.
  ///
  /// Always `0` when no `maxAge` was supplied, because in that case nothing was
  /// filtered — not because everything was fresh.
  final int staleCount;

  /// Timestamp of the newest considered report, or `null` if there were none.
  ///
  /// `null` means NOT KNOWN. It never means "long ago", and it must never be
  /// coalesced into a time or rendered as freshness.
  final DateTime? freshestReportAt;

  const FleetAggregate({
    required this.zones,
    required this.reportCount,
    required this.unknownCount,
    required this.staleCount,
    required this.freshestReportAt,
  });

  /// Nobody told us anything about this road.
  ///
  /// No reports were considered — either none were supplied, or every one was
  /// discarded as stale (see [staleCount]). This is **absence**, and a surface
  /// that renders absence as a clear road is lying to the driver.
  bool get isSilent => reportCount == 0;

  /// Vehicles reported this road, every one of them could read it, and none of
  /// them found a hazard.
  ///
  /// This — and only this — is a measured all-clear. It requires that reports
  /// exist, that none carried [RoadCondition.unknown], and that no hazard zone
  /// formed.
  bool get isMeasuredClear =>
      reportCount > 0 && unknownCount == 0 && zones.isEmpty;

  /// Vehicles reported this road and not one of them could tell what it was.
  ///
  /// Every considered report carried [RoadCondition.unknown]. The road was
  /// driven and remains unread. This is closer to [isSilent] than to
  /// [isMeasuredClear], and must not be rendered as reassurance.
  bool get isAllUnknown => reportCount > 0 && unknownCount == reportCount;

  /// How many considered reports carried a condition the fleet could actually
  /// read (i.e. anything other than [RoadCondition.unknown]).
  int get knownCount => reportCount - unknownCount;

  /// Whether any hazard zone was found.
  bool get hasHazards => zones.isNotEmpty;

  @override
  List<Object?> get props => [
    zones,
    reportCount,
    unknownCount,
    staleCount,
    freshestReportAt,
  ];

  @override
  String toString() =>
      'FleetAggregate(${zones.length} zones, $reportCount reports, '
      '$unknownCount unknown, $staleCount stale, freshest=$freshestReportAt)';
}
