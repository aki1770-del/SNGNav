/// Offline, deterministic snow-adjusted DAYLIGHT CLOCK.
///
/// Tells HER whether a trip instant falls in low-light hours (pre-dawn,
/// dusk / after sunset). Sunrise and sunset are ASTRONOMY — computed from the
/// date and the route's latitude/longitude, with no network and no system
/// clock — so the answer survives the compound-failure case this whole product
/// is built for (Google Maps fails AND GPS fails). A clock about HER trip's
/// light watches no person.
///
/// The solar position is the standard NOAA / Meeus low-precision algorithm
/// (good to well under a minute for civil purposes), implemented with
/// `dart:math` ONLY — zero dependencies. It NEVER calls [DateTime.now].
///
/// What this is NOT: it is not a hazard model. The daylight facts here state
/// only light and time. They never assert ice, refreeze, or any road hazard
/// from the time of day alone — that fabrication is the cardinal sin this
/// feature must not commit (see `snow_aware_pretrip_advisor.dart`, which owns
/// the real per-slot weather data).
library;

import 'dart:math' as math;

import 'trip_geo.dart';

/// Solar zenith angle (degrees) at the geometric sunrise/sunset, including the
/// standard refraction + solar-radius allowance.
const double _sunriseZenith = 90.833;

/// Solar zenith angle (degrees) at civil dawn / civil dusk (sun 6° below the
/// horizon). Between civil twilight and sunrise/sunset there is usable light;
/// beyond civil twilight is true darkness.
const double _civilZenith = 96.0;

/// Low-light classification of a single trip instant at a given place.
enum DaylightPhase {
  /// The sun is up — no low-light note is emitted.
  daylight,

  /// The instant is before sunrise — pre-dawn low light. The reference event
  /// is the COMING sunrise (on the instant's own civil day).
  preDawn,

  /// The instant is after sunset — dusk / night low light. The reference event
  /// is the sunset just PASSED (on the instant's own civil day).
  postDusk,

  /// The sun does not rise on this civil day at this latitude (polar night) —
  /// the whole trip is in darkness.
  polarNight,

  /// The sun does not set on this civil day at this latitude (polar day / white
  /// night) — full daylight, no low-light note.
  polarDay,
}

/// The solar facts the daylight chip needs for one trip instant + place.
///
/// All clock strings are HER LOCAL WALL CLOCK (`HH:MM`, 24-hour), already
/// converted from UTC through [TripGeo.utcOffset]. Numbers are produced once
/// here so a localization can reorder words but never restate a measured value.
class TripDaylight {
  const TripDaylight({
    required this.phase,
    required this.sunriseHHMM,
    required this.sunsetHHMM,
    required this.eventHHMM,
    required this.minutesToEvent,
    required this.deepDark,
  });

  /// Low-light classification of the trip instant.
  final DaylightPhase phase;

  /// Local sunrise as `HH:MM`, or null at polar night.
  final String? sunriseHHMM;

  /// Local sunset as `HH:MM`, or null at polar night.
  final String? sunsetHHMM;

  /// The reference event for this instant: the coming sunrise ([preDawn]) or
  /// the sunset just passed ([postDusk]); null when there is no chip-worthy
  /// reference (daylight / polar day / polar night).
  final String? eventHHMM;

  /// Absolute minutes between the instant and [eventHHMM] (never negative).
  final int minutesToEvent;

  /// True when the instant is beyond civil twilight (before civil dawn or after
  /// civil dusk) — true darkness rather than usable twilight. Always true at
  /// polar night.
  final bool deepDark;

  /// Whether this instant warrants a low-light note at all.
  bool get isLowLight =>
      phase == DaylightPhase.preDawn ||
      phase == DaylightPhase.postDusk ||
      phase == DaylightPhase.polarNight;

  /// Ordering used to pick the worst (darkest) of several candidate instants.
  /// Daylight / polar day contribute nothing; deep darkness outranks twilight;
  /// polar night (dark all day) is the most severe.
  int get severity {
    switch (phase) {
      case DaylightPhase.daylight:
      case DaylightPhase.polarDay:
        return 0;
      case DaylightPhase.preDawn:
      case DaylightPhase.postDusk:
        return deepDark ? 2 : 1;
      case DaylightPhase.polarNight:
        return 3;
    }
  }

  /// Value equality over all fields, matching the package's other DTOs
  /// ([TripGeo], [CommuteShape]) so two equal solar readings dedup, cache, and
  /// diff correctly (e.g. as a Set/Map key or in widget-rebuild comparison).
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TripDaylight &&
        other.phase == phase &&
        other.sunriseHHMM == sunriseHHMM &&
        other.sunsetHHMM == sunsetHHMM &&
        other.eventHHMM == eventHHMM &&
        other.minutesToEvent == minutesToEvent &&
        other.deepDark == deepDark;
  }

  @override
  int get hashCode => Object.hash(
        phase,
        sunriseHHMM,
        sunsetHHMM,
        eventHHMM,
        minutesToEvent,
        deepDark,
      );
}

/// Evaluate the daylight facts for a single trip [instant] at [geo].
///
/// [instant] is treated as a ROUTE-LOCAL wall-clock time regardless of whether
/// the caller passed a UTC or local [DateTime] — only its calendar/clock fields
/// are read, so the result is `isUtc`-independent (correction (c)). The civil
/// day used for sunrise/sunset is the instant's own local date, which keeps the
/// reference event on the right day (correction (b)): a pre-dawn instant names
/// the coming sunrise, never the prior day's sunset.
TripDaylight evaluateDaylight(DateTime instant, TripGeo geo) {
  final y = instant.year;
  final m = instant.month;
  final d = instant.day;

  // The naive wall-clock fields denote local civil time → convert to UTC.
  final refUtc = DateTime.utc(y, m, d, instant.hour, instant.minute)
      .subtract(geo.utcOffset);

  final solar = _solarDay(y, m, d, geo);

  String? local(DateTime? utc) =>
      utc == null ? null : _hhmmLocal(utc, geo.utcOffset);
  final sunriseHHMM = local(solar.sunrise);
  final sunsetHHMM = local(solar.sunset);

  if (solar.polarNight) {
    // The sun does not rise today. It is true all-day darkness ONLY when the
    // sun never reaches civil twilight either; if it climbs into civil twilight
    // around solar noon, [_solarDay] populates civilDawn/civilDusk and there is
    // usable midday light, so this is NOT deep dark.
    return TripDaylight(
      phase: DaylightPhase.polarNight,
      sunriseHHMM: null,
      sunsetHHMM: null,
      eventHHMM: null,
      minutesToEvent: 0,
      deepDark: solar.civilDawn == null,
    );
  }
  if (solar.polarDay) {
    return TripDaylight(
      phase: DaylightPhase.polarDay,
      sunriseHHMM: sunriseHHMM,
      sunsetHHMM: sunsetHHMM,
      eventHHMM: null,
      minutesToEvent: 0,
      deepDark: false,
    );
  }

  final sunrise = solar.sunrise;
  final sunset = solar.sunset;

  if (sunrise != null && refUtc.isBefore(sunrise)) {
    final deep = solar.civilDawn != null && refUtc.isBefore(solar.civilDawn!);
    return TripDaylight(
      phase: DaylightPhase.preDawn,
      sunriseHHMM: sunriseHHMM,
      sunsetHHMM: sunsetHHMM,
      eventHHMM: sunriseHHMM,
      minutesToEvent: sunrise.difference(refUtc).inMinutes.abs(),
      deepDark: deep,
    );
  }
  if (sunset != null && refUtc.isAfter(sunset)) {
    final deep = solar.civilDusk != null && refUtc.isAfter(solar.civilDusk!);
    return TripDaylight(
      phase: DaylightPhase.postDusk,
      sunriseHHMM: sunriseHHMM,
      sunsetHHMM: sunsetHHMM,
      eventHHMM: sunsetHHMM,
      minutesToEvent: refUtc.difference(sunset).inMinutes.abs(),
      deepDark: deep,
    );
  }

  return TripDaylight(
    phase: DaylightPhase.daylight,
    sunriseHHMM: sunriseHHMM,
    sunsetHHMM: sunsetHHMM,
    eventHHMM: null,
    minutesToEvent: 0,
    deepDark: false,
  );
}

// --- Solar geometry (NOAA / Meeus, dart:math only) -------------------------

/// Absolute UTC sunrise/sunset/civil-twilight instants for one civil day at a
/// place — or polar-day / polar-night flags when the sun does not cross the
/// horizon.
class _SolarDay {
  const _SolarDay({
    this.sunrise,
    this.sunset,
    this.civilDawn,
    this.civilDusk,
    this.polarDay = false,
    this.polarNight = false,
  });

  final DateTime? sunrise;
  final DateTime? sunset;
  final DateTime? civilDawn;
  final DateTime? civilDusk;
  final bool polarDay;
  final bool polarNight;
}

_SolarDay _solarDay(int y, int m, int d, TripGeo geo) {
  final jd0 = _julianDay(y, m, d);
  final lat = geo.latitude;
  final lon = geo.longitude;

  // Polar test at the sunrise zenith, using the declination at 0h UTC.
  final dec0 = _sunDeclination(_julianCentury(jd0));
  double polarCos(double zenithDeg) =>
      (_cosDeg(zenithDeg) - _sinDeg(lat) * _sinDeg(dec0)) /
      (_cosDeg(lat) * _cosDeg(dec0));
  final cosH = polarCos(_sunriseZenith);

  final base = DateTime.utc(y, m, d);
  DateTime? at(double? minutesUTC) => minutesUTC == null
      ? null
      // A negative or >1440 value correctly rolls to the prior/next UTC day via
      // Duration arithmetic — this is the midnight-wrap case, kept on purpose.
      : base.add(Duration(minutes: minutesUTC.round()));

  if (cosH > 1) {
    // No sunrise today (polar night). The sun may still climb into civil
    // twilight around solar noon (lat below the deep-polar-night line), which
    // is usable midday light. Only call it all-day darkness when the sun does
    // not even reach the civil zenith — leave civilDawn/civilDusk null then.
    if (polarCos(_civilZenith) > 1) {
      return const _SolarDay(polarNight: true);
    }
    return _SolarDay(
      polarNight: true,
      civilDawn: at(_eventMinutesUTC(jd0, lat, lon, _civilZenith, rise: true)),
      civilDusk: at(_eventMinutesUTC(jd0, lat, lon, _civilZenith, rise: false)),
    );
  }
  if (cosH < -1) {
    return const _SolarDay(polarDay: true);
  }

  return _SolarDay(
    sunrise: at(_eventMinutesUTC(jd0, lat, lon, _sunriseZenith, rise: true)),
    sunset: at(_eventMinutesUTC(jd0, lat, lon, _sunriseZenith, rise: false)),
    civilDawn: at(_eventMinutesUTC(jd0, lat, lon, _civilZenith, rise: true)),
    civilDusk: at(_eventMinutesUTC(jd0, lat, lon, _civilZenith, rise: false)),
  );
}

/// Minutes-from-UTC-midnight of a rise/set event on the [jd0] date, in the
/// canonical east-positive NOAA form, with one refinement pass for accuracy.
/// Returns null when the sun does not reach [zenithDeg] (no event that day).
double? _eventMinutesUTC(
  double jd0,
  double lat,
  double lonEast,
  double zenithDeg, {
  required bool rise,
}) {
  double? pass(double jd) {
    final t = _julianCentury(jd);
    final eqTime = _eqOfTime(t); // minutes
    final dec = _sunDeclination(t);
    final ha = _hourAngle(lat, dec, zenithDeg); // degrees, or null at poles
    if (ha == null) return null;
    // sunrise: 720 - 4*(lon + HA) - eqTime ; sunset: 720 - 4*(lon - HA) - eqTime
    return 720 - 4 * (lonEast + (rise ? ha : -ha)) - eqTime;
  }

  final first = pass(jd0);
  if (first == null) return null;
  final refined = pass(jd0 + first / 1440.0);
  return refined ?? first;
}

/// Hour angle (degrees) at [zenithDeg]; null when |cos H| > 1 (polar).
double? _hourAngle(double latDeg, double decDeg, double zenithDeg) {
  final cosH = (_cosDeg(zenithDeg) - _sinDeg(latDeg) * _sinDeg(decDeg)) /
      (_cosDeg(latDeg) * _cosDeg(decDeg));
  if (cosH > 1 || cosH < -1) return null;
  return _rad2deg(math.acos(cosH));
}

double _julianDay(int year, int month, int day) {
  var y = year;
  var m = month;
  if (m <= 2) {
    y -= 1;
    m += 12;
  }
  final a = (y / 100).floor();
  final b = 2 - a + (a / 4).floor();
  return (365.25 * (y + 4716)).floor() +
      (30.6001 * (m + 1)).floor() +
      day +
      b -
      1524.5;
}

double _julianCentury(double jd) => (jd - 2451545.0) / 36525.0;

double _geomMeanLongSun(double t) =>
    (280.46646 + t * (36000.76983 + t * 0.0003032)) % 360;

double _geomMeanAnomSun(double t) =>
    357.52911 + t * (35999.05029 - 0.0001537 * t);

double _eccentEarthOrbit(double t) =>
    0.016708634 - t * (0.000042037 + 0.0000001267 * t);

double _sunEqOfCenter(double t) {
  final m = _deg2rad(_geomMeanAnomSun(t));
  return math.sin(m) * (1.914602 - t * (0.004817 + 0.000014 * t)) +
      math.sin(2 * m) * (0.019993 - 0.000101 * t) +
      math.sin(3 * m) * 0.000289;
}

double _sunTrueLong(double t) => _geomMeanLongSun(t) + _sunEqOfCenter(t);

double _sunAppLong(double t) =>
    _sunTrueLong(t) - 0.00569 - 0.00478 * _sinDeg(125.04 - 1934.136 * t);

double _meanObliqEcliptic(double t) =>
    23 + (26 + ((21.448 - t * (46.815 + t * (0.00059 - t * 0.001813)))) / 60) / 60;

double _obliqCorr(double t) =>
    _meanObliqEcliptic(t) + 0.00256 * _cosDeg(125.04 - 1934.136 * t);

double _sunDeclination(double t) {
  final e = _deg2rad(_obliqCorr(t));
  final lambda = _deg2rad(_sunAppLong(t));
  return _rad2deg(math.asin(math.sin(e) * math.sin(lambda)));
}

/// Equation of time, in minutes.
double _eqOfTime(double t) {
  final epsilon = _deg2rad(_obliqCorr(t));
  final l0 = _deg2rad(_geomMeanLongSun(t));
  final e = _eccentEarthOrbit(t);
  final m = _deg2rad(_geomMeanAnomSun(t));
  final y = math.tan(epsilon / 2) * math.tan(epsilon / 2);
  final eTime = y * math.sin(2 * l0) -
      2 * e * math.sin(m) +
      4 * e * y * math.sin(m) * math.cos(2 * l0) -
      0.5 * y * y * math.sin(4 * l0) -
      1.25 * e * e * math.sin(2 * m);
  return _rad2deg(eTime) * 4;
}

double _deg2rad(double deg) => deg * math.pi / 180.0;
double _rad2deg(double rad) => rad * 180.0 / math.pi;
double _sinDeg(double deg) => math.sin(_deg2rad(deg));
double _cosDeg(double deg) => math.cos(_deg2rad(deg));

String _hhmmLocal(DateTime utcInstant, Duration offset) {
  // utcInstant is isUtc; shifting then reading .hour/.minute yields the local
  // wall-clock components without a timezone database.
  final local = utcInstant.add(offset);
  return '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}
