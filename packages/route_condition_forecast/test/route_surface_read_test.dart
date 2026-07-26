import 'package:driving_weather/driving_weather.dart';
import 'package:latlong2/latlong.dart';
import 'package:route_condition_forecast/route_condition_forecast.dart';
import 'package:test/test.dart';

SegmentConditionForecast seg(int index, WeatherCondition condition) {
  return SegmentConditionForecast(
    segment: RouteSegment(
      index: index,
      start: const LatLng(39.7, 140.1),
      end: const LatLng(39.8, 140.2),
      distanceKm: 1.0,
    ),
    condition: condition,
    hazardZones: const [],
    etaSeconds: 60.0 * index,
    confidence: 1.0,
  );
}

void main() {
  // Grounded on the real classifier contract (snow_rendering 0.3.0):
  // positive iceRisk classifies alone; deep cold classifies alone;
  // unreported precip at mild temperature CANNOT classify (null, never dry).
  final t = DateTime.utc(2026, 1, 15, 5); // fixed observation time
  const src = ObservationSource.measured;
  final blackIceSeg =
      seg(0, WeatherCondition(iceRisk: true, source: src, timestamp: t));
  final deepColdSeg = seg(
      1, WeatherCondition(temperatureCelsius: -5, source: src, timestamp: t));
  final drySeg = seg(
    2,
    WeatherCondition(
      temperatureCelsius: 10,
      precipType: PrecipitationType.none,
      source: src,
      timestamp: t,
    ),
  );
  final unknownSeg = seg(
      3, WeatherCondition(temperatureCelsius: 5, source: src, timestamp: t));

  test('per-segment surfaceState preserves the null-is-not-dry contract', () {
    expect(blackIceSeg.surfaceState, RoadSurfaceState.blackIce);
    expect(drySeg.surfaceState, RoadSurfaceState.dry);
    expect(unknownSeg.surfaceState, isNull); // cannot classify — NOT dry
  });

  test('fold: worst classified surface wins, unknowns are COUNTED not skipped',
      () {
    final read = surfaceAlongRoute([drySeg, blackIceSeg, unknownSeg]);
    expect(read.worstClassified, RoadSurfaceState.blackIce);
    expect(read.worstSegmentIndex, 1); // position in the folded list
    expect(read.unclassifiedSegmentCount, 1); // the unknown is TOLD
    expect(read.segmentCount, 3);
  });

  test('tie keeps the EARLIEST segment (first place she meets that surface)',
      () {
    final read = surfaceAlongRoute([blackIceSeg, deepColdSeg]);
    expect(read.worstClassified, RoadSurfaceState.blackIce);
    expect(read.worstSegmentIndex, 0);
  });

  test('all-unknown route: no invented surface, every segment counted', () {
    final read = surfaceAlongRoute([unknownSeg, unknownSeg]);
    expect(read.worstClassified, isNull);
    expect(read.worstSegmentIndex, isNull);
    expect(read.unclassifiedSegmentCount, 2);
    expect(read.segmentCount, 2);
  });

  test('empty route folds to nothing claimed', () {
    final read = surfaceAlongRoute(const []);
    expect(read.worstClassified, isNull);
    expect(read.unclassifiedSegmentCount, 0);
    expect(read.segmentCount, 0);
  });
}
