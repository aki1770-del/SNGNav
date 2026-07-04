import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:routing_engine/routing_engine.dart';
import 'package:routing_engine/src/maneuver_localizer.dart';

void main() async {
  print('=== CORRECTED types (review fixes applied) ===');
  for (final t in ['sharp_left','sharp_right','slight_left','ramp_right','ramp','proceed','roundabout_exit']) {
    final named = ManeuverLocalizer.localize(language: 'ja-JP', type: t, streetName: '県道1号', englishFallback: () => '[EN]');
    final bare = ManeuverLocalizer.localize(language: 'ja-JP', type: t, englishFallback: () => '[EN]');
    print('  ${t.padRight(16)} named: ${named.padRight(26)} bare: $bare');
  }
  print('  roundabout+exit3 bare : ${ManeuverLocalizer.localize(language: 'ja-JP', type: 'roundabout_enter', roundaboutExit: 3)}');
  print('  roundabout+exit2 named: ${ManeuverLocalizer.localize(language: 'ja-JP', type: 'roundabout_enter', roundaboutExit: 2, streetName: '国道153号')}');

  print('\n=== end-to-end via real engine: hairpin + multi-exit roundabout + side-less ramp ===');
  final steps = [
    {'name':'国道13号','distance':1800.0,'duration':160.0,'maneuver':{'type':'depart','modifier':'','location':[140.10,39.71]}},
    {'name':'山道','distance':900.0,'duration':120.0,'maneuver':{'type':'turn','modifier':'sharp right','location':[140.12,39.70]}},
    {'name':'国道153号','distance':500.0,'duration':60.0,'maneuver':{'type':'roundabout','modifier':'','exit':2,'location':[140.14,39.69]}},
    {'name':'','distance':700.0,'duration':80.0,'maneuver':{'type':'on ramp','modifier':'','location':[140.15,39.68]}},
    {'name':'','distance':300.0,'duration':40.0,'maneuver':{'type':'','modifier':'','location':[140.16,39.67]}},
    {'name':'','distance':0.0,'duration':0.0,'maneuver':{'type':'arrive','modifier':'','location':[140.18,39.65]}},
  ];
  final client = MockClient((r) async => http.Response.bytes(
    utf8.encode(jsonEncode({'code':'Ok','routes':[{'geometry':'_p~iF~ps|U','distance':4200.0,'duration':460.0,'legs':[{'steps':steps}]}]})),
    200, headers: {'content-type':'application/json; charset=utf-8'}));
  final engine = OsrmRoutingEngine(baseUrl:'http://test', client: client);
  final res = await engine.calculateRoute(const RouteRequest(origin: LatLng(39.71,140.10), destination: LatLng(39.65,140.18)));
  for (final m in res.maneuvers) { print('  #${m.index} [${m.type.padRight(16)}] ${m.instruction}'); }
  await engine.dispose();
}
