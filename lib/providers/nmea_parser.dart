/// NMEA 0183 sentence parser — pure Dart, no I/O.
///
/// Parses the two position sentences a GPS receiver emits most often:
///   * `$GPRMC` / `$GNRMC` — Recommended Minimum: lat/lon, speed-over-ground
///     (knots), course-over-ground (degrees), and an A/V validity flag.
///   * `$GPGGA` / `$GNGGA` — Fix data: lat/lon, fix quality, HDOP (→ accuracy),
///     and altitude.
///
/// The two sentences are complementary — RMC carries speed + heading but no
/// accuracy/altitude; GGA carries accuracy (via HDOP) + altitude but no
/// speed/heading. A real receiver interleaves them. So this parser is
/// **stateful**: each parsed position sentence is merged with the most recent
/// complementary fields, so a GGA emitted just after an RMC yields a complete
/// [GeoPosition] (lat/lon + accuracy + speed + heading) — which the downstream
/// Kalman dead-reckoning filter needs to initialise.
///
/// Honest bounds: this is a glance-grade parser for the common RMC/GGA pair. It
/// does NOT cover GSA/GSV/VTG/GLL, multi-constellation deduplication, or the
/// rarer talker-ID variants beyond the GP/GN/GL/GA prefixes. Checksums are
/// validated when present and the sentence is rejected on mismatch; sentences
/// without a `*hh` suffix are accepted (checksum-optional), matching the lenient
/// behaviour of most consumer receivers.
library;

import 'package:kalman_dr/kalman_dr.dart';

/// A stateful NMEA position-sentence parser.
///
/// Feed it line-by-line via [parseLine]; it returns a [GeoPosition] for each
/// usable position sentence (a GGA with a non-zero fix quality, or an RMC with
/// status `A`), or `null` for everything else (other sentence types, void
/// fixes, malformed lines, checksum mismatches).
class NmeaParser {
  /// Metres of horizontal accuracy per unit of HDOP.
  ///
  /// Horizontal accuracy ≈ HDOP × UERE (user-equivalent range error). A
  /// nominal consumer UERE of ~5 m is the standard rule-of-thumb, so the
  /// classic HDOP 0.9 maps to ≈4.5 m (navigation-grade). This is an
  /// approximation, not a measured CEP.
  final double hdopToMeters;

  /// Fallback accuracy (m) attached to an RMC fix when no GGA HDOP has been
  /// seen yet. RMC carries no accuracy of its own; a real receiver always
  /// pairs it with a GGA, but on a cold start we may parse an RMC first.
  final double defaultRmcAccuracy;

  // Most-recent complementary fields, carried across sentences.
  double _lastAccuracy = double.nan; // from GGA HDOP
  double _lastAltitude = double.nan; // from GGA
  double _lastSpeed = double.nan; // from RMC (m/s)
  double _lastHeading = double.nan; // from RMC (deg)

  NmeaParser({
    this.hdopToMeters = 5.0,
    this.defaultRmcAccuracy = 25.0,
  });

  /// Parse a single NMEA line. Returns a [GeoPosition] for a usable position
  /// sentence, else `null`.
  GeoPosition? parseLine(String rawLine) {
    var line = rawLine.trim();
    if (line.isEmpty || !line.startsWith(r'$')) return null;

    // Validate + strip an optional checksum suffix ("*hh").
    final starIndex = line.indexOf('*');
    if (starIndex >= 0) {
      final body = line.substring(1, starIndex); // between '$' and '*'
      final given = line.substring(starIndex + 1).trim();
      if (given.length >= 2) {
        final expected = _checksum(body);
        final givenHex = given.substring(0, 2).toUpperCase();
        if (givenHex != expected) return null; // corrupt — reject
      }
      line = line.substring(0, starIndex);
    }

    final fields = line.split(',');
    if (fields.isEmpty) return null;

    final tag = fields[0]; // e.g. $GPRMC, $GNGGA
    if (tag.length < 6) return null;
    final type = tag.substring(3); // RMC / GGA (talker is 2 chars)

    switch (type) {
      case 'RMC':
        return _parseRmc(fields);
      case 'GGA':
        return _parseGga(fields);
      default:
        return null;
    }
  }

  /// `$xxRMC,time,status,lat,N/S,lon,E/W,sog(kn),cog(deg),date,...`
  GeoPosition? _parseRmc(List<String> f) {
    if (f.length < 9) return null;
    if (f[2] != 'A') return null; // V = void / no valid fix

    final lat = _ddmmToDecimal(f[3], f[4]);
    final lon = _ddmmToDecimal(f[5], f[6]);
    if (lat == null || lon == null) return null;

    final sogKnots = double.tryParse(f[7]);
    final cogDeg = double.tryParse(f[8]);
    final speedMs = sogKnots != null ? sogKnots * 0.514444 : double.nan;
    final headingDeg = cogDeg ?? double.nan;

    // Update carried state.
    if (!speedMs.isNaN) _lastSpeed = speedMs;
    if (!headingDeg.isNaN) _lastHeading = headingDeg;

    return GeoPosition(
      latitude: lat,
      longitude: lon,
      accuracy: _lastAccuracy.isNaN ? defaultRmcAccuracy : _lastAccuracy,
      altitude: _lastAltitude,
      speed: speedMs,
      heading: headingDeg,
      timestamp: DateTime.now(),
      // Decoded from a receiver's own sentence — measured, not inferred.
      source: PositionSource.measured,
      extrapolatedFor: Duration.zero,
    );
  }

  /// `$xxGGA,time,lat,N/S,lon,E/W,fixQ,numSat,hdop,alt,M,...`
  GeoPosition? _parseGga(List<String> f) {
    if (f.length < 10) return null;

    final fixQuality = int.tryParse(f[6]) ?? 0;
    if (fixQuality == 0) return null; // 0 = invalid / no fix

    final lat = _ddmmToDecimal(f[2], f[3]);
    final lon = _ddmmToDecimal(f[4], f[5]);
    if (lat == null || lon == null) return null;

    final hdop = double.tryParse(f[8]);
    final altitude = double.tryParse(f[9]) ?? double.nan;
    final accuracy =
        hdop != null ? hdop * hdopToMeters : defaultRmcAccuracy;

    // Update carried state.
    _lastAccuracy = accuracy;
    _lastAltitude = altitude;

    return GeoPosition(
      latitude: lat,
      longitude: lon,
      accuracy: accuracy,
      altitude: altitude,
      speed: _lastSpeed,
      heading: _lastHeading,
      timestamp: DateTime.now(),
      // Decoded from a receiver's own sentence — measured, not inferred.
      source: PositionSource.measured,
      extrapolatedFor: Duration.zero,
    );
  }

  /// Convert an NMEA `ddmm.mmmm` (lat) / `dddmm.mmmm` (lon) coordinate plus its
  /// hemisphere letter (N/S/E/W) into signed decimal degrees.
  ///
  /// The whole-minutes are always the two integer digits immediately left of
  /// the decimal point, so this handles both the 2-degree latitude and the
  /// 3-degree longitude forms without needing to know which it is.
  static double? _ddmmToDecimal(String value, String hemisphere) {
    if (value.isEmpty) return null;
    final dot = value.indexOf('.');
    // Integer portion (everything before the decimal, or the whole string).
    final intPart = dot >= 0 ? value.substring(0, dot) : value;
    if (intPart.length < 3) return null; // need at least d + mm
    final degStr = intPart.substring(0, intPart.length - 2);
    final minWholeStr = intPart.substring(intPart.length - 2);
    final fracStr = dot >= 0 ? value.substring(dot) : '';

    final degrees = int.tryParse(degStr);
    final minutes = double.tryParse('$minWholeStr$fracStr');
    if (degrees == null || minutes == null) return null;

    var decimal = degrees + minutes / 60.0;
    final h = hemisphere.toUpperCase();
    if (h == 'S' || h == 'W') decimal = -decimal;
    return decimal;
  }

  /// XOR checksum of the bytes between `$` and `*`, as a 2-char upper-hex.
  static String _checksum(String body) {
    var sum = 0;
    for (final code in body.codeUnits) {
      sum ^= code;
    }
    return sum.toRadixString(16).toUpperCase().padLeft(2, '0');
  }
}
