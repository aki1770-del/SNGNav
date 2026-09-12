// Hand-written `dart:ffi` bindings for the iceoryx2 C API.
//
// Author: rust-systems-engineer (RSE), 2026-09-12.
// SPDX-License-Identifier: Apache-2.0
//
// The opaque-handle / NULL-allocation pattern was proven first, in Dart,
// against this library, by youndong (GitHub @youndong) in 2025. His binding
// reaches 22 iox2_* symbols; this file reaches 20; 16 are common. His work was
// contributed to a repository that is dual-licensed Apache-2.0 OR MIT, so it
// sits under both; this package is Apache-2.0. Credit where the path was
// already walked. (A first draft of this header said "the same 22-symbol
// shape" and "both sides Apache-2.0" -- both misstated his position, and were
// corrected on WDA's measurement, 2026-09-12.)
//
// WHY THIS FILE IS WRITTEN BY HAND AND NOT BY ffigen
// -------------------------------------------------
// ffigen was run against this exact header on 2026-09-12. It produced 25,581
// lines and 60 struct definitions, and TWO of those struct sizes were WRONG,
// silently: ffigen drops `__attribute__((aligned(n)))` and emits no `@ffi.Align`
// anywhere. Nothing in its output says which two. A generated binding that is
// 58/60 correct and does not know which two are wrong is worse than no binding,
// because it is trusted.
//
// So: OPAQUE HANDLES ONLY. Every iceoryx2 type here is `Pointer<Opaque>`. Dart
// never states the size of an iceoryx2 struct, and every caller-allocatable
// struct pointer is passed as `nullptr` so the LIBRARY heap-allocates it with
// its own idea of the size. A size Dart never wrote is a size Dart cannot get
// wrong. This is the path measured working from Dart against the real library.
//
// The ONE layout Dart declares is `sngnav_road_friction_t`, in
// road_friction_source.dart, because a payload has to be read. That is the
// single place where a Dart-declared layout meets a C-declared layout in this
// package, by design, and it is the place the ABI layout check is pointed at.
//
// ~~~ NO VERSION SYMBOL EXISTS ~~~
// Measured on the built libiceoryx2_ffi_c.so, 2026-09-12:
//     nm -D --defined-only ... | grep -iE 'version|abi|revision|semver|commit'
//     -> nothing, across 660 exported iox2_* symbols.
// The library cannot be asked what it is. A stale .so IS UNDETECTABLE AT OPEN.
// `Iox2Library.open` therefore verifies only that the symbols it needs RESOLVE,
// which catches a wrong library but not an old one. Stated rather than faked.

import 'dart:ffi' as ffi;

/// Success return value shared by the whole iceoryx2 C API (`IOX2_OK`).
const int iox2Ok = 0;

/// `iox2_service_type_e_IPC` — cross-process. `_LOCAL` (0) is same-process only.
const int iox2ServiceTypeIpc = 1;

/// `iox2_type_variant_e_FIXED_SIZE`.
const int iox2TypeVariantFixedSize = 0;

/// `iox2_log_level_e_WARN`. INFO is 2 in the same enum; WARN keeps the probe quiet.
const int iox2LogLevelWarn = 3;

// --- Native signatures ------------------------------------------------------
// Every handle is Pointer<Opaque>. An `_h_ref` in the C header is
// `const iox2_x_h *` — a pointer TO the handle — so it is Pointer<Pointer<Opaque>>
// here. Getting that indirection wrong is the one mistake this style still
// allows, so each is annotated with the C declaration it mirrors.

// iox2_node_builder_h iox2_node_builder_new(struct iox2_node_builder_t *)
typedef _NodeBuilderNewNative = ffi.Pointer<ffi.Opaque> Function(ffi.Pointer<ffi.Void>);
typedef Iox2NodeBuilderNewDart = ffi.Pointer<ffi.Opaque> Function(ffi.Pointer<ffi.Void>);

// int iox2_node_builder_create(iox2_node_builder_h, struct iox2_node_t *,
//                              enum iox2_service_type_e, iox2_node_h *)
typedef _NodeBuilderCreateNative = ffi.Int Function(
    ffi.Pointer<ffi.Opaque>, ffi.Pointer<ffi.Void>, ffi.Int32, ffi.Pointer<ffi.Pointer<ffi.Opaque>>);
typedef Iox2NodeBuilderCreateDart = int Function(
    ffi.Pointer<ffi.Opaque>, ffi.Pointer<ffi.Void>, int, ffi.Pointer<ffi.Pointer<ffi.Opaque>>);

// void iox2_node_drop(iox2_node_h)
typedef _DropHandleNative = ffi.Void Function(ffi.Pointer<ffi.Opaque>);
typedef Iox2DropHandleDart = void Function(ffi.Pointer<ffi.Opaque>);

// int iox2_node_wait(iox2_node_h_ref, uint64_t sec, uint32_t nsec)
typedef _NodeWaitNative = ffi.Int Function(ffi.Pointer<ffi.Pointer<ffi.Opaque>>, ffi.Uint64, ffi.Uint32);
typedef Iox2NodeWaitDart = int Function(ffi.Pointer<ffi.Pointer<ffi.Opaque>>, int, int);

// int iox2_service_name_new(struct iox2_service_name_t *, const char *,
//                           c_size_t, iox2_service_name_h *)
typedef _ServiceNameNewNative = ffi.Int Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Uint8>,
    ffi.Size, ffi.Pointer<ffi.Pointer<ffi.Opaque>>);
typedef Iox2ServiceNameNewDart = int Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Uint8>, int,
    ffi.Pointer<ffi.Pointer<ffi.Opaque>>);

// iox2_service_name_ptr iox2_cast_service_name_ptr(iox2_service_name_h)
typedef _CastServiceNamePtrNative = ffi.Pointer<ffi.Opaque> Function(ffi.Pointer<ffi.Opaque>);
typedef Iox2CastServiceNamePtrDart = ffi.Pointer<ffi.Opaque> Function(ffi.Pointer<ffi.Opaque>);

// iox2_service_builder_h iox2_node_service_builder(iox2_node_h_ref,
//     struct iox2_service_builder_t *, iox2_service_name_ptr)
typedef _NodeServiceBuilderNative = ffi.Pointer<ffi.Opaque> Function(
    ffi.Pointer<ffi.Pointer<ffi.Opaque>>, ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Opaque>);
typedef Iox2NodeServiceBuilderDart = ffi.Pointer<ffi.Opaque> Function(
    ffi.Pointer<ffi.Pointer<ffi.Opaque>>, ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Opaque>);

// iox2_service_builder_pub_sub_h iox2_service_builder_pub_sub(iox2_service_builder_h)
typedef _ServiceBuilderPubSubNative = ffi.Pointer<ffi.Opaque> Function(ffi.Pointer<ffi.Opaque>);
typedef Iox2ServiceBuilderPubSubDart = ffi.Pointer<ffi.Opaque> Function(ffi.Pointer<ffi.Opaque>);

// int iox2_service_builder_pub_sub_set_payload_type_details(
//     iox2_service_builder_pub_sub_h_ref, enum iox2_type_variant_e,
//     const char *, c_size_t, c_size_t size, c_size_t alignment)
typedef _SetPayloadTypeDetailsNative = ffi.Int Function(ffi.Pointer<ffi.Pointer<ffi.Opaque>>,
    ffi.Int32, ffi.Pointer<ffi.Uint8>, ffi.Size, ffi.Size, ffi.Size);
typedef Iox2SetPayloadTypeDetailsDart = int Function(
    ffi.Pointer<ffi.Pointer<ffi.Opaque>>, int, ffi.Pointer<ffi.Uint8>, int, int, int);

// int iox2_service_builder_pub_sub_open_or_create(iox2_service_builder_pub_sub_h,
//     struct iox2_port_factory_pub_sub_t *, iox2_port_factory_pub_sub_h *)
typedef _PubSubOpenOrCreateNative = ffi.Int Function(
    ffi.Pointer<ffi.Opaque>, ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Pointer<ffi.Opaque>>);
typedef Iox2PubSubOpenOrCreateDart = int Function(
    ffi.Pointer<ffi.Opaque>, ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Pointer<ffi.Opaque>>);

// iox2_port_factory_subscriber_builder_h
//     iox2_port_factory_pub_sub_subscriber_builder(iox2_port_factory_pub_sub_h_ref,
//         struct iox2_port_factory_subscriber_builder_t *)
typedef _SubscriberBuilderNative = ffi.Pointer<ffi.Opaque> Function(
    ffi.Pointer<ffi.Pointer<ffi.Opaque>>, ffi.Pointer<ffi.Void>);
typedef Iox2SubscriberBuilderDart = ffi.Pointer<ffi.Opaque> Function(
    ffi.Pointer<ffi.Pointer<ffi.Opaque>>, ffi.Pointer<ffi.Void>);

// int iox2_port_factory_subscriber_builder_create(
//     iox2_port_factory_subscriber_builder_h, struct iox2_subscriber_t *,
//     iox2_subscriber_h *)
typedef _SubscriberCreateNative = ffi.Int Function(
    ffi.Pointer<ffi.Opaque>, ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Pointer<ffi.Opaque>>);
typedef Iox2SubscriberCreateDart = int Function(
    ffi.Pointer<ffi.Opaque>, ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Pointer<ffi.Opaque>>);

// int iox2_subscriber_receive(iox2_subscriber_h_ref, struct iox2_sample_t *,
//                             iox2_sample_h *)
typedef _SubscriberReceiveNative = ffi.Int Function(ffi.Pointer<ffi.Pointer<ffi.Opaque>>,
    ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Pointer<ffi.Opaque>>);
typedef Iox2SubscriberReceiveDart = int Function(
    ffi.Pointer<ffi.Pointer<ffi.Opaque>>, ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Pointer<ffi.Opaque>>);

// void iox2_sample_payload(iox2_sample_h_ref, const void **, c_size_t *)
typedef _SamplePayloadNative = ffi.Void Function(ffi.Pointer<ffi.Pointer<ffi.Opaque>>,
    ffi.Pointer<ffi.Pointer<ffi.Void>>, ffi.Pointer<ffi.Size>);
typedef Iox2SamplePayloadDart = void Function(ffi.Pointer<ffi.Pointer<ffi.Opaque>>,
    ffi.Pointer<ffi.Pointer<ffi.Void>>, ffi.Pointer<ffi.Size>);

// c_size_t iox2_sample_payload_number_of_bytes(iox2_sample_h_ref)
typedef _SamplePayloadBytesNative = ffi.Size Function(ffi.Pointer<ffi.Pointer<ffi.Opaque>>);
typedef Iox2SamplePayloadBytesDart = int Function(ffi.Pointer<ffi.Pointer<ffi.Opaque>>);

// void iox2_set_log_level_from_env_or(enum iox2_log_level_e)
typedef _SetLogLevelNative = ffi.Void Function(ffi.Int32);
typedef Iox2SetLogLevelDart = void Function(int);

/// Thrown when the iceoryx2 shared library cannot be opened or is not the
/// library this binding was written against.
class Iox2LibraryException implements Exception {
  Iox2LibraryException(this.message);
  final String message;
  @override
  String toString() => 'Iox2LibraryException: $message';
}

/// Resolved iceoryx2 C entry points.
///
/// Holds no state of its own beyond the resolved function pointers; lifetime
/// of nodes, services and samples belongs to the caller.
class Iox2Library {
  Iox2Library._(
    this._lib, {
    required this.nodeBuilderNew,
    required this.nodeBuilderCreate,
    required this.nodeDrop,
    required this.nodeWait,
    required this.serviceNameNew,
    required this.serviceNameDrop,
    required this.castServiceNamePtr,
    required this.nodeServiceBuilder,
    required this.serviceBuilderPubSub,
    required this.setPayloadTypeDetails,
    required this.pubSubOpenOrCreate,
    required this.pubSubDrop,
    required this.subscriberBuilder,
    required this.subscriberCreate,
    required this.subscriberReceive,
    required this.subscriberDrop,
    required this.samplePayload,
    required this.samplePayloadNumberOfBytes,
    required this.sampleDrop,
    required this.setLogLevelFromEnvOr,
  });

  /// Opens [path] and resolves every symbol this binding uses.
  ///
  /// Resolution is eager and total on purpose: a missing symbol surfaces here,
  /// at open, NAMING ITSELF — never at the first receive, three layers down, as
  /// a null dereference. `lookupFunction` cannot be called through a type
  /// variable, so each symbol is written out; that verbosity is what makes each
  /// native signature readable next to the C declaration it mirrors.
  ///
  /// This CANNOT detect a stale-but-compatible library. There is no version
  /// symbol to ask (measured; see the file header).
  factory Iox2Library.open(String path) {
    final ffi.DynamicLibrary lib;
    try {
      lib = ffi.DynamicLibrary.open(path);
    } on ArgumentError catch (e) {
      throw Iox2LibraryException(
        'could not open iceoryx2 library at "$path": $e\n'
        'Build it with tool/build_iceoryx2.sh and pass the ICEORYX2_LIB it prints.',
      );
    }

    // Tracks which symbol is being resolved, so a failure names the symbol
    // rather than just saying a lookup failed.
    var symbol = '';
    T step<T>(String name, T Function() resolve) {
      symbol = name;
      return resolve();
    }

    try {
      return Iox2Library._(
        lib,
        nodeBuilderNew: step('iox2_node_builder_new',
            () => lib.lookupFunction<_NodeBuilderNewNative, Iox2NodeBuilderNewDart>(
                'iox2_node_builder_new')),
        nodeBuilderCreate: step('iox2_node_builder_create',
            () => lib.lookupFunction<_NodeBuilderCreateNative, Iox2NodeBuilderCreateDart>(
                'iox2_node_builder_create')),
        nodeDrop: step('iox2_node_drop',
            () => lib.lookupFunction<_DropHandleNative, Iox2DropHandleDart>('iox2_node_drop')),
        nodeWait: step('iox2_node_wait',
            () => lib.lookupFunction<_NodeWaitNative, Iox2NodeWaitDart>('iox2_node_wait')),
        serviceNameNew: step('iox2_service_name_new',
            () => lib.lookupFunction<_ServiceNameNewNative, Iox2ServiceNameNewDart>(
                'iox2_service_name_new')),
        serviceNameDrop: step('iox2_service_name_drop',
            () => lib.lookupFunction<_DropHandleNative, Iox2DropHandleDart>(
                'iox2_service_name_drop')),
        castServiceNamePtr: step('iox2_cast_service_name_ptr',
            () => lib.lookupFunction<_CastServiceNamePtrNative, Iox2CastServiceNamePtrDart>(
                'iox2_cast_service_name_ptr')),
        nodeServiceBuilder: step('iox2_node_service_builder',
            () => lib.lookupFunction<_NodeServiceBuilderNative, Iox2NodeServiceBuilderDart>(
                'iox2_node_service_builder')),
        serviceBuilderPubSub: step('iox2_service_builder_pub_sub',
            () => lib.lookupFunction<_ServiceBuilderPubSubNative, Iox2ServiceBuilderPubSubDart>(
                'iox2_service_builder_pub_sub')),
        setPayloadTypeDetails: step(
            'iox2_service_builder_pub_sub_set_payload_type_details',
            () => lib.lookupFunction<_SetPayloadTypeDetailsNative, Iox2SetPayloadTypeDetailsDart>(
                'iox2_service_builder_pub_sub_set_payload_type_details')),
        pubSubOpenOrCreate: step('iox2_service_builder_pub_sub_open_or_create',
            () => lib.lookupFunction<_PubSubOpenOrCreateNative, Iox2PubSubOpenOrCreateDart>(
                'iox2_service_builder_pub_sub_open_or_create')),
        pubSubDrop: step('iox2_port_factory_pub_sub_drop',
            () => lib.lookupFunction<_DropHandleNative, Iox2DropHandleDart>(
                'iox2_port_factory_pub_sub_drop')),
        subscriberBuilder: step('iox2_port_factory_pub_sub_subscriber_builder',
            () => lib.lookupFunction<_SubscriberBuilderNative, Iox2SubscriberBuilderDart>(
                'iox2_port_factory_pub_sub_subscriber_builder')),
        subscriberCreate: step('iox2_port_factory_subscriber_builder_create',
            () => lib.lookupFunction<_SubscriberCreateNative, Iox2SubscriberCreateDart>(
                'iox2_port_factory_subscriber_builder_create')),
        subscriberReceive: step('iox2_subscriber_receive',
            () => lib.lookupFunction<_SubscriberReceiveNative, Iox2SubscriberReceiveDart>(
                'iox2_subscriber_receive')),
        subscriberDrop: step('iox2_subscriber_drop',
            () => lib.lookupFunction<_DropHandleNative, Iox2DropHandleDart>(
                'iox2_subscriber_drop')),
        samplePayload: step('iox2_sample_payload',
            () => lib.lookupFunction<_SamplePayloadNative, Iox2SamplePayloadDart>(
                'iox2_sample_payload')),
        samplePayloadNumberOfBytes: step('iox2_sample_payload_number_of_bytes',
            () => lib.lookupFunction<_SamplePayloadBytesNative, Iox2SamplePayloadBytesDart>(
                'iox2_sample_payload_number_of_bytes')),
        sampleDrop: step('iox2_sample_drop',
            () => lib.lookupFunction<_DropHandleNative, Iox2DropHandleDart>('iox2_sample_drop')),
        setLogLevelFromEnvOr: step('iox2_set_log_level_from_env_or',
            () => lib.lookupFunction<_SetLogLevelNative, Iox2SetLogLevelDart>(
                'iox2_set_log_level_from_env_or')),
      );
    } on ArgumentError {
      throw Iox2LibraryException(
        'iceoryx2 library at "$path" does not export "$symbol". This is not the '
        'library these bindings were written against (iceoryx2 @ 05a3a8fa59b8).',
      );
    }
  }

  final ffi.DynamicLibrary _lib;

  final Iox2NodeBuilderNewDart nodeBuilderNew;
  final Iox2NodeBuilderCreateDart nodeBuilderCreate;
  final Iox2DropHandleDart nodeDrop;
  final Iox2NodeWaitDart nodeWait;
  final Iox2ServiceNameNewDart serviceNameNew;
  final Iox2DropHandleDart serviceNameDrop;
  final Iox2CastServiceNamePtrDart castServiceNamePtr;
  final Iox2NodeServiceBuilderDart nodeServiceBuilder;
  final Iox2ServiceBuilderPubSubDart serviceBuilderPubSub;
  final Iox2SetPayloadTypeDetailsDart setPayloadTypeDetails;
  final Iox2PubSubOpenOrCreateDart pubSubOpenOrCreate;
  final Iox2DropHandleDart pubSubDrop;
  final Iox2SubscriberBuilderDart subscriberBuilder;
  final Iox2SubscriberCreateDart subscriberCreate;
  final Iox2SubscriberReceiveDart subscriberReceive;
  final Iox2DropHandleDart subscriberDrop;
  final Iox2SamplePayloadDart samplePayload;
  final Iox2SamplePayloadBytesDart samplePayloadNumberOfBytes;
  final Iox2DropHandleDart sampleDrop;
  final Iox2SetLogLevelDart setLogLevelFromEnvOr;

  /// Exposed so a caller can resolve a symbol this binding does not wrap.
  ffi.DynamicLibrary get dynamicLibrary => _lib;
}
