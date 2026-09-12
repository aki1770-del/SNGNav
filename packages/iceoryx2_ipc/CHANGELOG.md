# Changelog

## 0.0.1 — 2026-09-12

First integration. Not published (`publish_to: none`).

**What it is.** A Dart subscriber for road-friction samples carried over Eclipse
iceoryx2 shared memory, and a bridge that classifies each sample with
`RoadFriction.classify` from the published `kuksa_dart_sdk` 0.2.9 — the same
function the KUKSA path uses, so the two transports cannot return different
verdicts for the same road. `quality == 0` on the wire becomes a `null` percent
and `RoadGrip.unknown`; absence never rides the measurement scale.

Includes the differential C/Dart ABI layout check for `sngnav_road_friction_t`
wired as a test, comparing per-field offset and width rather than only size and
alignment.

**What it is not.**

- Not released. No pub.dev publish, no version reachable by any consumer.
- Not verified on the IVI target, and not verified on aarch64 at runtime — the
  Dart half of the layout comparison has only ever run on host x86_64.
- Not usable across processes on Android; upstream iceoryx2 is inter-thread only
  there.
- Not protected by any iceoryx2 version symbol, because none is exported.
- Not a safety mechanism, not ASIL-rated, and makes no control claim.
- Not the sole owner of its iceoryx2 service name. `sngnav/road_friction` is a
  fixed machine-global string; a second publisher on the same host interleaves
  into the same stream, and sequence numbers then go backwards. Measured, and
  described in README.md. Single-publisher operation is assumed and currently
  enforced by nothing.
