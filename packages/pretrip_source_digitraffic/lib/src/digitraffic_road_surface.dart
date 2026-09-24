/// Measured ROAD-SURFACE reading from the Fintraffic Digitraffic road-weather
/// station this package already calls.
///
/// ## Why this exists
///
/// `/api/weather/v1/stations/{id}/data` returns ~97 sensors. Through 0.2.3
/// this package walked that list, took `NÄKYVYYS_M` — a number about the SKY —
/// and discarded every sensor about the ROAD: surface temperature, surface
/// state, freezing point, rate of change. Those are the quantities a driver
/// needs to know whether the wet road under her is about to be ice. They were
/// parsed and thrown away on every call, at no extra network cost to recover.
///
/// ## Scope bound, stated on the deliverable's face
///
/// **This serves a Finnish rural driver. It does not serve a Japanese one.**
/// Digitraffic covers Finland only (528 road-weather stations, measured
/// 2026-09-24). For Japan there is no road-surface source at all — no
/// publisher we have called returns a road-surface class anywhere in Japan.
/// Nothing here moves Akita one metre. It is built because the Finnish rural
/// driver is a weaver whose dignity is not lesser, and because this is the one
/// path in this catalog where a measured road-surface class can be proven
/// end-to-end. **Proving the pipeline where the data exists is not the same as
/// serving Akita, and the two must not be reported as one thing.**
///
/// ## The honesty rules, and why each exists
///
/// 1. **A channel the publisher does not define is never given a meaning.**
///    `/api/weather/v1/sensors` (read 2026-09-24) ships a 10-entry code table
///    for `KELI_1` (sensor 27) and `KELI_2` (28) — and an EMPTY table for
///    `KELI_3` (105) and `KELI_4` (115), and for `TIENPINNAN_TILA_1..4`
///    (167–170), whose `description` is `null` outright. Those four
///    `TIENPINNAN_TILA` channels and two `KELI` channels carry live integers
///    with no published meaning. Borrowing `KELI_1`'s scale for `KELI_3`
///    because the name matches is an assumption, not a measurement. They are
///    reported by name in [DigitrafficRoadSurfaceObservation.uninterpretedSensors]
///    so a consumer can never mistake our silence for their absence.
/// 2. **A declared fault is not a surface class.** Publisher code `0` reads
///    "The sensor has a fault". It sets
///    [DigitrafficRoadSurfaceObservation.sensorFaultDeclared] and produces no
///    state. The source declaring its own blindness must not arrive as a road
///    condition.
/// 3. **A class with no VSS equivalent stays null, never the benign one.**
///    Codes 2 "Moist", 4 "Wet and salty", 5 "Frost" and 8 "Probably moist and
///    salty" have no VSS allowed-value. `DRY` would be a lie toward benign;
///    inventing a value would be a lie outright. The publisher's own word is
///    carried verbatim in [RoadSurfaceStateReading.publisherLabel] and the VSS
///    field stays `null`, so nothing is lost and nothing is invented.
/// 4. **An aggregate never averages a cold point away.** Up to four surface
///    sensors sit at one station and disagree (7.3 / 7.6 / 6.9 / 7.0 °C,
///    measured 2026-09-24). A mean cannot say that one point alone is freezing.
///    The COLDEST surface, the HIGHEST freezing point and the FASTEST cooling
///    are reported, each naming the sensor it came from.
/// 5. **Stale is not current.** Every sensor carries its own `measuredTime`;
///    anything older than `maxObservationAge` is dropped rather than served.
///
/// Data © Fintraffic (digitraffic.fi), CC BY 4.0 — surface
/// [kDigitrafficVisibilityAttributionString] at your UI.
library;

/// Fintraffic's own `KELI` code table, verbatim from
/// `https://tie.digitraffic.fi/api/weather/v1/sensors`, sensor id 27
/// (`KELI_1`), read 2026-09-24T06:04Z. English strings are the publisher's
/// `descriptionEn`, not ours.
///
/// The same table is published for `KELI_2` (id 28). It is NOT published for
/// `KELI_3` (105) or `KELI_4` (115), which is why those two channels are never
/// interpreted here — see honesty rule 1.
const Map<int, String> kDigitrafficKeliCodeTable = <int, String>{
  0: 'The sensor has a fault',
  1: 'Dry',
  2: 'Moist',
  3: 'Wet',
  4: 'Wet and salty',
  5: 'Frost',
  6: 'Snow',
  7: 'Ice',
  8: 'Probably moist and salty',
  9: 'Slushy',
};

/// The `KELI` sensor channels Fintraffic publishes a code table for. Only
/// these are interpreted; see honesty rule 1.
const Set<String> kDigitrafficTabledSurfaceStateSensors = <String>{
  'KELI_1',
  'KELI_2',
};

/// Fintraffic `KELI` code → VSS `Vehicle.Exterior.RoadSurfaceCondition`
/// allowed-value string, or `null` where Fintraffic's class has no VSS
/// equivalent.
///
/// Five of ten codes map without loss. The other five do not, and this map
/// says so with an explicit `null` rather than by omission — the difference
/// between "we considered it and VSS cannot express it" and "we forgot".
///
/// - `0` fault → `null`. Not a surface (honesty rule 2).
/// - `1` Dry → `DRY`.
/// - `2` Moist → `null`. VSS has no MOIST. `DRY` understates toward benign,
///   `WET` overstates; both are false about a measurement.
/// - `3` Wet → `WET`.
/// - `4` Wet and salty → `null`. The surface is wet, but salt is the single
///   fact that changes whether it freezes, and `WET` discards it silently.
/// - `5` Frost → `null`. Hoarfrost is ice, but VSS `ICE` reads as an iced-over
///   surface and this is a deposit; the publisher's word "Frost" is more
///   precise than either VSS value.
/// - `6` Snow → `SNOW`.
/// - `7` Ice → `ICE`.
/// - `8` Probably moist and salty → `null`. The publisher itself hedges.
/// - `9` Slushy → `SLUSH`.
///
/// Integrator-overridable at the call site, per the sibling adapter's
/// `capMapping` precedent: a Finnish rural integrator who knows their own
/// roads may map `5` to `ICE` and should not have to fork this package to
/// do it. Consumers wanting the enum call
/// `RoadSurfaceCondition.fromVss(value)` from `navigation_safety_core` —
/// which is why this emits VSS STRINGS and takes no dependency on it.
const Map<int, String?> kDigitrafficKeliVssMapping = <int, String?>{
  0: null,
  1: 'DRY',
  2: null,
  3: 'WET',
  4: null,
  5: null,
  6: 'SNOW',
  7: 'ICE',
  8: null,
  9: 'SLUSH',
};

/// One road-surface-state channel, as the publisher reported it.
class RoadSurfaceStateReading {
  /// Constructs a reading. All fields come from one `sensorValues` entry.
  const RoadSurfaceStateReading({
    required this.sensorName,
    required this.code,
    required this.publisherLabel,
    required this.measuredAt,
    required this.vssRoadSurfaceCondition,
  });

  /// Fintraffic sensor name, e.g. `KELI_1`. Always one of
  /// [kDigitrafficTabledSurfaceStateSensors].
  final String sensorName;

  /// The publisher's integer code, verbatim.
  final int code;

  /// The publisher's own English word for [code] — never ours.
  final String publisherLabel;

  /// When the station measured this channel.
  final DateTime measuredAt;

  /// VSS `Vehicle.Exterior.RoadSurfaceCondition` allowed-value string, or
  /// `null` when Fintraffic's class has no VSS equivalent. Never a guess.
  final String? vssRoadSurfaceCondition;

  @override
  String toString() =>
      'RoadSurfaceStateReading($sensorName=$code "$publisherLabel"'
      '${vssRoadSurfaceCondition == null ? '' : ' → $vssRoadSurfaceCondition'})';
}

/// What one Digitraffic road-weather station measured about the ROAD.
///
/// `null` is returned instead of this object when nothing fresh was measured —
/// absence is never dressed as a benign reading.
class DigitrafficRoadSurfaceObservation {
  /// Constructs an observation. Built by [parseDigitrafficRoadSurface].
  const DigitrafficRoadSurfaceObservation({
    required this.stationId,
    required this.stationName,
    required this.distanceKm,
    required this.measuredAt,
    required this.surfaceStates,
    required this.sensorFaultDeclared,
    required this.uninterpretedSensors,
    this.coldestSurfaceCelsius,
    this.coldestSurfaceSensor,
    this.highestFreezingPointCelsius,
    this.highestFreezingPointSensor,
    this.fastestSurfaceCoolingCelsiusPerHour,
    this.fastestSurfaceCoolingSensor,
  });

  /// Fintraffic station id.
  final int stationId;

  /// Fintraffic station name, e.g. `vt4_Rovaniemi_Revontuli`.
  final String stationName;

  /// Distance from the requested point to the station, kilometres. She is on
  /// a road, not standing at the station — surface this at your UI.
  final double distanceKm;

  /// Newest contributing `measuredTime`.
  final DateTime measuredAt;

  /// Tabled surface-state channels, in sensor order. Empty when the station
  /// published no interpretable state. Two channels may disagree; both are
  /// carried, and no hazard ranking is imposed — the publisher does not
  /// publish one and the code order is not one (`4` "Wet and salty" is less
  /// hazardous than `3` "Wet").
  final List<RoadSurfaceStateReading> surfaceStates;

  /// True when a tabled channel reported code `0`, "The sensor has a fault".
  /// The station is declaring its own blindness; do not render a surface.
  final bool sensorFaultDeclared;

  /// Road-surface channels present in the payload that this package
  /// deliberately did NOT interpret, by sensor name — because Fintraffic
  /// publishes no code table for them (honesty rule 1). Present so a consumer
  /// sees that data exists which we refused to read, rather than inferring
  /// there was none.
  final List<String> uninterpretedSensors;

  /// Coldest of the station's `TIE_n` surface temperatures, °C. The coldest
  /// point is the one that ices first (bridges, overpasses, shaded bends).
  final double? coldestSurfaceCelsius;

  /// Which `TIE_n` sensor [coldestSurfaceCelsius] came from.
  final String? coldestSurfaceSensor;

  /// Highest of the station's `JÄÄTYMISPISTE_n` freezing points, °C — the
  /// temperature at which the solution on the surface freezes. Highest is the
  /// least headroom.
  final double? highestFreezingPointCelsius;

  /// Which `JÄÄTYMISPISTE_n` sensor [highestFreezingPointCelsius] came from.
  final String? highestFreezingPointSensor;

  /// Most negative `TIE_n_DERIVAATTA`, °C per hour — the fastest-cooling
  /// surface point. A MEASURED rate, not a forecast: this package does no
  /// projection, and a consumer that extrapolates it owns that claim.
  final double? fastestSurfaceCoolingCelsiusPerHour;

  /// Which `TIE_n_DERIVAATTA` sensor [fastestSurfaceCoolingCelsiusPerHour]
  /// came from.
  final String? fastestSurfaceCoolingSensor;

  @override
  String toString() =>
      'DigitrafficRoadSurfaceObservation($stationName #$stationId, '
      '${distanceKm.toStringAsFixed(1)} km, states=$surfaceStates, '
      'coldest=$coldestSurfaceCelsius°C @$coldestSurfaceSensor, '
      'fault=$sensorFaultDeclared, '
      'uninterpreted=${uninterpretedSensors.length})';
}

/// Sensor-name prefixes that belong to the road-surface family but carry no
/// publisher code table. Reported, never interpreted.
const List<String> _untabledSurfacePrefixes = <String>['TIENPINNAN_TILA_'];

/// Reads the road-surface family out of one `/stations/{id}/data` payload.
///
/// Returns `null` when nothing in the road-surface family is fresher than
/// [maxObservationAge] at [now] — never a benign default.
///
/// Pure: no I/O, no clock, no network. [now] is injected so the freshness gate
/// is testable.
DigitrafficRoadSurfaceObservation? parseDigitrafficRoadSurface(
  Map<String, dynamic> stationData, {
  required DateTime now,
  required int stationId,
  required String stationName,
  required double distanceKm,
  Duration maxObservationAge = const Duration(minutes: 30),
  Map<int, String?> vssMapping = kDigitrafficKeliVssMapping,
}) {
  final Object? values = stationData['sensorValues'];
  if (values is! List) return null;

  final states = <RoadSurfaceStateReading>[];
  final uninterpreted = <String>[];
  var faultDeclared = false;
  DateTime? newest;

  double? coldest;
  String? coldestSensor;
  double? highestFreezing;
  String? highestFreezingSensor;
  double? fastestCooling;
  String? fastestCoolingSensor;

  void noteTime(DateTime t) {
    if (newest == null || t.isAfter(newest!)) newest = t;
  }

  for (final Object? entry in values) {
    if (entry is! Map<String, dynamic>) continue;
    final Object? rawName = entry['name'];
    if (rawName is! String) continue;
    final name = rawName;

    final isUntabledFamily =
        _untabledSurfacePrefixes.any(name.startsWith) ||
        (name.startsWith('KELI_') &&
            !kDigitrafficTabledSurfaceStateSensors.contains(name));
    if (isUntabledFamily) {
      // Present, live, and deliberately not given a meaning (honesty rule 1).
      uninterpreted.add(name);
      continue;
    }

    final value = _readNum(entry['value']);
    final measuredAt = _parseIsoOrNull(entry['measuredTime']);
    if (value == null || measuredAt == null) continue;
    if (now.difference(measuredAt) > maxObservationAge) continue;

    if (kDigitrafficTabledSurfaceStateSensors.contains(name)) {
      final code = value.round();
      final label = kDigitrafficKeliCodeTable[code];
      if (label == null) {
        // A code the publisher's own table does not define — a table this
        // package read on 2026-09-24 and Fintraffic may have extended since.
        // Reported as uninterpreted rather than rendered as a surface.
        uninterpreted.add(name);
        continue;
      }
      noteTime(measuredAt);
      if (code == 0) {
        faultDeclared = true;
        continue;
      }
      final Object? inline = entry['sensorValueDescriptionEn'];
      states.add(
        RoadSurfaceStateReading(
          sensorName: name,
          code: code,
          publisherLabel: inline is String && inline.isNotEmpty
              ? inline
              : label,
          measuredAt: measuredAt,
          vssRoadSurfaceCondition: vssMapping[code],
        ),
      );
      continue;
    }

    if (name.startsWith('TIE_') && name.endsWith('_DERIVAATTA')) {
      if (fastestCooling == null || value < fastestCooling) {
        fastestCooling = value;
        fastestCoolingSensor = name;
      }
      noteTime(measuredAt);
      continue;
    }

    if (_isIndexedSensor(name, 'TIE_')) {
      if (coldest == null || value < coldest) {
        coldest = value;
        coldestSensor = name;
      }
      noteTime(measuredAt);
      continue;
    }

    if (_isIndexedSensor(name, 'JÄÄTYMISPISTE_')) {
      if (highestFreezing == null || value > highestFreezing) {
        highestFreezing = value;
        highestFreezingSensor = name;
      }
      noteTime(measuredAt);
      continue;
    }
  }

  final at = newest;
  if (at == null) return null;
  if (states.isEmpty &&
      !faultDeclared &&
      coldest == null &&
      highestFreezing == null &&
      fastestCooling == null) {
    return null;
  }

  states.sort((a, b) => a.sensorName.compareTo(b.sensorName));
  uninterpreted.sort();

  return DigitrafficRoadSurfaceObservation(
    stationId: stationId,
    stationName: stationName,
    distanceKm: distanceKm,
    measuredAt: at,
    surfaceStates: List<RoadSurfaceStateReading>.unmodifiable(states),
    sensorFaultDeclared: faultDeclared,
    uninterpretedSensors: List<String>.unmodifiable(uninterpreted),
    coldestSurfaceCelsius: coldest,
    coldestSurfaceSensor: coldestSensor,
    highestFreezingPointCelsius: highestFreezing,
    highestFreezingPointSensor: highestFreezingSensor,
    fastestSurfaceCoolingCelsiusPerHour: fastestCooling,
    fastestSurfaceCoolingSensor: fastestCoolingSensor,
  );
}

/// True for `PREFIX<digits>` exactly — `TIE_1` yes, `TIE_1_DERIVAATTA` no.
bool _isIndexedSensor(String name, String prefix) {
  if (!name.startsWith(prefix)) return false;
  final tail = name.substring(prefix.length);
  if (tail.isEmpty) return false;
  return int.tryParse(tail) != null;
}

double? _readNum(Object? raw) {
  if (raw is num) return raw.toDouble();
  if (raw is String) return double.tryParse(raw);
  return null;
}

DateTime? _parseIsoOrNull(Object? raw) {
  if (raw is! String || raw.isEmpty) return null;
  try {
    return DateTime.parse(raw).toLocal();
  } on FormatException {
    return null;
  }
}
