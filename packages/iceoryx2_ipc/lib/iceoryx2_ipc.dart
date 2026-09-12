// SPDX-FileCopyrightText: 2026 Akihiko Komada <aki1770@gmail.com>
// SPDX-License-Identifier: Apache-2.0

/// Zero-copy road-condition samples over Eclipse iceoryx2, classified by the
/// same rule the KUKSA path uses.
///
/// A publisher writes `sngnav_road_friction_t` into shared memory; this package
/// receives it and hands each sample to `RoadFriction.classify` from
/// `package:kuksa_dart_sdk`, so an iceoryx2 consumer and a KUKSA consumer
/// cannot disagree about whether a road is icy.
///
/// **Bounds.** Host Linux x86_64 only, today. Not verified on the IVI target,
/// not verified on aarch64 at runtime, and iceoryx2's own Android support is
/// inter-thread only. See README.md — the bounds are on the package's face
/// rather than in a commit message, because a consumer reads the former.
library;

export 'src/bridge/road_friction_bridge.dart';
export 'src/ffi/road_friction_source.dart';
