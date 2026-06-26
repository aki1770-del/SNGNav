// Minimal usage example for pretrip_source_met_norway.
//
// Fetches a MET Norway hourly forecast for a point and hands the resulting
// WeatherForecast MEASUREMENT to the pretrip_decision_advisor so an edge
// developer can build their own pre-trip "Before you drive" surface. The
// locationforecast product is GLOBAL, so this works for a Nagoya commute
// (HER) and an Akita one (HER mother) as well as a Nordic one.
//
// MET Norway terms REQUIRE an identifying User-Agent naming your app plus a
// contact point. The placeholder below is NOT accepted by api.met.no (it
// returns HTTP 403). Replace `kUserAgent` with your own app + contact email,
// then re-run to see a live forecast. Until you do, this example DOES NOT
// crash: it prints guidance and runs an offline mapper demo instead.
import 'dart:io';

import 'package:pretrip_decision_advisor/pretrip_decision_advisor.dart';
import 'package:pretrip_source_met_norway/pretrip_source_met_norway.dart';

/// The placeholder User-Agent. MET Norway's terms of service REJECT a generic
/// identifier with HTTP 403, so a developer must set this to their own app
/// name plus a contact point before the live fetch will work.
const String kPlaceholderUserAgent = 'your_app/1.0 contact@example.com';

/// Edit this to your own app + contact email to enable the live fetch, e.g.
///   'my_commute_app/1.0 me@example.com'
const String kUserAgent = kPlaceholderUserAgent;

Future<void> main() async {
  if (kUserAgent == kPlaceholderUserAgent) {
    print(
      'MET Norway requires an identifying User-Agent: set it to your app + '
      'contact email, then re-run',
    );
    print('(edit kUserAgent in example/main.dart — see README/QUICKSTART)');
    print('');
    print('Running the offline mapper demo instead so you can see the shape:');
    _runOfflineMapperDemo();
    exit(0);
  }

  final provider = MetNorwayHourlyForecastProvider(userAgent: kUserAgent);
  try {
    // Nagoya (HER). Coordinates are truncated to 4 decimals before sending.
    final forecast = await provider.fetchForecast(
      latitude: 35.1709,
      longitude: 136.8815,
    );
    if (forecast == null) {
      // null = no usable hourly slice; the driver's own judgement, never a
      // fabricated hazard. Surface "no data", not "all clear".
      print('No usable hourly forecast for this point.');
      return;
    }

    _printBriefing(forecast);
  } on MetNorwayForecastException catch (e) {
    // The library keeps its loud typed throw on purpose. The example, however,
    // must never crash on a developer's first run: a 403 almost always means
    // the User-Agent is not yet an accepted identifier.
    if (e.message.contains('HTTP 403')) {
      print(
        'MET Norway requires an identifying User-Agent: set it to your app + '
        'contact email, then re-run',
      );
      exit(0);
    }
    // Any other typed failure (timeout, non-JSON, oversize) is also surfaced
    // as one clear line rather than an unhandled stack trace.
    print('MET Norway forecast unavailable: ${e.message}');
    exit(0);
  } finally {
    provider.close();
  }
}

/// Maps a tiny bundled locationforecast/2.0/compact sample (no network) so the
/// example always produces a real briefing, even before the User-Agent is set.
void _runOfflineMapperDemo() {
  final forecast = mapLocationForecastToWeatherForecast(_sampleCompactResponse);
  if (forecast == null) {
    print('No usable hourly forecast in the offline sample.');
    return;
  }
  _printBriefing(forecast);
}

void _printBriefing(WeatherForecast forecast) {
  const advisor = SnowAwarePretripAdvisor();
  final briefing = advisor.brief(
    forecast: forecast,
    commute: CommuteShape(
      plannedDeparture: DateTime.now().add(const Duration(minutes: 30)),
      plannedDuration: const Duration(minutes: 30),
      routeIdentifiers: const ['morning-commute'],
      flexibility: CommuteFlexibility.discretionary,
    ),
    profile: const DriverProfileSpec(
      profileTag: 'demo',
      reactionTimeSeconds: 1.5,
    ),
  );

  print('Verdict: ${briefing.verdict.name}');
  print('Peak hazard: ${briefing.peakHazard.name}');
  // Attribution is REQUIRED wherever the data is shown:
  //   Data from MET Norway (https://api.met.no/) —
  //   data dual-licensed under NLOD 2.0 AND CC BY 4.0.
}

/// A minimal, structurally faithful compact-product sample for the offline
/// demo. Two hourly slices with a `next_1_hours` block, near-freezing with
/// light precipitation. Not a forecast for any real place or time.
final Map<String, dynamic> _sampleCompactResponse = <String, dynamic>{
  'properties': <String, dynamic>{
    'meta': <String, dynamic>{'updated_at': '2024-01-15T06:00:00Z'},
    'timeseries': <dynamic>[
      <String, dynamic>{
        'time': '2024-01-15T07:00:00Z',
        'data': <String, dynamic>{
          'instant': <String, dynamic>{
            'details': <String, dynamic>{
              'air_temperature': 0.5,
              'relative_humidity': 92.0,
            },
          },
          'next_1_hours': <String, dynamic>{
            'details': <String, dynamic>{'precipitation_amount': 0.8},
          },
        },
      },
      <String, dynamic>{
        'time': '2024-01-15T08:00:00Z',
        'data': <String, dynamic>{
          'instant': <String, dynamic>{
            'details': <String, dynamic>{
              'air_temperature': -0.3,
              'relative_humidity': 95.0,
            },
          },
          'next_1_hours': <String, dynamic>{
            'details': <String, dynamic>{'precipitation_amount': 1.2},
          },
        },
      },
    ],
  },
};
