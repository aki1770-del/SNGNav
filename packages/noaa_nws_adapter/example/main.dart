// ignore_for_file: avoid_print
//
// Minimal example for noaa_nws_adapter.
//
// Demonstrates constructing the NoaaNwsClient. The publisher (NWS)
// requires every request to carry a User-Agent of the form
// "(myappname.com, contact@email.com)" — the adapter does NOT default
// a User-Agent; constructing without one is a programmer error and
// raises ArgumentError up-front rather than 403-ing later.

import 'package:noaa_nws_adapter/noaa_nws_adapter.dart';

void main() {
  final client = NoaaNwsClient(
    userAgent: '(myapp.example.com, contact@example.com)',
  );
  print('NWS API base: ${client.apiBase}');
  print('Accept header: ${client.acceptHeader}');
  print('Winter event types catalogued: ${kNwsWinterEventTypes.length}');
  client.close();
}
