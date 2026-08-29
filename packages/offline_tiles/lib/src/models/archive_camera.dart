library;

import 'package:flutter_map/flutter_map.dart';
import 'package:mbtiles/mbtiles.dart';

/// The camera an offline archive can actually serve.
///
/// ## Why this type exists
///
/// An MBTiles archive states, in its own `metadata` table, where it covers and
/// at which zoom levels. A host app that hardcodes a camera instead is asserting
/// a coverage claim nothing measured — and the failure is silent: `flutter_map`
/// renders a blank grey rectangle for a tile the archive does not hold, with no
/// error, no log and no visible difference from "the map has not loaded yet".
///
/// Measured on an ARM IVI target 2026-08-29: an app whose camera was 580 km from
/// the shipped archive's bounds showed a green "OFFLINE MAP" badge over a blank
/// grey rectangle. The archive was fine. The camera was pointed at another
/// prefecture.
///
/// [ArchiveCamera.resolve] reads the claim the archive makes about itself and
/// turns it into a camera, falling back — per field, never wholesale — to the
/// values the caller supplies when the archive is absent or silent.
///
/// ## The two bounds are NOT symmetric
///
/// * **[minZoom] is a blankness floor.** `RuntimeTileResolver` only ever walks
///   *down* in zoom looking for a parent tile, so a request BELOW the archive's
///   lowest stored zoom resolves to nothing at all. Zooming out past the floor
///   empties the map. [resolve] therefore RAISES the floor to the archive's own
///   `minzoom` and never lowers it.
/// * **[maxZoom] is not a blankness ceiling.** Above the archive's highest
///   stored zoom the resolver finds a parent tile and
///   `OfflineTileProvider` crops and upscales it — blurry, but present. [resolve]
///   therefore never LOWERS a caller's ceiling; it only raises it to reach the
///   archive's own `maxzoom` when the caller asked for less.
///
/// ## Contract
///
/// Every value returned is finite, inside the Web-Mercator domain, and
/// self-consistent (`minZoom <= zoom <= maxZoom`). A malformed archive cannot
/// produce a NaN, an infinity, or an inverted zoom range through this type.
class ArchiveCamera {
  const ArchiveCamera({
    required this.center,
    required this.zoom,
    required this.minZoom,
    required this.maxZoom,
    required this.derivedFromArchive,
    this.bounds,
  });

  /// The point the map opens at.
  final LatLng center;

  /// The zoom the map opens at.
  final double zoom;

  /// The lowest zoom the camera may reach. At or above this the archive has
  /// tiles; below it the map goes blank.
  final double minZoom;

  /// The highest zoom the camera may reach.
  final double maxZoom;

  /// The archive's declared coverage rectangle, when it declares one.
  final LatLngBounds? bounds;

  /// True when at least one field above came from the archive's own metadata
  /// rather than from the caller's fallback.
  ///
  /// A host that shows a coverage badge should say so differently in the two
  /// cases: a fallback camera is a guess, not a measurement.
  final bool derivedFromArchive;

  /// Web-Mercator latitude limit. Outside this, tile arithmetic is undefined.
  static const double _mercatorLatLimit = 85.05112878;

  /// The camera to use when there is no archive at all.
  ///
  /// Identical in effect to [resolve] with a null [MbTilesMetadata], and named
  /// so a reader of the call site can see which case is being taken.
  factory ArchiveCamera.fallback({
    required LatLng center,
    required double zoom,
    required double minZoom,
    required double maxZoom,
  }) {
    return ArchiveCamera.resolve(
      metadata: null,
      fallbackCenter: center,
      fallbackZoom: zoom,
      fallbackMinZoom: minZoom,
      fallbackMaxZoom: maxZoom,
    );
  }

  /// Derives the camera from what [metadata] claims, per field.
  ///
  /// Passing `metadata: null` (no archive, or an archive with no readable
  /// metadata) returns the caller's own values, sanitised. That is what makes
  /// this safe to adopt in an app that ships a documented tileset: for an
  /// archive whose `center` already equals the app's hardcoded camera, the
  /// centre and zoom are unchanged.
  static ArchiveCamera resolve({
    required MbTilesMetadata? metadata,
    required LatLng fallbackCenter,
    required double fallbackZoom,
    required double fallbackMinZoom,
    required double fallbackMaxZoom,
  }) {
    // Sanitise the caller's own values first: they are the floor we degrade to,
    // so they must themselves be sound before anything is compared against them.
    var minZoom = _finiteOr(fallbackMinZoom, 0);
    var maxZoom = _finiteOr(fallbackMaxZoom, 22);
    var zoom = _finiteOr(fallbackZoom, 11);
    var center = _sanitiseLatLng(fallbackCenter) ?? const LatLng(0, 0);
    LatLngBounds? bounds;
    var derived = false;

    if (metadata != null) {
      bounds = _boundsFrom(metadata.bounds);

      // FLOOR — raise to the archive's lowest stored zoom. Below it the
      // resolver's downward walk finds nothing and the map is blank.
      final archiveMin = _finiteOrNull(metadata.minZoom);
      if (archiveMin != null) {
        minZoom = archiveMin;
        derived = true;
      }

      // CEILING — only ever raised. Above the archive's top zoom the resolver
      // upscales a parent tile, so a higher ceiling is blurry, never blank; and
      // lowering a ceiling the caller asked for would take away a zoom level
      // that works today.
      final archiveMax = _finiteOrNull(metadata.maxZoom);
      if (archiveMax != null && archiveMax > maxZoom) {
        maxZoom = archiveMax;
        derived = true;
      }

      // CENTRE — the archive's declared default view, else the centre of its
      // declared bounds.
      final declared = _sanitiseLatLng(metadata.defaultCenter);
      if (declared != null && (bounds == null || bounds.contains(declared))) {
        center = declared;
        derived = true;
      } else if (bounds != null) {
        // Either no declared centre, or one that falls outside the archive's own
        // bounds — a self-contradictory archive. The bounds are the claim about
        // where tiles exist, so they win.
        center = bounds.simpleCenter;
        derived = true;
      }

      final declaredZoom = _finiteOrNull(metadata.defaultZoom);
      if (declaredZoom != null) {
        zoom = declaredZoom;
        derived = true;
      }
    }

    // A metadata table with minzoom > maxzoom is malformed. Widen rather than
    // invert, so the camera stays usable instead of throwing at build time.
    if (minZoom > maxZoom) {
      final low = minZoom < maxZoom ? minZoom : maxZoom;
      final high = minZoom > maxZoom ? minZoom : maxZoom;
      minZoom = low;
      maxZoom = high;
    }

    return ArchiveCamera(
      center: center,
      zoom: zoom.clamp(minZoom, maxZoom),
      minZoom: minZoom,
      maxZoom: maxZoom,
      bounds: bounds,
      derivedFromArchive: derived,
    );
  }

  static LatLngBounds? _boundsFrom(MbTilesBounds? raw) {
    if (raw == null) return null;
    final sw = _sanitiseLatLng(LatLng(raw.bottom, raw.left));
    final ne = _sanitiseLatLng(LatLng(raw.top, raw.right));
    if (sw == null || ne == null) return null;
    // LatLngBounds asserts south <= north / west <= east; an archive that
    // states them the other way round would throw at construction.
    if (sw.latitude > ne.latitude || sw.longitude > ne.longitude) return null;
    return LatLngBounds(sw, ne);
  }

  /// Returns null for a null, NaN, infinite, or out-of-domain coordinate;
  /// otherwise a point clamped into the Web-Mercator domain.
  static LatLng? _sanitiseLatLng(LatLng? point) {
    if (point == null) return null;
    final lat = point.latitude;
    final lng = point.longitude;
    if (!lat.isFinite || !lng.isFinite) return null;
    return LatLng(
      lat.clamp(-_mercatorLatLimit, _mercatorLatLimit),
      lng.clamp(-180.0, 180.0),
    );
  }

  static double _finiteOr(double value, double fallback) =>
      value.isFinite ? value : fallback;

  static double? _finiteOrNull(double? value) =>
      (value != null && value.isFinite) ? value : null;

  @override
  String toString() =>
      'ArchiveCamera(center: $center, zoom: $zoom, '
      'minZoom: $minZoom, maxZoom: $maxZoom, '
      'derivedFromArchive: $derivedFromArchive)';
}
