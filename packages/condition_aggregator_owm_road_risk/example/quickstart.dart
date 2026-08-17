import 'package:condition_aggregator_owm_road_risk/condition_aggregator_owm_road_risk.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;

Future<void> main() async {
  // MockClient stands in for OpenWeatherMap so this runs offline.
  // In production: OwmRoadRiskProvider.withApiKey(apiKey: 'your-key').
  final mock = MockClient((req) async => http.Response(
      '[{"alerts":[{"event":"Black ice","event_level":3,'
      '"sender_name":"NWS Buffalo","description":"Black ice on US-219."}]}]',
      200));
  final provider = OwmRoadRiskProvider.withApiKey(apiKey: 'demo', httpClient: mock);

  final advisories = await provider.fetchActiveAdvisoriesAtPoint(
      latitude: 42.886, longitude: -78.879);
  for (final a in advisories) {
    print('${a.severity.name.toUpperCase()}: ${a.eventClass} — ${a.description}');
  }
  provider.close();
}
