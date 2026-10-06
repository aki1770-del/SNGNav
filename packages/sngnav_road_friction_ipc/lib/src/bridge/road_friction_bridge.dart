// SPDX-FileCopyrightText: 2026 Akihiko Komada <aki1770@gmail.com>
// SPDX-License-Identifier: Apache-2.0

/// The bridge from an iceoryx2 sample to our classification asset.
///
/// This file contains no transport code and no FFI. It takes a
/// [RoadFrictionSource] — any source, the real `Iox2RoadFrictionSource` or a
/// fake — and turns each sample into a [RoadFrictionReading] produced by
/// `RoadFriction.classify` from `package:kuksa_dart_sdk`.
///
/// The point of routing through that one function rather than re-deriving a
/// verdict here is that the iceoryx2 path and the KUKSA path then answer
/// identically. A second threshold table living in this package is a second
/// place for "the road is fine" to be wrong.
///
/// **The absence discipline, end to end.** The wire carries `quality == 0` for
/// "not measured"; the source maps that to a null [RoadFrictionSample.frictionPercent];
/// `classify(null)` returns [RoadGrip.unknown]. Absence never rides the
/// measurement scale, and it is never answered as grip.
library;

import 'package:kuksa_dart_sdk/kuksa_dart_sdk.dart';

import '../ffi/road_friction_source.dart';

/// One received sample, classified, with the wire metadata kept alongside.
///
/// The sequence number is retained because it is the only way a consumer can
/// see that samples were dropped — iceoryx2 publish-subscribe does not block a
/// publisher for a slow subscriber, so a gap here is real information and not
/// noise to be smoothed away.
final class ClassifiedRoadFriction {
  /// Wraps [reading] with the wire metadata it arrived with.
  const ClassifiedRoadFriction({
    required this.sequence,
    required this.measuredAtUnixNs,
    required this.reading,
  });

  /// Publisher-assigned sequence number, as received.
  final int sequence;

  /// Publisher's measurement timestamp, nanoseconds since the Unix epoch.
  final int measuredAtUnixNs;

  /// The verdict, from `RoadFriction.classify`.
  final RoadFrictionReading reading;

  /// The grip verdict.
  RoadGrip get grip => reading.grip;

  /// True when there is a usable measurement behind this sample.
  bool get isKnown => reading.isKnown;

  @override
  String toString() => 'ClassifiedRoadFriction(seq=$sequence, $reading)';
}

/// Polls a [RoadFrictionSource] and classifies what it returns.
///
/// The bridge owns no thread and no timer of its own beyond [watch]'s poll
/// interval, and it does not buffer. [tryNext] is a single non-blocking poll,
/// which keeps the caller in control of cadence — an IVI render loop and a
/// command-line demo want very different ones.
final class RoadFrictionBridge {
  /// Binds the bridge to [source]. Ownership of [source] stays with the caller
  /// unless [dispose] is called here.
  RoadFrictionBridge(this._source);

  final RoadFrictionSource _source;

  /// Polls once. Returns `null` when no new sample was available — which is
  /// *not* the same as an unknown reading, and is deliberately a different
  /// value: "nothing arrived" and "a sample arrived saying the road was not
  /// measured" are different facts and a caller may need to tell them apart.
  ClassifiedRoadFriction? tryNext() {
    final sample = _source.tryReceive();
    if (sample == null) return null;
    return classifySample(sample);
  }

  /// Classifies [sample] without touching the transport.
  ///
  /// Exposed because it is the whole of the bridge's logic, and a test should
  /// be able to reach it without staging a source.
  static ClassifiedRoadFriction classifySample(RoadFrictionSample sample) {
    return ClassifiedRoadFriction(
      sequence: sample.sequence,
      measuredAtUnixNs: sample.measuredAtUnixNs,
      // The single classification rule. Null percent — the wire's quality == 0
      // — becomes RoadGrip.unknown inside classify, never here.
      reading: RoadFriction.classify(sample.frictionPercent),
    );
  }

  /// Polls every [pollInterval] and emits each sample as it arrives.
  ///
  /// Stops when the returned subscription is cancelled. Errors from the source
  /// are forwarded to the stream rather than swallowed: a transport that has
  /// died is something the consumer must be told about, because the alternative
  /// is a screen that quietly keeps showing the last thing it knew.
  Stream<ClassifiedRoadFriction> watch({
    Duration pollInterval = const Duration(milliseconds: 20),
  }) async* {
    while (true) {
      final next = tryNext();
      if (next != null) {
        yield next;
      } else {
        await Future<void>.delayed(pollInterval);
      }
    }
  }

  /// Disposes the underlying source.
  void dispose() => _source.dispose();
}
