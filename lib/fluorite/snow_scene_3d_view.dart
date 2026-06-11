/// SnowScene3DView — the FIRST genuine 3D pixel of HER "Snow Scene".
///
/// A glanceable, **perspective-projected** road-ahead view: the driver looks
/// forward down a road that recedes to a horizon, and sees — in under a second
/// — what the road surface is doing (wet / snow / ice), how far she can see
/// before fog swallows the road, and how hard it is precipitating.
///
/// ## What this IS
///
/// A **CPU 3D→2D pinhole-camera projection drawn over a Skia [Canvas]** via
/// [CustomPainter]. World-space points on a flat ground plane (the road and its
/// lane markings, receding into the distance) are transformed through a simple
/// pinhole camera (world → view translation → perspective divide → screen) and
/// painted as 2D polygons. It is real perspective with depth — not a flat
/// top-down map.
///
/// The scene is driven entirely by the pure-Dart `snow_rendering` package:
///   * [RoadSurfaceState] → road surface tint + a glanceable advisory chip.
///   * [VisibilityDegradation] → a fog gradient whose reach maps to draw
///     distance: the road literally fades out where she can no longer see.
///   * [PrecipitationConfig] → a glanceable falling-particle density cue
///     (count derived from the real `particleCount` field, drawn statically —
///     this is a still first-pixel, not an animation).
///
/// ## What this is NOT (honest bounds)
///
/// This is **not** GPU rendering. There is no Impeller, no flutter_gpu, no
/// Filament, no Vulkan. GPU-3D on Flutter Linux desktop is currently BLOCKED
/// (Impeller's Linux Vulkan backend is an open design — flutter/flutter
/// #183495; flutter_scene/flutter_gpu cannot run; three_js is Flutter < 3.27
/// only and this repo is on 3.45). So there are **no PBR materials, no real
/// lighting, no shadows, no real terrain mesh** — the "road surface state" is a
/// flat colour wash, the "fog" is a linear gradient, not volumetric scattering.
/// It is a legible CPU approximation of the forward view, built to run and
/// build-verify HERE today, while the Filament path (see [FluoriteView] /
/// `fluorite_api.dart`) remains the GPU aspiration.
///
/// ## Placement
///
/// This is a **sibling** to [FluoriteView], not its content. FluoriteView's
/// contract anticipates a native Filament PlatformView; this CPU-projected
/// scene is a categorically different, honest first-pixel, so it stands on its
/// own rather than masquerading as the Filament path. It can still be handed to
/// `FluoriteView(placeholder: SnowScene3DView(...))` as the 2D fallback the
/// FluoriteView contract already reserves a slot for.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:snow_rendering/snow_rendering.dart';

import '../bloc/location_state.dart';

/// A glanceable perspective road-ahead scene driven by `snow_rendering` data.
///
/// Pass a [DrivingConditionAssessment] (build one with
/// `DrivingConditionAssessment.fromCondition(weatherCondition)`); the scene
/// renders the road surface, fog/draw-distance, and precipitation cue from it.
///
/// See the library doc-comment for the honest CPU-vs-GPU bounds.
class SnowScene3DView extends StatelessWidget {
  const SnowScene3DView({
    super.key,
    required this.assessment,
    this.showAdvisory = true,
    this.location,
  });

  /// The driving condition picture to render. The scene reads
  /// [DrivingConditionAssessment.surfaceState], `.visibility`, `.precipitation`
  /// and `.advisoryMessage` — never the raw weather.
  final DrivingConditionAssessment assessment;

  /// Whether to draw the glanceable advisory chip (top-left).
  final bool showAdvisory;

  /// Optional honest-uncertainty signal from the location pipeline
  /// ([LocationBloc] / `kalman_dr` dead reckoning).
  ///
  /// The scene is driven by weather alone — it has no idea where the driver
  /// actually is. Left unfed, it would keep painting a confident, crisp road
  /// even when GPS is lost and the real position is drifting: the dishonest
  /// failure D4 (and aviation RNP) forbids. When a [location] is supplied this
  /// view DEGRADES HONESTLY:
  ///
  ///  * `null` or navigation-grade [LocationQuality.fix] → no overlay; the
  ///    scene renders at full confidence.
  ///  * dead reckoning / [LocationQuality.degraded] / [LocationQuality.stale]
  ///    → an "uncertainty fog" scrim (desaturating the scene, thickening as the
  ///    confidence radius grows) plus a "GPS lost — position estimated ±N m"
  ///    banner.
  ///  * [LocationQuality.error] (provider error, or the `kalman_dr` 500 m DR
  ///    safety cap exceeded) → an explicit "POSITION UNAVAILABLE" overlay; the
  ///    confident road is hidden rather than shown as trustworthy.
  ///
  /// The view reads only [LocationState.quality], [LocationState.isDeadReckoning],
  /// [LocationState.confidenceRadius] and [LocationState.errorMessage].
  final LocationState? location;

  @override
  Widget build(BuildContext context) {
    final scene = RepaintBoundary(
      child: CustomPaint(
        painter: _RoadAheadPainter(assessment: assessment, showAdvisory: showAdvisory),
        // Expand to fill whatever box the parent gives us.
        child: const SizedBox.expand(),
      ),
    );

    final loc = location;
    final turnBack = assessment.recommendedResponse ==
        RecommendedResponse.considerTurningBack;
    final confidentFix = loc == null ||
        (loc.quality == LocationQuality.fix && !loc.isDeadReckoning);

    // A confident fix (or no location signal) AND no turn-back advisory → the
    // plain confident scene.
    if (confidentFix && !turnBack) return scene;

    final showDegradeBanner =
        loc != null && !confidentFix && loc.quality != LocationQuality.error;

    // Overlay order, back to front: scene, honest GPS-degradation layer (fog
    // scrim / position-unavailable floor), then the top banners. When a
    // turn-back banner is present the degradation layer's own banner is
    // suppressed so the two compose vertically instead of overlapping — the
    // whiteout-and-GPS-lost case is the product's core worst case, so the two
    // must read cleanly together.
    return Stack(
      fit: StackFit.expand,
      children: [
        scene,
        if (!confidentFix)
          _UncertaintyOverlay(location: loc, showBanner: !turnBack),
        if (turnBack)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _TurnBackBanner(),
                if (showDegradeBanner)
                  _DegradeBanner(text: _degradeBannerText(loc)),
              ],
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Honest-degradation overlay
// ---------------------------------------------------------------------------

/// Paints the honest GPS-degradation layer over the scene from a
/// [LocationState]. See [SnowScene3DView.location] for the contract.
class _UncertaintyOverlay extends StatelessWidget {
  const _UncertaintyOverlay({required this.location, this.showBanner = true});

  final LocationState location;

  /// When false, the degrade banner is suppressed (the caller is rendering it
  /// itself, below a higher-priority banner). The fog scrim / floor still show.
  final bool showBanner;

  /// Accuracy (m) at/below which a fix is navigation-grade — mirrors
  /// `GeoPosition.isNavigationGrade` (50 m). Kept as a local const so this view
  /// carries no hard dependency on the kalman_dr internals.
  static const double _navGradeMeters = 50.0;

  /// Accuracy (m) at which dead reckoning hits its safety cap and stops —
  /// mirrors `DeadReckoningState.maxAccuracy` (500 m).
  static const double _maxAccuracyMeters = 500.0;

  @override
  Widget build(BuildContext context) {
    // --- Honesty floor: position unavailable -------------------------------
    if (location.quality == LocationQuality.error) {
      return _PositionUnavailable(message: location.errorMessage);
    }

    // --- Degraded / dead-reckoning: scale uncertainty by the confidence
    //     radius so the scene visibly loses confidence as accuracy grows. -----
    final accuracy = location.confidenceRadius; // metres; 0 if no position
    final u = ((accuracy - _navGradeMeters) /
            (_maxAccuracyMeters - _navGradeMeters))
        .clamp(0.0, 1.0);
    final scrimOpacity = _lerp(0.14, 0.62, u);

    return Stack(
      fit: StackFit.expand,
      children: [
        // Uncertainty fog: a desaturating white scrim that thickens as the
        // confidence radius grows — the scene literally loses confidence.
        IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFFE9EEF2).withValues(alpha: scrimOpacity),
            ),
          ),
        ),
        if (showBanner)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _DegradeBanner(text: _degradeBannerText(location)),
          ),
      ],
    );
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;
}

/// The degrade-banner text for a degraded / stale / dead-reckoning location.
String _degradeBannerText(LocationState location) {
  final String banner;
  if (location.isDeadReckoning) {
    banner = 'GPS lost — position estimated';
  } else if (location.quality == LocationQuality.stale) {
    banner = 'GPS stale — last known position';
  } else {
    banner = 'GPS degraded — position approximate';
  }
  final accuracy = location.confidenceRadius;
  final accuracyLabel =
      accuracy > 0 ? '  ±${accuracy.toStringAsFixed(0)} m' : '';
  return '$banner$accuracyLabel';
}

/// The amber caution banner shown while the position is estimated.
class _DegradeBanner extends StatelessWidget {
  const _DegradeBanner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Container(
        width: double.infinity,
        color: const Color(0xFFB26A00).withValues(alpha: 0.92), // amber caution
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.gps_off, color: Colors.white, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The turn-back banner — the first-class trip-abandonment cue shown in
/// whiteout-class conditions. Deliberately more prominent than the amber
/// [_DegradeBanner]: this is the response that gets the driver home rather than
/// pushing on. Grounded in a recorded driver voice (see DRIVER_VOICES.md, the
/// Sapporo→Shinshinotsu whiteout) where the life-saving choice was to turn back.
class _TurnBackBanner extends StatelessWidget {
  const _TurnBackBanner();

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Container(
        width: double.infinity,
        color: const Color(0xFF8E1B1B).withValues(alpha: 0.94), // deep red
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: const Row(
          children: [
            Icon(Icons.u_turn_left, color: Colors.white, size: 22),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Whiteout conditions — consider turning back while you safely can',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The honesty floor — shown when the position is unavailable
/// ([LocationQuality.error] / DR 500 m safety cap exceeded). The confident road
/// is hidden under a heavy scrim so it cannot be mistaken for trustworthy.
class _PositionUnavailable extends StatelessWidget {
  const _PositionUnavailable({this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        fit: StackFit.expand,
        children: [
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.74),
              ),
            ),
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.location_disabled,
                      color: Colors.white, size: 48),
                  const SizedBox(height: 12),
                  const Text(
                    'POSITION UNAVAILABLE',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    message ??
                        'Location uncertainty exceeds the 500 m safety cap',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Minimal pinhole camera: world (x right, y up, z forward) → screen.
// ---------------------------------------------------------------------------

/// A point in 3D world space, metres. The driver/camera sits at the origin,
/// slightly above the road, looking down +z.
class _V3 {
  const _V3(this.x, this.y, this.z);
  final double x;
  final double y;
  final double z;
}

/// Projects world points to screen pixels through a simple pinhole camera.
///
/// Camera is at [camHeight] metres above the ground plane (y = 0), looking
/// straight down +z. A real perspective divide (1/z) gives depth: near road is
/// wide at the bottom of the screen, far road narrows toward the horizon.
class _PinholeCamera {
  _PinholeCamera({required this.size});

  final Size size;

  /// ~driver eye height, metres.
  static const double camHeight = 1.4;

  /// Focal length factor (controls effective FOV).
  static const double focal = 1.2;

  /// The screen-space y of the horizon (z → ∞). Used to anchor sky/fog.
  double get horizonY {
    // As z→∞, screenY → cy + focal*camHeight*scale/z → cy. We bias the horizon
    // slightly above centre so more road is visible.
    return size.height * 0.42;
  }

  /// Project a world point to a screen offset. Returns null if behind/at camera.
  Offset? project(_V3 p) {
    if (p.z <= 0.01) return null; // behind the camera — cull
    final cx = size.width / 2;
    final cy = horizonY;
    // Perspective divide. Scale chosen so the world fills the frame sensibly.
    final scale = size.height * focal;
    final sx = cx + (p.x * scale) / p.z;
    // Camera is camHeight above the plane; ground (y=0) appears below horizon.
    final sy = cy + ((camHeight - p.y) * scale) / p.z;
    return Offset(sx, sy);
  }
}

// ---------------------------------------------------------------------------
// Painter
// ---------------------------------------------------------------------------

class _RoadAheadPainter extends CustomPainter {
  _RoadAheadPainter({required this.assessment, required this.showAdvisory});

  final DrivingConditionAssessment assessment;
  final bool showAdvisory;

  // Road geometry, world metres.
  static const double _laneHalfWidth = 3.5; // half road width
  static const double _nearZ = 2.0; // start drawing road this far ahead
  static const double _maxZ = 220.0; // absolute far clip

  @override
  void paint(Canvas canvas, Size size) {
    final cam = _PinholeCamera(size: size);

    // --- Draw distance from visibility degradation ---------------------------
    // opacity 0.0 (clear, vis ≥ 1000m) → far draw distance; opacity 0.9
    // (whiteout) → road fades very close. Map opacity [0..0.9] → drawZ.
    final visOpacity = assessment.visibility.opacity; // 0.0 .. 0.9
    final drawZ = _lerp(_maxZ, 18.0, (visOpacity / 0.9).clamp(0.0, 1.0));

    _paintSky(canvas, size, cam);
    _paintRoad(canvas, size, cam, drawZ);
    _paintLaneMarkings(canvas, cam, drawZ);
    _paintFog(canvas, size, cam, drawZ);
    _paintPrecipitation(canvas, size);
    if (showAdvisory) _paintAdvisory(canvas, size);
  }

  // Sky / ground-fog backdrop above the horizon.
  void _paintSky(Canvas canvas, Size size, _PinholeCamera cam) {
    final horizon = cam.horizonY;
    final skyPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: const [Color(0xFF4A5A6A), Color(0xFF9FB0BE)],
      ).createShader(Rect.fromLTRB(0, 0, size.width, horizon));
    canvas.drawRect(Rect.fromLTRB(0, 0, size.width, horizon), skyPaint);
  }

  // The road quad, tinted by road surface state.
  void _paintRoad(Canvas canvas, Size size, _PinholeCamera cam, double drawZ) {
    // Ground (off-road) base.
    final groundPaint = Paint()..color = const Color(0xFF2A3138);
    canvas.drawRect(
      Rect.fromLTRB(0, cam.horizonY, size.width, size.height),
      groundPaint,
    );

    final farZ = math.min(drawZ, _maxZ);
    final nl = cam.project(_V3(-_laneHalfWidth, 0, _nearZ));
    final nr = cam.project(_V3(_laneHalfWidth, 0, _nearZ));
    final fl = cam.project(_V3(-_laneHalfWidth, 0, farZ));
    final fr = cam.project(_V3(_laneHalfWidth, 0, farZ));
    if (nl == null || nr == null || fl == null || fr == null) return;

    final road = Path()
      ..moveTo(nl.dx, nl.dy)
      ..lineTo(nr.dx, nr.dy)
      ..lineTo(fr.dx, fr.dy)
      ..lineTo(fl.dx, fl.dy)
      ..close();

    canvas.drawPath(road, Paint()..color = _surfaceColor(assessment.surfaceState));
  }

  // Dashed centre line + solid edge hint — gives the eye depth + lane sense.
  void _paintLaneMarkings(Canvas canvas, _PinholeCamera cam, double drawZ) {
    final farZ = math.min(drawZ, _maxZ);
    final markPaint = Paint()
      ..color = const Color(0xFFFFF3C4) // warm off-white
      ..style = PaintingStyle.fill;

    // Centre dashes from near to far, every ~6m with ~3m gaps.
    const dashLen = 3.0;
    const gap = 3.0;
    var z = _nearZ;
    while (z < farZ) {
      final a = cam.project(_V3(-0.15, 0.0, z));
      final b = cam.project(_V3(0.15, 0.0, z));
      final c = cam.project(_V3(0.15, 0.0, math.min(z + dashLen, farZ)));
      final d = cam.project(_V3(-0.15, 0.0, math.min(z + dashLen, farZ)));
      if (a != null && b != null && c != null && d != null) {
        final dash = Path()
          ..moveTo(a.dx, a.dy)
          ..lineTo(b.dx, b.dy)
          ..lineTo(c.dx, c.dy)
          ..lineTo(d.dx, d.dy)
          ..close();
        canvas.drawPath(dash, markPaint);
      }
      z += dashLen + gap;
    }
  }

  // Fog gradient anchored at the draw-distance horizon. The lower visibility,
  // the higher up the fog wall climbs from the road's vanishing point — the
  // road visibly fades where she can no longer see.
  void _paintFog(Canvas canvas, Size size, _PinholeCamera cam, double drawZ) {
    final visOpacity = assessment.visibility.opacity; // 0..0.9
    if (visOpacity <= 0.001) return; // perfectly clear — no fog wall

    // Screen y where the far edge of the visible road sits.
    final farEdge = cam.project(_V3(0, 0, math.min(drawZ, _maxZ)));
    final fogTop = cam.horizonY - 1; // fog starts a touch above horizon
    final fogBottom = (farEdge?.dy ?? cam.horizonY) + size.height * 0.15;

    final fogColor = const Color(0xFFE9EEF2);
    final fog = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          fogColor.withValues(alpha: visOpacity),
          fogColor.withValues(alpha: visOpacity * 0.25),
          fogColor.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.6, 1.0],
      ).createShader(Rect.fromLTRB(0, fogTop, size.width, fogBottom));
    canvas.drawRect(Rect.fromLTRB(0, fogTop, size.width, fogBottom), fog);
  }

  // Glanceable precipitation density cue. Particle COUNT comes from the real
  // PrecipitationConfig.particleCount field (0..500). We draw a representative,
  // deterministic sample (not the full count — this is a glance cue, not a
  // physics sim), scaled so heavier precip = denser screen.
  void _paintPrecipitation(Canvas canvas, Size size) {
    final config = assessment.precipitation;
    if (config.particleCount <= 0) return;

    // Map real particleCount (0..500) to a drawable on-screen sample (0..160).
    final sampleCount = (config.particleCount / 500.0 * 160).round().clamp(0, 160);
    final rng = math.Random(config.particleCount); // deterministic per condition
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.7);

    for (var i = 0; i < sampleCount; i++) {
      final dx = rng.nextDouble() * size.width;
      final dy = rng.nextDouble() * size.height;
      // Size cue from the real min/max size band.
      final r = _lerp(config.minSize, config.maxSize, rng.nextDouble()) * 0.5;
      canvas.drawCircle(Offset(dx, dy), r.clamp(0.6, 4.0), paint);
    }
  }

  // Glanceable advisory chip — the one-second read.
  void _paintAdvisory(Canvas canvas, Size size) {
    final text = assessment.advisoryMessage;
    final chipColor = _surfaceColor(assessment.surfaceState);
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        // Pin the bundled Material font: this painter doesn't inherit the
        // theme, and the chip must render the same glyphs on every embedder.
        style: const TextStyle(
          color: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.w600,
          fontFamily: 'Roboto',
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 2,
    )..layout(maxWidth: size.width * 0.7);

    const pad = 10.0;
    final chipRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(12, 12, tp.width + pad * 2, tp.height + pad * 2),
      const Radius.circular(8),
    );
    canvas.drawRRect(
      chipRect,
      Paint()..color = chipColor.withValues(alpha: 0.85),
    );
    canvas.drawRRect(
      chipRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Colors.white.withValues(alpha: 0.6),
    );
    tp.paint(canvas, const Offset(12 + pad, 12 + pad));
  }

  // Road surface state → a legible road tint.
  Color _surfaceColor(RoadSurfaceState state) {
    return switch (state) {
      RoadSurfaceState.dry => const Color(0xFF3C4248), // dark asphalt
      RoadSurfaceState.wet => const Color(0xFF2E4250), // dark, sheen-blue
      RoadSurfaceState.standingWater => const Color(0xFF26414F),
      RoadSurfaceState.slush => const Color(0xFF6B7178), // grey-brown mush
      RoadSurfaceState.compactedSnow => const Color(0xFFD7DEE5), // white-grey
      RoadSurfaceState.blackIce => const Color(0xFF7FA6C9), // pale icy blue sheen
    };
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  @override
  bool shouldRepaint(covariant _RoadAheadPainter old) {
    return old.assessment != assessment || old.showAdvisory != showAdvisory;
  }
}
