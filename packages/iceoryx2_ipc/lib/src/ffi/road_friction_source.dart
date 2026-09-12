// Road-friction samples read from iceoryx2 shared memory, cross-process.
//
// Author: rust-systems-engineer (RSE), 2026-09-12.
// SPDX-License-Identifier: Apache-2.0
//
// Symbol set and NULL-allocation pattern first proven in Dart by youndong
// (GitHub @youndong), 2025; Apache-2.0 on both sides.
//
// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
// THERE IS NO VERSION SYMBOL. A STALE LIBRARY IS UNDETECTABLE AT OPEN.
// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
// Measured on the built libiceoryx2_ffi_c.so, 2026-09-12:
//
//     nm -D --defined-only libiceoryx2_ffi_c.so \
//       | grep -iE 'version|abi|revision|semver|build_info|commit'
//     -> no output, across 660 exported iox2_* symbols
//
// iceoryx2 exports nothing that says what it is. [iceoryx2SourceSha] below
// records the commit these bindings were WRITTEN against, and that is a
// written claim, not a checked one: `open` cannot compare it to anything,
// because there is nothing in the library to compare it to. An honest absence
// beats a check that cannot fire.
//
// What IS actually checked, and it is worth knowing which is which:
//   * every symbol used resolves at open, by name (catches a wrong library,
//     not an old one);
//   * iceoryx2's own service-open refuses a payload type whose NAME, SIZE or
//     ALIGNMENT disagrees with the publisher's — a coarse cross-process guard
//     that does NOT see a field reorder at constant width;
//   * every received sample's payload byte count is compared to
//     `sizeOf<NativeRoadFriction>()` before a single byte is dereferenced.
//
// That last one is the scar. A stale-size probe written by this seat returned
// IOX2_OK with 88 bytes clobbered, and the 0.6.x arity defect this codebase
// carries returned 0.312216 on a 0-1 safety scale instead of crashing. A wrong
// layout here does not announce itself; it produces a plausible number about
// how much grip a car has on a road. So it is checked, and the failure is an
// exception rather than a value.

import 'dart:ffi' as ffi;

import 'iox2_bindings.dart';

/// The iceoryx2 commit these bindings were written and proven against.
///
/// Recorded, not enforced — see the file header. If you build against another
/// commit, this string is the only thing that will tell a later reader.
const String iceoryx2SourceSha = '05a3a8fa59b87af5ced3af12f9145d4f46de472b';

/// The iceoryx2 service name both ends open. Must equal
/// `SNGNAV_ROAD_FRICTION_SERVICE` in native/sngnav_road_friction.h.
const String roadFrictionServiceName = 'sngnav/road_friction';

/// The payload type name iceoryx2 records with the service. Must equal
/// `SNGNAV_ROAD_FRICTION_TYPE_NAME` in native/sngnav_road_friction.h.
const String roadFrictionTypeName = 'sngnav_road_friction_t';

/// The wire layout of `sngnav_road_friction_t`.
///
/// THIS IS THE ONE PLACE IN THIS PACKAGE WHERE A DART-DECLARED LAYOUT MEETS A
/// C-DECLARED LAYOUT. Everything else on the iceoryx2 side is an opaque
/// handle, deliberately, so that this is the only surface where the two can
/// disagree — and it is the surface `abi_layout_check.dart` is pointed at:
///
///     dart run ../driving_conditions/tool/abi_layout_check.dart \
///       --c native/sngnav_road_friction.h \
///       --dart lib/src/ffi/road_friction_source.dart \
///       --pair sngnav_road_friction_t=NativeRoadFriction
///
/// Field names differ in case from the C side on purpose; that check matches
/// by normalised name, never by position, because position-matching is nearly
/// a tautology.
final class NativeRoadFriction extends ffi.Struct {
  @ffi.Double()
  external double frictionPercent;

  @ffi.Int64()
  external int measuredAtUnixNs;

  @ffi.Uint32()
  external int sequence;

  @ffi.Uint8()
  external int quality;

  @ffi.Uint8()
  external int reserved0;

  @ffi.Uint8()
  external int reserved1;

  @ffi.Uint8()
  external int reserved2;
}

/// One road-friction reading, or the measured fact that there was none.
final class RoadFrictionSample {
  const RoadFrictionSample({
    required this.frictionPercent,
    required this.measuredAtUnixNs,
    required this.sequence,
  });

  /// Road friction in PERCENT, 0-100 — the VSS convention, not a 0.0-1.0
  /// ratio.
  ///
  /// `null` when and only when the wire carried `quality == 0`. Absence does
  /// not ride the measurement scale: there is no percentage that means "we did
  /// not measure", because every percentage means something about grip.
  final double? frictionPercent;

  final int measuredAtUnixNs;
  final int sequence;

  @override
  String toString() => 'RoadFrictionSample(seq=$sequence, '
      'friction=${frictionPercent ?? "NOT MEASURED"}, at=$measuredAtUnixNs)';
}

/// A source of road-friction samples.
///
/// Consumers code against this, not against iceoryx2. A fake implementation is
/// a class with a list and a cursor; that is the point.
abstract interface class RoadFrictionSource {
  /// The next sample, or `null` when none has arrived. Never blocks.
  RoadFrictionSample? tryReceive();

  void dispose();
}

/// Thrown when the wire does not carry what this binding expects.
///
/// Loud on purpose. The alternative to throwing here is returning a number.
class RoadFrictionWireException implements Exception {
  RoadFrictionWireException(this.message);
  final String message;
  @override
  String toString() => 'RoadFrictionWireException: $message';
}

// libc, resolved from the running process rather than from `package:ffi`.
//
// This keeps the whole FFI layer dependency-free — `dart:ffi` and nothing
// else — so it cannot be broken by a change to a pubspec owned by another
// seat. Linux host only, which is this package's entire declared scope.
typedef _CallocNative = ffi.Pointer<ffi.Void> Function(ffi.Size, ffi.Size);
typedef _CallocDart = ffi.Pointer<ffi.Void> Function(int, int);
typedef _FreeNative = ffi.Void Function(ffi.Pointer<ffi.Void>);
typedef _FreeDart = void Function(ffi.Pointer<ffi.Void>);

class _Libc {
  _Libc._(this.calloc, this.free);

  factory _Libc.process() {
    final p = ffi.DynamicLibrary.process();
    return _Libc._(
      p.lookupFunction<_CallocNative, _CallocDart>('calloc'),
      p.lookupFunction<_FreeNative, _FreeDart>('free'),
    );
  }

  final _CallocDart calloc;
  final _FreeDart free;

  /// A NUL-terminated copy of [s] in native memory. ASCII only — service and
  /// type names in this package are ASCII by construction, and a silent
  /// truncation of a multi-byte name would produce a service mismatch that
  /// looks like "no publisher".
  ffi.Pointer<ffi.Uint8> cString(String s) {
    final units = s.codeUnits;
    for (final u in units) {
      if (u > 0x7f) {
        throw RoadFrictionWireException(
          'name "$s" is not ASCII; this binding will not guess an encoding for '
          'a value iceoryx2 matches byte-for-byte.',
        );
      }
    }
    final p = calloc(units.length + 1, 1).cast<ffi.Uint8>();
    for (var i = 0; i < units.length; i++) {
      p[i] = units[i];
    }
    p[units.length] = 0;
    return p;
  }
}

/// A [RoadFrictionSource] backed by a real iceoryx2 publish-subscribe service.
///
/// Every caller-allocatable iceoryx2 struct is passed as `nullptr`, so the
/// library heap-allocates it at its own size. Dart never states the size of an
/// iceoryx2 struct, so a size Dart got wrong cannot exist.
final class Iox2RoadFrictionSource implements RoadFrictionSource {
  Iox2RoadFrictionSource._(
    this._iox2,
    this._libc,
    this._nodeSlot,
    this._serviceSlot,
    this._subscriberSlot,
    this._sampleSlot,
    this._payloadSlot,
  );

  /// Opens the `sngnav/road_friction` service and creates a subscriber.
  ///
  /// Returns as soon as the subscriber exists. A publisher need not be running
  /// yet — `open_or_create` makes the service, and [tryReceive] simply returns
  /// `null` until one appears.
  factory Iox2RoadFrictionSource.open({
    String libraryPath = 'libiceoryx2_ffi_c.so',
    String nodeName = 'sngnav_subscriber',
  }) {
    final iox2 = Iox2Library.open(libraryPath);
    final libc = _Libc.process();
    iox2.setLogLevelFromEnvOr(iox2LogLevelWarn);

    // Handle slots. An `_h_ref` argument in the C header is `const iox2_x_h *`
    // — a pointer TO the handle — so each handle that is later passed by ref
    // lives in its own native slot for the object's whole life.
    final nodeSlot = libc.calloc(1, ffi.sizeOf<ffi.Pointer<ffi.Opaque>>())
        .cast<ffi.Pointer<ffi.Opaque>>();
    final serviceSlot = libc.calloc(1, ffi.sizeOf<ffi.Pointer<ffi.Opaque>>())
        .cast<ffi.Pointer<ffi.Opaque>>();
    final subscriberSlot = libc.calloc(1, ffi.sizeOf<ffi.Pointer<ffi.Opaque>>())
        .cast<ffi.Pointer<ffi.Opaque>>();
    final sampleSlot = libc.calloc(1, ffi.sizeOf<ffi.Pointer<ffi.Opaque>>())
        .cast<ffi.Pointer<ffi.Opaque>>();
    final payloadSlot =
        libc.calloc(1, ffi.sizeOf<ffi.Pointer<ffi.Void>>()).cast<ffi.Pointer<ffi.Void>>();

    ffi.Pointer<ffi.Uint8> serviceNameStr = ffi.nullptr;
    ffi.Pointer<ffi.Uint8> typeNameStr = ffi.nullptr;
    ffi.Pointer<ffi.Opaque> serviceNameHandle = ffi.nullptr;
    final serviceNameSlot = libc.calloc(1, ffi.sizeOf<ffi.Pointer<ffi.Opaque>>())
        .cast<ffi.Pointer<ffi.Opaque>>();

    void freeSlots() {
      libc.free(nodeSlot.cast());
      libc.free(serviceSlot.cast());
      libc.free(subscriberSlot.cast());
      libc.free(sampleSlot.cast());
      libc.free(payloadSlot.cast());
    }

    try {
      // NULL for the struct pointer: the library allocates the node builder.
      final nodeBuilder = iox2.nodeBuilderNew(ffi.nullptr);
      var rc = iox2.nodeBuilderCreate(
          nodeBuilder, ffi.nullptr, iox2ServiceTypeIpc, nodeSlot);
      if (rc != iox2Ok) {
        throw RoadFrictionWireException('iox2_node_builder_create failed, error $rc');
      }

      serviceNameStr = libc.cString(roadFrictionServiceName);
      rc = iox2.serviceNameNew(
          ffi.nullptr, serviceNameStr, roadFrictionServiceName.length, serviceNameSlot);
      if (rc != iox2Ok) {
        throw RoadFrictionWireException('iox2_service_name_new failed, error $rc');
      }
      serviceNameHandle = serviceNameSlot.value;

      final serviceNamePtr = iox2.castServiceNamePtr(serviceNameHandle);
      final serviceBuilder =
          iox2.nodeServiceBuilder(nodeSlot, ffi.nullptr, serviceNamePtr);
      final pubSubSlot = libc.calloc(1, ffi.sizeOf<ffi.Pointer<ffi.Opaque>>())
          .cast<ffi.Pointer<ffi.Opaque>>();
      pubSubSlot.value = iox2.serviceBuilderPubSub(serviceBuilder);

      // sizeOf<NativeRoadFriction>() is measured by the Dart VM from the
      // declaration above; iceoryx2 compares it to the publisher's compiler-
      // measured sizeof and REFUSES a mismatch. Neither side is asked to
      // believe a literal.
      typeNameStr = libc.cString(roadFrictionTypeName);
      rc = iox2.setPayloadTypeDetails(
        pubSubSlot,
        iox2TypeVariantFixedSize,
        typeNameStr,
        roadFrictionTypeName.length,
        ffi.sizeOf<NativeRoadFriction>(),
        _roadFrictionAlignment,
      );
      if (rc != iox2Ok) {
        libc.free(pubSubSlot.cast());
        throw RoadFrictionWireException(
          'iox2_service_builder_pub_sub_set_payload_type_details failed, error $rc',
        );
      }

      rc = iox2.pubSubOpenOrCreate(pubSubSlot.value, ffi.nullptr, serviceSlot);
      libc.free(pubSubSlot.cast());
      if (rc != iox2Ok) {
        throw RoadFrictionWireException(
          'iox2_service_builder_pub_sub_open_or_create failed, error $rc. '
          'A publisher already running with a DIFFERENT payload size, '
          'alignment or type name for "$roadFrictionServiceName" is the '
          'likeliest cause, and iceoryx2 refusing it is the behaviour we want.',
        );
      }

      final subBuilder = iox2.subscriberBuilder(serviceSlot, ffi.nullptr);
      rc = iox2.subscriberCreate(subBuilder, ffi.nullptr, subscriberSlot);
      if (rc != iox2Ok) {
        throw RoadFrictionWireException(
          'iox2_port_factory_subscriber_builder_create failed, error $rc',
        );
      }

      return Iox2RoadFrictionSource._(
          iox2, libc, nodeSlot, serviceSlot, subscriberSlot, sampleSlot, payloadSlot);
    } catch (_) {
      freeSlots();
      rethrow;
    } finally {
      if (serviceNameHandle != ffi.nullptr) {
        iox2.serviceNameDrop(serviceNameHandle);
      }
      if (serviceNameStr != ffi.nullptr) libc.free(serviceNameStr.cast());
      if (typeNameStr != ffi.nullptr) libc.free(typeNameStr.cast());
      libc.free(serviceNameSlot.cast());
    }
  }

  /// Alignment of `sngnav_road_friction_t`.
  ///
  /// Dart exposes no `alignOf`. The struct is a double, an int64, a uint32 and
  /// four uint8 with NO alignment attributes, so its alignment is that of its
  /// widest member: 8. The value is not merely asserted here — the ABI layout
  /// check measures the C side with `_Alignof` and compares, and iceoryx2
  /// refuses the service if the publisher's compiler-measured alignment
  /// disagrees with this number. A wrong value fails loudly at open.
  static const int _roadFrictionAlignment = 8;

  final Iox2Library _iox2;
  final _Libc _libc;
  final ffi.Pointer<ffi.Pointer<ffi.Opaque>> _nodeSlot;
  final ffi.Pointer<ffi.Pointer<ffi.Opaque>> _serviceSlot;
  final ffi.Pointer<ffi.Pointer<ffi.Opaque>> _subscriberSlot;
  final ffi.Pointer<ffi.Pointer<ffi.Opaque>> _sampleSlot;
  final ffi.Pointer<ffi.Pointer<ffi.Void>> _payloadSlot;
  bool _disposed = false;

  @override
  RoadFrictionSample? tryReceive() {
    if (_disposed) {
      throw StateError('tryReceive() on a disposed Iox2RoadFrictionSource');
    }

    _sampleSlot.value = ffi.nullptr;
    final rc = _iox2.subscriberReceive(_subscriberSlot, ffi.nullptr, _sampleSlot);
    if (rc != iox2Ok) {
      throw RoadFrictionWireException('iox2_subscriber_receive failed, error $rc');
    }
    if (_sampleSlot.value == ffi.nullptr) {
      return null; // nothing published since the last call
    }

    try {
      // THE SCAR CHECK. Compare what arrived to what we are about to read
      // BEFORE reading it. A stale-size probe by this seat returned IOX2_OK
      // with 88 bytes clobbered; iceoryx2's own type check runs at service
      // open, not per sample, so this is the per-sample backstop.
      final bytes = _iox2.samplePayloadNumberOfBytes(_sampleSlot);
      final expected = ffi.sizeOf<NativeRoadFriction>();
      if (bytes != expected) {
        throw RoadFrictionWireException(
          'payload is $bytes bytes, this binding expects $expected. Refusing '
          'to read it. The publisher and this binding do not agree on '
          '$roadFrictionTypeName; do not trust a friction value from either '
          'until they do.',
        );
      }

      _payloadSlot.value = ffi.nullptr;
      _iox2.samplePayload(_sampleSlot, _payloadSlot, ffi.nullptr);
      if (_payloadSlot.value == ffi.nullptr) {
        throw RoadFrictionWireException(
          'iox2_sample_payload returned a null payload for a non-null sample',
        );
      }

      final native = _payloadSlot.value.cast<NativeRoadFriction>().ref;

      // The absence discipline, at the one point it can be enforced: quality
      // is read FIRST, and when it says NOT MEASURED the friction field is
      // never looked at. It is not clamped, not defaulted, not passed through
      // a fallback. It becomes null, and null is what the sink turns into
      // `unknown`.
      final measured = native.quality != 0;
      return RoadFrictionSample(
        frictionPercent: measured ? native.frictionPercent : null,
        measuredAtUnixNs: native.measuredAtUnixNs,
        sequence: native.sequence,
      );
    } finally {
      // The sample is released on EVERY path, including the throwing ones. A
      // leaked sample holds a shared-memory slot and the publisher runs out of
      // them silently.
      _iox2.sampleDrop(_sampleSlot.value);
      _sampleSlot.value = ffi.nullptr;
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    // Reverse construction order: subscriber, then service, then node.
    if (_subscriberSlot.value != ffi.nullptr) _iox2.subscriberDrop(_subscriberSlot.value);
    if (_serviceSlot.value != ffi.nullptr) _iox2.pubSubDrop(_serviceSlot.value);
    if (_nodeSlot.value != ffi.nullptr) _iox2.nodeDrop(_nodeSlot.value);
    _libc.free(_nodeSlot.cast());
    _libc.free(_serviceSlot.cast());
    _libc.free(_subscriberSlot.cast());
    _libc.free(_sampleSlot.cast());
    _libc.free(_payloadSlot.cast());
  }
}
