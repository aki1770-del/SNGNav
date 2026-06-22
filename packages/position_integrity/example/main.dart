// A worked example: feed a synthetic fix stream through the integrity floor and
// watch it catch a GPS multipath teleport that the accuracy number hides.
//
// Run it:  dart run example/main.dart
//
// The story: a driver heads north out of town at ~20 m/s. Halfway through, the
// GPS reflects off a snow-loaded building and the fix teleports 200 m sideways
// onto the next street — with a perfectly normal accuracy number. The floor
// sees a physically impossible jump, says so, and recommends a safe source.
import 'package:position_integrity/position_integrity.dart';

void main() {
  final monitor = PositionIntegrityMonitor();

  // 39.70°N, 140.10°E — rural Akita. Build a north-bound track at ~20 m/s.
  const baseLat = 39.70;
  const baseLon = 140.10;
  const mPerLatDeg = 111194.93; // metres per degree latitude
  final start = DateTime(2026, 1, 1, 7, 0, 0);

  PositionFix fix(double northMetres, double eastMetres, int second) =>
      PositionFix(
        latitude: baseLat + northMetres / mPerLatDeg,
        longitude: baseLon + eastMetres / (mPerLatDeg * 0.77), // cos(39.7°)
        accuracyMetres: 6, // a normal, confident-looking accuracy throughout
        timestamp: start.add(Duration(seconds: second)),
      );

  // second -> (north m, east m). At t=5 the fix teleports 200 m east.
  final track = <int, List<double>>{
    0: [0, 0],
    1: [20, 0],
    2: [40, 0],
    3: [60, 0],
    4: [80, 0],
    5: [100, 200], // <-- multipath: 200 m sideways jump, same accuracy
    6: [120, 0], // GPS recovers
    7: [140, 0],
  };

  // Pretend the app also runs a dead-reckoning estimate that is currently fresh.
  const drAge = Duration(seconds: 3);

  print('t   status    source         reason');
  print('--  --------  -------------  ------------------------------------------');
  track.forEach((second, offset) {
    final v = monitor.update(
      fix(offset[0], offset[1], second),
      deadReckoningAge: drAge,
    );
    print('${second.toString().padRight(3)} '
        '${v.status.name.padRight(8)}  '
        '${v.recommendedSource.name.padRight(13)}  '
        '${v.reason}');
  });

  print('\nThe floor flagged the teleport the instant it arrived — the app can '
      'suppress the wrong-street turn and hold the dead-reckoned dot until GPS '
      'is trustworthy again. No network, no calibration, no road graph.');
}
