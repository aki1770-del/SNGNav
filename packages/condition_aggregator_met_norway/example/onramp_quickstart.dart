// Quickstart: turn a MET Norway forecast slice into a driver-actionable
// Advisory — no network needed to see the value. Run: dart run example/onramp_quickstart.dart
import 'package:condition_aggregator_met_norway/condition_aggregator_met_norway.dart';

void main() {
  // A next-hour slice shaped like MET Norway locationforecast/2.0/compact:
  // -2 C with 5 mm/h precipitation = freezing + heavy = winter road hazard.
  final advisory = mapLocationForecastResponseToAdvisory(response: {
    'geometry': {'type': 'Point', 'coordinates': [10.75, 59.91]},
    'properties': {'timeseries': [
      {'time': '2026-01-15T08:00:00Z', 'data': {
        'instant': {'details': {'air_temperature': -2.0}},
        'next_1_hours': {'summary': {'symbol_code': 'snow'},
          'details': {'precipitation_amount': 5.0}},
      }},
    ]},
  });
  print('${advisory!.eventClass} (${advisory.severity.name}) — ${advisory.headline}');
  print('  ${advisory.areaDescription} | expires ${advisory.expires}');
  print('  ${advisory.description}');
}
