/// NmeaParser unit tests — pure-Dart RMC/GGA parsing.
///
/// Asserts the ddmm.mmmm → decimal-degrees conversion, hemisphere signs,
/// HDOP → accuracy, speed/heading carry-over, checksum handling, and rejection
/// of void / invalid / malformed sentences.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_snow_scene/providers/nmea_parser.dart';

void main() {
  group('GGA', () {
    test('classic GGA → 48.1173N, 11.5167E with HDOP-derived accuracy', () {
      final parser = NmeaParser();
      final pos = parser.parseLine(
        r'$GPGGA,123519,4807.038,N,01131.000,E,1,08,0.9,545.4,M,46.9,M,,*47',
      );
      expect(pos, isNotNull);
      expect(pos!.latitude, closeTo(48.1173, 0.0001));
      expect(pos.longitude, closeTo(11.5167, 0.0001));
      // HDOP 0.9 * 5.0 m/HDOP = 4.5 m → navigation-grade.
      expect(pos.accuracy, closeTo(4.5, 0.001));
      expect(pos.isNavigationGrade, isTrue);
      expect(pos.altitude, closeTo(545.4, 0.001));
    });

    test('GNGGA talker variant is accepted', () {
      final parser = NmeaParser();
      final pos = parser.parseLine(
        r'$GNGGA,123519,4807.038,N,01131.000,E,1,08,0.9,545.4,M,46.9,M,,*59',
      );
      expect(pos, isNotNull);
      expect(pos!.latitude, closeTo(48.1173, 0.0001));
    });

    test('GGA with fix quality 0 (invalid) → null', () {
      final parser = NmeaParser();
      final pos = parser.parseLine(
        r'$GPGGA,123519,4807.038,N,01131.000,E,0,00,99.9,,M,,M,,*45',
      );
      expect(pos, isNull);
    });

    test('southern + western hemisphere signs', () {
      final parser = NmeaParser();
      // 33°51.408'S, 151°12.480'E (Sydney-ish) and a W example.
      final pos = parser.parseLine(
        r'$GPGGA,000000,3351.408,S,15112.480,W,1,08,1.0,10.0,M,,M,,',
      );
      expect(pos, isNotNull);
      expect(pos!.latitude, closeTo(-(33 + 51.408 / 60), 0.0001));
      expect(pos.longitude, closeTo(-(151 + 12.480 / 60), 0.0001));
    });
  });

  group('RMC', () {
    test('active RMC → lat/lon + speed(m/s from knots) + heading', () {
      final parser = NmeaParser();
      final pos = parser.parseLine(
        r'$GPRMC,123519,A,4807.038,N,01131.000,E,022.4,084.4,230394,003.1,W*6A',
      );
      expect(pos, isNotNull);
      expect(pos!.latitude, closeTo(48.1173, 0.0001));
      expect(pos.longitude, closeTo(11.5167, 0.0001));
      // 22.4 knots * 0.514444 = 11.52 m/s.
      expect(pos.speed, closeTo(22.4 * 0.514444, 0.001));
      expect(pos.heading, closeTo(84.4, 0.001));
    });

    test('GNRMC talker variant is accepted', () {
      final parser = NmeaParser();
      final pos = parser.parseLine(
        r'$GNRMC,123519,A,4807.038,N,01131.000,E,000.0,000.0,230394,,*03',
      );
      expect(pos, isNotNull);
      expect(pos!.speed, closeTo(0.0, 0.001));
    });

    test('void RMC (status V) → null', () {
      final parser = NmeaParser();
      final pos = parser.parseLine(
        r'$GPRMC,123519,V,,,,,,,230394,,*33',
      );
      expect(pos, isNull);
    });
  });

  group('stateful merge', () {
    test('GGA after RMC carries speed+heading → Kalman-feedable', () {
      final parser = NmeaParser();
      // RMC first establishes speed + heading.
      final rmc = parser.parseLine(
        r'$GPRMC,123519,A,4807.038,N,01131.000,E,022.4,084.4,230394,003.1,W*6A',
      );
      expect(rmc, isNotNull);
      // GGA carries the carried speed/heading + its own HDOP accuracy.
      final gga = parser.parseLine(
        r'$GPGGA,123520,4807.040,N,01131.010,E,1,08,0.9,545.4,M,46.9,M,,*43',
      );
      expect(gga, isNotNull);
      expect(gga!.speed.isFinite, isTrue);
      expect(gga.heading.isFinite, isTrue);
      expect(gga.speed, closeTo(22.4 * 0.514444, 0.001));
      expect(gga.accuracy, closeTo(4.5, 0.001));
    });
  });

  group('checksum + malformed', () {
    test('valid checksum accepted, corrupt checksum rejected', () {
      final parser = NmeaParser();
      const good =
          r'$GPGGA,123519,4807.038,N,01131.000,E,1,08,0.9,545.4,M,46.9,M,,*47';
      expect(parser.parseLine(good), isNotNull);
      // Same body, wrong checksum byte.
      const bad =
          r'$GPGGA,123519,4807.038,N,01131.000,E,1,08,0.9,545.4,M,46.9,M,,*00';
      expect(parser.parseLine(bad), isNull);
    });

    test('non-position sentence (GSV) → null', () {
      final parser = NmeaParser();
      expect(
        parser.parseLine(r'$GPGSV,3,1,11,03,03,111,00,04,15,270,00*7F'),
        isNull,
      );
    });

    test('empty / garbage lines → null', () {
      final parser = NmeaParser();
      expect(parser.parseLine(''), isNull);
      expect(parser.parseLine('not an nmea line'), isNull);
      expect(parser.parseLine(r'$GPRMC'), isNull); // truncated
    });
  });
}
