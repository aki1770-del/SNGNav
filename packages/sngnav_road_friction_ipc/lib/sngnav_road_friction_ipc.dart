// SPDX-FileCopyrightText: 2026 Akihiko Komada <aki1770@gmail.com>
// SPDX-License-Identifier: Apache-2.0

/// Zero-copy road-condition samples over Eclipse iceoryx™ (iceoryx2™) shared
/// memory, classified by `RoadFriction.classify` from `kuksa_dart_sdk`, the
/// same rule that package applies to friction read over Eclipse KUKSA™. The
/// rule is `kuksa_dart_sdk`'s, not the Eclipse KUKSA™ project's.
///
/// A publisher writes `sngnav_road_friction_t` into shared memory; this package
/// receives it and hands each sample to `RoadFriction.classify` from
/// `package:kuksa_dart_sdk`, so an iceoryx2™ consumer and a KUKSA™ consumer
/// cannot disagree about whether a road is icy.
///
/// **Bounds.** Host Linux x86_64 only, today. Not verified on the IVI target,
/// not verified on aarch64 at runtime, and iceoryx2™'s own Android support is
/// inter-thread only. See README.md — the bounds are on the package's face
/// rather than in a commit message, because a consumer reads the former.
///
/// `IpcRoadFrictionSource.open` throws [IpcLibraryException] when the
/// iceoryx2™ library cannot be loaded, naming the path it tried; it is exported
/// so a caller can catch it by type.
///
/// Eclipse, iceoryx, iceoryx2 and KUKSA are trademarks of Eclipse Foundation
/// AISBL. This package is not part of the Eclipse iceoryx™ or Eclipse KUKSA™
/// projects and is not endorsed by either. `kuksa_dart_sdk`, which supplies
/// the classification rule, is by the same author and is not part of the
/// Eclipse KUKSA™ project either.
library;

export 'src/bridge/road_friction_bridge.dart';
export 'src/ffi/iox2_bindings.dart' show IpcLibraryException;
export 'src/ffi/road_friction_source.dart';
