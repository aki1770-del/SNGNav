library;

import 'package:driving_consent/driving_consent.dart';
import 'package:driving_weather/driving_weather.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalman_dr/kalman_dr.dart';

import 'package:sngnav_snow_scene/bloc/consent_event.dart';
import 'package:sngnav_snow_scene/bloc/location_event.dart';
import 'package:sngnav_snow_scene/bloc/weather_event.dart';

void main() {
  final position = GeoPosition(
    latitude: 35.1709,
    longitude: 136.8815,
    accuracy: 5,
    timestamp: DateTime(2026, 3, 12),
  );
  final condition = WeatherCondition.clear(
    timestamp: DateTime(2026, 3, 12),
  );

  group('ConsentEvent props', () {
    test('load event uses base empty props', () {
      expect(const ConsentLoadRequested().props, isEmpty);
    });

    test('grant and revoke events expose purpose-scoped props', () {
      expect(
        const ConsentGrantRequested(
          purpose: ConsentPurpose.fleetLocation,
          jurisdiction: Jurisdiction.appi,
        ).props,
        [ConsentPurpose.fleetLocation, Jurisdiction.appi],
      );
      expect(
        const ConsentRevokeRequested(
          purpose: ConsentPurpose.fleetLocation,
        ).props,
        [ConsentPurpose.fleetLocation],
      );
    });
  });

  group('LocationEvent props', () {
    test('start, stop, and stale timeout use base empty props', () {
      expect(const LocationStartRequested().props, isEmpty);
      expect(const LocationStopRequested().props, isEmpty);
      expect(const LocationStaleTimeout().props, isEmpty);
    });

    test('position and error events expose payload props', () {
      expect(LocationPositionReceived(position).props, [position]);
      expect(const LocationErrorOccurred('gps lost').props, ['gps lost']);
    });
  });

  group('WeatherEvent props', () {
    test('start and stop monitoring use base empty props', () {
      expect(const WeatherMonitorStarted().props, isEmpty);
      expect(const WeatherMonitorStopped().props, isEmpty);
    });

    test('condition and error events expose payload props', () {
      expect(WeatherConditionReceived(condition).props, [condition]);
      expect(const WeatherErrorOccurred('network down').props, ['network down']);
    });
  });
}