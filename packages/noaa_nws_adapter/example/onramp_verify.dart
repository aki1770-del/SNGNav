import 'package:noaa_nws_adapter/noaa_nws_adapter.dart';

void main() async {
  final client = NoaaNwsClient(userAgent: '(myapp.example.com, you@example.com)');
  try {
    // Active winter alerts near these coordinates (Grand Forks, ND).
    final alerts = await client.fetchActiveWinterAlerts(
      latitude: 47.9253,
      longitude: -97.0329,
    );
    print('Active winter alerts: ${alerts.length}');
    for (final a in alerts) {
      print('• ${a.event} [${a.severity.name}] — ${a.headline}');
    }
  } on NoaaNwsHttpException catch (e) {
    print('NWS unreachable: $e'); // honest failure; never a fake "all clear"
  } finally {
    client.close();
  }
}
