import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:routing_engine/routing_engine.dart';

const _localDefaultBaseUrl = 'http://localhost:8005';
const _publicDefaultBaseUrl = 'https://valhalla1.openstreetmap.de';
const _warmRequestCount = 5;
const _reusedClientCount = 3;

final _request = RouteRequest(
  origin: const LatLng(35.1709, 136.9066),
  destination: const LatLng(34.9551, 137.1771),
  costing: 'auto',
  language: 'ja-JP',
);

Future<void> main() async {
  final localBaseUrl = _normalizeBaseUrl(
    Platform.environment['LOCAL_VALHALLA_BASE_URL'] ??
        Platform.environment['VALHALLA_BASE_URL'] ??
        _localDefaultBaseUrl,
  );
  final publicBaseUrl = _normalizeBaseUrl(
    Platform.environment['PUBLIC_VALHALLA_BASE_URL'] ?? _publicDefaultBaseUrl,
  );
  final runPublic =
      (Platform.environment['RUN_PUBLIC_VALHALLA_BENCHMARK'] ?? '1') != '0';

  final localStatus = await _fetchStatus(localBaseUrl);
  if (!localStatus.available) {
    stderr.writeln(
      'Local Valhalla is unavailable at $localBaseUrl. Start the daemon first.',
    );
    exitCode = 1;
    return;
  }

  final coldLocal = await _runColdSample(localBaseUrl);
  final warmLocal = await _runWarmSeries(localBaseUrl, _warmRequestCount);
  final reusedLocal = await _runReusedClientSeries(
    localBaseUrl,
    _reusedClientCount,
  );

  Sample? publicSample;
  StatusSnapshot? publicStatus;
  Object? publicError;
  if (runPublic) {
    publicStatus = await _fetchStatus(publicBaseUrl);
    try {
      publicSample = await _runColdSample(
        publicBaseUrl,
        routeTimeout: const Duration(seconds: 20),
      );
    } catch (error) {
      publicError = error;
    }
  }

  stdout.writeln('# Valhalla Benchmark');
  stdout.writeln();
  stdout.writeln('Machine: ${Platform.operatingSystem}');
  stdout.writeln(
    'Engine: local Valhalla ${localStatus.version ?? 'unknown'} at $localBaseUrl',
  );
  stdout.writeln(
    'Dataset: Sprint 18 hierarchy-preserving local hierarchy (operator-provided)',
  );
  stdout.writeln(
    'Route family: Sakae Station (35.1709,136.9066) -> Higashiokazaki Station (34.9551,137.1771)',
  );
  stdout.writeln('Request shape: auto, ja-JP, kilometers');
  stdout.writeln();
  stdout.writeln(
    'Cold request: ${_formatSample(coldLocal)} (connection reuse: no)',
  );
  stdout.writeln(
    'Warm request mean: ${_formatSeconds(warmLocal.mean)} ' 
    '(min ${_formatSeconds(warmLocal.min)}, max ${_formatSeconds(warmLocal.max)}) ' 
    '[${warmLocal.samples.length} samples, connection reuse: no]',
  );
  stdout.writeln(
    'Reused-client series: ${_formatSeries(reusedLocal.samples)} ' 
    '(mean ${_formatSeconds(reusedLocal.mean)}, min ${_formatSeconds(reusedLocal.min)}, ' 
    'max ${_formatSeconds(reusedLocal.max)}) [connection reuse: yes]',
  );

  if (runPublic) {
    if (publicSample != null) {
      final delta = publicSample.latency - warmLocal.mean;
      stdout.writeln(
        'Comparison to public baseline: fresh public exact-payload rerun at '
        '$publicBaseUrl = ${_formatSample(publicSample)}; '
        'delta vs local warm mean = ${_formatSignedSeconds(delta)}.',
      );
      if (publicStatus != null) {
        stdout.writeln(
          'Public status: ${publicStatus.version ?? 'unknown'} '
          '(${publicStatus.available ? 'reachable' : 'status unavailable'})',
        );
      }
    } else {
      stdout.writeln(
        'Comparison to public baseline: public rerun failed at $publicBaseUrl '
        '(${publicError ?? 'unknown error'}).',
      );
    }
  } else {
    stdout.writeln(
      'Comparison to public baseline: skipped by RUN_PUBLIC_VALHALLA_BENCHMARK=0.',
    );
  }

  stdout.writeln(
    'Interpretation: local Valhalla removes most network latency on the fixed '
    'Sakae -> Higashiokazaki payload and provides a repeatable developer loop.',
  );
  stdout.writeln('Propagation required: yes');
}

Future<Sample> _runColdSample(
  String baseUrl, {
  Duration routeTimeout = const Duration(seconds: 15),
}) async {
  final engine = ValhallaRoutingEngine(
    baseUrl: baseUrl,
    routeTimeout: routeTimeout,
  );
  try {
    return await _runSample(engine);
  } finally {
    await engine.dispose();
  }
}

Future<SeriesSummary> _runWarmSeries(String baseUrl, int count) async {
  final samples = <Sample>[];
  for (var index = 0; index < count; index++) {
    samples.add(await _runColdSample(baseUrl));
  }
  return SeriesSummary(samples);
}

Future<SeriesSummary> _runReusedClientSeries(String baseUrl, int count) async {
  final engine = ValhallaRoutingEngine(baseUrl: baseUrl);
  final samples = <Sample>[];
  try {
    for (var index = 0; index < count; index++) {
      samples.add(await _runSample(engine));
    }
  } finally {
    await engine.dispose();
  }
  return SeriesSummary(samples);
}

Future<Sample> _runSample(ValhallaRoutingEngine engine) async {
  final route = await engine.calculateRoute(_request);
  return Sample(
    latency: route.engineInfo.queryLatency,
    distanceKm: route.totalDistanceKm,
    routeTimeSeconds: route.totalTimeSeconds,
    shapePoints: route.shape.length,
    maneuvers: route.maneuvers.length,
  );
}

Future<StatusSnapshot> _fetchStatus(String baseUrl) async {
  final client = http.Client();
  try {
    final response = await client
        .get(Uri.parse('$baseUrl/status'))
        .timeout(const Duration(seconds: 5));
    if (response.statusCode != 200) {
      return const StatusSnapshot(available: false);
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return StatusSnapshot(
      available: true,
      version: json['version'] as String?,
    );
  } catch (_) {
    return const StatusSnapshot(available: false);
  } finally {
    client.close();
  }
}

String _normalizeBaseUrl(String baseUrl) =>
    baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;

String _formatSample(Sample sample) =>
    '${_formatSeconds(sample.latency)}; route ${sample.distanceKm.toStringAsFixed(3)} km, '
    '${sample.routeTimeSeconds.toStringAsFixed(3)} s, '
    '${sample.shapePoints} shape pts, ${sample.maneuvers} maneuvers';

String _formatSeries(List<Sample> samples) =>
    samples.map((sample) => _formatSeconds(sample.latency)).join(', ');

String _formatSeconds(Duration duration) =>
    '${(duration.inMicroseconds / 1000000).toStringAsFixed(6)} s';

String _formatSignedSeconds(Duration duration) {
  final sign = duration.isNegative ? '-' : '+';
  return '$sign${_formatSeconds(duration.abs())}';
}

class Sample {
  const Sample({
    required this.latency,
    required this.distanceKm,
    required this.routeTimeSeconds,
    required this.shapePoints,
    required this.maneuvers,
  });

  final Duration latency;
  final double distanceKm;
  final double routeTimeSeconds;
  final int shapePoints;
  final int maneuvers;
}

class SeriesSummary {
  SeriesSummary(this.samples);

  final List<Sample> samples;

  Duration get min =>
      samples.map((sample) => sample.latency).reduce(_shorterDuration);

  Duration get max =>
      samples.map((sample) => sample.latency).reduce(_longerDuration);

  Duration get mean {
    final totalMicroseconds = samples.fold<int>(
      0,
      (sum, sample) => sum + sample.latency.inMicroseconds,
    );
    return Duration(microseconds: totalMicroseconds ~/ samples.length);
  }

  static Duration _shorterDuration(Duration left, Duration right) =>
      left <= right ? left : right;

  static Duration _longerDuration(Duration left, Duration right) =>
      left >= right ? left : right;
}

class StatusSnapshot {
  const StatusSnapshot({required this.available, this.version});

  final bool available;
  final String? version;
}